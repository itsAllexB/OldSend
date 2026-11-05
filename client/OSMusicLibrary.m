#import "OSMusicLibrary.h"
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <notify.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <unistd.h>

/*
 * Add to Music.
 *
 * iOS 6 has no public API for adding songs to the Music app. On iOS 5 and 6 every process that
 * writes the library (the iTunes Store's itunesstored for downloads, the Music app for edits)
 * does it in-process with the private MusicLibrary.framework, which owns MediaLibrary.sqlitedb:
 * its own SQLite functions, triggers, sort and search maps, change revisions (what iTunes sync
 * reads) and artwork cache. Writing the database with plain SQLite would bypass all of that, so
 * OldSend uses the framework's own importer, exactly as itunesstored does for a purchase:
 *
 *   1. the file moves into the Music app's media folder, /var/mobile/Media/iTunes_Control/Music/Fxx
 *      (where iTunes and the Store put songs), under a random 4-letter name;
 *   2. an MLTrackImport carries the tags read with AVFoundation (title, artist, album, album
 *      artist, genre, composer, year, track and disc numbers, duration, artwork);
 *   3. -[ML3TrackImporter importTrack:withCompletionBlock:] inserts the track in one database
 *      transaction (all or nothing) and writes the artwork in the library's own formats;
 *   4. the track is looked up again before OldSend forgets its copy. If anything fails, the
 *      file goes back to History and nothing else changes.
 *
 * Checked on an iPhone 4S with iOS 6.1.3 (MusicLibrary.framework of 10B329).
 */

#define OS_MUSIC_LOCK "/var/mobile/Library/OldSend/.music.lock"
#define OS_MUSICLIBRARY_PATH "/System/Library/PrivateFrameworks/MusicLibrary.framework/MusicLibrary"

/* ML3 media types (item.media_type), which MLTrackImport maps to iTunes media kinds. */
#define OS_ML3_MEDIA_TYPE_SONG 8
#define OS_ML3_MEDIA_TYPE_AUDIOBOOK 2

/* MusicLibrary.framework, private (class-dump of iOS 6.1.3, confirmed with the runtime). */
@interface NSObject (OSMusicLibraryPrivate)
+ (NSString *)mainDatabasePath;
+ (NSString *)mediaFolderPath;
- (id)initWithPath:(NSString *)path enableWrites:(BOOL)enableWrites;
- (BOOL)writable;
- (id)initWithMusicLibrary:(id)library;
- (void)importTrack:(id)track withCompletionBlock:(void (^)(BOOL success, long long persistentID))completion;
- (void)setAssetFilePath:(NSString *)path;
- (void)setMediaType:(unsigned long)mediaType;
- (void)setShouldAddToPurchasedPlaylist:(BOOL)shouldAdd;
- (void)setArtworkData:(NSData *)data;
- (void)setValue:(id)value forEntityProperty:(NSString *)property;
+ (BOOL)trackWithPersistentID:(long long)persistentID existsInLibrary:(id)library;
@end

BOOL OSAddToMusicEnabled(void) {
    NSNumber *value = [[NSUserDefaults standardUserDefaults] objectForKey:@"add_to_music"];
    return value == nil || [value boolValue];  /* on unless turned off */
}

BOOL OSIsMusicFile(NSString *path) {
    static NSSet *extensions = nil;
    if (extensions == nil) {
        extensions = [[NSSet alloc] initWithObjects:@"mp3", @"m4a", @"m4b", @"aac", @"wav",
                      @"aif", @"aiff", @"aifc", @"caf", nil];
    }
    return [extensions containsObject:[[path pathExtension] lowercaseString]];
}

/* The writable library, opened once per process. Only the import path uses it. */
static Class os_ml3_class(NSString *name) {
    static BOOL loaded = NO;
    if (!loaded) {
        loaded = YES;
        dlopen(OS_MUSICLIBRARY_PATH, RTLD_LAZY);
    }
    return NSClassFromString(name);
}

static id os_music_library(void) {
    static id library = nil;
    @synchronized (@"OSMusicLibrary") {
        Class libraryClass = os_ml3_class(@"ML3MusicLibrary");
        if (library == nil && libraryClass != Nil &&
            [libraryClass respondsToSelector:@selector(mainDatabasePath)] &&
            [libraryClass instancesRespondToSelector:@selector(initWithPath:enableWrites:)]) {
            library = [[libraryClass alloc] initWithPath:[libraryClass mainDatabasePath] enableWrites:YES];
            if (library != nil && [library respondsToSelector:@selector(writable)] && ![library writable]) {
                [library release];
                library = nil;
            }
        }
    }
    return library;
}

/* A metadata item's key as a string: ID3 frames ("TRCK"), iTunes atoms ("trkn", "@day" for
   "\xA9day"). AVFoundation hands some of them over as four-character codes. */
static NSString *os_metadata_key(AVMetadataItem *item) {
    id key = [item key];
    if ([key isKindOfClass:[NSString class]]) return key;
    if ([key isKindOfClass:[NSNumber class]]) {
        uint32_t code = [key unsignedIntValue];
        char text[5];
        int i;
        for (i = 0; i < 4; i++) {
            unsigned char c = (unsigned char)((code >> (24 - 8 * i)) & 0xff);
            text[i] = (c == 0xA9) ? '@' : (c >= 0x20 && c < 0x7f ? (char)c : '?');
        }
        text[4] = '\0';
        return [NSString stringWithUTF8String:text];
    }
    return nil;
}

static NSString *os_metadata_string(AVMetadataItem *item) {
    id value = [item value];
    NSString *text = nil;
    if ([value isKindOfClass:[NSString class]]) text = value;
    else if ([value isKindOfClass:[NSNumber class]]) text = [value stringValue];
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [text length] > 0 ? text : nil;
}

static NSData *os_metadata_artwork(AVMetadataItem *item) {
    id value = [item value];
    if ([value isKindOfClass:[NSData class]] && [value length] > 0) return value;
    if ([value isKindOfClass:[NSDictionary class]]) {  /* ID3 APIC: { MIME, data, ... } */
        id data = [value objectForKey:@"data"];
        if ([data isKindOfClass:[NSData class]] && [data length] > 0) return data;
    }
    return nil;
}

/* "3/12" (ID3) or the iTunes trkn/disk atom (2 bytes padding, number, total). */
static void os_metadata_pair(AVMetadataItem *item, NSNumber **number, NSNumber **count) {
    id value = [item value];
    int first = 0, second = 0;

    if ([value isKindOfClass:[NSData class]] && [value length] >= 6) {
        const unsigned char *b = [value bytes];
        first = (b[2] << 8) | b[3];
        second = (b[4] << 8) | b[5];
    } else if ([value isKindOfClass:[NSNumber class]]) {
        first = [value intValue];
    } else if ([value isKindOfClass:[NSString class]]) {
        NSArray *parts = [value componentsSeparatedByString:@"/"];
        first = [[parts objectAtIndex:0] intValue];
        if ([parts count] > 1) second = [[parts objectAtIndex:1] intValue];
    }
    if (first > 0 && *number == nil) *number = [NSNumber numberWithInt:first];
    if (second > 0 && *count == nil) *count = [NSNumber numberWithInt:second];
}

static NSNumber *os_metadata_year(AVMetadataItem *item) {
    NSString *text = os_metadata_string(item);
    int year;
    if ([text length] < 4) return nil;
    year = [[text substringToIndex:4] intValue];
    return (year > 0 && year < 10000) ? [NSNumber numberWithInt:year] : nil;
}

/* ID3 TCON may hold an ID3v1 genre number: "(17)", "(17)Rock" or "17". */
static NSString *os_genre_name(NSString *text) {
    static NSString * const genres[] = {
        @"Blues", @"Classic Rock", @"Country", @"Dance", @"Disco", @"Funk", @"Grunge", @"Hip-Hop",
        @"Jazz", @"Metal", @"New Age", @"Oldies", @"Other", @"Pop", @"R&B", @"Rap", @"Reggae",
        @"Rock", @"Techno", @"Industrial", @"Alternative", @"Ska", @"Death Metal", @"Pranks",
        @"Soundtrack", @"Euro-Techno", @"Ambient", @"Trip-Hop", @"Vocal", @"Jazz+Funk", @"Fusion",
        @"Trance", @"Classical", @"Instrumental", @"Acid", @"House", @"Game", @"Sound Clip",
        @"Gospel", @"Noise", @"AlternRock", @"Bass", @"Soul", @"Punk", @"Space", @"Meditative",
        @"Instrumental Pop", @"Instrumental Rock", @"Ethnic", @"Gothic", @"Darkwave",
        @"Techno-Industrial", @"Electronic", @"Pop-Folk", @"Eurodance", @"Dream", @"Southern Rock",
        @"Comedy", @"Cult", @"Gangsta", @"Top 40", @"Christian Rap", @"Pop/Funk", @"Jungle",
        @"Native American", @"Cabaret", @"New Wave", @"Psychadelic", @"Rave", @"Showtunes",
        @"Trailer", @"Lo-Fi", @"Tribal", @"Acid Punk", @"Acid Jazz", @"Polka", @"Retro",
        @"Musical", @"Rock & Roll", @"Hard Rock"
    };
    NSScanner *scanner;
    int number;

    if (text == nil) return nil;
    scanner = [NSScanner scannerWithString:text];
    if ([scanner scanString:@"(" intoString:NULL] && [scanner scanInt:&number] &&
        [scanner scanString:@")" intoString:NULL]) {
        NSString *rest = [[text substringFromIndex:[scanner scanLocation]]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([rest length] > 0) return rest;
    } else {
        scanner = [NSScanner scannerWithString:text];
        if (!([scanner scanInt:&number] && [scanner isAtEnd])) return text;
    }
    if (number >= 0 && number < (int)(sizeof(genres) / sizeof(genres[0]))) return genres[number];
    return nil;
}

/* Tags into ML3 track properties (the column names MusicLibrary's ML3TrackProperty* constants
   hold). Returns the artwork separately. */
static NSMutableDictionary *os_track_properties(AVURLAsset *asset, NSString *name, NSData **artwork) {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    NSString *title = nil, *artist = nil, *album = nil, *albumArtist = nil, *genre = nil, *composer = nil;
    NSNumber *year = nil, *track = nil, *trackCount = nil, *disc = nil, *discCount = nil;
    NSData *art = nil;
    CMTime duration;

    for (AVMetadataItem *item in [asset commonMetadata]) {
        NSString *key = [item commonKey];
        if ([key isEqualToString:AVMetadataCommonKeyTitle] && title == nil) title = os_metadata_string(item);
        else if ([key isEqualToString:AVMetadataCommonKeyArtist] && artist == nil) artist = os_metadata_string(item);
        else if ([key isEqualToString:AVMetadataCommonKeyAlbumName] && album == nil) album = os_metadata_string(item);
        else if ([key isEqualToString:AVMetadataCommonKeyType] && genre == nil) genre = os_genre_name(os_metadata_string(item));
        else if ([key isEqualToString:AVMetadataCommonKeyArtwork] && art == nil) art = os_metadata_artwork(item);
    }

    for (NSString *format in [asset availableMetadataFormats]) {
        for (AVMetadataItem *item in [asset metadataForFormat:format]) {
            NSString *key = os_metadata_key(item);
            if (key == nil) continue;
            if ([key isEqualToString:@"TRCK"] || [key isEqualToString:@"trkn"]) {
                os_metadata_pair(item, &track, &trackCount);
            } else if ([key isEqualToString:@"TPOS"] || [key isEqualToString:@"disk"]) {
                os_metadata_pair(item, &disc, &discCount);
            } else if ([key isEqualToString:@"TYER"] || [key isEqualToString:@"TDRC"] ||
                       [key isEqualToString:@"TDOR"] || [key isEqualToString:@"@day"]) {
                if (year == nil) year = os_metadata_year(item);
            } else if ([key isEqualToString:@"TPE2"] || [key isEqualToString:@"aART"]) {
                if (albumArtist == nil) albumArtist = os_metadata_string(item);
            } else if ([key isEqualToString:@"TCOM"] || [key isEqualToString:@"@wrt"]) {
                if (composer == nil) composer = os_metadata_string(item);
            } else if ([key isEqualToString:@"TCON"] || [key isEqualToString:@"@gen"]) {
                if (genre == nil) genre = os_genre_name(os_metadata_string(item));
            } else if ([key isEqualToString:@"TIT2"] || [key isEqualToString:@"@nam"]) {
                if (title == nil) title = os_metadata_string(item);
            } else if ([key isEqualToString:@"TPE1"] || [key isEqualToString:@"@ART"]) {
                if (artist == nil) artist = os_metadata_string(item);
            } else if ([key isEqualToString:@"TALB"] || [key isEqualToString:@"@alb"]) {
                if (album == nil) album = os_metadata_string(item);
            } else if ([key isEqualToString:@"APIC"] || [key isEqualToString:@"covr"]) {
                if (art == nil) art = os_metadata_artwork(item);
            }
        }
    }

    if (title == nil) title = [name stringByDeletingPathExtension];
    [values setObject:title forKey:@"item_extra.title"];
    if (artist != nil) [values setObject:artist forKey:@"item_artist.item_artist"];
    if (album != nil) [values setObject:album forKey:@"album.album"];
    if (albumArtist != nil) [values setObject:albumArtist forKey:@"album_artist.album_artist"];
    if (genre != nil) [values setObject:genre forKey:@"genre.genre"];
    if (composer != nil) [values setObject:composer forKey:@"composer.composer"];
    if (year != nil) [values setObject:year forKey:@"item_extra.year"];
    if (track != nil) [values setObject:track forKey:@"track_number"];
    if (trackCount != nil) [values setObject:trackCount forKey:@"item_extra.track_count"];
    if (disc != nil) [values setObject:disc forKey:@"disc_number"];
    if (discCount != nil) [values setObject:discCount forKey:@"item_extra.disc_count"];

    duration = [asset duration];
    if ((duration.flags & kCMTimeFlags_Valid) && duration.timescale > 0 && duration.value > 0) {
        [values setObject:[NSNumber numberWithDouble:(double)duration.value * 1000.0 / duration.timescale]
                   forKey:@"item_extra.total_time_ms"];
    }
    *artwork = art;
    return values;
}

/* A free iTunes-style name in iTunes_Control/Music/F00..F49, e.g. F07/QZMB.mp3. */
static NSString *os_music_destination(NSString *mediaFolder, NSString *extension) {
    NSFileManager *manager = [NSFileManager defaultManager];
    int attempt;

    for (attempt = 0; attempt < 100; attempt++) {
        NSString *folder = [mediaFolder stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"iTunes_Control/Music/F%02u", arc4random_uniform(50)]];
        char name[5];
        int i;
        NSString *path;

        for (i = 0; i < 4; i++) name[i] = (char)('A' + arc4random_uniform(26));
        name[4] = '\0';
        path = [folder stringByAppendingPathComponent:
                [[NSString stringWithUTF8String:name] stringByAppendingPathExtension:extension]];
        if ([manager fileExistsAtPath:path]) continue;
        if (![manager createDirectoryAtPath:folder
                withIntermediateDirectories:YES
                                 attributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0755]
                                                                        forKey:NSFilePosixPermissions]
                                      error:NULL]) {
            return nil;
        }
        return path;
    }
    return nil;
}

static OSMusicResult os_add_locked(NSString *path, NSString **detail) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *name = [path lastPathComponent];
    NSString *extension = [[path pathExtension] lowercaseString];
    Class libraryClass, importClass, importerClass, trackClass;
    id library, trackImport, importer;
    AVURLAsset *asset;
    NSMutableDictionary *values;
    NSData *artwork = nil;
    NSString *destination;
    NSDate *now;
    BOOL copied = NO;
    __block BOOL success = NO;
    __block long long persistentID = 0;

    if (!OSIsMusicFile(path)) {
        *detail = @"not a supported audio type";
        return OSMusicNotSupported;
    }
    if (![manager fileExistsAtPath:path]) {
        *detail = @"file is gone";
        return OSMusicFailed;
    }

    asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    if (![asset isPlayable] || [[asset tracksWithMediaType:AVMediaTypeAudio] count] == 0 ||
        [[asset tracksWithMediaType:AVMediaTypeVideo] count] > 0) {
        *detail = @"iOS can't play it as audio";
        return OSMusicNotSupported;
    }

    library = os_music_library();
    libraryClass = os_ml3_class(@"ML3MusicLibrary");
    importClass = os_ml3_class(@"MLTrackImport");
    importerClass = os_ml3_class(@"ML3TrackImporter");
    trackClass = os_ml3_class(@"ML3Track");
    if (library == nil || importClass == Nil || importerClass == Nil ||
        ![importClass instancesRespondToSelector:@selector(setValue:forEntityProperty:)] ||
        ![importerClass instancesRespondToSelector:@selector(importTrack:withCompletionBlock:)]) {
        *detail = @"MusicLibrary.framework is not available";
        return OSMusicFailed;
    }

    values = os_track_properties(asset, name, &artwork);

    destination = os_music_destination([libraryClass mediaFolderPath] ?: @"/var/mobile/Media", extension);
    if (destination == nil) {
        *detail = @"can't create a folder in iTunes_Control/Music";
        return OSMusicFailed;
    }
    /* Move (same volume, so no second copy and no extra space); copy only if that fails. */
    if (rename([path fileSystemRepresentation], [destination fileSystemRepresentation]) != 0) {
        if (![manager copyItemAtPath:path toPath:destination error:NULL]) {
            *detail = [NSString stringWithFormat:@"can't move the file (%s)", strerror(errno)];
            return OSMusicFailed;
        }
        copied = YES;
    }

    now = [NSDate date];
    [values setObject:[NSNumber numberWithLongLong:
                       [[[manager attributesOfItemAtPath:destination error:NULL] objectForKey:NSFileSize] longLongValue]]
               forKey:@"item_extra.file_size"];
    [values setObject:[NSNumber numberWithLongLong:(long long)[now timeIntervalSinceReferenceDate]]
               forKey:@"item_extra.date_created"];
    [values setObject:[NSNumber numberWithLongLong:(long long)[now timeIntervalSinceReferenceDate]]
               forKey:@"item_extra.date_modified"];

    trackImport = [[importClass alloc] init];
    [trackImport setAssetFilePath:destination];
    [trackImport setMediaType:[extension isEqualToString:@"m4b"] ? OS_ML3_MEDIA_TYPE_AUDIOBOOK
                                                           : OS_ML3_MEDIA_TYPE_SONG];
    /* Not a purchase: no "Purchased" playlist. */
    if ([trackImport respondsToSelector:@selector(setShouldAddToPurchasedPlaylist:)]) {
        [trackImport setShouldAddToPurchasedPlaylist:NO];
    }
    for (NSString *property in values) {
        [trackImport setValue:[values objectForKey:property] forEntityProperty:property];
    }
    if (artwork != nil) [trackImport setArtworkData:artwork];

    importer = [[importerClass alloc] initWithMusicLibrary:library];
    /* The importer runs one database transaction and calls back before it returns. */
    [importer importTrack:trackImport withCompletionBlock:^(BOOL ok, long long pid) {
        success = ok;
        persistentID = pid;
    }];
    [importer release];
    [trackImport release];

    if (success && persistentID != 0 && trackClass != Nil &&
        [trackClass respondsToSelector:@selector(trackWithPersistentID:existsInLibrary:)]) {
        success = [trackClass trackWithPersistentID:persistentID existsInLibrary:library];
    }
    if (!success || persistentID == 0) {
        /* Not in the library: the file goes back to History. */
        if (copied) {
            [manager removeItemAtPath:destination error:NULL];
        } else if (rename([destination fileSystemRepresentation], [path fileSystemRepresentation]) != 0) {
            [manager copyItemAtPath:destination toPath:path error:NULL];
        }
        *detail = @"the music library did not accept it";
        return OSMusicFailed;
    }

    if (copied) [manager removeItemAtPath:path error:NULL];
    /* The library posts this itself when the change is committed; post it now as well so
       the Music app refreshes even if this process is suspended right after. */
    notify_post([[@"com.apple.mobileipod.librarychanged-" stringByAppendingString:
                  [libraryClass mainDatabasePath]] UTF8String]);
    *detail = [NSString stringWithFormat:@"%@ (%@)",
               [destination substringFromIndex:[[libraryClass mediaFolderPath] length]],
               [values objectForKey:@"item_extra.title"]];
    return OSMusicAdded;
}

OSMusicResult OSAddFileToMusic(NSString *path, NSString **detail) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *text = nil;
    OSMusicResult result;
    int lock = open(OS_MUSIC_LOCK, O_RDWR | O_CREAT, 0644);

    if (lock >= 0) flock(lock, LOCK_EX);
    result = os_add_locked(path, &text);
    if (lock >= 0) {
        flock(lock, LOCK_UN);
        close(lock);
    }
    if (detail != NULL) *detail = [text copy];
    [pool release];
    if (detail != NULL) [*detail autorelease];
    return result;
}

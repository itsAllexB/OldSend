#import "OSShareInbox.h"
#include <stdlib.h>

#define OS_OUTGOING_DIR @"/var/mobile/Library/OldSend/Outgoing"

static NSString *os_mime_type(NSString *name) {
    static NSDictionary *types = nil;
    NSString *type;

    if (types == nil) {
        types = [[NSDictionary alloc] initWithObjectsAndKeys:
            @"image/jpeg", @"jpg", @"image/jpeg", @"jpeg", @"image/png", @"png",
            @"image/gif", @"gif", @"image/tiff", @"tif", @"image/tiff", @"tiff",
            @"image/bmp", @"bmp", @"image/heic", @"heic",
            @"video/quicktime", @"mov", @"video/mp4", @"mp4", @"video/x-m4v", @"m4v",
            @"video/3gpp", @"3gp",
            @"audio/mpeg", @"mp3", @"audio/mp4", @"m4a", @"audio/aac", @"aac",
            @"audio/wav", @"wav", @"audio/aiff", @"aiff",
            @"application/pdf", @"pdf", @"application/zip", @"zip",
            @"text/plain", @"txt", @"text/html", @"html", @"text/html", @"htm",
            @"application/rtf", @"rtf", nil];
    }
    type = [types objectForKey:[[name pathExtension] lowercaseString]];
    return type != nil ? type : @"application/octet-stream";
}

/* A new folder in Outgoing for one share, so files keep their own names. */
static NSString *os_new_outgoing_folder(void) {
    NSString *path = [OS_OUTGOING_DIR stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"shared-%u-%u",
                       (unsigned)[[NSDate date] timeIntervalSince1970], (unsigned)arc4random()]];
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return path;
}

/* Moves (or, failing that, copies) `source` into `folder` as `name`; returns the Send item. */
static NSDictionary *os_file_item(NSString *source, NSString *name, NSString *folder) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *destination;
    NSString *type;
    long long size;

    name = [name lastPathComponent];
    if ([name length] == 0 || [name hasPrefix:@"."]) name = [source lastPathComponent];
    destination = [folder stringByAppendingPathComponent:name];
    if (![manager moveItemAtPath:source toPath:destination error:NULL] &&
        ![manager copyItemAtPath:source toPath:destination error:NULL]) {
        return nil;
    }
    size = [[[manager attributesOfItemAtPath:destination error:NULL] objectForKey:NSFileSize] longLongValue];
    if (size <= 0) return nil;
    type = os_mime_type(name);
    return [NSDictionary dictionaryWithObjectsAndKeys:
            ([type hasPrefix:@"image/"] || [type hasPrefix:@"video/"]) ? @"media" : @"file", @"kind",
            destination, @"path",
            name, @"name",
            type, @"type",
            [NSNumber numberWithLongLong:size], @"size", nil];
}

static NSString *os_query_value(NSURL *url, NSString *key) {
    for (NSString *pair in [[url query] componentsSeparatedByString:@"&"]) {
        NSRange equals = [pair rangeOfString:@"="];
        if (equals.location != NSNotFound && [[pair substringToIndex:equals.location] isEqualToString:key]) {
            return [[pair substringFromIndex:equals.location + 1]
                    stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        }
    }
    return nil;
}

@implementation OSShareInbox

+ (BOOL)canHandleURL:(NSURL *)url {
    NSString *scheme = [[url scheme] lowercaseString];
    return [scheme isEqualToString:@"oldsend"] || [url isFileURL];
}

+ (NSArray *)itemsForOpenedFile:(NSURL *)url {
    NSString *path = [[url path] stringByStandardizingPath];
    NSDictionary *item;

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return [NSArray array];
    /* "Open in…" leaves a copy in an Inbox folder; it is moved out of there. */
    item = os_file_item(path, [path lastPathComponent], os_new_outgoing_folder());
    return item != nil ? [NSArray arrayWithObject:item] : [NSArray array];
}

+ (NSArray *)itemsForShareFolder:(NSString *)directory {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSMutableArray *items = [NSMutableArray array];
    NSString *folder = nil;
    NSArray *manifest;

    /* Only folders written by the add-on: named OldSendShare-*, in an app's temporary directory,
       which is inside the mobile user's data for App Store apps and /tmp for system apps like
       Safari. */
    directory = [directory stringByStandardizingPath];
    if ([directory rangeOfString:@"/../"].location != NSNotFound ||
        ![[directory lastPathComponent] hasPrefix:@"OldSendShare-"]) {
        return items;
    }
    {
        static NSString * const allowed[] = { @"/var/mobile/", @"/private/var/mobile/", @"/tmp/",
                                               @"/private/tmp/", @"/var/tmp/", @"/private/var/tmp/" };
        BOOL inside = NO;
        unsigned i;
        for (i = 0; i < sizeof allowed / sizeof allowed[0]; i++) {
            if ([directory hasPrefix:allowed[i]]) inside = YES;
        }
        if (!inside) return items;
    }
    manifest = [NSArray arrayWithContentsOfFile:[directory stringByAppendingPathComponent:@"manifest.plist"]];

    for (NSDictionary *entry in manifest) {
        NSString *kind;

        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        kind = [entry objectForKey:@"kind"];
        if ([kind isEqualToString:@"text"]) {
            NSString *text = [entry objectForKey:@"text"];
            if ([text isKindOfClass:[NSString class]] && [text length] > 0) {
                [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"text", @"kind", text, @"text", nil]];
            }
        } else if ([kind isEqualToString:@"file"]) {
            NSString *file = [[entry objectForKey:@"file"] lastPathComponent];
            NSString *source = [directory stringByAppendingPathComponent:file];
            NSDictionary *item;

            if ([file length] == 0 || ![manager fileExistsAtPath:source]) continue;
            if (folder == nil) folder = os_new_outgoing_folder();
            item = os_file_item(source, [entry objectForKey:@"name"], folder);
            if (item != nil) [items addObject:item];
        }
    }
    [manager removeItemAtPath:directory error:NULL];
    return items;
}

+ (NSArray *)itemsForURL:(NSURL *)url {
    [[NSFileManager defaultManager] createDirectoryAtPath:OS_OUTGOING_DIR
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    if ([url isFileURL]) return [self itemsForOpenedFile:url];
    if ([[[url host] lowercaseString] isEqualToString:@"share"]) {
        NSString *directory = os_query_value(url, @"dir");
        if ([directory length] > 0) return [self itemsForShareFolder:directory];
    }
    return [NSArray array];
}

@end

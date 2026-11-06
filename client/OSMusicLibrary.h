#import <Foundation/Foundation.h>

/* Settings > Save to Music: move received songs into the Music app's library (default on). */
BOOL OSAddToMusicEnabled(void);

/* YES for the audio file types the Music app can hold: MP3, AAC/ALAC in .m4a, .m4b audiobooks,
   ADTS .aac, and WAV, AIFF and CAF (as they are if iOS plays them, as Apple Lossless if not).
   FLAC, Ogg, Opus and the like are not: they stay in History. Looks at the extension only. */
BOOL OSIsMusicFile(NSString *path);

typedef enum {
    OSMusicAdded = 0,        /* in the Music app now; the file at path is gone (moved) */
    OSMusicNotSupported,     /* not audio iOS can play (or it has video): left where it is */
    OSMusicFailed            /* the library or the file system said no: left where it is */
} OSMusicResult;

/* Adds the file to the Music app's library the way the iTunes Store app adds a download:
   the file moves into iTunes_Control/Music/Fxx, and MusicLibrary.framework's own importer
   (ML3TrackImporter) writes the track, with its tags and artwork, into MediaLibrary.sqlitedb.
   Blocks (reads tags, writes the database): call it off the main thread. One import at a time
   across OldSend's processes (the app and the background service). */
OSMusicResult OSAddFileToMusic(NSString *path, NSString **detail);

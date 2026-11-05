#import <Foundation/Foundation.h>

/* Turns what other apps hand to OldSend into Send-tab items (dictionaries with "kind" text,
   media or file, as SendViewController keeps them):

   - oldsend://share?dir=<folder>: from the OldSend share-sheet add-on (share/), which writes
     the shared items and a manifest.plist into a folder in the sharing app's temporary directory.
   - a file:// URL: a file opened in OldSend with "Open in…".

   Files are moved or copied into /var/mobile/Library/OldSend/Outgoing, keeping their names. */
@interface OSShareInbox : NSObject

+ (BOOL)canHandleURL:(NSURL *)url;
+ (NSArray *)itemsForURL:(NSURL *)url;

@end

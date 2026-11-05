/* OldSendShare: adds an "OldSend" button to the iOS 6 share sheet (UIActivityViewController) in
   every app, so links, text, photos, videos and files can be sent with OldSend from anywhere.

   Loaded into UIKit apps by MobileSubstrate (OldSendShare.plist), but uses only the Objective-C
   runtime, no Substrate API. Tapping the button writes the shared items and a manifest.plist into
   a folder in the app's own temporary directory (writable even for sandboxed apps), then opens
   oldsend://share?dir=<folder>; OldSend (client/OSShareInbox.m) takes the items from there and
   opens its Send tab with them. */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <notify.h>

#import "OSShareIcon.h"

/* AssetsLibrary is only loaded when a shared item is a Photos asset, so most apps never load it.
   These protocols stand in for its headers (typed, so e.g. -size cannot resolve to UIImage's). */
@protocol OSAssetRepresentation <NSObject>
- (NSString *)filename;
- (long long)size;
- (NSUInteger)getBytes:(uint8_t *)buffer fromOffset:(long long)offset length:(NSUInteger)length error:(NSError **)error;
@end

@protocol OSAsset <NSObject>
- (id<OSAssetRepresentation>)defaultRepresentation;
@end

@protocol OSAssetsLibrary <NSObject>
- (void)assetForURL:(NSURL *)url resultBlock:(void (^)(id<OSAsset> asset))result failureBlock:(void (^)(NSError *error))failure;
@end

@interface OSShareActivity : UIActivity {
    NSArray *_items;
    NSString *_folder;
    NSMutableArray *_manifest;
    NSInteger _pendingAssets;
    id<OSAssetsLibrary> _library;
    NSUInteger _imageCount;
}
@end

static BOOL os_is_supported(id item) {
    if ([item isKindOfClass:[NSString class]] || [item isKindOfClass:[NSAttributedString class]] ||
        [item isKindOfClass:[UIImage class]] || [item isKindOfClass:[NSData class]]) {
        return YES;
    }
    return [item isKindOfClass:[NSURL class]];
}

@implementation OSShareActivity

- (NSString *)activityType {
    return @"com.lihaoyun6.oldsend.share";
}

- (NSString *)activityTitle {
    return @"OldSend";
}

- (UIImage *)activityImage {
    BOOL retina = [[UIScreen mainScreen] scale] > 1.5f;
    NSData *data = retina ? [NSData dataWithBytes:kOSShareIcon2x length:sizeof kOSShareIcon2x]
                          : [NSData dataWithBytes:kOSShareIcon1x length:sizeof kOSShareIcon1x];
    return [UIImage imageWithData:data scale:retina ? 2.0f : 1.0f];
}

- (BOOL)canPerformWithActivityItems:(NSArray *)activityItems {
    for (id item in activityItems) {
        if (os_is_supported(item)) return YES;
    }
    return NO;
}

- (void)prepareWithActivityItems:(NSArray *)activityItems {
    NSMutableArray *classes = [NSMutableArray array];
    for (id item in activityItems) [classes addObject:NSStringFromClass([item class])];
    NSLog(@"OldSendShare: sharing %@", [classes componentsJoinedByString:@", "]);
    [_items release];
    _items = [activityItems copy];
}

- (NSString *)fileNameForImage {
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setDateFormat:@"yyyyMMdd_HHmmss"];
    _imageCount++;
    return [NSString stringWithFormat:@"IMG_%@%@.jpg", [formatter stringFromDate:[NSDate date]],
            _imageCount > 1 ? [NSString stringWithFormat:@"_%u", (unsigned)_imageCount] : @""];
}

- (void)addFileWithData:(NSData *)data name:(NSString *)name {
    NSString *file = [NSString stringWithFormat:@"%u-%@", (unsigned)[_manifest count], name];
    if ([data writeToFile:[_folder stringByAppendingPathComponent:file] atomically:NO]) {
        [_manifest addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                              @"file", @"kind", file, @"file", name, @"name", nil]];
    }
}

- (void)addFileAtPath:(NSString *)path {
    NSString *name = [path lastPathComponent];
    NSString *file = [NSString stringWithFormat:@"%u-%@", (unsigned)[_manifest count], name];
    if ([[NSFileManager defaultManager] copyItemAtPath:path
                                                toPath:[_folder stringByAppendingPathComponent:file]
                                                 error:NULL]) {
        [_manifest addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                              @"file", @"kind", file, @"file", name, @"name", nil]];
    }
}

- (void)addText:(NSString *)text {
    if ([text length] == 0) return;
    [_manifest addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"text", @"kind", text, @"text", nil]];
}

/* Copies a Photos asset (assets-library:// URL) into the folder, off the main thread. */
- (void)addAssetURL:(NSURL *)url {
    Class libraryClass;

    if (_library == nil) {
        dlopen("/System/Library/Frameworks/AssetsLibrary.framework/AssetsLibrary", RTLD_LAZY);
        libraryClass = NSClassFromString(@"ALAssetsLibrary");
        if (libraryClass == Nil) return;
        _library = (id<OSAssetsLibrary>)[[libraryClass alloc] init];
    }
    _pendingAssets++;
    /* A placeholder keeps the manifest in the order things were shared. */
    NSUInteger slot = [_manifest count];
    [_manifest addObject:[NSNull null]];
    [self retain];
    [_library assetForURL:url resultBlock:^(id<OSAsset> asset) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSDictionary *entry = nil;
            id<OSAssetRepresentation> representation = [asset defaultRepresentation];
            NSString *name = [representation filename];
            if (representation != nil && [name length] > 0) {
                NSString *file = [NSString stringWithFormat:@"%u-%@", (unsigned)slot, name];
                NSString *path = [_folder stringByAppendingPathComponent:file];
                FILE *out = fopen([path fileSystemRepresentation], "wb");
                if (out != NULL) {
                    uint8_t *buffer = malloc(256 * 1024);
                    long long offset = 0, size = [representation size];
                    BOOL ok = buffer != NULL;
                    while (ok && offset < size) {
                        NSUInteger read = [representation getBytes:buffer fromOffset:offset
                                                            length:256 * 1024 error:NULL];
                        if (read == 0 || fwrite(buffer, 1, read, out) != read) ok = NO;
                        offset += read;
                    }
                    free(buffer);
                    fclose(out);
                    if (ok) {
                        entry = [NSDictionary dictionaryWithObjectsAndKeys:
                                 @"file", @"kind", file, @"file", name, @"name", nil];
                    }
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (entry != nil) [_manifest replaceObjectAtIndex:slot withObject:entry];
                [self assetDone];
            });
        });
    } failureBlock:^(NSError *error) {
        NSLog(@"OldSendShare: cannot read %@: %@", url, error);
        [self assetDone];
    }];
}

- (void)assetDone {
    _pendingAssets--;
    if (_pendingAssets == 0) [self handOver];
    [self release];
}

- (void)performActivity {
    NSString *folderName = [NSString stringWithFormat:@"OldSendShare-%u-%u",
                            (unsigned)[[NSDate date] timeIntervalSince1970], (unsigned)arc4random()];

    [_folder release];
    _folder = [[NSTemporaryDirectory() stringByAppendingPathComponent:folderName] retain];
    [[NSFileManager defaultManager] createDirectoryAtPath:_folder
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    [_manifest release];
    _manifest = [[NSMutableArray alloc] init];
    _pendingAssets = 1;  /* held until every item is queued */
    _imageCount = 0;

    for (id item in _items) {
        if ([item isKindOfClass:[NSAttributedString class]]) {
            [self addText:[item string]];
        } else if ([item isKindOfClass:[NSString class]]) {
            [self addText:item];
        } else if ([item isKindOfClass:[UIImage class]]) {
            NSData *jpeg = UIImageJPEGRepresentation(item, 0.92f);
            if (jpeg != nil) [self addFileWithData:jpeg name:[self fileNameForImage]];
        } else if ([item isKindOfClass:[NSData class]]) {
            [self addFileWithData:item name:@"Shared file"];
        } else if ([item isKindOfClass:[NSURL class]]) {
            NSURL *url = item;
            if ([url isFileURL]) {
                [self addFileAtPath:[url path]];
            } else if ([[[url scheme] lowercaseString] isEqualToString:@"assets-library"]) {
                [self addAssetURL:url];
            } else {
                [self addText:[url absoluteString]];
            }
        }
    }
    [self retain];
    [self assetDone];
}

- (void)handOver {
    NSMutableArray *entries = [NSMutableArray array];
    NSString *escaped;
    NSURL *url;

    for (id entry in _manifest) {
        if ([entry isKindOfClass:[NSDictionary class]]) [entries addObject:entry];
    }
    [entries writeToFile:[_folder stringByAppendingPathComponent:@"manifest.plist"] atomically:YES];
    escaped = [(NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)_folder, NULL,
                                                                  CFSTR("!*'();:@&=+$,/?%#[] "),
                                                                  kCFStringEncodingUTF8) autorelease];
    url = [NSURL URLWithString:[@"oldsend://share?dir=" stringByAppendingString:escaped]];
    if ([entries count] == 0 || ![[UIApplication sharedApplication] openURL:url]) {
        NSLog(@"OldSendShare: nothing handed over (%u items)", (unsigned)[entries count]);
        [[NSFileManager defaultManager] removeItemAtPath:_folder error:NULL];
        [self activityDidFinish:NO];
        return;
    }
    [self activityDidFinish:YES];
}

- (void)dealloc {
    [_items release];
    [_folder release];
    [_manifest release];
    [_library release];
    [super dealloc];
}

@end

static id (*os_original_init)(id, SEL, NSArray *, NSArray *);

static id os_init_with_items(id self, SEL _cmd, NSArray *items, NSArray *activities) {
    NSMutableArray *list = activities != nil ? [NSMutableArray arrayWithArray:activities] : [NSMutableArray array];
    OSShareActivity *activity = [[OSShareActivity alloc] init];
    [list addObject:activity];
    [activity release];
    return os_original_init(self, _cmd, items, list);
}

/* In SpringBoard: post the notifications OldSend's background service queues as
   /var/mobile/Library/OldSend/daemon/notify-*.plist. A process without an app of its own cannot
   post an app's notification, so SpringBoard schedules them as OldSend's local notifications;
   tapping one opens OldSend. */
@interface NSObject (OSSpringBoard)
+ (id)sharedInstance;
- (id)applicationWithDisplayIdentifier:(NSString *)identifier;
- (void)scheduleLocalNotifications:(NSArray *)notifications replaceExistingNotifications:(BOOL)replace;
@end

static void os_post_service_notifications(void) {
    NSString *directory = @"/var/mobile/Library/OldSend/daemon";
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *names = [[manager contentsOfDirectoryAtPath:directory error:NULL]
                      sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *notifications = [NSMutableArray array];
    Class controller = NSClassFromString(@"SBApplicationController");
    id app;

    for (NSString *name in names) {
        NSString *path;
        NSString *body;
        UILocalNotification *notification;

        if (![name hasPrefix:@"notify-"]) continue;
        path = [directory stringByAppendingPathComponent:name];
        body = [[NSDictionary dictionaryWithContentsOfFile:path] objectForKey:@"body"];
        [manager removeItemAtPath:path error:NULL];
        if (![body isKindOfClass:[NSString class]] || [body length] == 0) continue;
        notification = [[[UILocalNotification alloc] init] autorelease];
        notification.fireDate = [NSDate dateWithTimeIntervalSinceNow:0.5];
        notification.alertBody = body;
        notification.soundName = UILocalNotificationDefaultSoundName;
        [notifications addObject:notification];
    }
    if ([notifications count] == 0 || controller == Nil) return;
    app = [[controller sharedInstance] applicationWithDisplayIdentifier:@"com.lihaoyun6.oldsend"];
    if ([app respondsToSelector:@selector(scheduleLocalNotifications:replaceExistingNotifications:)]) {
        [app scheduleLocalNotifications:notifications replaceExistingNotifications:NO];
    }
}

__attribute__((constructor)) static void os_share_init(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *bundle = [[NSBundle mainBundle] bundleIdentifier];
    Class controller = NSClassFromString(@"UIActivityViewController");
    Method method;

    if ([bundle isEqualToString:@"com.apple.springboard"]) {
        int token;
        notify_register_dispatch("com.lihaoyun6.oldsend.notify", &token, dispatch_get_main_queue(), ^(int t) {
            NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
            os_post_service_notifications();
            [inner release];
        });
    }

    if (controller != Nil && ![bundle isEqualToString:@"com.lihaoyun6.oldsend"]) {
        method = class_getInstanceMethod(controller, @selector(initWithActivityItems:applicationActivities:));
        if (method != NULL) {
            os_original_init = (id (*)(id, SEL, NSArray *, NSArray *))
                method_setImplementation(method, (IMP)os_init_with_items);
        }
    }
    [pool release];
}

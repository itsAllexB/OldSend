#import "OSDaemon.h"
#import "OSServer.h"
#import "OSTransfer.h"
#import <UIKit/UIKit.h>
#include <notify.h>
#include <dlfcn.h>
#include <signal.h>
#include <unistd.h>

#define OS_NOTE_APP       "com.lihaoyun6.oldsend.app"             /* state: app pid in the foreground, else 0 */
#define OS_NOTE_CHANGED   "com.lihaoyun6.oldsend.daemon.changed"  /* service -> app: request/transfer/texts */
#define OS_NOTE_DECISION  "com.lihaoyun6.oldsend.decision"        /* app -> service: decision.plist written */
#define OS_NOTE_CANCEL    "com.lihaoyun6.oldsend.cancel"          /* app -> service: cancel the transfer */
#define OS_NOTE_SETTINGS  "com.lihaoyun6.oldsend.settings"        /* app -> service: settings changed */
#define OS_NOTE_NOTIFY    "com.lihaoyun6.oldsend.notify"          /* service -> SpringBoard: notify-*.plist */

#define OS_REQUEST_PATH   OS_DAEMON_DIR @"/request.plist"
#define OS_DECISION_PATH  OS_DAEMON_DIR @"/decision.plist"
#define OS_TRANSFER_PATH  OS_DAEMON_DIR @"/transfer.plist"
#define OS_TEXTS_PATH     OS_DAEMON_DIR @"/texts.plist"

static BOOL gHeadless = NO;

BOOL OSIsHeadless(void) {
    return gHeadless;
}

void OSSetHeadless(BOOL headless) {
    gHeadless = headless;
}

static void os_ensure_dir(void) {
    [[NSFileManager defaultManager] createDirectoryAtPath:OS_DAEMON_DIR
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
}

BOOL OSDaemonEnabled(void) {
    return [[NSFileManager defaultManager] fileExistsAtPath:OS_DAEMON_FLAG];
}

void OSSetDaemonEnabled(BOOL enabled) {
    os_ensure_dir();
    if (enabled) {
        [[NSData data] writeToFile:OS_DAEMON_FLAG atomically:YES];
    } else {
        [[NSFileManager defaultManager] removeItemAtPath:OS_DAEMON_FLAG error:NULL];
    }
    notify_post(OS_NOTE_SETTINGS);
}

static void os_post(const char *name) {
    notify_post(name);
}

/* The app's foreground pid lives in the state of a Darwin notification name. notifyd forgets a
   name's state once nobody is registered for it, so both processes keep one registration open. */
static int os_app_state_token(void) {
    static int token = -1;
    if (token == -1 && notify_register_check(OS_NOTE_APP, &token) != NOTIFY_STATUS_OK) token = -1;
    return token;
}

#pragma mark - Service side

BOOL OSDaemonAppIsActive(void) {
    int token = os_app_state_token();
    uint64_t pid = 0;

    if (token == -1) return NO;
    notify_get_state(token, &pid);
    /* A crashed app leaves its pid behind; only a live process counts. */
    return pid > 0 && kill((pid_t)pid, 0) == 0;
}

/* A notify-*.plist for OldSend's add-on in SpringBoard (share/OldSendShare.m) to act on. */
static void os_queue_notification(NSDictionary *item) {
    NSString *path;

    os_ensure_dir();
    path = [OS_DAEMON_DIR stringByAppendingPathComponent:
            [NSString stringWithFormat:@"notify-%.3f-%u.plist",
             [NSDate timeIntervalSinceReferenceDate], (unsigned)arc4random()]];
    [item writeToFile:path atomically:YES];
    os_post(OS_NOTE_NOTIFY);
}

void OSDaemonNotify(NSString *body) {
    if (!gHeadless || [body length] == 0 || OSDaemonAppIsActive()) return;
    os_queue_notification([NSDictionary dictionaryWithObject:body forKey:@"body"]);
}

static volatile BOOL gDecisionWaiting = NO;

BOOL OSDaemonAsk(NSString *title, NSString *message, NSString *notificationBody) {
    NSString *identifier = [NSString stringWithFormat:@"%.3f-%u",
                            [NSDate timeIntervalSinceReferenceDate], (unsigned)arc4random()];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:120];
    BOOL accepted = NO;

    os_ensure_dir();
    [[NSFileManager defaultManager] removeItemAtPath:OS_DECISION_PATH error:NULL];
    [[NSDictionary dictionaryWithObjectsAndKeys:identifier, @"id", title, @"title",
      message != nil ? message : @"", @"message", nil] writeToFile:OS_REQUEST_PATH atomically:YES];
    gDecisionWaiting = YES;
    os_post(OS_NOTE_CHANGED);
    if (gHeadless && [notificationBody length] > 0 && !OSDaemonAppIsActive()) {
        os_queue_notification([NSDictionary dictionaryWithObjectsAndKeys:notificationBody, @"body",
                               [NSNumber numberWithBool:YES], @"request", nil]);
    }

    while ([deadline timeIntervalSinceNow] > 0) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSDictionary *decision = [NSDictionary dictionaryWithContentsOfFile:OS_DECISION_PATH];
        BOOL answered = [[decision objectForKey:@"id"] isEqual:identifier];
        if (answered) accepted = [[decision objectForKey:@"accepted"] boolValue];
        [pool release];
        if (answered) break;
        if (OSSenderGaveUp()) {
            [[OSServer shared] appendLog:@"The sender gave up while waiting for an answer"];
            break;
        }
        usleep(250000);
    }
    gDecisionWaiting = NO;
    /* The request is answered or gone: "Tap to accept" shouldn't stay in Notification Center. */
    os_queue_notification([NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"withdraw"]);
    [[NSFileManager defaultManager] removeItemAtPath:OS_REQUEST_PATH error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:OS_DECISION_PATH error:NULL];
    os_post(OS_NOTE_CHANGED);
    return accepted;
}

void OSDaemonPublishTransfer(OSTransfer *transfer) {
    if (!gHeadless || transfer == nil) return;
    os_ensure_dir();
    [[transfer snapshot] writeToFile:OS_TRANSFER_PATH atomically:YES];
    os_post(OS_NOTE_CHANGED);
}

void OSDaemonAddTexts(NSArray *texts, NSString *notificationBody) {
    NSMutableArray *all;

    if (!gHeadless || [texts count] == 0) return;
    os_ensure_dir();
    all = [NSMutableArray arrayWithContentsOfFile:OS_TEXTS_PATH];
    if (all == nil) all = [NSMutableArray array];
    [all addObjectsFromArray:texts];
    [all writeToFile:OS_TEXTS_PATH atomically:YES];
    os_post(OS_NOTE_CHANGED);
    OSDaemonNotify(notificationBody);
}

/* IOKit power assertions, looked up at run time (no IOKit headers in the iOS SDK). */
typedef int (*OSAssertionCreate)(CFStringRef type, uint32_t level, CFStringRef name, uint32_t *assertion);
typedef int (*OSAssertionRelease)(uint32_t assertion);

void OSDaemonHoldAwake(BOOL hold) {
    static uint32_t assertion = 0;
    static OSAssertionCreate create = NULL;
    static OSAssertionRelease release = NULL;

    if (create == NULL) {
        void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        if (iokit == NULL) return;
        create = (OSAssertionCreate)dlsym(iokit, "IOPMAssertionCreateWithName");
        release = (OSAssertionRelease)dlsym(iokit, "IOPMAssertionRelease");
        if (create == NULL || release == NULL) {
            create = NULL;
            return;
        }
    }
    if (hold && assertion == 0) {
        create(CFSTR("NoIdleSleepAssertion"), 255, CFSTR("OldSend transfer"), &assertion);
    } else if (!hold && assertion != 0) {
        release(assertion);
        assertion = 0;
    }
}

@interface OSDaemonService : NSObject
- (void)tick:(NSTimer *)timer;
@end

@implementation OSDaemonService

/* Serve while the app is not in the foreground; let the app have the port (once nothing is
   running here) while it is. Leave when Run in Background is turned off. */
- (void)tick:(NSTimer *)timer {
    OSServer *server = [OSServer shared];
    BOOL busy = [server hasActiveSession] || gDecisionWaiting || [server savingText] != nil;

    if (!OSDaemonEnabled() && !busy) {
        [server appendLog:@"Run in Background turned off, stopping"];
        exit(0);
    }
    if (OSDaemonAppIsActive()) {
        if (!busy && ![server isPaused]) {
            [server appendLog:@"OldSend is open, handing over"];
            [server setPaused:YES];
        }
    } else if ([server isPaused]) {
        [server appendLog:@"OldSend is closed, serving in the background"];
        [server setPaused:NO];
    }
}

@end

int OSDaemonMain(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    OSDaemonService *service;
    OSServer *server;
    int token;

    gHeadless = YES;
    signal(SIGPIPE, SIG_IGN);
    if (!OSDaemonEnabled()) {
        /* launchd only starts it while the flag exists, but be safe. */
        [pool release];
        return 0;
    }

    /* A previous run may have died with a request or transfer on file. */
    [[NSFileManager defaultManager] removeItemAtPath:OS_REQUEST_PATH error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:OS_DECISION_PATH error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:OS_TRANSFER_PATH error:NULL];

    service = [[OSDaemonService alloc] init];
    server = [OSServer shared];
    [server setPaused:OSDaemonAppIsActive()];
    [server start];

    notify_register_dispatch(OS_NOTE_APP, &token, dispatch_get_main_queue(), ^(int t) {
        [service tick:nil];
    });
    notify_register_dispatch(OS_NOTE_SETTINGS, &token, dispatch_get_main_queue(), ^(int t) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *alias;
        [defaults synchronize];
        alias = [defaults stringForKey:@"device_alias"];
        if ([alias length] > 0 && ![alias isEqualToString:[server alias]]) [server setAlias:alias];
        [service tick:nil];
    });
    notify_register_dispatch(OS_NOTE_CANCEL, &token, dispatch_get_main_queue(), ^(int t) {
        [server cancelReceiving];
    });
    /* Joined another network (or lost it): reopen the sockets, rejoin multicast, announce. */
    notify_register_dispatch("com.apple.system.config.network_change", &token, dispatch_get_main_queue(), ^(int t) {
        [server resume];
    });

    [NSTimer scheduledTimerWithTimeInterval:3.0 target:service selector:@selector(tick:) userInfo:nil repeats:YES];
    [server appendLog:@"Background service started"];
    CFRunLoopRun();

    [service release];
    [pool release];
    return 0;
}

#pragma mark - App side

@interface OSDaemonClient () <UIAlertViewDelegate>
@end

@implementation OSDaemonClient

+ (OSDaemonClient *)shared {
    static OSDaemonClient *client = nil;
    if (client == nil) client = [[OSDaemonClient alloc] init];
    return client;
}

- (id)init {
    if ((self = [super init])) {
        int token;
        notify_register_dispatch(OS_NOTE_CHANGED, &_changedToken, dispatch_get_main_queue(), ^(int t) {
            [self serviceChanged];
        });
        notify_register_dispatch("com.apple.system.config.network_change", &token, dispatch_get_main_queue(), ^(int t) {
            if (![[OSServer shared] isPaused]) [[OSServer shared] resume];
        });
    }
    return self;
}

- (void)publishActive:(BOOL)active {
    int token = os_app_state_token();
    if (token != -1) notify_set_state(token, active ? (uint64_t)getpid() : 0);
    os_post(OS_NOTE_APP);
}

- (void)appDidBecomeActive {
    [_pauseTimer invalidate];
    [_pauseTimer release];
    _pauseTimer = nil;
    [self publishActive:YES];
    [[OSServer shared] setPaused:NO];
    if (OSDaemonEnabled()) {
        /* Photos received by the service are copied into Photos by the app. */
        [[OSServer shared] retryPendingPhotos];
    }
    [self serviceChanged];
}

- (void)pauseWhenIdle:(NSTimer *)timer {
    OSServer *server = [OSServer shared];
    if ([server hasActiveSession]) return;  /* finish the transfer first (background time) */
    [server setPaused:YES];
    [self publishActive:NO];
    [_pauseTimer invalidate];
    [_pauseTimer release];
    _pauseTimer = nil;
}

- (void)appDidEnterBackground {
    if (!OSDaemonEnabled()) {
        [self publishActive:NO];
        return;
    }
    /* Hand the port to the service. */
    [self pauseWhenIdle:nil];
    if ([[OSServer shared] hasActiveSession] && _pauseTimer == nil) {
        _pauseTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(pauseWhenIdle:)
                                                      userInfo:nil repeats:YES] retain];
    }
}

- (void)appWillTerminate {
    [self publishActive:NO];
}

- (void)backgroundTimeExpired {
    /* iOS is about to suspend the app; a transfer still running here cannot finish. Stop it and
       hand over now, or the suspended app would keep the service paused. */
    if (!OSDaemonEnabled()) return;
    if ([[OSServer shared] hasActiveSession]) {
        [[OSServer shared] cancelSending];
        [[OSServer shared] cancelReceiving];
    }
    [[OSServer shared] setPaused:YES];
    [self publishActive:NO];
    [_pauseTimer invalidate];
    [_pauseTimer release];
    _pauseTimer = nil;
}

- (void)settingsChanged {
    os_post(OS_NOTE_SETTINGS);
}

- (void)cancelRemoteTransfer {
    os_post(OS_NOTE_CANCEL);
}

- (void)serviceChanged {
    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) return;
    [self showRequestIfAny];
    [self mirrorTransfer];
    [self showTexts];
}

- (void)showRequestIfAny {
    NSDictionary *request = [NSDictionary dictionaryWithContentsOfFile:OS_REQUEST_PATH];
    NSString *identifier = [request objectForKey:@"id"];

    if (identifier == nil) {
        /* Answered elsewhere or timed out. */
        if (_requestAlert != nil) {
            UIAlertView *alert = _requestAlert;
            _requestAlert = nil;
            [alert setDelegate:nil];
            [alert dismissWithClickedButtonIndex:0 animated:YES];
            [alert release];
        }
        return;
    }
    if ([identifier isEqualToString:_shownRequest]) return;
    [_shownRequest release];
    _shownRequest = [identifier copy];
    _requestAlert = [[UIAlertView alloc] initWithTitle:[request objectForKey:@"title"]
                                               message:[request objectForKey:@"message"]
                                              delegate:self
                                     cancelButtonTitle:NSLocalizedString(@"common.decline", nil)
                                     otherButtonTitles:NSLocalizedString(@"common.accept", nil), nil];
    [_requestAlert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView != _requestAlert) return;
    [[NSDictionary dictionaryWithObjectsAndKeys:_shownRequest, @"id",
      [NSNumber numberWithBool:buttonIndex != alertView.cancelButtonIndex], @"accepted", nil]
     writeToFile:OS_DECISION_PATH atomically:YES];
    os_post(OS_NOTE_DECISION);
    [_requestAlert release];
    _requestAlert = nil;
}

- (void)mirrorTransfer {
    NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfFile:OS_TRANSFER_PATH];
    NSString *identifier = [snapshot objectForKey:@"id"];
    OSTransferState state = (OSTransferState)[[snapshot objectForKey:@"state"] intValue];

    if (identifier == nil) return;
    if ([identifier isEqualToString:_remoteTransferId]) {
        [_remoteTransfer applySnapshot:snapshot];
        return;
    }
    /* Only open the screen for a transfer that is still running. */
    if (state != OSTransferStateRunning && state != OSTransferStateWaiting) return;
    [_remoteTransferId release];
    _remoteTransferId = [identifier copy];
    [_remoteTransfer release];
    _remoteTransfer = [[OSTransfer alloc] initWithSnapshot:snapshot];
    [[NSNotificationCenter defaultCenter] postNotificationName:OSTransferDidStartNotification
                                                        object:_remoteTransfer];
}

- (void)showTexts {
    NSArray *texts = [NSArray arrayWithContentsOfFile:OS_TEXTS_PATH];
    if ([texts count] == 0) return;
    [[NSFileManager defaultManager] removeItemAtPath:OS_TEXTS_PATH error:NULL];
    [[NSNotificationCenter defaultCenter] postNotificationName:OSServerDidReceiveTextNotification
                                                        object:[OSServer shared]
                                                      userInfo:[NSDictionary dictionaryWithObject:
                                                                [texts componentsJoinedByString:@"\n\n"]
                                                                                           forKey:@"text"]];
}

@end

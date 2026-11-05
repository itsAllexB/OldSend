#import "AppDelegate.h"
#include <string.h>
#include <netinet/in.h>
#import "ReceiveViewController.h"
#import "SendViewController.h"
#import "FilesViewController.h"
#import "SettingsViewController.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import "OSServer.h"
#import "OSPlatform.h"
#import "OSNavigationController.h"
#import "OSTransfer.h"
#import "TransferViewController.h"
#import "OSShareInbox.h"
#import "OSDaemon.h"

@interface UIWindow (OSRootViewController)
- (void)setRootViewController:(UIViewController *)controller;
@end

@interface OSTabBarController : UITabBarController
@end

@implementation OSTabBarController

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    if (OSIsPad()) return YES;
    return orientation == UIInterfaceOrientationPortrait;
}

- (UIViewController *)visibleContentController {
    UIViewController *controller = self.selectedViewController;
    if ([controller isKindOfClass:[UINavigationController class]]) {
        controller = [(UINavigationController *)controller topViewController];
    }
    return controller;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation
                                         duration:(NSTimeInterval)duration {
    [super willAnimateRotationToInterfaceOrientation:orientation duration:duration];
    [[self visibleContentController] willAnimateRotationToInterfaceOrientation:orientation
                                                                      duration:duration];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation {
    [super didRotateFromInterfaceOrientation:orientation];
    [[self visibleContentController] didRotateFromInterfaceOrientation:orientation];
}

@end

@implementation AppDelegate

static BOOL OSIsWiFiReachable(void) {
    struct sockaddr_in zeroAddress;
    SCNetworkReachabilityRef reachability;
    SCNetworkReachabilityFlags flags = 0;
    BOOL reachable;
    BOOL needsConnection;

    memset(&zeroAddress, 0, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;

    reachability = SCNetworkReachabilityCreateWithAddress(
        NULL, (const struct sockaddr *)&zeroAddress);
    if (reachability == NULL) return YES;

    if (!SCNetworkReachabilityGetFlags(reachability, &flags)) {
        CFRelease(reachability);
        return YES;
    }
    CFRelease(reachability);

    reachable = (flags & kSCNetworkReachabilityFlagsReachable) != 0;
    needsConnection = (flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0;
#if TARGET_OS_IPHONE
    if ((flags & kSCNetworkReachabilityFlagsIsWWAN) != 0) return NO;
#endif
    return reachable && !needsConnection;
}

- (void)showWiFiAlertIfNeeded {
    if (OSIsWiFiReachable()) return;
    if (_wifiAlert != nil) return;

    _wifiAlert = [[UIAlertView alloc]
        initWithTitle:NSLocalizedString(@"wifi.missing_title", nil)
              message:NSLocalizedString(@"wifi.missing_message", nil)
             delegate:self
    cancelButtonTitle:NSLocalizedString(@"common.ok", nil)
    otherButtonTitles:nil];
    [_wifiAlert show];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (alertView == _wifiAlert) {
        [_wifiAlert release];
        _wifiAlert = nil;
        [_window makeKeyAndVisible];
    }
}

- (UINavigationController *)navigationControllerWithController:(UIViewController *)controller
                                                          title:(NSString *)title
                                                          image:(NSString *)image
                                                     systemItem:(NSInteger)systemItem
                                                            tag:(NSInteger)tag {
    UINavigationController *navigation = [[OSNavigationController alloc]
                                          initWithRootViewController:controller];
    UITabBarItem *item;

    if (image == nil) {
        item = [[UITabBarItem alloc] initWithTabBarSystemItem:(UITabBarSystemItem)systemItem
                                                          tag:tag];
        item.title = title;
    } else {
        item = [[UITabBarItem alloc] initWithTitle:title
                                            image:[UIImage imageNamed:image]
                                              tag:tag];
    }
    navigation.tabBarItem = item;
    [item release];
    return [navigation autorelease];
}

/* The ...WithOptions variant, so that a URL OldSend is launched with (share sheet, "Open in…")
   is then delivered to application:openURL:sourceApplication:annotation:. */
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    ReceiveViewController *receive = [[ReceiveViewController alloc] init];
    SendViewController *send = [[SendViewController alloc] init];
    FilesViewController *files = [[FilesViewController alloc] init];
    SettingsViewController *settings = [[SettingsViewController alloc] init];

    UINavigationController *receiveNavigation =
        [self navigationControllerWithController:receive
                                           title:NSLocalizedString(@"tab.receive", nil)
                                           image:@"TabReceive.png"
                                      systemItem:-1
                                             tag:0];
    UINavigationController *sendNavigation =
        [self navigationControllerWithController:send
                                           title:NSLocalizedString(@"tab.send", nil)
                                           image:@"TabSend.png"
                                      systemItem:-1
                                             tag:1];
    UINavigationController *filesNavigation =
        [self navigationControllerWithController:files
                                           title:NSLocalizedString(@"tab.files", nil)
                                           image:@"TabHistory.png"
                                      systemItem:-1
                                             tag:2];
    UINavigationController *settingsNavigation =
        [self navigationControllerWithController:settings
                                           title:NSLocalizedString(@"tab.settings", nil)
                                           image:@"TabSettings.png"
                                      systemItem:-1
                                             tag:3];

    [receive release];
    [send release];
    [files release];
    [settings release];

    _tabs = [[OSTabBarController alloc] init];
    _tabs.viewControllers = [NSArray arrayWithObjects:
                             receiveNavigation, sendNavigation, filesNavigation,
                             settingsNavigation, nil];

    if ([_window respondsToSelector:@selector(setRootViewController:)]) {
        [_window setRootViewController:_tabs];
    } else {
        [_window addSubview:_tabs.view];
    }
    [_window makeKeyAndVisible];

    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    _backgroundTask = UIBackgroundTaskInvalid;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(transferDidStart:)
                                                 name:OSTransferDidStartNotification
                                               object:nil];
    [[OSServer shared] start];

    [self performSelector:@selector(showWiFiAlertIfNeeded)
               withObject:nil
               afterDelay:1.5];
    return YES;
}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation {
    NSArray *items;
    UINavigationController *sendNavigation;
    UIViewController *modal;

    if (![OSShareInbox canHandleURL:url]) return NO;
    items = [OSShareInbox itemsForURL:url];
    [[OSServer shared] appendLog:[NSString stringWithFormat:@"Shared from %@: %d item(s)",
                                  sourceApplication != nil ? sourceApplication : @"?", (int)[items count]]];

    /* Show the Send tab with the shared items, on top of nothing but a running transfer. */
    modal = _tabs.modalViewController;
    if (modal != nil) {
        UIViewController *top = [modal isKindOfClass:[UINavigationController class]]
                              ? [(UINavigationController *)modal topViewController] : modal;
        if (!([top isKindOfClass:[TransferViewController class]] &&
              [[(TransferViewController *)top transfer] isActive])) {
            [_tabs dismissModalViewControllerAnimated:NO];
        }
    }
    _tabs.selectedIndex = 1;
    sendNavigation = (UINavigationController *)_tabs.selectedViewController;
    [sendNavigation popToRootViewControllerAnimated:NO];
    if ([[sendNavigation.viewControllers objectAtIndex:0] respondsToSelector:@selector(addSharedItems:)]) {
        [(SendViewController *)[sendNavigation.viewControllers objectAtIndex:0] addSharedItems:items];
    }
    return YES;
}

- (void)transferDidStart:(NSNotification *)notification {
    TransferViewController *controller = [[TransferViewController alloc] initWithTransfer:[notification object]];
    UINavigationController *navigation = [[OSNavigationController alloc] initWithRootViewController:controller];
    UIViewController *presenter = _tabs;

    /* On top of whatever is open (a picker, the text viewer, another transfer). */
    while (presenter.modalViewController != nil) {
        presenter = presenter.modalViewController;
    }
    [presenter presentModalViewController:navigation animated:YES];
    [controller release];
    [navigation release];
}

- (void)endBackgroundTask {
    if (_backgroundTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
        _backgroundTask = UIBackgroundTaskInvalid;
    }
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    /* Ask iOS for its usual few minutes of background time, so a running transfer can finish
       and OldSend stays reachable for a while after switching apps. */
    [self endBackgroundTask];
    _backgroundTask = [application beginBackgroundTaskWithExpirationHandler:^{
        [[OSServer shared] appendLog:@"Background time is up"];
        [self endBackgroundTask];
    }];
    /* With Run in Background on, the background service takes over (once a transfer is done). */
    [[OSDaemonClient shared] appDidEnterBackground];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    [[OSDaemonClient shared] appDidBecomeActive];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    [self endBackgroundTask];
    /* If iOS suspended the app, it may have reclaimed the server's sockets. */
    [[OSServer shared] resume];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    [[OSDaemonClient shared] appWillTerminate];
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    [[OSServer shared] stop];
}

- (void)dealloc {
    [_wifiAlert release];
    [_tabs release];
    [_window release];
    [super dealloc];
}

@end

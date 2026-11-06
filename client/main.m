/* Changed by itsAllexB from OldSend by lihaoyun6; the changes are in the git history. */
#import <UIKit/UIKit.h>
#include <string.h>
#import "AppDelegate.h"
#import "OSDaemon.h"

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool;
    int ret;

    /* launchd starts the same binary as the background service (Settings > Run in Background). */
    if (argc > 1 && strcmp(argv[1], "--daemon") == 0) {
        return OSDaemonMain();
    }

    pool = [[NSAutoreleasePool alloc] init];
    ret = UIApplicationMain(argc, argv, nil, @"AppDelegate");
    [pool release];
    return ret;
}

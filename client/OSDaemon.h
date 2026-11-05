#import <Foundation/Foundation.h>

@class OSTransfer;

/* Run in background (Settings, off by default): the OldSend binary started by launchd with
   --daemon (/Library/LaunchDaemons/com.itsallexb.oldsendd.plist) runs the same LocalSend server
   headless whenever the app is not in the foreground, so the phone stays discoverable and can
   receive with the app closed.

   - On/off: launchd keeps the service alive while OS_DAEMON_FLAG exists (KeepAlive PathState);
     the Settings switch creates or removes it, and the service exits when it is gone.
   - Handover: the app publishes its pid while it is in the foreground (Darwin notification
     com.lihaoyun6.oldsend.app with state). The service then pauses (closes its sockets) once it
     has no session running; the app pauses its own server when it leaves the foreground. Both
     listeners retry binding every second, so the port moves over within a second or two.
   - Requests: without Quick Save, the service writes request.plist and posts a notification
     (through SpringBoard, see share/); tapping it opens the app, which shows the prompt and
     writes decision.plist. The service publishes the transfer in transfer.plist, which the app
     shows on its live transfer screen, and leaves received texts in texts.plist.
   - Battery: no polling beyond 1 s socket timeouts while the phone is awake, a multicast
     announcement only every minute, and a no-idle-sleep assertion only while files are coming in.
     When the phone sleeps, iOS freezes the service like everything else. */

#define OS_DAEMON_DIR @"/var/mobile/Library/OldSend/daemon"
#define OS_DAEMON_FLAG OS_DAEMON_DIR @"/enabled"

/* YES inside the background service. */
BOOL OSIsHeadless(void);
void OSSetHeadless(BOOL headless);
int OSDaemonMain(void);

BOOL OSDaemonEnabled(void);
void OSSetDaemonEnabled(BOOL enabled);

/* Service side. */
BOOL OSDaemonAppIsActive(void);
/* Blocks the calling (network) thread until the user answers in the app, or 2 minutes pass. */
BOOL OSDaemonAsk(NSString *title, NSString *message, NSString *notificationBody);
/* Posts an OldSend notification through SpringBoard, unless the app is in the foreground. */
void OSDaemonNotify(NSString *body);
void OSDaemonPublishTransfer(OSTransfer *transfer);
void OSDaemonAddTexts(NSArray *texts, NSString *notificationBody);
void OSDaemonHoldAwake(BOOL hold);

/* App side. */
@interface OSDaemonClient : NSObject <NSObject> {
    int _changedToken;
    NSString *_shownRequest;
    id _requestAlert;
    OSTransfer *_remoteTransfer;
    NSString *_remoteTransferId;
    NSTimer *_pauseTimer;
}
+ (OSDaemonClient *)shared;
- (void)appDidBecomeActive;
- (void)appDidEnterBackground;
- (void)appWillTerminate;
- (void)backgroundTimeExpired;
- (void)settingsChanged;
- (void)cancelRemoteTransfer;
@end

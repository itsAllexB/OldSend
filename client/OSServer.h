#import <Foundation/Foundation.h>

@class UIAlertView;
@class OSTransfer;

extern NSString * const OSServerDidUpdateNotification;
extern NSString * const OSServerSendDidFinishNotification;
extern NSString * const OSServerSendProgressNotification;
extern NSString * const OSServerDidReceiveTextNotification;

/* Settings > Save to Photos: copy received photos and videos into the Photos app (default on). */
BOOL OSSaveToPhotosEnabled(void);
/* For prompts: the sender closed the connection we are answering. */
BOOL OSSenderGaveUp(void);

@interface OSServer : NSObject {
@private
    volatile BOOL _running;
    BOOL _refreshingDevices;
    NSString *_alias;
    NSString *_model;
    NSString *_fingerprint;
    NSString *_localIP;
    NSString *_status;
    NSMutableArray *_log;
    NSMutableArray *_devices;
    NSTimer *_announceTimer;
    void *_identity;
    NSUInteger _photoSaveToken;
    NSUInteger _photoActiveToken;
    NSString *_photoActivePath;
    NSInteger _savingCount;
    NSInteger _pendingReceiveCompleteCount;
    NSString *_receiveStatus;
    NSCondition *_decisionCondition;
    BOOL _decisionMade;
    BOOL _decisionAccepted;
    UIAlertView *_decisionAlert;
    BOOL _receiving;
    BOOL _sessionActive;
    float _uploadProgress;
    long long _sessionTotalBytes;
    long long _sessionBaseBytes;
    long long _currentFileWritten;
    float _sessionProgress;
    NSString *_uploadName;
    NSMutableArray *_photoQueue;
    BOOL _photoQueueRunning;
    NSMutableArray *_receivedTexts;
    NSTimer *_receiveWatchdog;
    NSTimeInterval _lastReceiveActivity;
    volatile NSUInteger _networkGeneration;
    OSTransfer *_sendTransfer;
    OSTransfer *_receiveTransfer;
    volatile BOOL _paused;
    NSTimer *_publishTimer;
    volatile BOOL _retryingPhotos;
    NSMutableArray *_musicQueue;
    BOOL _musicThreadRunning;
    id _photoLibrary;
    NSInteger _photosTotal;
    NSInteger _photosDone;
    NSInteger _musicTotal;
    NSInteger _musicDone;
    NSMutableArray *_musicKept;
}

+ (OSServer *)shared;
+ (NSString *)localIPAddress;
+ (NSString *)generateAlias;

- (void)start;
- (void)stop;
/* Call when the app returns to the foreground: reopens the sockets iOS may have reclaimed. */
- (void)resume;
/* Paused: no listening, discovery or announcements (the app and the background service hand
   the port to each other this way). */
- (void)setPaused:(BOOL)paused;
- (BOOL)isPaused;
/* A request waiting for an answer, or a transfer running, in either direction. */
- (BOOL)hasActiveSession;
/* Copies received photos/videos not yet in Photos into Photos (if Save to Photos is on), and
   adds received songs not yet in Music to Music (if Save to Music is on, also in the service). */
- (void)retryPendingPhotos;
/* Adds received songs not yet in the Music app to it (if Save to Music is on). */
- (void)retryPendingMusic;
- (void)announceNow;
- (void)refreshDevices;

- (NSString *)alias;
- (void)setAlias:(NSString *)alias;
- (NSString *)statusText;
- (NSString *)receiveStatus;
- (BOOL)isSavingToPhotos;
/* While received files go into Photos or Music: "Saving to Photos… 3 of 15", and how far along
   (0 to 1); nil and 0 otherwise. It doesn't hold anything up: History fills and empties as usual. */
- (NSString *)savingText;
- (float)savingProgress;
- (BOOL)isReceiving;
- (BOOL)isSessionActive;
- (float)uploadProgress;
- (NSString *)uploadName;
- (NSString *)fingerprint;
- (NSString *)localIP;
- (int)port;
- (NSArray *)devices;
- (NSArray *)receivedFiles;
- (BOOL)deleteReceivedFile:(NSDictionary *)file;
- (NSArray *)logLines;

- (void)sendItems:(NSArray *)items toDevice:(NSDictionary *)device;
- (void)cancelSending;
- (void)cancelReceiving;

- (void)appendLog:(NSString *)line;

@end

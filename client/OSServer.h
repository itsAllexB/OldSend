#import <Foundation/Foundation.h>

@class UIAlertView;
@class OSTransfer;

extern NSString * const OSServerDidUpdateNotification;
extern NSString * const OSServerSendDidFinishNotification;
extern NSString * const OSServerSendProgressNotification;
extern NSString * const OSServerDidReceiveTextNotification;

/* Settings > Save to Photos: copy received photos and videos into the Photos app (default on). */
BOOL OSSaveToPhotosEnabled(void);

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
    NSCondition *_photoCondition;
    BOOL _photoSaveInProgress;
    BOOL _photoFinished;
    BOOL _photoSuccess;
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
}

+ (OSServer *)shared;
+ (NSString *)localIPAddress;
+ (NSString *)generateAlias;

- (void)start;
- (void)stop;
/* Call when the app returns to the foreground: reopens the sockets iOS may have reclaimed. */
- (void)resume;
- (void)announceNow;
- (void)refreshDevices;

- (NSString *)alias;
- (void)setAlias:(NSString *)alias;
- (NSString *)statusText;
- (NSString *)receiveStatus;
- (BOOL)isSavingToPhotos;
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

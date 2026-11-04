#import <Foundation/Foundation.h>

/* One send or receive session, as shown on the transfer screen: the peer, every file with its own
   progress, and totals, speed and time left. OSServer creates and updates these on the main
   thread; the screen reads them. */

extern NSString * const OSTransferDidStartNotification;   /* object: the new OSTransfer */
extern NSString * const OSTransferDidChangeNotification;  /* object: the OSTransfer (state changes, not progress) */

typedef enum {
    OSTransferStateWaiting = 0,  /* sending: waiting for the receiver to accept */
    OSTransferStateRunning,
    OSTransferStateFinished,
    OSTransferStateDeclined,
    OSTransferStateCancelled,
    OSTransferStateFailed
} OSTransferState;

typedef enum {
    OSTransferFileQueued = 0,
    OSTransferFileRunning,
    OSTransferFileDone,
    OSTransferFileSkipped,
    OSTransferFileFailed
} OSTransferFileState;

@interface OSTransferFile : NSObject {
    NSString *_name;
    long long _size;
    long long _written;
    OSTransferFileState _state;
}
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) long long size;
@property (nonatomic, assign) long long written;
@property (nonatomic, assign) OSTransferFileState state;
@end

@interface OSTransfer : NSObject {
    BOOL _sending;
    NSString *_peerAlias;
    NSString *_peerType;
    NSArray *_files;
    OSTransferState _state;
    NSString *_message;
    NSTimeInterval _startTime;
    NSTimeInterval _endTime;
    NSMutableArray *_samples;
}
@property (nonatomic, readonly) BOOL sending;
@property (nonatomic, readonly) NSString *peerAlias;
@property (nonatomic, readonly) NSString *peerType;
@property (nonatomic, readonly) NSArray *files;
@property (nonatomic, readonly) OSTransferState state;
@property (nonatomic, readonly) NSString *message;

/* files: NSDictionaries with "name" (NSString) and "size" (NSNumber). */
- (id)initSending:(BOOL)sending peer:(NSString *)alias type:(NSString *)deviceType files:(NSArray *)files;

- (void)setRunning;
- (void)fileStarted:(NSInteger)index;
- (void)file:(NSInteger)index wrote:(long long)written;
- (void)fileFinished:(NSInteger)index;
- (void)fileSkipped:(NSInteger)index;
/* Ends the transfer; files still queued or running become skipped/failed. A finished transfer
   keeps its first end state, so a late failure after a cancel stays "cancelled". */
- (void)endWithState:(OSTransferState)state message:(NSString *)message;

- (BOOL)isActive;
- (long long)totalBytes;        /* without skipped files */
- (long long)transferredBytes;
- (NSInteger)fileCount;         /* without skipped files */
- (NSInteger)finishedFileCount;
- (double)bytesPerSecond;       /* over the last few seconds; 0 when unknown */
- (NSTimeInterval)secondsLeft;  /* -1 when unknown */
- (NSTimeInterval)elapsed;

@end

NSString *OSFormatBytes(long long bytes);
NSString *OSFormatDuration(NSTimeInterval seconds);

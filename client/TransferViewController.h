#import <UIKit/UIKit.h>

@class OSTransfer;

/* Live view of one transfer, like LocalSend's progress page: the peer, each file with its own
   progress and state, and the overall progress, files, size, speed and time left. */
@interface TransferViewController : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    OSTransfer *_transfer;
    UIImageView *_peerIcon;
    UILabel *_peerLabel;
    UILabel *_stateLabel;
    UITableView *_tableView;
    UIView *_panel;
    UILabel *_percentLabel;
    UILabel *_timeLabel;
    UIProgressView *_totalProgress;
    UILabel *_filesValue;
    UILabel *_sizeValue;
    UILabel *_speedValue;
    NSTimer *_timer;
    BOOL _showingDone;
}

- (id)initWithTransfer:(OSTransfer *)transfer;
- (OSTransfer *)transfer;

@end

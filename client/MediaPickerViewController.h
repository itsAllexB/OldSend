/* Changed by AllexB from OldSend by lihaoyun6; the changes are in the git history. */
#import <UIKit/UIKit.h>

@protocol MediaPickerDelegate <NSObject>
- (void)mediaPicker:(id)picker didFinishWithItems:(NSArray *)items;
- (void)mediaPickerDidCancel:(id)picker;
@end

@interface MediaPickerViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate> {
    UITableView *_tableView;
    NSMutableArray *_assets;
    NSMutableArray *_loadingAssets;
    id _library;
    NSMutableSet *_selectedIndexes;
    UIActivityIndicatorView *_spinner;
    UILabel *_emptyLabel;
    id<MediaPickerDelegate> _delegate;
    BOOL _loading;
    BOOL _exporting;
    BOOL _openedAtNewest;
    UIView *_exportHUD;
    /* Hold or slide to select many: see "Drag to select" in the .m. */
    id _dragRecognizer;
    BOOL _dragSelecting;
    NSInteger _dragAnchor;
    NSInteger _dragCurrent;
    NSSet *_dragOriginal;
    id _displayLink;
    CFTimeInterval _lastTick;
}

@property (nonatomic, assign) id<MediaPickerDelegate> delegate;

@end

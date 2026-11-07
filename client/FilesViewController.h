/* Changed by AllexB from OldSend by lihaoyun6; the changes are in the git history. */
#import <UIKit/UIKit.h>

@interface FilesViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate> {
    UITableView *_tableView;
    UILabel *_emptyLabel;
    NSArray *_files;
    UIToolbar *_toolbar;
    UIBarButtonItem *_deleteItem;
    UIBarButtonItem *_selectAllItem;
    UISegmentedControl *_deleteControl;
    UISegmentedControl *_selectAllControl;
    NSMutableSet *_selectedPaths;
    BOOL _batchEditing;
    BOOL _rowEditing;
    NSURL *_previewURL;
}

@end

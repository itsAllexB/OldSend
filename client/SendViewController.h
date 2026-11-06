/* Changed by itsAllexB from OldSend by lihaoyun6; the changes are in the git history. */
#import <UIKit/UIKit.h>
#import "TextInputViewController.h"
#import "SendFilePickerViewController.h"
#import "MediaPickerViewController.h"

@interface SendViewController : UIViewController <UITableViewDataSource, UITableViewDelegate,
                                                   UIActionSheetDelegate,
                                                   UIImagePickerControllerDelegate,
                                                   UINavigationControllerDelegate,
                                                   TextInputViewControllerDelegate,
                                                   SendFilePickerDelegate,
                                                   MediaPickerDelegate> {
    UITableView *_tableView;
    UILabel *_emptyLabel;
    UIBarButtonItem *_addButton;
    NSMutableArray *_pendingItems;
    id _mediaPopover;
    UIActionSheet *_typeSheet;
}

/* Items shared from other apps (see OSShareInbox), added to what is ready to send. */
- (void)addSharedItems:(NSArray *)items;

@end

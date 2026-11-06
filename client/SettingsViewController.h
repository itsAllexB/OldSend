/* Changed by itsAllexB from OldSend by lihaoyun6; the changes are in the git history. */
#import <UIKit/UIKit.h>

@interface SettingsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate> {
    UITableView *_tableView;
    UITextField *_nicknameField;
    UIButton *_randomButton;
    UISwitch *_quickSaveSwitch;
    UISwitch *_photosSwitch;
    UISwitch *_musicSwitch;
    UISwitch *_backgroundSwitch;
}

@end

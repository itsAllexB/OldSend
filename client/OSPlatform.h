/* Changed by itsAllexB from OldSend by lihaoyun6; the changes are in the git history. */
#import <UIKit/UIKit.h>

/* YES on iPad, including iPad 1 running iPhone OS 3.2 / 4.x. */
BOOL OSIsPad(void);

/* Small hint text: bold on iPad, regular on iPhone/iPod. */
UIFont *OSSmallFont(CGFloat size);

/* A localized format with a count in it: the key's ".one" form when the count is 1. */
NSString *OSCountedString(NSString *key, NSInteger count);

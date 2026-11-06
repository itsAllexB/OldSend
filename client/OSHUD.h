/* Changed by itsAllexB from OldSend by lihaoyun6; the changes are in the git history. */
#import <Foundation/Foundation.h>

extern NSString * const OSHUDDidCancelNotification;

@interface OSHUD : NSObject

+ (void)showSendingTo:(NSString *)alias;
+ (void)showCancelling;
+ (void)updateSendProgress:(float)progress;
+ (void)hide;
+ (void)hideSaving;

@end

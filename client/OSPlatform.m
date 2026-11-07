/* Changed by AllexB from OldSend by lihaoyun6; the changes are in the git history. */
#import "OSPlatform.h"

BOOL OSIsPad(void) {
    /* userInterfaceIdiom is unavailable/unreliable when linked against the
       3.1.3 SDK; the hardware model string is what OldSeek uses in practice. */
    return [[[UIDevice currentDevice] model] rangeOfString:@"iPad"].location != NSNotFound;
}

UIFont *OSSmallFont(CGFloat size) {
    if (OSIsPad()) return [UIFont boldSystemFontOfSize:size];
    return [UIFont systemFontOfSize:size];
}

NSString *OSCountedString(NSString *key, NSInteger count) {
    return NSLocalizedString(count == 1 ? [key stringByAppendingString:@".one"] : key, nil);
}

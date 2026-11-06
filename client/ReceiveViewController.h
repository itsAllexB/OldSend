#import <UIKit/UIKit.h>

@interface ReceiveViewController : UIViewController {
    UIImageView *_wifiView;
    UIImageView *_wifiBlueView;
    UILabel *_nameLabel;
    UILabel *_statusLabel;
    UIProgressView *_progressView;
    UILabel *_progressLabel;
    BOOL _visible;
    BOOL _wifiBreathing;
    BOOL _wifiActive;
    BOOL _wifiFastAnimation;
    UIView *_infoOverlay;
}

@end

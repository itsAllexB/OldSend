#import "ReceiveViewController.h"
#import "OSServer.h"
#import "OSPlatform.h"
#import "OSNavigationController.h"
#import "TextViewController.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <arpa/inet.h>

@implementation ReceiveViewController

- (void)loadView {
    CGRect frame = [[UIScreen mainScreen] applicationFrame];
    UIView *view = [[UIView alloc] initWithFrame:frame];
    view.backgroundColor = [UIColor whiteColor];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _wifiView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ReceiveWifiLarge.png"]];
    _wifiView.contentMode = UIViewContentModeCenter;
    _wifiView.frame = CGRectMake((frame.size.width - 160) / 2, 18, 160, 160);
    _wifiView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [view addSubview:_wifiView];

    _wifiBlueView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ReceiveWifiLargeBlue.png"]];
    _wifiBlueView.contentMode = UIViewContentModeCenter;
    _wifiBlueView.frame = _wifiView.frame;
    _wifiBlueView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    _wifiBlueView.alpha = 1.0f;
    [view addSubview:_wifiBlueView];

    _nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 200, frame.size.width - 40, 40)];
    _nameLabel.backgroundColor = [UIColor clearColor];
    _nameLabel.font = [UIFont boldSystemFontOfSize:23];
    _nameLabel.textColor = [UIColor colorWithWhite:0.24f alpha:1.0f];
    _nameLabel.adjustsFontSizeToFitWidth = YES;
    _nameLabel.minimumFontSize = 14;
    _nameLabel.textAlignment = UITextAlignmentCenter;
    [view addSubview:_nameLabel];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 246, frame.size.width - 40, 20)];
    _statusLabel.backgroundColor = [UIColor clearColor];
    _statusLabel.font = OSSmallFont(12);
    _statusLabel.textAlignment = UITextAlignmentCenter;
    _statusLabel.textColor = [UIColor colorWithWhite:0.45f alpha:1.0f];
    _statusLabel.adjustsFontSizeToFitWidth = YES;
    _statusLabel.minimumFontSize = 9;
    [view addSubview:_statusLabel];

    _progressView = [[UIProgressView alloc] initWithFrame:CGRectMake(30, 274, frame.size.width - 60, 9)];
    _progressView.progressViewStyle = UIProgressViewStyleDefault;
    _progressView.hidden = YES;
    _progressView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [view addSubview:_progressView];

    _progressLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 288, frame.size.width - 40, 16)];
    _progressLabel.backgroundColor = [UIColor clearColor];
    _progressLabel.font = OSSmallFont(11);
    _progressLabel.textAlignment = UITextAlignmentCenter;
    _progressLabel.textColor = [UIColor colorWithWhite:0.45f alpha:1.0f];
    _progressLabel.hidden = YES;
    _progressLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [view addSubview:_progressLabel];

    _footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, frame.size.height - 36,
                                                             frame.size.width - 40, 24)];
    _footerLabel.backgroundColor = [UIColor clearColor];
    _footerLabel.font = OSSmallFont(11);
    _footerLabel.textAlignment = UITextAlignmentCenter;
    _footerLabel.textColor = [UIColor colorWithWhite:0.55f alpha:1.0f];
    _footerLabel.text = NSLocalizedString(@"receive.footer", nil);
    _footerLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [view addSubview:_footerLabel];

    self.view = view;
    [view release];

    [self layoutContent];
}

- (void)layoutContent {
    CGRect bounds = self.view.bounds;
    CGFloat width = bounds.size.width;
    CGFloat height = bounds.size.height;

    if (OSIsPad()) {
        CGFloat iconSize = 320.0f;
        CGFloat iconY = (height > 800.0f) ? 110.0f : 40.0f;
        CGFloat nameY = iconY + iconSize + 36.0f;
        CGFloat progressWidth = width - 240.0f;
        if (progressWidth > 560.0f) progressWidth = 560.0f;

        _wifiView.image = [UIImage imageNamed:@"ReceiveWifiLarge-iPad.png"];
        _wifiBlueView.image = [UIImage imageNamed:@"ReceiveWifiLargeBlue-iPad.png"];
        _wifiView.frame = CGRectMake((width - iconSize) / 2, iconY, iconSize, iconSize);
        _wifiBlueView.frame = _wifiView.frame;
        _nameLabel.frame = CGRectMake(40, nameY, width - 80, 52);
        _statusLabel.frame = CGRectMake(40, nameY + 58, width - 80, 26);
        _progressView.frame = CGRectMake((width - progressWidth) / 2, nameY + 104,
                                         progressWidth, 12);
        _progressLabel.frame = CGRectMake(40, nameY + 124, width - 80, 20);
        _footerLabel.frame = CGRectMake(20, height - 44, width - 40, 24);

        _nameLabel.font = [UIFont boldSystemFontOfSize:34];
        _nameLabel.minimumFontSize = 20;
        _statusLabel.font = OSSmallFont(16);
        _statusLabel.minimumFontSize = 12;
        _progressLabel.font = OSSmallFont(14);
        _footerLabel.font = OSSmallFont(13);
    } else {
        _wifiView.image = [UIImage imageNamed:@"ReceiveWifiLarge.png"];
        _wifiBlueView.image = [UIImage imageNamed:@"ReceiveWifiLargeBlue.png"];
        _wifiView.frame = CGRectMake((width - 160) / 2, 18, 160, 160);
        _wifiBlueView.frame = _wifiView.frame;
        _nameLabel.frame = CGRectMake(20, 200, width - 40, 40);
        _statusLabel.frame = CGRectMake(20, 246, width - 40, 20);
        _progressView.frame = CGRectMake(30, 274, width - 60, 9);
        _progressLabel.frame = CGRectMake(20, 288, width - 40, 16);
        _footerLabel.frame = CGRectMake(20, height - 36, width - 40, 24);

        _nameLabel.font = [UIFont boldSystemFontOfSize:23];
        _nameLabel.minimumFontSize = 14;
        _statusLabel.font = OSSmallFont(12);
        _statusLabel.minimumFontSize = 9;
        _progressLabel.font = OSSmallFont(11);
        _footerLabel.font = OSSmallFont(11);
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    if (OSIsPad()) return YES;
    return orientation == UIInterfaceOrientationPortrait;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation
                                         duration:(NSTimeInterval)duration {
    [self layoutContent];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation {
    [self layoutContent];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"tab.receive", nil);
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(serverDidUpdate:)
                                                 name:OSServerDidUpdateNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(textReceived:)
                                                 name:OSServerDidReceiveTextNotification
                                               object:nil];
    {
        /* iOS's own info button (the Send page's device rows use OldSend's own "i"). */
        UIButton *info = [UIButton buttonWithType:UIButtonTypeInfoLight];
        UIBarButtonItem *item;
        [info addTarget:self action:@selector(infoTapped:) forControlEvents:UIControlEventTouchUpInside];
        info.frame = CGRectMake(0, 0, 40, 30);
        item = [[UIBarButtonItem alloc] initWithCustomView:info];
        self.navigationItem.rightBarButtonItem = item;
        [item release];
    }
    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _visible = YES;
    [self layoutContent];
    [self refresh];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _visible = NO;
    [self stopWifiBreathing];
    [self hideInfo];
}

#pragma mark Network info card (like LocalSend's)

/* Every IPv4 address of an interface that is up: Wi-Fi, and cellular or personal hotspot. */
static NSArray *os_ipv4_addresses(void) {
    NSMutableArray *addresses = [NSMutableArray array];
    struct ifaddrs *list = NULL;
    struct ifaddrs *entry;

    if (getifaddrs(&list) != 0) return addresses;
    for (entry = list; entry != NULL; entry = entry->ifa_next) {
        char text[INET_ADDRSTRLEN];
        NSString *address;
        if (entry->ifa_addr == NULL || entry->ifa_addr->sa_family != AF_INET) continue;
        if ((entry->ifa_flags & IFF_UP) == 0 || (entry->ifa_flags & IFF_LOOPBACK) != 0) continue;
        if (inet_ntop(AF_INET, &((struct sockaddr_in *)entry->ifa_addr)->sin_addr, text, sizeof text) == NULL) continue;
        address = [NSString stringWithUTF8String:text];
        if (![addresses containsObject:address]) [addresses addObject:address];
    }
    freeifaddrs(list);
    return addresses;
}

static UILabel *os_info_label(CGRect frame, NSString *text, UIColor *color, BOOL bold) {
    UILabel *label = [[[UILabel alloc] initWithFrame:frame] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.font = bold ? [UIFont boldSystemFontOfSize:15] : [UIFont systemFontOfSize:15];
    label.textColor = color;
    label.text = text;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumFontSize = 11;
    return label;
}

- (void)infoTapped:(id)sender {
    if (_infoOverlay != nil) {
        [self hideInfo];
    } else {
        [self showInfo];
    }
}

- (void)showInfo {
    OSServer *server = [OSServer shared];
    NSArray *addresses = os_ipv4_addresses();
    CGRect bounds = self.view.bounds;
    CGFloat width = 270.0f;
    CGFloat rowHeight = 22.0f;
    CGFloat height = 24.0f + rowHeight * (2 + MAX((NSInteger)[addresses count], 1));
    UIColor *keyColor = [UIColor colorWithWhite:0.45f alpha:1.0f];
    UIColor *valueColor = [UIColor colorWithWhite:0.12f alpha:1.0f];
    UIButton *dismiss;
    UIView *card;
    CGFloat y = 12.0f;
    NSUInteger i;

    /* A full-screen button behind the card: a tap anywhere closes it. */
    _infoOverlay = [[UIView alloc] initWithFrame:bounds];
    _infoOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    dismiss = [UIButton buttonWithType:UIButtonTypeCustom];
    dismiss.frame = _infoOverlay.bounds;
    dismiss.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [dismiss addTarget:self action:@selector(hideInfo) forControlEvents:UIControlEventTouchUpInside];
    [_infoOverlay addSubview:dismiss];

    card = [[UIView alloc] initWithFrame:CGRectMake(bounds.size.width - width - 8.0f, 8.0f, width, height)];
    card.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    card.backgroundColor = [UIColor colorWithRed:0.96f green:0.97f blue:0.98f alpha:1.0f];
    card.layer.cornerRadius = 10.0f;
    card.layer.borderWidth = 1.0f;
    card.layer.borderColor = [UIColor colorWithWhite:0.82f alpha:1.0f].CGColor;
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.25f;
    card.layer.shadowRadius = 6.0f;
    card.layer.shadowOffset = CGSizeMake(0, 2);
    card.userInteractionEnabled = NO;

    [card addSubview:os_info_label(CGRectMake(14, y, 100, rowHeight), NSLocalizedString(@"receive.info_name", nil), keyColor, NO)];
    [card addSubview:os_info_label(CGRectMake(112, y, width - 124, rowHeight), [server alias], valueColor, YES)];
    y += rowHeight;
    [card addSubview:os_info_label(CGRectMake(14, y, 100, rowHeight), NSLocalizedString(@"receive.info_ip", nil), keyColor, NO)];
    if ([addresses count] == 0) {
        [card addSubview:os_info_label(CGRectMake(112, y, width - 124, rowHeight), @"–", valueColor, YES)];
        y += rowHeight;
    }
    for (i = 0; i < [addresses count]; i++) {
        [card addSubview:os_info_label(CGRectMake(112, y, width - 124, rowHeight), [addresses objectAtIndex:i], valueColor, YES)];
        y += rowHeight;
    }
    [card addSubview:os_info_label(CGRectMake(14, y, 100, rowHeight), NSLocalizedString(@"receive.info_port", nil), keyColor, NO)];
    [card addSubview:os_info_label(CGRectMake(112, y, width - 124, rowHeight),
                                   [NSString stringWithFormat:@"%d", [server port]], valueColor, YES)];

    [_infoOverlay addSubview:card];
    [card release];
    _infoOverlay.alpha = 0.0f;
    [self.view addSubview:_infoOverlay];
    [UIView animateWithDuration:0.15 animations:^{ _infoOverlay.alpha = 1.0f; }];
}

- (void)hideInfo {
    UIView *overlay = _infoOverlay;
    if (overlay == nil) return;
    _infoOverlay = nil;
    [UIView animateWithDuration:0.15 animations:^{ overlay.alpha = 0.0f; }
                     completion:^(BOOL finished) {
                         [overlay removeFromSuperview];
                         [overlay release];
                     }];
}

- (void)startWifiBreathing {
    BOOL fast = _wifiActive;

    if (!_visible) return;
    if (_wifiBreathing && _wifiFastAnimation == fast) return;

    _wifiBreathing = YES;
    _wifiFastAnimation = fast;
    [_wifiBlueView.layer removeAllAnimations];

    {
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
        animation.fromValue = [NSNumber numberWithFloat:1.0f];
        animation.toValue = [NSNumber numberWithFloat:0.0f];
        animation.duration = fast ? 0.5 : 1.8;
        animation.autoreverses = YES;
        animation.repeatCount = HUGE_VALF;
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        animation.removedOnCompletion = NO;
        [_wifiBlueView.layer addAnimation:animation forKey:@"wifiBreathing"];
    }
}

- (void)stopWifiBreathing {
    _wifiBreathing = NO;
    _wifiFastAnimation = NO;
    [_wifiBlueView.layer removeAllAnimations];
    _wifiBlueView.alpha = 1.0f;
}

- (void)serverDidUpdate:(NSNotification *)notification {
    [self refresh];
}

- (void)textReceived:(NSNotification *)notification {
    NSString *text = [[notification userInfo] objectForKey:@"text"];
    TextViewController *controller;
    UINavigationController *navigation;
    UIViewController *presenter;

    if ([text length] == 0) return;

    controller = [[TextViewController alloc] initWithText:text];
    navigation = [[OSNavigationController alloc] initWithRootViewController:controller];

    presenter = self.tabBarController != nil ? self.tabBarController : self;
    if (presenter.modalViewController != nil) {
        presenter = presenter.modalViewController;
    }
    [presenter presentModalViewController:navigation animated:YES];

    [controller release];
    [navigation release];
}

- (void)refresh {
    OSServer *server = [OSServer shared];
    NSString *alias = [server alias];
    BOOL active = [server isSessionActive] || [server isReceiving] || [server isSavingToPhotos];

    _wifiActive = active;
    if (!_visible) {
        [self stopWifiBreathing];
    } else {
        [self startWifiBreathing];
    }
    _nameLabel.text = alias;

    _statusLabel.text = [server receiveStatus];

    {
        BOOL receiving = [server isSessionActive] || [server isReceiving];
        _progressView.hidden = !receiving;
        _progressLabel.hidden = !receiving;
        if (receiving) {
            float progress = [server uploadProgress];
            _progressView.progress = progress;
            _progressLabel.text = [NSString stringWithFormat:@"%d%%",
                                   (int)(progress * 100.0f)];
        }
    }

    _statusLabel.textColor = [UIColor colorWithWhite:0.45f alpha:1.0f];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_wifiView release];
    [_wifiBlueView release];
    [_nameLabel release];
    [_statusLabel release];
    [_progressView release];
    [_progressLabel release];
    [_footerLabel release];
    [_infoOverlay release];
    [super dealloc];
}

@end

#import "TransferViewController.h"
#import "OSTransfer.h"
#import "OSServer.h"
#import "OSPlatform.h"
#import "FileTypeIcon.h"
#import "OSDaemon.h"

#define OS_PANEL_HEIGHT 112.0f
#define OS_HEADER_HEIGHT 64.0f
#define OS_ROW_HEIGHT 60.0f

static UILabel *os_label(CGRect frame, UIFont *font, UIColor *color, UITextAlignment alignment) {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textColor = color;
    label.textAlignment = alignment;
    return label;
}

static NSString *os_device_icon(NSString *type) {
    type = [type lowercaseString];
    if ([type isEqualToString:@"mobile"]) return @"DeviceMobile.png";
    if ([type isEqualToString:@"web"]) return @"DeviceWeb.png";
    if ([type isEqualToString:@"headless"]) return @"DeviceHeadless.png";
    if ([type isEqualToString:@"server"]) return @"DeviceServer.png";
    return @"DeviceDesktop.png";
}

@interface OSTransferFileCell : UITableViewCell {
    UIImageView *_iconView;
    UILabel *_nameLabel;
    UILabel *_detailLabel;
    UIProgressView *_progressView;
}
- (void)setFile:(OSTransferFile *)file;
@end

@implementation OSTransferFileCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _iconView.contentMode = UIViewContentModeCenter;
        [self.contentView addSubview:_iconView];
        _nameLabel = os_label(CGRectZero, [UIFont boldSystemFontOfSize:15],
                              [UIColor blackColor], UITextAlignmentLeft);
        _nameLabel.lineBreakMode = UILineBreakModeMiddleTruncation;
        [self.contentView addSubview:_nameLabel];
        _detailLabel = os_label(CGRectZero, [UIFont systemFontOfSize:12],
                                [UIColor colorWithWhite:0.45f alpha:1.0f], UITextAlignmentLeft);
        [self.contentView addSubview:_detailLabel];
        _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        [self.contentView addSubview:_progressView];
    }
    return self;
}

- (void)layoutSubviews {
    CGRect bounds;
    [super layoutSubviews];
    bounds = self.contentView.bounds;
    _iconView.frame = CGRectMake(8, floorf((bounds.size.height - 32) / 2), 32, 32);
    _nameLabel.frame = CGRectMake(50, 7, bounds.size.width - 58, 20);
    _detailLabel.frame = CGRectMake(50, 27, bounds.size.width - 58, 16);
    _progressView.frame = CGRectMake(50, 46, bounds.size.width - 62, 9);
}

- (void)setFile:(OSTransferFile *)file {
    NSString *detail;
    UIColor *detailColor = [UIColor colorWithWhite:0.45f alpha:1.0f];
    BOOL running = file.state == OSTransferFileRunning;

    _iconView.image = [UIImage imageNamed:OSFileTypeIconName(file.name)];
    _nameLabel.text = file.name;
    _nameLabel.textColor = file.state == OSTransferFileSkipped ? [UIColor grayColor] : [UIColor blackColor];

    switch (file.state) {
        case OSTransferFileRunning:
            detail = [NSString stringWithFormat:NSLocalizedString(@"transfer.file_progress", nil),
                      OSFormatBytes(file.written), OSFormatBytes(file.size)];
            if (file.size > 0) {
                detail = [detail stringByAppendingFormat:@" · %d%%",
                          (int)((double)file.written * 100.0 / (double)file.size)];
            }
            break;
        case OSTransferFileDone:
            detail = OSFormatBytes(file.size);
            break;
        case OSTransferFileSkipped:
            detail = [NSString stringWithFormat:@"%@ · %@", OSFormatBytes(file.size),
                      NSLocalizedString(@"transfer.file_skipped", nil)];
            break;
        case OSTransferFileFailed:
            detail = [NSString stringWithFormat:@"%@ · %@", OSFormatBytes(file.size),
                      NSLocalizedString(@"transfer.file_failed", nil)];
            detailColor = [UIColor colorWithRed:0.80f green:0.15f blue:0.15f alpha:1.0f];
            break;
        default:
            detail = [NSString stringWithFormat:@"%@ · %@", OSFormatBytes(file.size),
                      NSLocalizedString(@"transfer.file_waiting", nil)];
            break;
    }
    _detailLabel.text = detail;
    _detailLabel.textColor = detailColor;
    _progressView.hidden = !running;
    if (running) {
        _progressView.progress = file.size > 0 ? (float)((double)file.written / (double)file.size) : 0.0f;
    }
    self.accessoryType = file.state == OSTransferFileDone ? UITableViewCellAccessoryCheckmark
                                                          : UITableViewCellAccessoryNone;
}

- (void)dealloc {
    [_iconView release];
    [_nameLabel release];
    [_detailLabel release];
    [_progressView release];
    [super dealloc];
}

@end

@implementation TransferViewController

- (id)initWithTransfer:(OSTransfer *)transfer {
    if ((self = [super init])) {
        _transfer = [transfer retain];
    }
    return self;
}

- (OSTransfer *)transfer {
    return _transfer;
}

- (UILabel *)addPanelRow:(NSString *)key y:(CGFloat)y width:(CGFloat)width {
    UILabel *keyLabel = os_label(CGRectMake(14, y, 120, 17), [UIFont systemFontOfSize:13],
                                 [UIColor colorWithWhite:0.45f alpha:1.0f], UITextAlignmentLeft);
    UILabel *valueLabel = os_label(CGRectMake(120, y, width - 134, 17), [UIFont boldSystemFontOfSize:13],
                                   [UIColor colorWithWhite:0.2f alpha:1.0f], UITextAlignmentRight);
    keyLabel.text = key;
    valueLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_panel addSubview:keyLabel];
    [_panel addSubview:valueLabel];
    [keyLabel release];
    return [valueLabel autorelease];
}

- (void)loadView {
    CGRect frame = [[UIScreen mainScreen] applicationFrame];
    CGFloat width = frame.size.width;
    UIView *view = [[UIView alloc] initWithFrame:frame];
    UIView *header;
    UIView *line;

    view.backgroundColor = [UIColor whiteColor];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, OS_HEADER_HEIGHT)];
    header.backgroundColor = [UIColor whiteColor];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _peerIcon = [[UIImageView alloc] initWithFrame:CGRectMake(10, 10, 44, 44)];
    _peerIcon.contentMode = UIViewContentModeCenter;
    [header addSubview:_peerIcon];
    _peerLabel = os_label(CGRectMake(64, 11, width - 76, 22), [UIFont boldSystemFontOfSize:17],
                          [UIColor blackColor], UITextAlignmentLeft);
    _peerLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:_peerLabel];
    _stateLabel = os_label(CGRectMake(64, 34, width - 76, 18), [UIFont systemFontOfSize:13],
                           [UIColor colorWithWhite:0.45f alpha:1.0f], UITextAlignmentLeft);
    _stateLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _stateLabel.adjustsFontSizeToFitWidth = YES;
    _stateLabel.minimumFontSize = 10;
    [header addSubview:_stateLabel];
    line = [[UIView alloc] initWithFrame:CGRectMake(0, OS_HEADER_HEIGHT - 1, width, 1)];
    line.backgroundColor = [UIColor colorWithWhite:0.85f alpha:1.0f];
    line.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:line];
    [line release];
    [view addSubview:header];
    [header release];

    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, OS_HEADER_HEIGHT, width,
                                                               frame.size.height - OS_HEADER_HEIGHT - OS_PANEL_HEIGHT)
                                              style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.rowHeight = OS_ROW_HEIGHT;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [view addSubview:_tableView];

    _panel = [[UIView alloc] initWithFrame:CGRectMake(0, frame.size.height - OS_PANEL_HEIGHT,
                                                      width, OS_PANEL_HEIGHT)];
    _panel.backgroundColor = [UIColor colorWithWhite:0.95f alpha:1.0f];
    _panel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 1)];
    line.backgroundColor = [UIColor colorWithWhite:0.80f alpha:1.0f];
    line.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_panel addSubview:line];
    [line release];

    _percentLabel = os_label(CGRectMake(14, 9, 120, 19), [UIFont boldSystemFontOfSize:15],
                             [UIColor colorWithWhite:0.15f alpha:1.0f], UITextAlignmentLeft);
    [_panel addSubview:_percentLabel];
    _timeLabel = os_label(CGRectMake(120, 10, width - 134, 17), [UIFont systemFontOfSize:13],
                          [UIColor colorWithWhite:0.45f alpha:1.0f], UITextAlignmentRight);
    _timeLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_panel addSubview:_timeLabel];
    _totalProgress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _totalProgress.frame = CGRectMake(14, 33, width - 28, 9);
    _totalProgress.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_panel addSubview:_totalProgress];

    _filesValue = [[self addPanelRow:NSLocalizedString(@"transfer.files", nil) y:50 width:width] retain];
    _sizeValue = [[self addPanelRow:NSLocalizedString(@"transfer.size", nil) y:69 width:width] retain];
    _speedValue = [[self addPanelRow:NSLocalizedString(@"transfer.speed", nil) y:88 width:width] retain];
    [view addSubview:_panel];

    self.view = view;
    [view release];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(_transfer.sending ? @"transfer.sending_title" : @"transfer.receiving_title", nil);
    _peerIcon.image = [UIImage imageNamed:os_device_icon(_transfer.peerType)];
    _peerLabel.text = _transfer.peerAlias;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(transferDidChange:)
                                                 name:OSTransferDidChangeNotification
                                               object:_transfer];
    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_timer == nil && [_transfer isActive]) {
        _timer = [[NSTimer scheduledTimerWithTimeInterval:0.33
                                                   target:self
                                                 selector:@selector(timerFired:)
                                                 userInfo:nil
                                                  repeats:YES] retain];
    }
    [self refresh];
}

- (void)stopTimer {
    [_timer invalidate];
    [_timer release];
    _timer = nil;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    /* The timer retains its target; stopping it here lets the controller go away. */
    [self stopTimer];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    if (OSIsPad()) return YES;
    return orientation == UIInterfaceOrientationPortrait;
}

- (void)timerFired:(NSTimer *)timer {
    [self refresh];
}

- (void)transferDidChange:(NSNotification *)notification {
    [self refresh];
}

- (void)cancelTapped:(id)sender {
    if (_transfer.remote) {
        /* Run by the background service. */
        [[OSDaemonClient shared] cancelRemoteTransfer];
    } else if (_transfer.sending) {
        [[OSServer shared] cancelSending];
    } else {
        [[OSServer shared] cancelReceiving];
    }
    [_transfer endWithState:OSTransferStateCancelled message:nil];
}

- (void)doneTapped:(id)sender {
    [self stopTimer];
    [self dismissModalViewControllerAnimated:YES];
}

- (NSString *)stateText {
    NSString *alias = _transfer.peerAlias;
    switch (_transfer.state) {
        case OSTransferStateWaiting:
            return [NSString stringWithFormat:NSLocalizedString(@"transfer.waiting", nil), alias];
        case OSTransferStateRunning:
            return [NSString stringWithFormat:NSLocalizedString(_transfer.sending ? @"transfer.sending_to"
                                                                                  : @"transfer.receiving_from", nil),
                    alias];
        case OSTransferStateFinished:
            return NSLocalizedString(@"transfer.finished", nil);
        case OSTransferStateDeclined:
            return [NSString stringWithFormat:NSLocalizedString(@"transfer.declined", nil), alias];
        case OSTransferStateCancelled:
            return [_transfer.message length] > 0 ? _transfer.message : NSLocalizedString(@"transfer.cancelled", nil);
        default:
            return [_transfer.message length] > 0 ? _transfer.message : NSLocalizedString(@"transfer.failed", nil);
    }
}

- (void)refresh {
    BOOL active = [_transfer isActive];
    long long total = [_transfer totalBytes];
    long long done = [_transfer transferredBytes];
    float progress = total > 0 ? (float)((double)done / (double)total) : (_transfer.state == OSTransferStateFinished ? 1.0f : 0.0f);
    double speed = [_transfer bytesPerSecond];
    UIColor *stateColor = [UIColor colorWithWhite:0.45f alpha:1.0f];

    if (progress > 1.0f) progress = 1.0f;
    if (_transfer.state == OSTransferStateFinished) {
        stateColor = [UIColor colorWithRed:0.10f green:0.55f blue:0.20f alpha:1.0f];
    } else if (!active) {
        stateColor = [UIColor colorWithRed:0.80f green:0.15f blue:0.15f alpha:1.0f];
    }
    _stateLabel.text = [self stateText];
    _stateLabel.textColor = stateColor;

    _totalProgress.progress = progress;
    _percentLabel.text = [NSString stringWithFormat:@"%d%%", (int)(progress * 100.0f)];
    if (active) {
        NSTimeInterval left = [_transfer secondsLeft];
        _timeLabel.text = left >= 0 ? [NSString stringWithFormat:NSLocalizedString(@"transfer.left", nil),
                                       OSFormatDuration(left)]
                                    : @"";
    } else {
        _timeLabel.text = [_transfer elapsed] > 0
                        ? [NSString stringWithFormat:NSLocalizedString(@"transfer.took", nil),
                           OSFormatDuration([_transfer elapsed])]
                        : @"";
    }
    _filesValue.text = [NSString stringWithFormat:@"%d / %d",
                        (int)[_transfer finishedFileCount], (int)[_transfer fileCount]];
    _sizeValue.text = [NSString stringWithFormat:@"%@ / %@", OSFormatBytes(done), OSFormatBytes(total)];
    _speedValue.text = speed > 0 ? [NSString stringWithFormat:@"%@/s", OSFormatBytes((long long)speed)] : @"–";

    if (active && self.navigationItem.rightBarButtonItem == nil) {
        UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"common.cancel", nil)
                                                                   style:UIBarButtonItemStyleBordered
                                                                  target:self
                                                                  action:@selector(cancelTapped:)];
        self.navigationItem.rightBarButtonItem = cancel;
        [cancel release];
    } else if (!active && !_showingDone) {
        UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                    target:self
                                                                                    action:@selector(doneTapped:)];
        _showingDone = YES;
        self.navigationItem.rightBarButtonItem = doneButton;
        [doneButton release];
        [self stopTimer];
    }

    {
        NSArray *cells = [_tableView visibleCells];
        for (OSTransferFileCell *cell in cells) {
            NSIndexPath *path = [_tableView indexPathForCell:cell];
            if (path != nil && path.row < (NSInteger)[_transfer.files count]) {
                [cell setFile:[_transfer.files objectAtIndex:path.row]];
            }
        }
    }
    [self scrollToRunningFile];
}

- (void)scrollToRunningFile {
    NSInteger i;
    for (i = 0; i < (NSInteger)[_transfer.files count]; i++) {
        OSTransferFile *file = [_transfer.files objectAtIndex:i];
        if (file.state == OSTransferFileRunning) {
            NSIndexPath *path = [NSIndexPath indexPathForRow:i inSection:0];
            CGRect rect = [_tableView rectForRowAtIndexPath:path];
            if (!CGRectContainsRect(_tableView.bounds, rect) && !_tableView.dragging && !_tableView.decelerating) {
                [_tableView scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
            }
            return;
        }
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_transfer.files count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"TransferFile";
    OSTransferFileCell *cell = (OSTransferFileCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[[OSTransferFileCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:identifier] autorelease];
    }
    [cell setFile:[_transfer.files objectAtIndex:indexPath.row]];
    return cell;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_timer invalidate];
    [_timer release];
    [_transfer release];
    [_peerIcon release];
    [_peerLabel release];
    [_stateLabel release];
    [_tableView release];
    [_panel release];
    [_percentLabel release];
    [_timeLabel release];
    [_totalProgress release];
    [_filesValue release];
    [_sizeValue release];
    [_speedValue release];
    [super dealloc];
}

@end

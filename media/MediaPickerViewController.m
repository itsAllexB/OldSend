#import "MediaPickerViewController.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#include <math.h>

@protocol MediaSelectionCircle <NSObject>
- (void)setChecked:(BOOL)checked;
@end

static MediaPickerViewController *gActiveMediaPicker = nil;
static id gActiveGroup = nil;
static id gActiveFilter = nil;

static NSInteger MediaColumns(CGFloat width) {
    return width > 500.0f ? 8 : 4;
}

static CGFloat MediaThumbSize(CGFloat width, NSInteger columns) {
    CGFloat gap = 8.0f;
    return floorf((width - (columns + 1) * gap) / columns);
}

#pragma mark - Drag to select

/* The grid has no controls in it: a UIButton takes the touch for itself, so a finger laid on a
   thumbnail couldn't scroll. Three recognizers on the table share every touch instead:
     - a tap selects one thumbnail;
     - a short hold on a thumbnail, or a slide mostly sideways from it, starts selecting a range;
     - the table's own pan, which waits for that second one to fail: anything else is a scroll.
   Behaviour and tuning are those of Photos Select, by the same author. */
static const NSTimeInterval kMediaHoldDelay = 0.3;
static const CGFloat kMediaSlop = 10.0f;
static const CGFloat kMediaSidewaysRatio = 1.4f;   /* within about 35 degrees of horizontal */
static const CGFloat kMediaEdgeZone = 54.0f;       /* points from the top or bottom of the grid */
static const CGFloat kMediaMinSpeed = 80.0f;       /* points per second at the start of the zone */
static const CGFloat kMediaMaxSpeed = 1400.0f;     /* at the edge, or past it */

@interface MediaPickerViewController (DragSelect)
- (BOOL)canStartDragAtPoint:(CGPoint)tablePoint;
@end

@interface MediaDragRecognizer : UIGestureRecognizer {
    MediaPickerViewController *_picker;
    NSTimer *_holdTimer;
    CGPoint _startPoint;
    CGPoint _currentPoint;
}
@property (nonatomic, assign) MediaPickerViewController *picker;
@property (nonatomic, readonly) CGPoint startPoint;    /* window coordinates */
@property (nonatomic, readonly) CGPoint currentPoint;  /* window coordinates */
@end

@implementation MediaDragRecognizer

@synthesize picker = _picker, startPoint = _startPoint, currentPoint = _currentPoint;

- (void)stopHoldTimer {
    [_holdTimer invalidate];
    _holdTimer = nil;
}

- (void)reset {
    [super reset];
    [self stopHoldTimer];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    UIScrollView *table = (UIScrollView *)self.view;

    [super touchesBegan:touches withEvent:event];
    /* A touch that stops a moving grid only stops it, as in Photos. */
    if ([[event touchesForGestureRecognizer:self] count] != 1 || table.decelerating ||
        ![_picker canStartDragAtPoint:[touch locationInView:table]]) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    _startPoint = _currentPoint = [touch locationInView:nil];
    /* Common modes: the run loop may already be tracking the scroll view. */
    _holdTimer = [NSTimer timerWithTimeInterval:kMediaHoldDelay target:self
                                       selector:@selector(holdTimerFired:) userInfo:nil repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:_holdTimer forMode:NSRunLoopCommonModes];
}

- (void)holdTimerFired:(NSTimer *)timer {
    _holdTimer = nil;
    if (self.state == UIGestureRecognizerStatePossible) self.state = UIGestureRecognizerStateBegan;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    _currentPoint = [[touches anyObject] locationInView:nil];
    if (self.state == UIGestureRecognizerStatePossible) {
        CGFloat dx = _currentPoint.x - _startPoint.x;
        CGFloat dy = _currentPoint.y - _startPoint.y;
        if (dx * dx + dy * dy < kMediaSlop * kMediaSlop) return;
        self.state = fabsf(dx) > fabsf(dy) * kMediaSidewaysRatio ? UIGestureRecognizerStateBegan
                                                                 : UIGestureRecognizerStateFailed;
    } else if (self.state == UIGestureRecognizerStateBegan || self.state == UIGestureRecognizerStateChanged) {
        self.state = UIGestureRecognizerStateChanged;
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    if (self.state == UIGestureRecognizerStatePossible) {
        self.state = UIGestureRecognizerStateFailed;
    } else if (self.state == UIGestureRecognizerStateBegan || self.state == UIGestureRecognizerStateChanged) {
        self.state = UIGestureRecognizerStateEnded;
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    self.state = self.state == UIGestureRecognizerStatePossible ? UIGestureRecognizerStateFailed
                                                                : UIGestureRecognizerStateCancelled;
}

/* Nothing else may stop this one once it has started. */
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}

- (void)dealloc {
    [self stopHoldTimer];
    [super dealloc];
}

@end

@interface MediaVideoOverlayView : UIView {
    UILabel *_durationLabel;
    UIImageView *_iconView;
}
- (void)setDuration:(double)seconds;
@end

@implementation MediaVideoOverlayView

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;

        _durationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _durationLabel.backgroundColor = [UIColor clearColor];
        _durationLabel.font = [UIFont boldSystemFontOfSize:13];
        _durationLabel.textColor = [UIColor whiteColor];
        _durationLabel.textAlignment = UITextAlignmentRight;
        [self addSubview:_durationLabel];

        _iconView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"MediaVideoIcon.png"]];
        _iconView.backgroundColor = [UIColor clearColor];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_iconView];
    }
    return self;
}

- (void)setDuration:(double)seconds {
    NSInteger total = (NSInteger)(seconds + 0.5);
    NSInteger hours;
    NSInteger minutes;
    NSInteger secs;

    if (total < 0) total = 0;
    hours = total / 3600;
    minutes = (total % 3600) / 60;
    secs = total % 60;

    if (hours > 0) {
        _durationLabel.text = [NSString stringWithFormat:@"%d:%02d:%02d",
                               (int)hours, (int)minutes, (int)secs];
    } else {
        _durationLabel.text = [NSString stringWithFormat:@"%d:%02d",
                               (int)minutes, (int)secs];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat barHeight = self.bounds.size.height * 0.30f;
    if (barHeight > 18.0f) barHeight = 18.0f;
    if (barHeight < 12.0f) barHeight = 12.0f;
    _durationLabel.frame = CGRectMake(self.bounds.size.width - 66.0f,
                                      self.bounds.size.height - barHeight,
                                      60.0f, barHeight);
    _iconView.frame = CGRectMake(5.0f,
                                 self.bounds.size.height - barHeight + (barHeight - 10.0f) / 2.0f,
                                 16.0f, 10.0f);
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat barHeight = self.bounds.size.height * 0.30f;
    CGFloat barY;
    CGFloat iconW = 12.0f;
    CGFloat iconH = 9.0f;
    CGFloat iconX = 5.0f;
    CGFloat iconY;

    if (barHeight > 18.0f) barHeight = 18.0f;
    if (barHeight < 12.0f) barHeight = 12.0f;
    barY = self.bounds.size.height - barHeight;
    iconY = barY + (barHeight - iconH) / 2.0f;

    CGContextSetFillColorWithColor(context,
                                   [UIColor colorWithWhite:0.0f alpha:0.46f].CGColor);
    CGContextFillRect(context, CGRectMake(0, barY, self.bounds.size.width, barHeight));

}

- (void)dealloc {
    [_durationLabel release];
    [_iconView release];
    [super dealloc];
}

@end

@interface MediaThumbCell : UITableViewCell {
    UIImageView *_thumbs[8];
    id _checkViews[8];
    id _videoOverlays[8];
}
- (UIImageView *)thumbAtIndex:(NSInteger)index;
- (id)checkViewAtIndex:(NSInteger)index;
- (id)videoOverlayAtIndex:(NSInteger)index;
@end

@implementation MediaThumbCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        NSInteger i;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        for (i = 0; i < 8; i++) {
            UIImageView *thumb = [[UIImageView alloc] initWithFrame:CGRectZero];
            thumb.backgroundColor = [UIColor colorWithWhite:0.88f alpha:1.0f];
            thumb.clipsToBounds = YES;
            thumb.contentMode = UIViewContentModeScaleAspectFill;
            [self.contentView addSubview:thumb];
            _thumbs[i] = thumb;

            {
                MediaVideoOverlayView *overlay = [[MediaVideoOverlayView alloc] initWithFrame:CGRectZero];
                overlay.hidden = YES;
                [self.contentView addSubview:overlay];
                _videoOverlays[i] = overlay;
            }

            {
                Class circleClass = NSClassFromString(@"SelectionCircleView");
                if (circleClass != nil) {
                    UIView *circle = [[circleClass alloc] initWithFrame:CGRectZero];
                    circle.hidden = YES;
                    circle.userInteractionEnabled = NO;
                    [self.contentView addSubview:circle];
                    _checkViews[i] = circle;
                }
            }
        }
    }
    return self;
}

- (UIImageView *)thumbAtIndex:(NSInteger)index {
    if (index < 0 || index >= 8) return nil;
    return _thumbs[index];
}

- (id)checkViewAtIndex:(NSInteger)index {
    if (index < 0 || index >= 8) return nil;
    return _checkViews[index];
}

- (id)videoOverlayAtIndex:(NSInteger)index {
    if (index < 0 || index >= 8) return nil;
    return _videoOverlays[index];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    NSInteger columns = MediaColumns(width);
    CGFloat gap = 8.0f;
    CGFloat thumb = MediaThumbSize(width, columns);
    NSInteger i;

    for (i = 0; i < 8; i++) {
        if (i < columns) {
            _thumbs[i].frame = CGRectMake(gap + i * (thumb + gap), gap, thumb, thumb);
            if (_videoOverlays[i] != nil) {
                [(UIView *)_videoOverlays[i] setFrame:_thumbs[i].frame];
            }
            if (_checkViews[i] != nil) {
                [(UIView *)_checkViews[i] setFrame:CGRectMake(CGRectGetMaxX(_thumbs[i].frame) - 36.0f,
                                                              CGRectGetMaxY(_thumbs[i].frame) - 36.0f,
                                                              36.0f, 36.0f)];
                [self.contentView bringSubviewToFront:(UIView *)_checkViews[i]];
            }
        } else {
            _thumbs[i].hidden = YES;
            if (_videoOverlays[i] != nil) [(UIView *)_videoOverlays[i] setHidden:YES];
            if (_checkViews[i] != nil) [(UIView *)_checkViews[i] setHidden:YES];
        }
    }
}

- (void)dealloc {
    NSInteger i;
    for (i = 0; i < 8; i++) {
        [_thumbs[i] release];
        [(id)_videoOverlays[i] release];
        [(id)_checkViews[i] release];
    }
    [super dealloc];
}

@end

@implementation MediaPickerViewController

@synthesize delegate = _delegate;

- (void)loadView {
    CGRect frame = [[UIScreen mainScreen] applicationFrame];
    UIView *view = [[UIView alloc] initWithFrame:frame];
    view.backgroundColor = [UIColor whiteColor];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _tableView = [[UITableView alloc] initWithFrame:view.bounds style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.backgroundColor = [UIColor whiteColor];
    _tableView.allowsSelection = NO;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view addSubview:_tableView];
    {
        MediaDragRecognizer *drag = [[MediaDragRecognizer alloc] initWithTarget:self action:@selector(dragSelect:)];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(thumbTapped:)];

        drag.picker = self;
        drag.delaysTouchesEnded = NO;
        [_tableView addGestureRecognizer:drag];
        [_tableView.panGestureRecognizer requireGestureRecognizerToFail:drag];
        tap.delegate = self;
        [tap requireGestureRecognizerToFail:drag];
        [_tableView addGestureRecognizer:tap];
        _dragRecognizer = drag;
        [tap release];
    }

    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 120, frame.size.width - 40, 60)];
    _emptyLabel.backgroundColor = [UIColor clearColor];
    _emptyLabel.font = [UIFont boldSystemFontOfSize:13];
    _emptyLabel.textAlignment = UITextAlignmentCenter;
    _emptyLabel.textColor = [UIColor grayColor];
    _emptyLabel.numberOfLines = 2;
    _emptyLabel.text = NSLocalizedString(@"media.no_photos", nil);
    _emptyLabel.hidden = YES;
    [view addSubview:_emptyLabel];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spinner.frame = CGRectMake((frame.size.width - 37) / 2, (frame.size.height - 37) / 2, 37, 37);
    _spinner.hidesWhenStopped = YES;
    _spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [view addSubview:_spinner];

    self.view = view;
    [view release];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"media.picker_title", nil);

    _assets = [[NSMutableArray alloc] init];
    _selectedIndexes = [[NSMutableSet alloc] init];

    UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                           target:self
                                                                           action:@selector(cancelTapped:)];
    self.navigationItem.leftBarButtonItem = cancel;
    [cancel release];

    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"common.done", nil)
                                                             style:UIBarButtonItemStyleDone
                                                            target:self
                                                            action:@selector(doneTapped:)];
    self.navigationItem.rightBarButtonItem = done;
    done.enabled = NO;
    [done release];

    [self loadAssets];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _emptyLabel.frame = CGRectMake(20, self.view.bounds.size.height * 0.4f,
                                   self.view.bounds.size.width - 40, 60);
    _spinner.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self openAtNewest];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopAutoscroll];
}

/* Like Photos: the oldest at the top, opening at the bottom with the newest. Once only, and not
   before the grid has its real size. */
- (void)openAtNewest {
    NSInteger rows;

    if (_openedAtNewest || _loading || self.view.window == nil) return;
    rows = [self tableView:_tableView numberOfRowsInSection:0];
    if (rows == 0) return;
    _openedAtNewest = YES;
    [_tableView layoutIfNeeded];
    [_tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:rows - 1 inSection:0]
                      atScrollPosition:UITableViewScrollPositionBottom
                              animated:NO];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    if ([[[UIDevice currentDevice] model] rangeOfString:@"iPad"].location != NSNotFound) {
        return YES;
    }
    return orientation == UIInterfaceOrientationPortrait;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation
                                         duration:(NSTimeInterval)duration {
    _emptyLabel.frame = CGRectMake(20, self.view.bounds.size.height * 0.4f,
                                   self.view.bounds.size.width - 40, 60);
    _spinner.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2);
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation {
    [_tableView reloadData];
}

- (void)loadAssets {
    ALAssetsLibrary *library;

    _loading = YES;

    [_loadingAssets release];
    _loadingAssets = [[NSMutableArray alloc] init];
    [_spinner startAnimating];

    library = [[ALAssetsLibrary alloc] init];
    if (library == nil) {
        [self finishLoading];
        return;
    }

    [_library release];
    _library = library;
    if (gActiveMediaPicker != self) {
        [gActiveMediaPicker release];
        gActiveMediaPicker = [self retain];
    }

    [library enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos
                           usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
        if (group == nil) {
            [gActiveMediaPicker performSelectorOnMainThread:@selector(finishLoading)
                                                 withObject:nil
                                              waitUntilDone:NO];
            return;
        }

        {
            ALAssetsFilter *filter = [ALAssetsFilter allAssets];
            [group setAssetsFilter:filter];

            if (gActiveGroup != group) {
                [gActiveGroup release];
                gActiveGroup = [group retain];
            }
            if (gActiveFilter != filter) {
                [gActiveFilter release];
                gActiveFilter = [filter retain];
            }
        }

        [group enumerateAssetsUsingBlock:^(ALAsset *asset, NSUInteger index, BOOL *stop2) {
            if (asset != nil) {
                [gActiveMediaPicker addLoadingAsset:asset];
            }
        }];
    }
                          failureBlock:^(NSError *error) {
        [gActiveMediaPicker performSelectorOnMainThread:@selector(finishLoading)
                                             withObject:nil
                                          waitUntilDone:NO];
    }];
}

- (void)addLoadingAsset:(id)asset {
    if (asset != nil) [_loadingAssets addObject:asset];
}

- (void)finishLoading {
    if (!_loading) return;
    _loading = NO;

    [_spinner stopAnimating];
    [_assets release];
    _assets = [_loadingAssets retain];
    [_loadingAssets release];
    _loadingAssets = nil;
    /* _library stays alive until the picker goes away: an ALAsset is only usable while the
       library that returned it exists. Releasing it here left every asset without a
       representation, so Done exported nothing and no photo or video reached the Send tab. */
    [gActiveGroup release];
    gActiveGroup = nil;
    [gActiveFilter release];
    gActiveFilter = nil;

    _emptyLabel.hidden = ([_assets count] > 0);
    [_tableView reloadData];
    [self openAtNewest];
    [self updateDoneButton];

    if (gActiveMediaPicker == self) {
        gActiveMediaPicker = nil;
        [self release];
    }
}

- (void)updateDoneButton {
    NSUInteger selected = [_selectedIndexes count];
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"media.done_count", nil),
                       (int)selected];
    self.navigationItem.rightBarButtonItem.title = title;
    self.navigationItem.rightBarButtonItem.enabled = (selected > 0);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger columns = MediaColumns(tableView.bounds.size.width);
    return (NSInteger)(([_assets count] + columns - 1) / columns);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = tableView.bounds.size.width;
    NSInteger columns = MediaColumns(width);
    return MediaThumbSize(width, columns) + 16.0f;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"MediaThumbCell";
    MediaThumbCell *cell = (MediaThumbCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    NSInteger columns;
    NSInteger i;

    if (cell == nil) {
        cell = [[[MediaThumbCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:identifier] autorelease];
    }
    cell.backgroundColor = [UIColor whiteColor];
    cell.contentView.backgroundColor = [UIColor whiteColor];

    columns = MediaColumns(tableView.bounds.size.width);
    for (i = 0; i < 8; i++) {
        UIImageView *thumb = [cell thumbAtIndex:i];
        id check = [cell checkViewAtIndex:i];
        NSInteger assetIndex = indexPath.row * columns + i;

        if (i < columns && assetIndex < (NSInteger)[_assets count]) {
            ALAsset *asset = [_assets objectAtIndex:assetIndex];
            CGImageRef thumbnail = [asset thumbnail];
            UIImage *image = thumbnail != NULL ? [UIImage imageWithCGImage:thumbnail] : nil;
            BOOL selected = [_selectedIndexes containsObject:
                             [NSNumber numberWithInteger:assetIndex]];

            thumb.hidden = NO;
            thumb.image = image;
            {
                id overlay = [cell videoOverlayAtIndex:i];
                BOOL isVideo = [[asset valueForProperty:ALAssetPropertyType]
                                isEqualToString:ALAssetTypeVideo];
                if (overlay != nil) {
                    [overlay setHidden:!isVideo];
                    if (isVideo) {
                        double duration = [[asset valueForProperty:ALAssetPropertyDuration] doubleValue];
                        [(MediaVideoOverlayView *)overlay setDuration:duration];
                    }
                }
            }
            if (check != nil) {
                [check setHidden:!selected];
                [(id<MediaSelectionCircle>)check setChecked:selected];
            }
        } else {
            thumb.hidden = YES;
            thumb.image = nil;
            {
                id overlay = [cell videoOverlayAtIndex:i];
                if (overlay != nil) [overlay setHidden:YES];
            }
            if (check != nil) [check setHidden:YES];
        }
    }
    return cell;
}

- (void)setCheckForIndex:(NSInteger)index selected:(BOOL)selected {
    NSInteger columns = MediaColumns(_tableView.bounds.size.width);
    NSInteger row = index / columns;
    NSInteger column = index % columns;
    NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:0];
    MediaThumbCell *cell = (MediaThumbCell *)[_tableView cellForRowAtIndexPath:path];
    id check = [cell checkViewAtIndex:column];

    if (check != nil) {
        [(UIView *)check setHidden:!selected];
        [(id<MediaSelectionCircle>)check setChecked:selected];
    }
}

/* The thumbnail under a point in the table, or -1. Each thumbnail owns the gaps around it, so a
   finger between two still means one of them. With `nearest`, a point past the last thumbnail,
   above the first row or below the last still gives one, so a range follows the finger smoothly. */
- (NSInteger)assetIndexAtPoint:(CGPoint)point nearest:(BOOL)nearest {
    CGFloat width = _tableView.bounds.size.width;
    NSInteger count = (NSInteger)[_assets count];
    NSInteger columns = MediaColumns(width);
    CGFloat gap = 8.0f;
    CGFloat thumb = MediaThumbSize(width, columns);
    CGFloat rowHeight = thumb + 16.0f;
    NSInteger row, column, index;

    if (count == 0) return -1;
    if (point.y < 0.0f) return nearest ? 0 : -1;
    row = (NSInteger)(point.y / rowHeight);
    if (row >= (count + columns - 1) / columns) return nearest ? count - 1 : -1;
    column = (NSInteger)floorf((point.x - gap / 2.0f) / (thumb + gap));
    if (column < 0) column = 0;
    if (column >= columns) column = columns - 1;
    index = row * columns + column;
    if (index >= count) return nearest ? count - 1 : -1;
    return index;
}

- (void)setIndex:(NSInteger)index selected:(BOOL)selected {
    NSNumber *key = [NSNumber numberWithInteger:index];

    if ([_selectedIndexes containsObject:key] == selected) return;
    if (selected) {
        [_selectedIndexes addObject:key];
    } else {
        [_selectedIndexes removeObject:key];
    }
    [self setCheckForIndex:index selected:selected];
}

- (void)thumbTapped:(UITapGestureRecognizer *)tap {
    NSInteger index = [self assetIndexAtPoint:[tap locationInView:_tableView] nearest:NO];

    if (index < 0) return;
    [self setIndex:index selected:![_selectedIndexes containsObject:[NSNumber numberWithInteger:index]]];
    [self updateDoneButton];
}

/* A tap that stops a moving grid only stops it. */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    return !_tableView.decelerating;
}

- (BOOL)canStartDragAtPoint:(CGPoint)tablePoint {
    return [self assetIndexAtPoint:tablePoint nearest:NO] >= 0;
}

/* Everything from the first thumbnail to the one under the finger, in reading order, takes the
   first one's new state; thumbnails the range leaves go back to how they were. */
- (void)dragToIndex:(NSInteger)index {
    NSInteger oldLow, oldHigh, newLow, newHigh, low, high, i;

    if (index < 0 || index == _dragCurrent) return;
    oldLow = _dragCurrent < 0 ? _dragAnchor : MIN(_dragAnchor, _dragCurrent);
    oldHigh = _dragCurrent < 0 ? _dragAnchor : MAX(_dragAnchor, _dragCurrent);
    newLow = MIN(_dragAnchor, index);
    newHigh = MAX(_dragAnchor, index);
    low = MIN(oldLow, newLow);
    high = MAX(oldHigh, newHigh);
    for (i = low; i <= high; i++) {
        BOOL inRange = i >= newLow && i <= newHigh;
        /* Only what entered or left the range: a long selection must not cost more per frame. */
        if (_dragCurrent >= 0 && inRange && i >= oldLow && i <= oldHigh) continue;
        [self setIndex:i selected:inRange ? _dragSelecting
                                          : [_dragOriginal containsObject:[NSNumber numberWithInteger:i]]];
    }
    _dragCurrent = index;
    [self updateDoneButton];
}

- (void)dragSelect:(MediaDragRecognizer *)recognizer {
    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan: {
            NSInteger start = [self assetIndexAtPoint:[_tableView convertPoint:recognizer.startPoint fromView:nil]
                                              nearest:NO];
            [_dragOriginal release];
            _dragOriginal = nil;
            if (start < 0) return;
            _dragOriginal = [_selectedIndexes copy];
            _dragSelecting = ![_dragOriginal containsObject:[NSNumber numberWithInteger:start]];
            _dragAnchor = start;
            _dragCurrent = -1;
            [self dragToIndex:start];
        }   /* fall through: the finger may have moved on already */
        case UIGestureRecognizerStateChanged:
            if (_dragOriginal == nil) return;
            [self dragToIndex:[self assetIndexAtPoint:[_tableView convertPoint:recognizer.currentPoint fromView:nil]
                                              nearest:YES]];
            [self updateAutoscroll];
            break;
        default:
            [self stopAutoscroll];
            [_dragOriginal release];
            _dragOriginal = nil;
            break;
    }
}

/* Near the top or bottom of the grid it scrolls, faster closer to the edge, and the selection
   keeps following. Gentle at the start of the zone, quick at the edge. */
- (CGFloat)autoscrollSpeed {
    CGPoint point = [_tableView convertPoint:[(MediaDragRecognizer *)_dragRecognizer currentPoint] fromView:nil];
    CGFloat top = _tableView.contentOffset.y;
    CGFloat bottom = top + _tableView.bounds.size.height;
    CGFloat zone = MIN(kMediaEdgeZone, (bottom - top) / 4.0f);
    CGFloat depth, sign;

    if (point.y < top + zone) {
        depth = (top + zone - point.y) / zone;
        sign = -1.0f;
    } else if (point.y > bottom - zone) {
        depth = (point.y - (bottom - zone)) / zone;
        sign = 1.0f;
    } else {
        return 0.0f;
    }
    if (depth > 1.0f) depth = 1.0f;
    return sign * (kMediaMinSpeed + (kMediaMaxSpeed - kMediaMinSpeed) * depth * depth);
}

- (void)updateAutoscroll {
    if ([self autoscrollSpeed] == 0.0f) {
        [self stopAutoscroll];
    } else if (_displayLink == nil) {
        /* The link retains self; stopAutoscroll always runs when the finger lifts. */
        _displayLink = [[CADisplayLink displayLinkWithTarget:self selector:@selector(autoscrollTick:)] retain];
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        _lastTick = 0;
    }
}

- (void)stopAutoscroll {
    [_displayLink invalidate];
    [_displayLink release];
    _displayLink = nil;
}

- (void)autoscrollTick:(CADisplayLink *)link {
    CGFloat speed = [self autoscrollSpeed];
    CFTimeInterval now = link.timestamp;
    CFTimeInterval step = _lastTick > 0 ? MIN(now - _lastTick, 0.05) : link.duration;
    CGFloat maxY = MAX(0.0f, _tableView.contentSize.height - _tableView.bounds.size.height);
    CGFloat y;
    CGFloat scale = [UIScreen mainScreen].scale;

    if (speed == 0.0f) {
        [self stopAutoscroll];
        return;
    }
    _lastTick = now;
    y = _tableView.contentOffset.y + speed * (CGFloat)step;
    y = MAX(0.0f, MIN(maxY, y));
    /* Whole pixels, so thumbnails stay sharp while scrolling. */
    y = roundf(y * scale) / scale;
    if (y == _tableView.contentOffset.y) return;
    [_tableView setContentOffset:CGPointMake(_tableView.contentOffset.x, y) animated:NO];
    [self dragToIndex:[self assetIndexAtPoint:[_tableView convertPoint:[(MediaDragRecognizer *)_dragRecognizer currentPoint]
                                                              fromView:nil]
                                      nearest:YES]];
}

- (void)cancelTapped:(id)sender {
    if ([_delegate respondsToSelector:@selector(mediaPickerDidCancel:)]) {
        [_delegate mediaPickerDidCancel:self];
    } else {
        [self dismissModalViewControllerAnimated:YES];
    }
}

- (void)showExportHUD {
    UIView *container;
    UIView *box;
    UIActivityIndicatorView *spinner;
    CGRect bounds;

    if (_exportHUD != nil) return;
    container = self.navigationController != nil ? self.navigationController.view : self.view;
    bounds = container.bounds;

    _exportHUD = [[UIView alloc] initWithFrame:bounds];
    _exportHUD.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.28f];
    _exportHUD.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _exportHUD.userInteractionEnabled = YES;

    box = [[UIView alloc] initWithFrame:CGRectMake((bounds.size.width - 86.0f) / 2.0f,
                                                   (bounds.size.height - 86.0f) / 2.0f,
                                                   86.0f, 86.0f)];
    box.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.78f];
    box.layer.cornerRadius = 12.0f;
    box.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                           UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    box.userInteractionEnabled = NO;
    [_exportHUD addSubview:box];

    spinner = [[UIActivityIndicatorView alloc]
               initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    spinner.frame = CGRectMake((86.0f - 37.0f) / 2.0f, (86.0f - 37.0f) / 2.0f, 37.0f, 37.0f);
    spinner.hidesWhenStopped = NO;
    [spinner startAnimating];
    [box addSubview:spinner];

    [spinner release];
    [box release];
    [container addSubview:_exportHUD];
}

- (void)hideExportHUD {
    [_exportHUD removeFromSuperview];
    [_exportHUD release];
    _exportHUD = nil;
}

- (void)doneTapped:(id)sender {
    if (_exporting) return;
    _exporting = YES;

    self.navigationItem.leftBarButtonItem.enabled = NO;
    _tableView.userInteractionEnabled = NO;
    [self showExportHUD];

    [self performSelectorInBackground:@selector(exportSelectedItems)
                           withObject:nil];
}

/* MIME type for a photo or video file name, as LocalSend's own clients send it. */
static NSString *MediaMimeType(NSString *name) {
    NSString *extension = [[name pathExtension] lowercaseString];
    if ([extension isEqualToString:@"jpg"] || [extension isEqualToString:@"jpeg"]) return @"image/jpeg";
    if ([extension isEqualToString:@"png"]) return @"image/png";
    if ([extension isEqualToString:@"gif"]) return @"image/gif";
    if ([extension isEqualToString:@"tif"] || [extension isEqualToString:@"tiff"]) return @"image/tiff";
    if ([extension isEqualToString:@"bmp"]) return @"image/bmp";
    if ([extension isEqualToString:@"mov"]) return @"video/quicktime";
    if ([extension isEqualToString:@"mp4"]) return @"video/mp4";
    if ([extension isEqualToString:@"m4v"]) return @"video/x-m4v";
    return @"application/octet-stream";
}

/* File extension for a representation's UTI, for assets that don't report a file name. */
static NSString *MediaExtensionForUTI(NSString *uti, BOOL video) {
    uti = [uti lowercaseString];
    if ([uti rangeOfString:@"jpeg"].location != NSNotFound) return @"JPG";
    if ([uti rangeOfString:@"png"].location != NSNotFound) return @"PNG";
    if ([uti rangeOfString:@"gif"].location != NSNotFound) return @"GIF";
    if ([uti rangeOfString:@"tiff"].location != NSNotFound) return @"TIFF";
    if ([uti rangeOfString:@"mpeg-4"].location != NSNotFound) return @"MP4";
    if ([uti rangeOfString:@"m4v"].location != NSNotFound) return @"M4V";
    if ([uti rangeOfString:@"quicktime"].location != NSNotFound) return @"MOV";
    return video ? @"MOV" : @"JPG";
}

/* Copies one asset's original file (the photo or video as the camera saved it) out of the
   library, under its own name (IMG_0001.JPG), into a new folder in the temporary directory,
   so that two assets with the same name can't overwrite each other. Returns the Send item,
   or nil if the library couldn't give the file. */
- (NSDictionary *)exportAsset:(ALAsset *)asset {
    NSFileManager *manager = [NSFileManager defaultManager];
    ALAssetRepresentation *representation = [asset defaultRepresentation];
    BOOL video = [[asset valueForProperty:ALAssetPropertyType] isEqualToString:ALAssetTypeVideo];
    long long size;
    NSString *name = nil;
    NSString *folder;
    NSString *path;
    NSFileHandle *handle;
    uint8_t *buffer;
    long long offset = 0;

    if (representation == nil) return nil;
    size = [representation size];
    if (size <= 0) return nil;

    if ([representation respondsToSelector:@selector(filename)]) {
        name = [[representation filename] lastPathComponent];
    }
    if ([name length] == 0 || [name hasPrefix:@"."]) {
        name = [NSString stringWithFormat:@"%@_%u.%@", video ? @"VID" : @"IMG",
                (unsigned)[[NSDate date] timeIntervalSince1970],
                MediaExtensionForUTI([representation UTI], video)];
    }

    folder = [NSTemporaryDirectory() stringByAppendingPathComponent:
              [NSString stringWithFormat:@"picked-%u-%u",
               (unsigned)[[NSDate date] timeIntervalSince1970], (unsigned)arc4random()]];
    if (![manager createDirectoryAtPath:folder withIntermediateDirectories:YES
                             attributes:nil error:NULL]) {
        return nil;
    }
    path = [folder stringByAppendingPathComponent:name];
    [manager createFileAtPath:path contents:nil attributes:nil];
    handle = [NSFileHandle fileHandleForWritingAtPath:path];
    buffer = (uint8_t *)malloc(256 * 1024);

    if (handle != nil && buffer != NULL) {
        while (offset < size) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSUInteger length = (NSUInteger)MIN((long long)(256 * 1024), size - offset);
            NSUInteger read = [representation getBytes:buffer
                                            fromOffset:offset
                                                length:length
                                                 error:NULL];
            if (read > 0) {
                [handle writeData:[NSData dataWithBytesNoCopy:buffer length:read freeWhenDone:NO]];
                offset += read;
            }
            [pool release];
            if (read == 0) break;
        }
        [handle closeFile];
    }
    if (buffer != NULL) free(buffer);

    if (offset != size) {
        [manager removeItemAtPath:folder error:NULL];
        return nil;
    }
    return [NSDictionary dictionaryWithObjectsAndKeys:
            video ? @"video" : @"photo", @"kind",
            path, @"path",
            name, @"name",
            MediaMimeType(name), @"type",
            [NSNumber numberWithLongLong:size], @"size", nil];
}

- (NSArray *)selectedItems {
    NSMutableArray *items = [NSMutableArray array];
    NSArray *indexes = [[_selectedIndexes allObjects] sortedArrayUsingSelector:@selector(compare:)];
    NSInteger i;

    for (i = 0; i < (NSInteger)[indexes count]; i++) {
        NSInteger index = [[indexes objectAtIndex:i] integerValue];
        NSDictionary *item;

        if (index < 0 || index >= (NSInteger)[_assets count]) continue;
        item = [self exportAsset:[_assets objectAtIndex:index]];
        if (item != nil) [items addObject:item];
    }
    return items;
}

- (void)exportSelectedItems {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSArray *items = [[self selectedItems] retain];

    [self performSelectorOnMainThread:@selector(finishExportWithItems:)
                           withObject:items
                        waitUntilDone:NO];
    [items release];
    [pool release];
}

- (void)finishExportWithItems:(NSArray *)items {
    _exporting = NO;
    [self hideExportHUD];
    self.navigationItem.leftBarButtonItem.enabled = YES;
    _tableView.userInteractionEnabled = YES;

    if ([_delegate respondsToSelector:@selector(mediaPicker:didFinishWithItems:)]) {
        [_delegate mediaPicker:self didFinishWithItems:items];
    } else {
        [self dismissModalViewControllerAnimated:YES];
    }
}

- (void)dealloc {
    if (gActiveMediaPicker == self) gActiveMediaPicker = nil;
    [gActiveGroup release];
    gActiveGroup = nil;
    [gActiveFilter release];
    gActiveFilter = nil;
    [_dragRecognizer release];
    [_dragOriginal release];
    [_tableView release];
    [_assets release];
    [_loadingAssets release];
    [_selectedIndexes release];
    [_spinner release];
    [_exportHUD release];
    [_emptyLabel release];
    [_library release];
    [super dealloc];
}

@end


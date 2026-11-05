#import "OSTransfer.h"

NSString * const OSTransferDidStartNotification = @"OSTransferDidStartNotification";
NSString * const OSTransferDidChangeNotification = @"OSTransferDidChangeNotification";

#define OS_SPEED_WINDOW 3.0

NSString *OSFormatBytes(long long bytes) {
    if (bytes < 1024) {
        return [NSString stringWithFormat:@"%lld B", bytes];
    } else if (bytes < 1024 * 1024) {
        return [NSString stringWithFormat:@"%.1f KB", (double)bytes / 1024.0];
    } else if (bytes < 1024LL * 1024LL * 1024LL) {
        return [NSString stringWithFormat:@"%.1f MB", (double)bytes / (1024.0 * 1024.0)];
    }
    return [NSString stringWithFormat:@"%.2f GB", (double)bytes / (1024.0 * 1024.0 * 1024.0)];
}

NSString *OSFormatDuration(NSTimeInterval seconds) {
    long total = (long)(seconds + 0.5);
    if (total < 0) total = 0;
    if (total >= 3600) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", total / 3600, (total / 60) % 60, total % 60];
    }
    return [NSString stringWithFormat:@"%ld:%02ld", total / 60, total % 60];
}

@implementation OSTransferFile

- (void)dealloc {
    [_name release];
    [super dealloc];
}

@end

@implementation OSTransfer

- (id)initSending:(BOOL)sending peer:(NSString *)alias type:(NSString *)deviceType files:(NSArray *)files {
    if ((self = [super init])) {
        NSMutableArray *list = [NSMutableArray arrayWithCapacity:[files count]];

        for (NSDictionary *info in files) {
            OSTransferFile *file = [[OSTransferFile alloc] init];
            file.name = [info objectForKey:@"name"];
            file.size = [[info objectForKey:@"size"] longLongValue];
            [list addObject:file];
            [file release];
        }
        _sending = sending;
        _peerAlias = [alias copy];
        _peerType = [deviceType copy];
        _files = [list copy];
        _state = sending ? OSTransferStateWaiting : OSTransferStateRunning;
        _startTime = [NSDate timeIntervalSinceReferenceDate];
        _samples = [[NSMutableArray alloc] init];
        _identifier = [[NSString alloc] initWithFormat:@"%.3f-%u", _startTime, (unsigned)arc4random()];
    }
    return self;
}

- (NSDictionary *)snapshot {
    NSMutableArray *files = [NSMutableArray arrayWithCapacity:[_files count]];
    for (OSTransferFile *file in _files) {
        [files addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                          file.name != nil ? file.name : @"", @"name",
                          [NSNumber numberWithLongLong:file.size], @"size",
                          [NSNumber numberWithLongLong:file.written], @"written",
                          [NSNumber numberWithInt:file.state], @"state", nil]];
    }
    return [NSDictionary dictionaryWithObjectsAndKeys:
            _identifier, @"id",
            [NSNumber numberWithBool:_sending], @"sending",
            _peerAlias != nil ? _peerAlias : @"", @"peer",
            _peerType != nil ? _peerType : @"", @"type",
            [NSNumber numberWithInt:_state], @"state",
            _message != nil ? _message : @"", @"message",
            [NSNumber numberWithDouble:[self elapsed]], @"elapsed",
            files, @"files", nil];
}

- (id)initWithSnapshot:(NSDictionary *)snapshot {
    NSMutableArray *files = [NSMutableArray array];
    for (NSDictionary *file in [snapshot objectForKey:@"files"]) {
        [files addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                          [file objectForKey:@"name"], @"name", [file objectForKey:@"size"], @"size", nil]];
    }
    if ((self = [self initSending:[[snapshot objectForKey:@"sending"] boolValue]
                             peer:[snapshot objectForKey:@"peer"]
                             type:[snapshot objectForKey:@"type"]
                            files:files])) {
        [_identifier release];
        _identifier = [[snapshot objectForKey:@"id"] copy];
        _remote = YES;
        _startTime = [NSDate timeIntervalSinceReferenceDate] - [[snapshot objectForKey:@"elapsed"] doubleValue];
        [self applySnapshot:snapshot];
    }
    return self;
}

- (void)applySnapshot:(NSDictionary *)snapshot {
    NSArray *files = [snapshot objectForKey:@"files"];
    OSTransferState state = (OSTransferState)[[snapshot objectForKey:@"state"] intValue];
    NSUInteger i;

    if (![self isActive]) return;
    for (i = 0; i < [files count] && i < [_files count]; i++) {
        NSDictionary *info = [files objectAtIndex:i];
        OSTransferFile *file = [_files objectAtIndex:i];
        file.written = [[info objectForKey:@"written"] longLongValue];
        file.state = (OSTransferFileState)[[info objectForKey:@"state"] intValue];
    }
    [self addSample];
    if (state == OSTransferStateRunning || state == OSTransferStateWaiting) {
        if (_state != state) {
            _state = state;
            [self changed];
        }
        return;
    }
    {
        NSString *message = [snapshot objectForKey:@"message"];
        NSTimeInterval elapsed = [[snapshot objectForKey:@"elapsed"] doubleValue];
        _state = state;
        [_message release];
        _message = [message length] > 0 ? [message copy] : nil;
        _endTime = [NSDate timeIntervalSinceReferenceDate];
        _startTime = _endTime - elapsed;
        [self changed];
    }
}

- (void)changed {
    [[NSNotificationCenter defaultCenter] postNotificationName:OSTransferDidChangeNotification object:self];
}

- (OSTransferFile *)fileAt:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)[_files count]) return nil;
    return [_files objectAtIndex:index];
}

- (void)setRunning {
    if (_state != OSTransferStateWaiting) return;
    _state = OSTransferStateRunning;
    /* The time spent waiting for the receiver to accept is not transfer time. */
    _startTime = [NSDate timeIntervalSinceReferenceDate];
    [self changed];
}

- (void)addSample {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSArray *sample = [NSArray arrayWithObjects:[NSNumber numberWithDouble:now],
                       [NSNumber numberWithLongLong:[self transferredBytes]], nil];

    [_samples addObject:sample];
    while ([_samples count] > 2 &&
           now - [[[_samples objectAtIndex:1] objectAtIndex:0] doubleValue] >= OS_SPEED_WINDOW) {
        [_samples removeObjectAtIndex:0];
    }
}

- (void)fileStarted:(NSInteger)index {
    OSTransferFile *file = [self fileAt:index];
    if (file == nil || ![self isActive]) return;
    if (_state == OSTransferStateWaiting) [self setRunning];
    file.state = OSTransferFileRunning;
    file.written = 0;
    [self addSample];
    [self changed];
}

- (void)file:(NSInteger)index wrote:(long long)written {
    OSTransferFile *file = [self fileAt:index];
    if (file == nil || ![self isActive]) return;
    file.written = written;
    [self addSample];
}

- (void)fileFinished:(NSInteger)index {
    OSTransferFile *file = [self fileAt:index];
    if (file == nil || ![self isActive]) return;
    file.state = OSTransferFileDone;
    if (file.size > 0) file.written = file.size;
    [self addSample];
    [self changed];
}

- (void)fileSkipped:(NSInteger)index {
    OSTransferFile *file = [self fileAt:index];
    if (file == nil) return;
    file.state = OSTransferFileSkipped;
    [self changed];
}

- (void)endWithState:(OSTransferState)state message:(NSString *)message {
    if (![self isActive]) return;
    _state = state;
    [_message release];
    _message = [message copy];
    _endTime = [NSDate timeIntervalSinceReferenceDate];
    for (OSTransferFile *file in _files) {
        if (file.state == OSTransferFileRunning) {
            file.state = state == OSTransferStateFinished ? OSTransferFileDone : OSTransferFileFailed;
        } else if (file.state == OSTransferFileQueued) {
            file.state = state == OSTransferStateFinished ? OSTransferFileDone : OSTransferFileSkipped;
        }
    }
    [self changed];
}

- (BOOL)isActive {
    return _state == OSTransferStateWaiting || _state == OSTransferStateRunning;
}

- (long long)totalBytes {
    long long total = 0;
    for (OSTransferFile *file in _files) {
        if (file.state != OSTransferFileSkipped) total += file.size;
    }
    return total;
}

- (long long)transferredBytes {
    long long done = 0;
    for (OSTransferFile *file in _files) {
        if (file.state == OSTransferFileDone) {
            done += file.size;
        } else if (file.state == OSTransferFileRunning || file.state == OSTransferFileFailed) {
            done += file.written;
        }
    }
    return done;
}

- (NSInteger)fileCount {
    NSInteger count = 0;
    for (OSTransferFile *file in _files) {
        if (file.state != OSTransferFileSkipped) count++;
    }
    return count;
}

- (NSInteger)finishedFileCount {
    NSInteger count = 0;
    for (OSTransferFile *file in _files) {
        if (file.state == OSTransferFileDone) count++;
    }
    return count;
}

- (NSTimeInterval)elapsed {
    NSTimeInterval end = [self isActive] ? [NSDate timeIntervalSinceReferenceDate] : _endTime;
    return end > _startTime ? end - _startTime : 0;
}

- (double)bytesPerSecond {
    if (![self isActive]) {
        /* Average over the whole transfer once it is over. */
        NSTimeInterval elapsed = [self elapsed];
        return elapsed > 0.2 ? (double)[self transferredBytes] / elapsed : 0;
    }
    if ([_samples count] < 2) return 0;
    {
        NSArray *first = [_samples objectAtIndex:0];
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval span = now - [[first objectAtIndex:0] doubleValue];
        long long bytes = [self transferredBytes] - [[first objectAtIndex:1] longLongValue];
        if (span < 0.5 || bytes < 0) return 0;
        return (double)bytes / span;
    }
}

- (NSTimeInterval)secondsLeft {
    double speed = [self bytesPerSecond];
    long long left = [self totalBytes] - [self transferredBytes];
    if (![self isActive] || speed <= 1.0) return -1;
    return left > 0 ? (double)left / speed : 0;
}

- (void)dealloc {
    [_peerAlias release];
    [_peerType release];
    [_files release];
    [_message release];
    [_samples release];
    [_identifier release];
    [super dealloc];
}

@end

#import "AutomationBridge.h"

@interface CollectionFixture : NSObject
@property(nonatomic, strong) NSArray *values;
@property(nonatomic) BOOL failGet;
- (NSArray *)get;
@end
@implementation CollectionFixture
- (NSArray *)get {
    if (self.failGet) [NSException raise:NSRangeException format:@"Collection changed during evaluation"];
    return self.values;
}
@end

// Reproduce the crash's stale count with no corresponding element.
@interface ChangedArray : NSArray
@end
@implementation ChangedArray
- (NSUInteger)count { return 1; }
- (id)objectAtIndex:(NSUInteger)index {
    [NSException raise:NSRangeException format:@"range {0, 1} extends beyond bounds for empty array"];
    return nil;
}
@end

int main(void) {
    @autoreleasepool {
        int failures = 0;
        #define CHECK(condition, message) do { \
            if (!(condition)) { NSLog(@"FAIL: %@", message); failures++; } \
            else { NSLog(@"PASS: %@", message); } \
        } while (0)
        CollectionFixture *fixture = [CollectionFixture new];
        NSError *error = nil;
        fixture.values = @[];
        NSArray *empty = FCSnapshotElements(fixture, &error);
        CHECK(empty != nil && empty.count == 0 && error == nil, @"An empty browser is a successful read");

        NSMutableArray *live = [NSMutableArray arrayWithArray:@[@"first", @"second"]];
        fixture.values = live;
        NSArray *snapshot = FCSnapshotElements(fixture, &error);
        [live removeAllObjects];
        CHECK(([snapshot isEqualToArray:@[@"first", @"second"]]), @"Later collection changes do not alter the detached snapshot");

        fixture.values = nil;
        CHECK(FCSnapshotElements(fixture, &error) == nil && error != nil, @"An unavailable collection fails instead of becoming an empty success");

        error = nil;
        fixture.failGet = YES;
        CHECK(FCSnapshotElements(fixture, &error) == nil && error != nil, @"An exception during remote evaluation is contained");

        error = nil;
        fixture.failGet = NO;
        fixture.values = [ChangedArray new];
        CHECK(FCSnapshotElements(fixture, &error) == nil && error != nil, @"The reported range exception returns a failure without terminating");
        error = nil;
        fixture.values = @[@"reopened"];
        CHECK(([FCSnapshotElements(fixture, &error) isEqualToArray:@[@"reopened"]] && error == nil), @"A later read recovers after the collection changes");
        NSLog(@"Automation bridge checks: %d failures", failures);
        return failures == 0 ? 0 : 1;
    }
}

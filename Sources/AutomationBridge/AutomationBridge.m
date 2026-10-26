#import "AutomationBridge.h"
#import <ScriptingBridge/ScriptingBridge.h>

NSArray *FCSnapshotElements(id elements, NSError **error) {
    @try {
        NSArray *resolved = [elements get];
        if (![resolved isKindOfClass:[NSArray class]]) {
            if (error) *error = [NSError errorWithDomain:@"Tethri.Automation" code:1 userInfo:@{
                NSLocalizedDescriptionKey: @"The browser collection is unavailable."
            }];
            return nil;
        }
        // Never fast-enumerate SBElementArray: its remote count and contents can
        // change between Apple Events. Only the detached result reaches Swift.
        NSUInteger count = resolved.count;
        NSMutableArray *snapshot = [NSMutableArray arrayWithCapacity:count];
        for (NSUInteger index = 0; index < count; index++) {
            [snapshot addObject:[resolved objectAtIndex:index]];
        }
        return [snapshot copy];
    } @catch (NSException *exception) {
        if (error) *error = [NSError errorWithDomain:@"Tethri.Automation" code:2 userInfo:@{
            NSLocalizedDescriptionKey: @"The browser collection changed during the read.",
            @"exceptionName": exception.name
        }];
        return nil;
    }
}

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Evaluate a Scripting Bridge collection and copy it before Swift enumerates it.
/// NSError also contains Objective-C exceptions, which Swift do/catch cannot catch.
FOUNDATION_EXPORT NSArray * _Nullable FCSnapshotElements(id elements, NSError **error);

NS_ASSUME_NONNULL_END

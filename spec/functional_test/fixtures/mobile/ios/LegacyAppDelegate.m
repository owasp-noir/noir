#import "LegacyAppDelegate.h"

// A legacy Objective-C app delegate. Its open-URL / continue-userActivity
// handlers use the Objective-C message-send syntax (and wrapped signatures),
// which the Swift-only discovery used to miss entirely.
@implementation LegacyAppDelegate

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options
{
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"token"]) {
            return [self handleObjcDeepLink:item.value];
        }
    }
    return [self handleObjcDeepLink:url];
}

- (BOOL)application:(UIApplication *)application
    continueUserActivity:(NSUserActivity *)userActivity
      restorationHandler:(void (^)(NSArray *))restorationHandler
{
    return [self routeObjcUniversalLink:userActivity];
}

@end

//
//  SDLUIKitDelegate.m
//  ogwu
//
//  Created by Kenechukwu Akubue on 11/09/2026.
//

// SDLUIKitDelegate.m

#import <UIKit/UIKit.h>
#import <GoogleSignIn/GoogleSignIn.h>

@interface SDLUIKitDelegate : NSObject <UIApplicationDelegate>
@end

@interface SDLUIKitDelegate (GIDSignInHandling)
- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
            options:(NSDictionary<NSString *, id> *)options;
@end

@implementation SDLUIKitDelegate (GIDSignInHandling)

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
            options:(NSDictionary<NSString *, id> *)options {
    NSLog(@"calling me..................................");
    return [[GIDSignIn sharedInstance] handleURL:url];
}

@end

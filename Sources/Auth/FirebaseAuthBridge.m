#import "FirebaseBridge.h"

__attribute__((constructor))
static void _RegisterAuthBridgeDelegateProtocol(void) {
    (void)@protocol(FirebaseAuthBridgeDelegate);
}

@implementation FirebaseAuthBridge

- (void)addAuthStateDidChangeListener {
    __weak __auto_type weakSelf = self;
    self.handle = [[FIRAuth auth] addAuthStateDidChangeListener:^(FIRAuth *auth, FIRUser *user) {
        [weakSelf.delegate authStateChanged:auth user:user];
    }];
}

- (void)removeAuthStateDidChangeListener {
    [[FIRAuth auth] removeAuthStateDidChangeListener:self.handle];
}

- (void)createUserWithEmail:(NSString *)email password:(NSString *)password {
    __weak __auto_type weakSelf = self;
    [[FIRAuth auth] createUserWithEmail:email
                                password:password
                              completion:^(FIRAuthDataResult * _Nullable authResult,
                                           NSError * _Nullable error) {
        [weakSelf.delegate userCreated:authResult error:error];
    }];
}

- (void)signInWithGoogle {
    // 1. Cleanly grab the window from the AppDelegate to avoid deprecation warnings
    UIViewController *rootViewController = nil;
    UIScene *scene = [UIApplication sharedApplication].connectedScenes.allObjects.firstObject;
    UIWindowScene *windowScene = (UIWindowScene *) scene;
    rootViewController = windowScene.windows.firstObject.rootViewController;
    NSLog(@"%@", rootViewController);
    
    
    // 2. Trigger Google Sign-In with the valid SDLLaunchStoryboardViewController
    __weak __auto_type weakSelf = self;
    [GIDSignIn.sharedInstance signInWithPresentingViewController:rootViewController
                                                      completion:^(GIDSignInResult * _Nullable signInResult, NSError * _Nullable error) {
        __auto_type strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        [weakSelf.delegate signInWithGoogleCompletion:signInResult error:error];
    }];
}

- (BOOL)signOut {
    NSError *signOutError;
    BOOL status = [[FIRAuth auth] signOut:&signOutError];
    if (!status) {
        NSLog(@"Error signing out: %@", signOutError);
    }
    return status;
}

- (void)signInWithCredentials:(FIRAuthCredential *)credential {
    __weak __auto_type weakSelf = self;
    [[FIRAuth auth] signInWithCredential:credential
                              completion:^(FIRAuthDataResult * _Nullable authResult,
                                           NSError * _Nullable error) {
        [weakSelf.delegate signInWithCredentialsCompletion:authResult error:error];
    }];
}
@end

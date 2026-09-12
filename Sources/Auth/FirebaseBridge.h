//
//  FirebaseBridge.h
//  ogwu
//
//  Created by Kenechukwu Akubue on 07/09/2026.
//


#import <Foundation/Foundation.h>
#import <FirebaseAuth/FirebaseAuth.h>
#import <UIKit/UIKit.h>
#import <GoogleSignIn/GoogleSignIn.h>

#pragma mark - Auth

@protocol FirebaseAuthBridgeDelegate <NSObject>
@optional
- (void)authStateChanged:(FIRAuth *)auth user:(FIRUser *)user;
- (void)userCreated:(FIRAuthDataResult *)authResult error:(NSError *)error;
- (void)signInWithGoogleCompletion:(GIDSignInResult *)result error:(NSError *)error;
- (void)signInWithCredentialsCompletion:(FIRAuthDataResult *)authResult error:(NSError *)error;
@end

@interface FirebaseAuthBridge : NSObject
@property (nonatomic, weak) id<FirebaseAuthBridgeDelegate> delegate;
@property (nonatomic, strong) FIRAuthStateDidChangeListenerHandle handle;
- (void)addAuthStateDidChangeListener;
- (void)removeAuthStateDidChangeListener;
- (void)createUserWithEmail:(NSString *)email password:(NSString *)password;
- (void)signInWithGoogle;
- (void)signInWithCredentials:(FIRAuthCredential *)credential;
- (BOOL)signOut;
@end

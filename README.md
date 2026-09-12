# pyobjus-firebase

Native Objective-C bridges that make Firebase's block-based iOS SDKs usable from [pyobjus](https://github.com/kivy/pyobjus) — built for [Kivy](https://kivy.org) apps running on iOS via [kivy-ios](https://github.com/kivy/kivy-ios).

> Part of the [SimpleObjus](https://github.com/SimpleObjus) organisation — bridges and tooling for using native Objective-C/iOS APIs from Python.

## Why this exists

Firebase's iOS SDKs lean heavily on Objective-C **blocks** for callbacks — auth state listeners, completion handlers, snapshot listeners, and so on. pyobjus has no way to hand a Python callable to a method expecting a block argument, so calls like these can't be made directly from Python:

```objc
[[FIRAuth auth] addAuthStateDidChangeListener:^(FIRAuth *auth, FIRUser *user) {
    // never reachable from pyobjus
}];
```

**pyobjus-firebase** solves this with a small, native "bridge" layer: tiny Objective-C classes that call the block-based Firebase APIs internally and re-expose the results through plain **delegate protocols** — which pyobjus *can* call into via `objc_delegate`/`@protocol`. Your Python code never touches a block; it just implements a normal delegate method.

## What's included

| Bridge | Wraps | Status |
|---|---|---|
| `FirebaseAuthBridge` | `FIRAuth` — auth state listener, email/password sign-up, Google Sign-In, sign-out | ✅ Stable |
| `FirestoreBridge` | `Firestore` — document/collection listeners, reads, writes | 🚧 Planned |
| `RealtimeDBBridge` | `FIRDatabase` — value/child event observers, transactions | 🚧 Planned |
| `StorageBridge` | `FIRStorage` — upload/download progress and completion | 🚧 Planned |
| `MessagingBridge` | `FIRMessaging` — push token and message callbacks | 🚧 Planned |
| `FunctionsBridge` | `FIRFunctions` (Cloud Functions client SDK) — callable function invocation | 🚧 Planned |
| `AppCheckBridge` | `FIRAppCheck` — token provider callbacks and token refresh listeners | 🚧 Planned |
| `AILogicBridge` | Firebase AI Logic (Vertex AI in Firebase / Gemini API) — streaming and completion callbacks for generative model calls | 🚧 Planned |

Contributions adding new bridges (Analytics, Remote Config, Crashlytics, Dynamic Links successor / App Links handling, In-App Messaging, Performance Monitoring, etc.) are very welcome — see [Contributing](#contributing).

## How it works

Every bridge follows the same shape:

1. A native Objective-C class (e.g. `FirebaseAuthBridge`) wraps one Firebase feature area and internally holds the real block-based calls.
2. A companion `@protocol` (e.g. `FirebaseAuthBridgeDelegate`) declares the callback methods, with every method marked `@optional` so a Python delegate only needs to implement the ones it actually uses.
3. Each protocol is force-registered into the Objective-C runtime via an `__attribute__((constructor))` function, so pyobjus's `objc_getProtocol()` can always find it — regardless of dead-code stripping or link order.
4. From Python, you `autoclass()` the bridge, assign a plain Python object as its `delegate`, and implement whichever callback methods you need using pyobjus's `@protocol(...)` decorator.

```
Firebase SDK (blocks)
        │
        ▼
 FirebaseXyzBridge.m  ── native shim, calls the block API internally
        │
        ▼
 FirebaseXyzBridgeDelegate  ── plain Objective-C protocol
        │
        ▼
   pyobjus @protocol(...)  ── your Python delegate methods
```

## Installation

This is source you drop into your kivy-ios Xcode project — it is **not** a CocoaPod, framework, or pip package, since it has to be compiled directly into your app target alongside your existing Firebase setup.

1. Copy `FirebaseBridge.h` and `FirebaseBridge.m` (and any other `*Bridge.h`/`.m` pairs you need) into your Xcode project.
2. Make sure they're checked under your app target's **Compile Sources** build phase.
3. If your project compiles under manual reference counting (MRC) by default, either:
   - leave the bridge files as-is (they're written to be MRC-compatible, using `unsafe_unretained` instead of `weak`), or
   - enable ARC for just these files via `-fobjc-arc` in **Compiler Flags**, if you'd rather use `weak`.
4. Make sure Firebase (and Google Sign-In, if you're using that bridge) are already linked in your project — via CocoaPods, SPM, or manually — since these bridge files assume the relevant headers are already resolvable.

### Requirements

- pyobjus, installed and working in your kivy-ios build
- Firebase iOS SDK (`FirebaseAuth`, plus whichever product a given bridge wraps)
- Xcode project targeting iOS 13+

## Usage

### Auth state listener

```python
from pyobjus import autoclass, protocol

autoclass("FIRApp").configure()
FirebaseAuthBridge = autoclass("FirebaseAuthBridge")

class AuthDelegate:
    @protocol("FirebaseAuthBridgeDelegate")
    def authStateChanged_user_(self, auth, user):
        if user:
            print("Signed in as:", user.email().UTF8String())
        else:
            print("Signed out")

bridge = FirebaseAuthBridge.alloc().init()
delegate = AuthDelegate()
bridge.delegate = delegate
bridge.addAuthStateDidChangeListener()

# keep `bridge` and `delegate` alive for as long as you want the listener active
```

### Email/password sign-up

```python
class AuthDelegate:
    @protocol("FirebaseAuthBridgeDelegate")
    def userCreated_error_(self, auth_result, error):
        if error:
            print("Sign-up failed:", error.localizedDescription().UTF8String())
        else:
            print("User created:", auth_result.user().uid().UTF8String())

bridge.createUserWithEmail_password_("user@example.com", "hunter22")
```

### Google Sign-In

```python
GIDConfiguration = autoclass("GIDConfiguration")
GIDSignIn = autoclass("GIDSignIn")
FIRApp = autoclass("FIRApp")
FIRGoogleAuthProvider = autoclass("FIRGoogleAuthProvider")

client_id = FIRApp.defaultApp().options().clientID()
config = GIDConfiguration.alloc().initWithClientID_(client_id)
GIDSignIn.sharedInstance().setConfiguration_(config)

class AuthDelegate:
    @protocol("FirebaseAuthBridgeDelegate")
    def signInWithGoogleCompletion_error_(self, result, error):
        if error:
            print("Google sign-in failed:", error.localizedDescription().UTF8String())
            return
        user = result.user()
        credential = FIRGoogleAuthProvider.credentialWithIDToken_accessToken_(
            user.idToken().tokenString(), user.accessToken().tokenString()
        )
        # pass `credential` on to FIRAuth signInWithCredential:completion:

# call this from a real user action (a button press), never during app startup —
# the presenting view controller isn't ready that early
bridge.signInWithGoogle()
```

**Important:** trigger `signInWithGoogle()` from an actual user interaction (e.g. a button's `on_press`), not from `__init__` or any other app-startup code path. Calling it before the app's window is fully up and key can silently fail and surface as a misleading "user canceled the sign-in flow" error.

### Sign out

```python
success = bridge.signOut()
if not success:
    print("Sign-out failed:", bridge.lastError().localizedDescription().UTF8String())
```

## Required native setup

- **URL scheme (Google Sign-In only):** add your `GoogleService-Info.plist`'s `REVERSED_CLIENT_ID` as a `CFBundleURLTypes` entry in `Info.plist` — this is required even though the sign-in flow is otherwise self-contained.
- **`application:openURL:options:`:** if your app doesn't already have an editable `AppDelegate.m` (true for kivy-ios/SDL2 apps, where the delegate class is `SDLUIKitDelegate`), add it via an Objective-C category rather than editing SDL2's own source. See [`docs/url-handling.md`](docs/url-handling.md) *(coming soon)* for the full pattern.

## Contributing

New bridges should follow the existing pattern in `FirebaseBridge.h`/`.m`:

1. Add a `@protocol FooBridgeDelegate` with `@optional` methods for each callback.
2. Add one line to the shared `_RegisterFirebaseBridgeProtocols()` constructor for the new protocol.
3. Add a `FooBridge` class wrapping the relevant Firebase calls.
4. Include a usage example in this README.

Issues and PRs welcome — including bug reports on existing bridges, new Firebase product coverage, and documentation improvements.

## License

MIT — see [LICENSE](LICENSE).

## Disclaimer

This project is not affiliated with or endorsed by Google or Firebase. "Firebase" and "Google Sign-In" are trademarks of Google LLC.

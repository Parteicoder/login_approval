# login_approval

An "Is this you signing in?" sheet for Flutter, in the style of GitHub Mobile.
Someone starts a sign-in in a browser, your signed-in app pops up a sheet with the
details and a number, and the user answers there.

**This package is UI and polling only.** It has no networking, no storage, no
cryptography and no biometrics. All security lives in the
[`LoginApprovalClient`](#the-client-you-implement) you write and in your backend.
A modified copy of this package can draw a wrong screen, but it cannot approve
anything **if your client follows the three rules below**: your client decides what
is sent, and your server decides what is accepted.

## What you get

- `LoginApprovalController`: polls your client, holds the request on screen, guards against double taps.
- `LoginApprovalHost`: puts the sheet above your app (use it in `MaterialApp.builder`). The app behind it can neither be tapped, focused nor read by screen readers while the sheet is up.
- `LoginApprovalSheet`: the card itself, if you want to host it yourself.
- `LoginApprovalTexts`: every string, English by default.
- Number matching in two flavours: **choose** one of three numbers, or **type** the two-digit number. The approve controls stay disabled for 2 seconds so nobody taps blindly.
- Polling only while the app is in the foreground, fast for two minutes after start or resume, then slow.

## Quick start

```dart
final controller = LoginApprovalController(
  client: MyApprovalClient(),            // you write this
  onError: (error, stack) => log(error), // network errors never reach the UI
)..start();                              // call stop() when the user signs out

MaterialApp(
  builder: (context, child) =>
      LoginApprovalHost(controller: controller, child: child!),
  // ...
);
```

## The client you implement

```dart
class MyApprovalClient implements LoginApprovalClient {
  @override
  Future<LoginApprovalRequest?> fetchPending() async { /* GET pending request or null */ }

  @override
  Future<LoginApprovalOutcome> approve(String requestId, int number) async {
    // 1. Verify the user (biometrics / device credential).
    // 2. Sign what your backend expects, with a key that never leaves the device.
    // 3. Send it and map the answer to an outcome.
  }

  @override
  Future<LoginApprovalOutcome> deny(String requestId) async { /* "this wasn't me" */ }
}
```

**Three rules your client must follow** (the package cannot enforce them):

1. **Verify the user on every `approve()` call**, freshly, with no grace period. With an Android Keystore key that means `setUserAuthenticationParameters(0, ...)` so each signature needs its own biometric or device credential prompt. A package that calls `approve(id, anything)` without a tap must still get nowhere.
2. **Build the prompt text and the signed message from your own copy of the server data for that request id**, never from the `LoginApprovalRequest` object or the number that the package passes in. Look the id up in what *you* fetched; unknown id means abort.
3. **Let the server rebuild the signed message and verify it.** Never trust bytes the client built.

There is deliberately **no `confirmUser()` callback**. Verifying the user and signing
belong together (for example one biometric-bound signature); a separate callback would
let the two drift apart.

The request you return only carries what the sheet draws: an id, the expiry time, the
mode, the numbers to choose from, some detail lines and an optional warning. It never
carries "the right answer".

## What your backend should do

A sign-in approval is only as strong as the server behind it. The package cannot
enforce any of this. A sound design:

- Create one request per sign-in attempt, with a random id, a short life (about 90 s) and a **single open request per account**.
- Generate the number with a cryptographically secure random source. Keep the right answer on the server only.
- **Your backend must end the request on the first wrong number; the package cannot.** Otherwise a choice of three, or of 90 possibilities, can simply be guessed.
- Rate-limit requests per account and per address, to stop prompt bombing. Show the user where and from what the sign-in came.
- Bind the decision to a device key: the app signs a message that contains the request id, the number, a nonce and the expiry, and the server rebuilds that message itself and checks the signature. Use domain separation so the signature cannot be replayed for anything else.
- Make every state change atomic (`pending` → `approved` / `denied` / `expired`) and redeem an approval **exactly once**, handing the browser its session only through the browser's own channel.
- Keep a way back (recovery codes) and log decisions without logging secrets.

## Good to know

- **Device clock:** `LoginApprovalRequest.expiresAt` must be on the *device's* clock. Convert "the server says 90 seconds are left" to `DateTime.now().add(...)`. If the device clock runs ahead, requests count as expired and are dropped without a message.
- **Feedback:** when a decision is `rejected` or the request `expired`, the sheet simply goes away. Listen to `controller.lastOutcome` (it is a `ChangeNotifier`) to show your own message, for example a snack bar.
- **Several ids:** `approve`, `deny` and `dismiss` take the `requestId` of the request that was on screen. If the request changed under the user's finger, the call is ignored.
- **Enable delay:** the controller itself ignores `approve` until `enableDelay` is over, so a custom UI cannot skip it by accident.
- **Android back button:** the host cannot intercept it. The navigator behind the sheet still receives it, so back may pop a route you cannot see or close the app from the root route. Put `PopScope(canPop: controller.current == null, ...)` on your root routes if that matters to you.
- **Large text, dark mode, right-to-left** work; the sheet scrolls and sits above the keyboard.

## Honest limits

Number matching raises the bar against careless approvals and prompt bombing. It does
**not** stop a real-time phishing proxy that relays the number to a victim. Only
origin-bound credentials such as passkeys (WebAuthn) do. Treat this as a convenient
second factor, not as phishing-resistant authentication.

## Accessibility

The number buttons are Material buttons with their own label, enabled state and tap
action (covered by a semantics test), the headline and warning are live regions, the
sheet scrolls and works at large text sizes, and focus and screen readers are kept away
from the app behind it. Strings are yours to translate. The package has not been
checked with TalkBack or VoiceOver on a real device yet.

## Requirements

Flutter 3.50 or newer (the package uses `material_ui`).

## License

MIT

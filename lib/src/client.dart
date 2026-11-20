import 'models.dart';

/// The contract your app implements. All security lives behind it.
///
/// This package never talks to a server, never signs anything and never asks
/// for a fingerprint. Do that in [approve]: verify the user, sign what your
/// backend expects and send the result. A separate "confirm user" callback
/// would split verification from signing, which is weaker, so there is none.
abstract interface class LoginApprovalClient {
  /// Returns the request that is waiting right now, or `null`.
  ///
  /// May throw on network errors. The controller reports them and tries again.
  Future<LoginApprovalRequest?> fetchPending();

  /// The user picked or typed [number] for the request [requestId].
  Future<LoginApprovalOutcome> approve(String requestId, int number);

  /// The user said "this wasn't me".
  Future<LoginApprovalOutcome> deny(String requestId);

  /// The user closed the sheet without deciding. Optional, does nothing by default.
  Future<void> dismiss(String requestId) async {}
}

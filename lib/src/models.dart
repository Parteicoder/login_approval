import 'package:flutter/foundation.dart';

/// How the backend answered an approve or deny call.
enum LoginApprovalOutcome {
  /// The decision was accepted.
  accepted,

  /// The decision was refused (for example a wrong number). The request is gone.
  rejected,

  /// The request ran out of time before the decision arrived.
  expired,

  /// The decision could not be delivered. The request stays and can be retried.
  failed,
}

/// How the user answers the number challenge.
enum LoginApprovalInputMode {
  /// Pick the matching number from [LoginApprovalRequest.choices].
  choose,

  /// Type the two-digit number shown on the device that is signing in.
  type,
}

/// One labelled line of context, for example `Browser` / `Chrome on Windows`
/// or `App` / `App on Linux`.
@immutable
final class LoginApprovalDetail {
  /// Creates a detail line.
  const LoginApprovalDetail(this.label, this.value);

  /// Short label.
  final String label;

  /// Value shown next to the label.
  final String value;
}

/// A sign-in waiting for a decision.
///
/// The request carries only what the sheet needs to draw. It never knows
/// which number is the right one; the backend decides.
@immutable
final class LoginApprovalRequest {
  /// Creates a request. Throws [ArgumentError] if the data is inconsistent.
  LoginApprovalRequest({
    required this.id,
    required this.expiresAt,
    required this.mode,
    List<int> choices = const [],
    List<LoginApprovalDetail> details = const [],
    this.warning,
    this.enableDelay = const Duration(seconds: 2),
  }) : choices = List.unmodifiable(choices),
       details = List.unmodifiable(details) {
    if (id.isEmpty) throw ArgumentError.value(id, 'id', 'must not be empty');
    if (enableDelay.isNegative) {
      throw ArgumentError.value(enableDelay, 'enableDelay', 'must not be negative');
    }
    switch (mode) {
      case LoginApprovalInputMode.choose:
        if (this.choices.length < 2 || this.choices.toSet().length != this.choices.length) {
          throw ArgumentError.value(choices, 'choices', 'need at least two distinct numbers');
        }
        if (this.choices.any((n) => !isValidNumber(n))) {
          throw ArgumentError.value(choices, 'choices', 'numbers must have two digits');
        }
      case LoginApprovalInputMode.type:
        if (this.choices.isNotEmpty) {
          throw ArgumentError.value(choices, 'choices', 'must be empty in type mode');
        }
    }
  }

  /// Opaque id, handed back to the client on approve, deny and dismiss.
  final String id;

  /// When the request stops being valid, **on this device's clock**.
  ///
  /// Convert the server's expiry to the device clock (for example "server says
  /// 90 seconds left" becomes `DateTime.now().add(90 s)`). If the device clock
  /// runs ahead, requests count as expired and are silently dropped.
  final DateTime expiresAt;

  /// Whether the user chooses a number or types it.
  final LoginApprovalInputMode mode;

  /// The numbers to choose from. Empty in type mode.
  final List<int> choices;

  /// Context lines such as browser or app, system and time.
  final List<LoginApprovalDetail> details;

  /// An optional highlighted warning, for example about an unusual sign-in.
  final String? warning;

  /// How long the approve controls stay disabled after the sheet appears.
  final Duration enableDelay;

  /// Whether [n] is a two-digit number (10 to 99).
  static bool isValidNumber(int n) => n >= 10 && n <= 99;
}

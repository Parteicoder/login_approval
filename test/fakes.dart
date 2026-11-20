import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:login_approval/login_approval.dart';

/// A clock the tests move by hand together with `tester.pump`.
class TestClock {
  DateTime time = DateTime.utc(2026, 1, 1, 12);
  DateTime call() => time;

  Future<void> advance(WidgetTester tester, Duration d) async {
    time = time.add(d);
    await tester.pump(d);
  }
}

class FakeClient implements LoginApprovalClient {
  FakeClient(this.clock);
  final TestClock clock;

  LoginApprovalRequest? pending;
  Object? fetchError;
  int fetches = 0;
  final approved = <(String, int)>[];
  final denied = <String>[];
  final dismissed = <String>[];
  LoginApprovalOutcome approveResult = LoginApprovalOutcome.accepted;
  LoginApprovalOutcome denyResult = LoginApprovalOutcome.accepted;
  Object? approveError;
  Completer<LoginApprovalOutcome>? approveGate;

  @override
  Future<LoginApprovalRequest?> fetchPending() async {
    fetches++;
    final error = fetchError;
    if (error != null) throw error;
    return pending;
  }

  @override
  Future<LoginApprovalOutcome> approve(String requestId, int number) async {
    approved.add((requestId, number));
    final error = approveError;
    if (error != null) throw error;
    final gate = approveGate;
    if (gate != null) return gate.future;
    return approveResult;
  }

  @override
  Future<LoginApprovalOutcome> deny(String requestId) async {
    denied.add(requestId);
    return denyResult;
  }

  @override
  Future<void> dismiss(String requestId) async => dismissed.add(requestId);

  LoginApprovalRequest request({
    String id = 'r1',
    Duration expiresIn = const Duration(seconds: 90),
    LoginApprovalInputMode mode = LoginApprovalInputMode.choose,
    List<int>? choices,
    Duration enableDelay = Duration.zero,
    String? warning,
  }) {
    return LoginApprovalRequest(
      id: id,
      expiresAt: clock.time.add(expiresIn),
      mode: mode,
      choices: choices ?? (mode == LoginApprovalInputMode.choose ? [17, 42, 78] : []),
      details: const [
        LoginApprovalDetail('Browser', 'Chrome on Windows'),
        LoginApprovalDetail('Time', '12:00'),
      ],
      warning: warning,
      enableDelay: enableDelay,
    );
  }
}

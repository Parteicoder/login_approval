import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:login_approval/login_approval.dart';

import 'fakes.dart';

void main() {
  late TestClock clock;
  late FakeClient client;
  late List<Object> errors;
  late LoginApprovalController controller;

  setUp(() {
    clock = TestClock();
    client = FakeClient(clock);
    errors = [];
    controller = LoginApprovalController(
      client: client,
      clock: clock.call,
      onError: (e, _) => errors.add(e),
    );
  });

  // testWidgets checks for pending timers at the end of the body, so the
  // controller must be disposed inside it.
  void cTest(String name, Future<void> Function(WidgetTester tester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        controller.dispose();
      }
    });
  }

  cTest('does nothing before start', (tester) async {
    client.pending = client.request();
    await clock.advance(tester, const Duration(minutes: 5));
    expect(client.fetches, 0);
    expect(controller.current, isNull);
  });

  cTest('start polls at once and shows a pending request', (tester) async {
    client.pending = client.request();
    controller.start();
    await tester.pump();
    expect(client.fetches, 1);
    expect(controller.current?.id, 'r1');
    expect(controller.shownAt, clock.time);
    expect(controller.lastOutcome, isNull);
  });

  cTest('polls fast for the fast window, then slow', (tester) async {
    controller.start();
    await tester.pump();
    expect(client.fetches, 1);
    await clock.advance(tester, const Duration(seconds: 3));
    expect(client.fetches, 2);
    await clock.advance(tester, const Duration(seconds: 3));
    expect(client.fetches, 3);
    await clock.advance(tester, const Duration(minutes: 3));
    final afterFast = client.fetches;
    await clock.advance(tester, const Duration(seconds: 60));
    final slowPolls = client.fetches - afterFast;
    expect(slowPolls, inInclusiveRange(1, 3), reason: 'slow interval is 30 s, fast would give 20');
  });

  cTest('a second start does not start a second loop', (tester) async {
    controller.start();
    controller.start();
    await tester.pump();
    expect(client.fetches, 1);
  });

  cTest('stop ends polling and removes the request', (tester) async {
    client.pending = client.request();
    controller.start();
    await tester.pump();
    controller.stop();
    expect(controller.current, isNull);
    final n = client.fetches;
    await clock.advance(tester, const Duration(minutes: 5));
    expect(client.fetches, n);
  });

  cTest('start after stop works and shows the request again', (tester) async {
    client.pending = client.request();
    controller.start();
    await tester.pump();
    controller.dismiss();
    await tester.pump();
    controller.stop();
    controller.start();
    await tester.pump();
    expect(controller.current?.id, 'r1', reason: 'stop forgets dismissed ids');
  });

  cTest('a poll that finishes after stop is ignored', (tester) async {
    final gate = Completer<LoginApprovalRequest?>();
    final slow = _SlowClient(gate.future);
    final c = LoginApprovalController(client: slow, clock: clock.call);
    addTearDown(c.dispose);
    c.start();
    c.stop();
    gate.complete(client.request());
    await tester.pump();
    expect(c.current, isNull);
  });

  cTest('background pauses polling, resume polls again at once', (tester) async {
    controller.start();
    await tester.pump();
    controller.setForeground(false);
    final n = client.fetches;
    await clock.advance(tester, const Duration(minutes: 5));
    expect(client.fetches, n);
    controller.setForeground(true);
    await tester.pump();
    expect(client.fetches, n + 1);
  });

  cTest('fetch errors are reported and polling goes on', (tester) async {
    client.fetchError = StateError('offline');
    controller.start();
    await tester.pump();
    expect(errors, hasLength(1));
    client.fetchError = null;
    client.pending = client.request();
    await clock.advance(tester, const Duration(seconds: 3));
    expect(controller.current?.id, 'r1');
  });

  cTest('the same id keeps the request, a new id replaces it', (tester) async {
    client.pending = client.request();
    controller.start();
    await tester.pump();
    final first = controller.shownAt;
    await clock.advance(tester, const Duration(seconds: 3));
    expect(controller.shownAt, first, reason: 'same id, not shown again');
    client.pending = client.request(id: 'r2');
    await clock.advance(tester, const Duration(seconds: 3));
    expect(controller.current?.id, 'r2');
  });

  cTest('a request that is already expired is never shown', (tester) async {
    client.pending = client.request(expiresIn: const Duration(seconds: -1));
    controller.start();
    await tester.pump();
    expect(controller.current, isNull);
  });

  cTest('the request disappears by itself when it expires', (tester) async {
    client.pending = client.request(expiresIn: const Duration(seconds: 10));
    controller.start();
    await tester.pump();
    expect(controller.current, isNotNull);
    await clock.advance(tester, const Duration(seconds: 10));
    expect(controller.current, isNull);
    expect(controller.lastOutcome, LoginApprovalOutcome.expired);
    client.pending = client.request(expiresIn: const Duration(seconds: 10));
    await clock.advance(tester, const Duration(seconds: 3));
    expect(controller.current, isNull, reason: 'expired id is not shown again');
  });

  cTest('the request goes away when the server has none any more', (tester) async {
    client.pending = client.request();
    controller.start();
    await tester.pump();
    client.pending = null;
    await clock.advance(tester, const Duration(seconds: 3));
    expect(controller.current, isNull);
  });

  group('approve', () {
    Future<void> shown(WidgetTester tester, [LoginApprovalRequest? r]) async {
      client.pending = r ?? client.request();
      controller.start();
      await tester.pump();
    }

    cTest('sends id and number, then removes the request', (tester) async {
      await shown(tester);
      final out = await controller.approve(42);
      expect(out, LoginApprovalOutcome.accepted);
      expect(client.approved, [('r1', 42)]);
      expect(controller.current, isNull);
      expect(controller.lastOutcome, LoginApprovalOutcome.accepted);
      expect(controller.busy, isFalse);
    });

    cTest('the same request does not come back after approval', (tester) async {
      await shown(tester);
      await controller.approve(42);
      await clock.advance(tester, const Duration(seconds: 3));
      expect(controller.current, isNull);
    });

    cTest('a rejected decision removes the request', (tester) async {
      await shown(tester);
      client.approveResult = LoginApprovalOutcome.rejected;
      expect(await controller.approve(17), LoginApprovalOutcome.rejected);
      expect(controller.current, isNull);
    });

    cTest('a failed decision keeps the request so the user can retry', (tester) async {
      await shown(tester);
      client.approveResult = LoginApprovalOutcome.failed;
      expect(await controller.approve(17), LoginApprovalOutcome.failed);
      expect(controller.current, isNotNull);
      client.approveResult = LoginApprovalOutcome.accepted;
      expect(await controller.approve(17), LoginApprovalOutcome.accepted);
      expect(controller.current, isNull);
    });

    cTest('a client that throws gives failed and reports the error', (tester) async {
      await shown(tester);
      client.approveError = StateError('boom');
      expect(await controller.approve(17), LoginApprovalOutcome.failed);
      expect(errors, hasLength(1));
      expect(controller.current, isNotNull);
      expect(controller.busy, isFalse);
    });

    cTest('a second call while one is running is ignored', (tester) async {
      await shown(tester);
      client.approveGate = Completer();
      final first = controller.approve(17);
      await tester.pump();
      expect(controller.busy, isTrue);
      expect(await controller.approve(42), isNull);
      expect(await controller.deny(), isNull);
      client.approveGate!.complete(LoginApprovalOutcome.accepted);
      expect(await first, LoginApprovalOutcome.accepted);
      expect(client.approved, hasLength(1));
      expect(client.denied, isEmpty);
    });

    cTest('a number that was not offered throws and sends nothing', (tester) async {
      await shown(tester);
      expect(() => controller.approve(99), throwsArgumentError);
      expect(client.approved, isEmpty);
    });

    cTest('type mode accepts any two-digit number only', (tester) async {
      await shown(tester, client.request(mode: LoginApprovalInputMode.type));
      expect(() => controller.approve(5), throwsArgumentError);
      expect(() => controller.approve(100), throwsArgumentError);
      expect(await controller.approve(63), LoginApprovalOutcome.accepted);
    });

    cTest('nothing on screen gives null', (tester) async {
      expect(await controller.approve(42), isNull);
      expect(await controller.deny(), isNull);
    });

    cTest('an expired request gives expired and sends nothing', (tester) async {
      await shown(tester, client.request(expiresIn: const Duration(seconds: 5)));
      clock.time = clock.time.add(const Duration(seconds: 6));
      expect(await controller.approve(42), LoginApprovalOutcome.expired);
      expect(client.approved, isEmpty);
      expect(controller.current, isNull);
    });

    cTest('a new request cannot replace the one being decided', (tester) async {
      await shown(tester);
      client.approveGate = Completer();
      final running = controller.approve(17);
      await tester.pump();
      client.pending = client.request(id: 'r2');
      await clock.advance(tester, const Duration(seconds: 3));
      expect(controller.current?.id, 'r1');
      client.approveGate!.complete(LoginApprovalOutcome.accepted);
      await running;
      await clock.advance(tester, const Duration(seconds: 3));
      expect(controller.current?.id, 'r2');
    });

    cTest('stop during a decision keeps it and drops the request afterwards', (tester) async {
      await shown(tester);
      client.approveGate = Completer();
      final running = controller.approve(17);
      await tester.pump();
      controller.stop();
      expect(controller.current, isNotNull, reason: 'busy request stays until the call ends');
      client.approveGate!.complete(LoginApprovalOutcome.accepted);
      await running;
      expect(controller.current, isNull);
    });
  });

  group('deny and dismiss', () {
    cTest('deny calls the client and removes the request', (tester) async {
      client.pending = client.request();
      controller.start();
      await tester.pump();
      expect(await controller.deny(), LoginApprovalOutcome.accepted);
      expect(client.denied, ['r1']);
      expect(controller.current, isNull);
    });

    cTest('dismiss tells the client and the request does not return', (tester) async {
      client.pending = client.request();
      controller.start();
      await tester.pump();
      controller.dismiss();
      await tester.pump();
      expect(client.dismissed, ['r1']);
      await clock.advance(tester, const Duration(seconds: 3));
      expect(controller.current, isNull);
    });
  });

  cTest('no notification and no polling after dispose', (tester) async {
    client.pending = client.request();
    final c = LoginApprovalController(client: client, clock: clock.call);
    c.start();
    await tester.pump();
    c.dispose();
    final n = client.fetches;
    await clock.advance(tester, const Duration(minutes: 5));
    expect(client.fetches, n);
  });

  test('intervals must be positive', () {
    expect(
      () => LoginApprovalController(client: client, fastInterval: Duration.zero),
      throwsArgumentError,
    );
  });
}

class _SlowClient implements LoginApprovalClient {
  _SlowClient(this.result);
  final Future<LoginApprovalRequest?> result;

  @override
  Future<LoginApprovalRequest?> fetchPending() => result;

  @override
  Future<LoginApprovalOutcome> approve(String requestId, int number) =>
      throw UnimplementedError();

  @override
  Future<LoginApprovalOutcome> deny(String requestId) => throw UnimplementedError();

  @override
  Future<void> dismiss(String requestId) async {}
}

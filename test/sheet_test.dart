import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:login_approval/login_approval.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

void main() {
  late TestClock clock;
  late FakeClient client;
  late LoginApprovalController controller;
  var behindTaps = 0;

  setUp(() {
    clock = TestClock();
    client = FakeClient(clock);
    controller = LoginApprovalController(client: client, clock: clock.call);
    behindTaps = 0;
  });

  Widget app({
    LoginApprovalTexts texts = const LoginApprovalTexts(),
    ThemeData? theme,
    double textScale = 1,
    bool pauseWhenInBackground = true,
  }) {
    return MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: LoginApprovalHost(
          controller: controller,
          texts: texts,
          pauseWhenInBackground: pauseWhenInBackground,
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Center(
          child: TextButton(onPressed: () => behindTaps++, child: const Text('behind')),
        ),
      ),
    );
  }

  // Shows a request and ends with the controller disposed and the tree gone,
  // because testWidgets fails on timers that are still pending.
  Future<void> pumpWith(
    WidgetTester tester,
    LoginApprovalRequest? request, {
    Widget? widget,
  }) async {
    client.pending = request;
    await tester.pumpWidget(widget ?? app());
    controller.start();
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    controller.dispose();
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('shows title, details and the three numbers', (tester) async {
    await pumpWith(tester, client.request());
    expect(find.text('Is this you signing in?'), findsOneWidget);
    expect(find.text('Chrome on Windows'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('78'), findsOneWidget);
    expect(find.text('Expires in 1:30'), findsOneWidget);
    await finish(tester);
  });

  for (final theme in [
    ThemeData(colorScheme: const ColorScheme.light()),
    ThemeData(colorScheme: const ColorScheme.dark()),
  ]) {
    testWidgets('number digits use the button foreground colour (${theme.brightness.name})', (tester) async {
      await pumpWith(tester, client.request(), widget: app(theme: theme));
      final digits = tester.widget<RichText>(
        find.descendant(of: find.widgetWithText(FilledButton, '42'), matching: find.byType(RichText)),
      );
      expect(digits.text.style?.color, theme.colorScheme.onPrimary);
      await finish(tester);
    });
  }

  testWidgets('nothing is drawn without a request', (tester) async {
    await pumpWith(tester, null);
    expect(find.text('Is this you signing in?'), findsNothing);
    await tester.tap(find.text('behind'));
    expect(behindTaps, 1);
    await finish(tester);
  });

  testWidgets('number buttons stay disabled until the enable delay is over', (tester) async {
    await pumpWith(tester, client.request(enableDelay: const Duration(seconds: 2)));
    await tester.tap(find.text('42'), warnIfMissed: false);
    await tester.pump();
    expect(client.approved, isEmpty, reason: 'too early');
    await clock.advance(tester, const Duration(seconds: 2));
    await tester.tap(find.text('42'));
    await tester.pump();
    expect(client.approved, [('r1', 42)]);
    await finish(tester);
  });

  testWidgets('the countdown moves', (tester) async {
    await pumpWith(tester, client.request());
    await clock.advance(tester, const Duration(seconds: 30));
    expect(find.text('Expires in 1:00'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the app behind cannot be tapped while the sheet is up', (tester) async {
    await pumpWith(tester, client.request());
    await tester.tap(find.text('behind'), warnIfMissed: false);
    expect(behindTaps, 0);
    await finish(tester);
  });

  testWidgets('the app behind is hidden from screen readers and focus while the sheet is up', (tester) async {
    await pumpWith(tester, client.request());
    final excluded = find.ancestor(
      of: find.text('behind'),
      matching: find.byWidgetPredicate((w) => w is ExcludeSemantics && w.excluding),
    );
    expect(excluded, findsOneWidget);
    final focusExcluded = find.ancestor(
      of: find.text('behind'),
      matching: find.byWidgetPredicate((w) => w is ExcludeFocus && w.excluding),
    );
    expect(focusExcluded, findsOneWidget);
    await finish(tester);
  });

  testWidgets('the sheet goes away after a decision and the app is usable again', (tester) async {
    await pumpWith(tester, client.request(enableDelay: Duration.zero));
    await tester.tap(find.text('42'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Is this you signing in?'), findsNothing);
    await tester.tap(find.text('behind'));
    expect(behindTaps, 1);
    await finish(tester);
  });

  testWidgets("'No, this wasn't me' works at once, without the delay", (tester) async {
    await pumpWith(tester, client.request(enableDelay: const Duration(seconds: 2)));
    await tester.tap(find.text("No, this wasn't me"));
    await tester.pump();
    expect(client.denied, ['r1']);
    await finish(tester);
  });

  testWidgets("'Not now' dismisses", (tester) async {
    await pumpWith(tester, client.request());
    await tester.tap(find.text('Not now'));
    await tester.pump();
    expect(client.dismissed, ['r1']);
    expect(find.text('Is this you signing in?'), findsNothing);
    await finish(tester);
  });

  testWidgets('a failed decision shows the message and keeps the sheet', (tester) async {
    await pumpWith(tester, client.request(enableDelay: Duration.zero));
    client.approveResult = LoginApprovalOutcome.failed;
    await tester.tap(find.text('42'));
    await tester.pump();
    await tester.pump();
    expect(find.text('That did not work. Please try again.'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a warning is shown', (tester) async {
    await pumpWith(tester, client.request(warning: 'New country'));
    expect(find.text('New country'), findsOneWidget);
    await finish(tester);
  });

  group('type mode', () {
    LoginApprovalRequest typeRequest() =>
        client.request(mode: LoginApprovalInputMode.type, enableDelay: Duration.zero);

    testWidgets('approve needs exactly two digits', (tester) async {
      await pumpWith(tester, typeRequest());
      FilledButton button() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Approve'));
      expect(button().onPressed, isNull);
      await tester.enterText(find.byType(TextField), '4');
      await tester.pump();
      expect(button().onPressed, isNull);
      await tester.enterText(find.byType(TextField), '47');
      await tester.pump();
      expect(button().onPressed, isNotNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pump();
      expect(client.approved, [('r1', 47)]);
      await finish(tester);
    });

    testWidgets('letters are filtered out and the length is capped', (tester) async {
      await pumpWith(tester, typeRequest());
      await tester.enterText(find.byType(TextField), 'a4b7c9');
      await tester.pump();
      expect(find.text('47'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a number below 10 never enables the button', (tester) async {
      await pumpWith(tester, typeRequest());
      await tester.enterText(find.byType(TextField), '07');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Approve')).onPressed,
        isNull,
      );
      await finish(tester);
    });

    testWidgets('the field is cleared for the next request', (tester) async {
      await pumpWith(tester, typeRequest());
      await tester.enterText(find.byType(TextField), '47');
      await tester.pump();
      client.pending = client.request(
        id: 'r2',
        mode: LoginApprovalInputMode.type,
        enableDelay: Duration.zero,
      );
      controller.dismiss(requestId: 'r1');
      await clock.advance(tester, const Duration(seconds: 3));
      expect(controller.current?.id, 'r2');
      expect(find.text('47'), findsNothing);
      await finish(tester);
    });
  });

  testWidgets('texts can be replaced', (tester) async {
    await pumpWith(
      tester,
      client.request(),
      widget: app(
        texts: LoginApprovalTexts(
          title: 'Bist du das?',
          deny: 'Nein',
          timeLeft: (d) => 'Noch ${d.inSeconds} s',
        ),
      ),
    );
    expect(find.text('Bist du das?'), findsOneWidget);
    expect(find.text('Nein'), findsOneWidget);
    expect(find.text('Noch 90 s'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('dark theme and 200 percent text do not overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpWith(
      tester,
      client.request(warning: 'Unusual sign-in from a new country'),
      widget: app(theme: ThemeData.dark(), textScale: 2),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Is this you signing in?'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('number buttons are real buttons for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpWith(tester, client.request());
    final data = tester.getSemantics(find.widgetWithText(FilledButton, '42'));
    expect(data.label, contains('42'));
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isEnabled, Tristate.isTrue);
    expect(data.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
    await finish(tester);
  });

  testWidgets('a disabled number button says so to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpWith(tester, client.request(enableDelay: const Duration(seconds: 5)));
    final data = tester.getSemantics(find.widgetWithText(FilledButton, '42'));
    expect(data.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    handle.dispose();
    await finish(tester);
  });

  testWidgets('the buttons switch on by themselves when the delay is over', (tester) async {
    await pumpWith(tester, client.request(enableDelay: const Duration(seconds: 2)));
    FilledButton button() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, '42'));
    expect(button().onPressed, isNull);
    await clock.advance(tester, const Duration(seconds: 2));
    expect(button().onPressed, isNotNull);
    await finish(tester);
  });

  testWidgets('a new request restarts the delay for its own buttons', (tester) async {
    await pumpWith(tester, client.request(enableDelay: const Duration(seconds: 2)));
    await clock.advance(tester, const Duration(seconds: 2));
    client.pending = client.request(
      id: 'r2',
      choices: [31, 52, 64],
      enableDelay: const Duration(seconds: 2),
    );
    controller.dismiss(requestId: 'r1');
    await clock.advance(tester, const Duration(seconds: 3));
    expect(controller.current?.id, 'r2');
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '52'));
    expect(button.onPressed, isNull, reason: 'fresh request, fresh delay');
    await clock.advance(tester, const Duration(seconds: 2));
    await tester.tap(find.text('52'));
    await tester.pump();
    expect(client.approved, [('r2', 52)]);
    await finish(tester);
  });

  testWidgets('the host follows a swapped controller', (tester) async {
    // MaterialApp.home is built once, so drive the swap through a notifier.
    final other = LoginApprovalController(client: client, clock: clock.call);
    final current = ValueNotifier<LoginApprovalController>(controller);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<LoginApprovalController>(
          valueListenable: current,
          builder: (context, c, _) =>
              LoginApprovalHost(controller: c, child: const Scaffold(body: Text('app'))),
        ),
      ),
    );
    current.value = other;
    await tester.pump();
    client.pending = client.request(id: 'o1');
    other.start();
    await tester.pump();
    await tester.pump();
    expect(find.text('Is this you signing in?'), findsOneWidget);
    other.dispose();
    current.dispose();
    await finish(tester);
  });

  testWidgets('a stale tap on a replaced request sends nothing', (tester) async {
    await pumpWith(tester, client.request());
    final stale = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '42')).onPressed!;
    client.pending = client.request(id: 'r2', choices: [31, 52, 64]);
    controller.dismiss(requestId: 'r1');
    await clock.advance(tester, const Duration(seconds: 3));
    expect(controller.current?.id, 'r2');
    stale();
    await tester.pump();
    expect(client.approved, isEmpty, reason: 'the old button belonged to r1');
    await finish(tester);
  });

  group('lifecycle', () {
    testWidgets('paused stops polling, resumed polls again', (tester) async {
      await pumpWith(tester, null);
      final n = client.fetches;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await clock.advance(tester, const Duration(minutes: 5));
      expect(client.fetches, n);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(client.fetches, n + 1);
      await finish(tester);
    });

    testWidgets('inactive alone does not pause (system dialogs, biometric prompt)', (tester) async {
      await pumpWith(tester, null);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final n = client.fetches;
      await clock.advance(tester, const Duration(seconds: 6));
      expect(client.fetches, greaterThan(n));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await finish(tester);
    });

    testWidgets('pauseWhenInBackground: false keeps polling', (tester) async {
      await pumpWith(tester, null, widget: app(pauseWhenInBackground: false));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final n = client.fetches;
      await clock.advance(tester, const Duration(seconds: 6));
      expect(client.fetches, greaterThan(n));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await finish(tester);
    });
  });
}

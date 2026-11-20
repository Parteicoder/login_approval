import 'dart:math';

import 'package:login_approval/login_approval.dart';
import 'package:material_ui/material_ui.dart';

void main() => runApp(const ExampleApp());

/// An in-memory stand-in for your backend. In a real app this class talks to
/// your server, verifies the user (for example with a biometric-bound key) and
/// signs the decision.
class FakeBackend implements LoginApprovalClient {
  LoginApprovalRequest? _pending;
  int? _answer;

  /// Simulates "someone starts a sign-in in a browser".
  int startSignIn({required bool typeMode}) {
    final random = Random.secure();
    final answer = 10 + random.nextInt(90);
    final choices = <int>{answer};
    while (choices.length < 3) {
      choices.add(10 + random.nextInt(90));
    }
    _answer = answer;
    _pending = LoginApprovalRequest(
      id: 'demo-${DateTime.now().millisecondsSinceEpoch}',
      expiresAt: DateTime.now().add(const Duration(seconds: 90)),
      mode: typeMode ? LoginApprovalInputMode.type : LoginApprovalInputMode.choose,
      choices: typeMode ? const [] : (choices.toList()..shuffle(random)),
      details: const [
        LoginApprovalDetail('Browser', 'Firefox on Linux'),
        LoginApprovalDetail('Time', 'just now'),
      ],
    );
    return answer; // the "browser" shows this number
  }

  @override
  Future<LoginApprovalRequest?> fetchPending() async => _pending;

  @override
  Future<LoginApprovalOutcome> approve(String requestId, int number) async {
    if (_pending?.id != requestId) return LoginApprovalOutcome.expired;
    final ok = number == _answer;
    _pending = null; // a wrong number ends the request, so guessing does not work
    return ok ? LoginApprovalOutcome.accepted : LoginApprovalOutcome.rejected;
  }

  @override
  Future<LoginApprovalOutcome> deny(String requestId) async {
    _pending = null;
    return LoginApprovalOutcome.accepted;
  }

  @override
  Future<void> dismiss(String requestId) async {}
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final backend = FakeBackend();
  late final LoginApprovalController controller = LoginApprovalController(
    client: backend,
    fastInterval: const Duration(seconds: 1),
    onError: (error, _) => debugPrint('login_approval: $error'),
  )..start();
  int? shownInBrowser;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      builder: (context, child) => LoginApprovalHost(controller: controller, child: child!),
      home: Scaffold(
        appBar: AppBar(title: const Text('login_approval')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                shownInBrowser == null
                    ? 'No sign-in started'
                    : 'The "browser" shows: $shownInBrowser',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () =>
                    setState(() => shownInBrowser = backend.startSignIn(typeMode: false)),
                child: const Text('Start sign-in (choose the number)'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () =>
                    setState(() => shownInBrowser = backend.startSignIn(typeMode: true)),
                child: const Text('Start sign-in (type the number)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:login_approval/login_approval.dart';

LoginApprovalRequest _make({
  String id = 'a',
  LoginApprovalInputMode mode = LoginApprovalInputMode.choose,
  List<int> choices = const [11, 22, 33],
  Duration delay = const Duration(seconds: 2),
}) => LoginApprovalRequest(
  id: id,
  expiresAt: DateTime.utc(2026),
  mode: mode,
  choices: choices,
  enableDelay: delay,
);

void main() {
  test('a valid choose request keeps its data and its lists are unmodifiable', () {
    final r = _make();
    expect(r.choices, [11, 22, 33]);
    expect(() => r.choices.add(44), throwsUnsupportedError);
    expect(() => r.details.add(const LoginApprovalDetail('a', 'b')), throwsUnsupportedError);
  });

  test('rejects an empty id', () {
    expect(() => _make(id: ''), throwsArgumentError);
  });

  test('choose mode needs two or more distinct two-digit numbers', () {
    expect(() => _make(choices: const [11]), throwsArgumentError);
    expect(() => _make(choices: const [11, 11, 22]), throwsArgumentError);
    expect(() => _make(choices: const [9, 22]), throwsArgumentError);
    expect(() => _make(choices: const [22, 100]), throwsArgumentError);
  });

  test('type mode must not carry choices', () {
    expect(() => _make(mode: LoginApprovalInputMode.type, choices: const [11, 22]), throwsArgumentError);
    expect(_make(mode: LoginApprovalInputMode.type, choices: const []).choices, isEmpty);
  });

  test('rejects a negative enable delay', () {
    expect(() => _make(delay: const Duration(seconds: -1)), throwsArgumentError);
  });

  test('isValidNumber accepts 10 to 99 only', () {
    expect(LoginApprovalRequest.isValidNumber(9), isFalse);
    expect(LoginApprovalRequest.isValidNumber(10), isTrue);
    expect(LoginApprovalRequest.isValidNumber(99), isTrue);
    expect(LoginApprovalRequest.isValidNumber(100), isFalse);
  });

  test('default countdown text', () {
    expect(LoginApprovalTexts.defaultTimeLeft(const Duration(seconds: 65)), 'Expires in 1:05');
    expect(LoginApprovalTexts.defaultTimeLeft(Duration.zero), 'Expires in 0:00');
  });
}

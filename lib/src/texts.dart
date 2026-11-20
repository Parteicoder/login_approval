/// All strings of the sheet. The defaults are English; pass your own to translate.
class LoginApprovalTexts {
  /// Creates a text set. Every field has an English default.
  const LoginApprovalTexts({
    this.title = 'Is this you signing in?',
    this.subtitle = 'A sign-in was started in a browser. Only continue if it was you.',
    this.chooseNumber = 'Tap the number shown in your browser',
    this.typeNumber = 'Enter the number shown in your browser',
    this.numberLabel = 'Number',
    this.approve = 'Approve',
    this.deny = "No, this wasn't me",
    this.notNow = 'Not now',
    this.failed = 'That did not work. Please try again.',
    this.timeLeft = defaultTimeLeft,
  });

  /// Headline of the sheet.
  final String title;

  /// Short explanation under the headline.
  final String subtitle;

  /// Prompt above the numbers in choose mode.
  final String chooseNumber;

  /// Prompt above the text field in type mode.
  final String typeNumber;

  /// Label of the text field in type mode.
  final String numberLabel;

  /// Label of the approve button in type mode.
  final String approve;

  /// Label of the "this wasn't me" button.
  final String deny;

  /// Label of the button that closes the sheet without a decision.
  final String notNow;

  /// Shown when the decision could not be delivered.
  final String failed;

  /// Builds the countdown text.
  final String Function(Duration remaining) timeLeft;

  /// English countdown such as `Expires in 1:05`.
  static String defaultTimeLeft(Duration remaining) {
    final m = remaining.inMinutes;
    final s = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return 'Expires in $m:$s';
  }
}

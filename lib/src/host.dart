import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'sheet.dart';
import 'texts.dart';

/// Puts the sheet above your app while a request is waiting.
///
/// Place it in `MaterialApp.builder`. While the sheet is up, the app behind it
/// can neither be tapped nor focused, and screen readers skip it.
///
/// With [pauseWhenInBackground] the host calls
/// [LoginApprovalController.setForeground] on lifecycle changes, so polling
/// stops in the background and runs again right after the app resumes.
class LoginApprovalHost extends StatefulWidget {
  /// Creates the host.
  const LoginApprovalHost({
    super.key,
    required this.controller,
    required this.child,
    this.texts = const LoginApprovalTexts(),
    this.pauseWhenInBackground = true,
  });

  /// The controller to show.
  final LoginApprovalController controller;

  /// Your app.
  final Widget child;

  /// The strings of the sheet.
  final LoginApprovalTexts texts;

  /// Whether to stop polling while the app is in the background.
  final bool pauseWhenInBackground;

  @override
  State<LoginApprovalHost> createState() => _LoginApprovalHostState();
}

class _LoginApprovalHostState extends State<LoginApprovalHost> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apply(WidgetsBinding.instance.lifecycleState);
  }

  @override
  void didUpdateWidget(LoginApprovalHost old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.setForeground(true);
      _apply(WidgetsBinding.instance.lifecycleState);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _apply(state);

  // `inactive` (system dialogs, biometric prompt) still counts as foreground.
  void _apply(AppLifecycleState? state) {
    if (!widget.pauseWhenInBackground) return;
    final background = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    widget.controller.setForeground(!background);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final shown = widget.controller.current != null;
        return Stack(
          children: [
            Positioned.fill(
              child: ExcludeFocus(
                excluding: shown,
                child: ExcludeSemantics(excluding: shown, child: widget.child),
              ),
            ),
            // The host usually sits above the Navigator, so there is no Overlay
            // for the text field of the sheet. This one brings its own.
            if (shown)
              Positioned.fill(
                child: Overlay.wrap(
                  child: Stack(
                    children: [
                      const ModalBarrier(dismissible: false, color: Color(0x99000000)),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: LoginApprovalSheet(
                          controller: widget.controller,
                          texts: widget.texts,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

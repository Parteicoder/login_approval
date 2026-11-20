import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'controller.dart';
import 'models.dart';
import 'texts.dart';

/// The "Is this you?" card. Draws nothing while [LoginApprovalController.current] is `null`.
///
/// [LoginApprovalHost] places it for you. Use the sheet directly only if you
/// want to host it yourself, for example inside your own dialog.
class LoginApprovalSheet extends StatefulWidget {
  /// Creates the sheet.
  const LoginApprovalSheet({
    super.key,
    required this.controller,
    this.texts = const LoginApprovalTexts(),
  });

  /// Source of the request and target of the user's decision.
  final LoginApprovalController controller;

  /// The strings to show.
  final LoginApprovalTexts texts;

  @override
  State<LoginApprovalSheet> createState() => _LoginApprovalSheetState();
}

class _LoginApprovalSheetState extends State<LoginApprovalSheet> {
  final _field = TextEditingController();
  Timer? _tick;
  Timer? _delayTimer;
  String? _id;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(LoginApprovalSheet old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
      _id = null;
      _sync();
    }
  }

  // Keeps the countdown and the enable delay moving while a request is shown.
  void _sync() {
    final id = widget.controller.current?.id;
    if (id == _id) return;
    _id = id;
    _tick?.cancel();
    _tick = null;
    _delayTimer?.cancel();
    _delayTimer = null;
    _field.clear();
    final request = widget.controller.current;
    final shownAt = widget.controller.shownAt;
    if (request != null && shownAt != null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      final wait = request.enableDelay - widget.controller.now().difference(shownAt);
      if (!wait.isNegative) {
        _delayTimer = Timer(wait, () {
          if (mounted) setState(() {});
        });
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _tick?.cancel();
    _delayTimer?.cancel();
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final request = widget.controller.current;
        if (request == null) return const SizedBox.shrink();
        return _buildSheet(context, request);
      },
    );
  }

  Widget _buildSheet(BuildContext context, LoginApprovalRequest request) {
    final c = widget.controller;
    final t = widget.texts;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = c.now();
    final left = request.expiresAt.difference(now);
    final remaining = left.isNegative ? Duration.zero : left;
    final shownAt = c.shownAt ?? now;
    final ready = !c.busy && now.difference(shownAt) >= request.enableDelay;

    final children = <Widget>[
      Semantics(
        header: true,
        liveRegion: true,
        child: Text(t.title, style: theme.textTheme.headlineSmall),
      ),
      const SizedBox(height: 8),
      Text(t.subtitle, style: theme.textTheme.bodyMedium),
      if (request.warning != null) ...[
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                request.warning!,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ),
        ),
      ],
      if (request.details.isNotEmpty) ...[
        const SizedBox(height: 16),
        for (final d in request.details)
          MergeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      d.label,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  Expanded(child: Text(d.value, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
          ),
      ],
      const SizedBox(height: 20),
      Text(
        request.mode == LoginApprovalInputMode.choose ? t.chooseNumber : t.typeNumber,
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      if (request.mode == LoginApprovalInputMode.choose)
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            for (final n in request.choices)
              FilledButton(
                onPressed: ready ? () => unawaited(c.approve(n, requestId: request.id)) : null,
                style: FilledButton.styleFrom(minimumSize: const Size(88, 64)),
                child: Text('$n', style: theme.textTheme.headlineMedium),
              ),
          ],
        )
      else
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _field,
          builder: (context, value, _) {
            final typed = int.tryParse(value.text);
            final valid =
                value.text.length == 2 && typed != null && LoginApprovalRequest.isValidNumber(typed);
            void submit() {
              if (ready && valid) unawaited(c.approve(typed, requestId: request.id));
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _field,
                  enabled: !c.busy,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: InputDecoration(labelText: t.numberLabel),
                  onSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: ready && valid ? submit : null,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: Text(t.approve),
                ),
              ],
            );
          },
        ),
      if (c.busy) ...[const SizedBox(height: 16), const LinearProgressIndicator()],
      if (c.lastOutcome == LoginApprovalOutcome.failed) ...[
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(t.failed, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error)),
        ),
      ],
      const SizedBox(height: 16),
      Text(
        t.timeLeft(remaining),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: c.busy ? null : () => unawaited(c.deny(requestId: request.id)),
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.error,
          minimumSize: const Size.fromHeight(48),
        ),
        child: Text(t.deny),
      ),
      TextButton(
        onPressed: c.busy ? null : () => c.dismiss(requestId: request.id),
        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: Text(t.notNow),
      ),
    ];

    // Lift the sheet above the keyboard in type mode.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: scheme.surface,
        elevation: 8,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

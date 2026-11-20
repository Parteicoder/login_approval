import 'dart:async';

import 'package:flutter/foundation.dart';

import 'client.dart';
import 'models.dart';

/// Receives errors thrown by the [LoginApprovalClient].
typedef LoginApprovalErrorHandler = void Function(Object error, StackTrace stackTrace);

/// Polls the [LoginApprovalClient] and holds the request that is on screen.
///
/// Call [start] when the user is signed in to your app and [stop] when they
/// sign out. [LoginApprovalHost] pauses polling while the app is in the
/// background by calling [setForeground].
class LoginApprovalController extends ChangeNotifier {
  /// Creates a controller.
  ///
  /// After [start] and after every [pollNow] it polls every [fastInterval] for
  /// [fastWindow], then every [slowInterval]. [clock] exists for tests.
  LoginApprovalController({
    required this.client,
    this.fastInterval = const Duration(seconds: 3),
    this.slowInterval = const Duration(seconds: 30),
    this.fastWindow = const Duration(minutes: 2),
    this.onError,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (fastInterval <= Duration.zero || slowInterval <= Duration.zero) {
      throw ArgumentError('Poll intervals must be positive.');
    }
  }

  /// Your backend adapter.
  final LoginApprovalClient client;

  /// Poll interval right after [start] or [pollNow].
  final Duration fastInterval;

  /// Poll interval once the fast window is over.
  final Duration slowInterval;

  /// How long the fast interval lasts.
  final Duration fastWindow;

  /// Called with every error the client throws. Errors never leave the controller.
  final LoginApprovalErrorHandler? onError;

  final DateTime Function() _clock;

  static const _maxIgnored = 16;

  LoginApprovalRequest? _current;
  DateTime? _shownAt;
  bool _busy = false;
  LoginApprovalOutcome? _lastOutcome;
  bool _started = false;
  bool _foreground = true;
  bool _polling = false;
  Future<void>? _pollFuture;
  bool _disposed = false;
  int _generation = 0;
  DateTime _fastUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _pollTimer;
  Timer? _expiryTimer;
  final _ignored = <String>[];

  /// The request on screen, or `null`.
  LoginApprovalRequest? get current => _current;

  /// When [current] first appeared, on the controller's clock.
  DateTime? get shownAt => _shownAt;

  /// Whether an approve or deny call is running.
  bool get busy => _busy;

  /// The result of the last approve or deny call. Cleared when a request appears.
  LoginApprovalOutcome? get lastOutcome => _lastOutcome;

  /// The controller's notion of now.
  DateTime now() => _clock();

  bool get _active => _started && _foreground && !_disposed;

  /// Starts polling. Does nothing when already started.
  void start() {
    if (_disposed || _started) return;
    _started = true;
    _fastUntil = _clock().add(fastWindow);
    unawaited(_poll());
  }

  /// Stops polling and removes the request on screen (unless a decision is in flight).
  void stop() {
    if (_disposed) return;
    _started = false;
    _generation++;
    _polling = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _ignored.clear();
    if (!_busy && _current != null) {
      _clear();
      notifyListeners();
    }
  }

  /// Tells the controller whether the app is in the foreground.
  void setForeground(bool foreground) {
    if (_disposed || _foreground == foreground) return;
    _foreground = foreground;
    if (foreground) {
      if (_started) {
        _fastUntil = _clock().add(fastWindow);
        unawaited(_poll());
      }
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  /// Polls right away and switches back to the fast interval.
  ///
  /// Completes when the poll is done. If one is already running, waits for it.
  Future<void> pollNow() async {
    if (!_active) return;
    _fastUntil = _clock().add(fastWindow);
    await _poll();
  }

  Future<void> _poll() {
    if (!_active) return Future<void>.value();
    if (_polling) return _pollFuture ?? Future<void>.value();
    return _pollFuture = _doPoll();
  }

  Future<void> _doPoll() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _polling = true;
    final generation = _generation;
    try {
      final request = await client.fetchPending();
      if (generation != _generation || _disposed) return;
      _accept(request);
    } catch (error, stack) {
      if (generation == _generation) _report(error, stack);
    } finally {
      if (generation == _generation) {
        _polling = false;
        if (_active) {
          final interval = _clock().isBefore(_fastUntil) ? fastInterval : slowInterval;
          _pollTimer = Timer(interval, () {
            _pollTimer = null;
            unawaited(_poll());
          });
        }
      }
    }
  }

  void _accept(LoginApprovalRequest? request) {
    if (request == null) {
      if (_current != null && !_busy) {
        _clear();
        notifyListeners();
      }
      return;
    }
    if (_busy || _ignored.contains(request.id) || _current?.id == request.id) return;
    if (!request.expiresAt.isAfter(_clock())) return;
    _current = request;
    _shownAt = _clock();
    _lastOutcome = null;
    _armExpiry(request);
    notifyListeners();
  }

  void _armExpiry(LoginApprovalRequest request) {
    _expiryTimer?.cancel();
    final wait = request.expiresAt.difference(_clock());
    _expiryTimer = Timer(wait.isNegative ? Duration.zero : wait, () {
      _expiryTimer = null;
      if (_current?.id != request.id || _busy || _disposed) return;
      _expire(request);
    });
  }

  /// The user picked or typed [number] for the request [requestId].
  ///
  /// Returns `null`, and sends nothing, when the call does not fit what is on
  /// screen: no request, another request id (the screen changed under the
  /// finger), a number that was not offered, the enable delay is not over yet,
  /// or a decision is already running. The reason is passed to [onError] where
  /// it points to a bug in the caller.
  Future<LoginApprovalOutcome?> approve(int number, {required String requestId}) {
    final request = _current;
    if (request != null && request.id == requestId) {
      final allowed = request.mode == LoginApprovalInputMode.choose
          ? request.choices.contains(number)
          : LoginApprovalRequest.isValidNumber(number);
      if (!allowed) {
        _report(ArgumentError.value(number, 'number', 'not allowed for this request'), StackTrace.current);
        return Future.value();
      }
      final shownAt = _shownAt;
      if (shownAt != null && _clock().difference(shownAt) < request.enableDelay) {
        return Future.value();
      }
    }
    return _decide(requestId, (id) => client.approve(id, number));
  }

  /// The user said "this wasn't me" about the request [requestId].
  /// Returns `null` when the call was ignored, see [approve].
  Future<LoginApprovalOutcome?> deny({required String requestId}) =>
      _decide(requestId, client.deny);

  Future<LoginApprovalOutcome?> _decide(
    String requestId,
    Future<LoginApprovalOutcome> Function(String id) call,
  ) async {
    final request = _current;
    if (request == null || request.id != requestId || _busy || _disposed) return null;
    if (!request.expiresAt.isAfter(_clock())) {
      _expire(request);
      return LoginApprovalOutcome.expired;
    }
    _busy = true;
    _lastOutcome = null;
    notifyListeners();
    var outcome = LoginApprovalOutcome.failed;
    try {
      outcome = await call(request.id);
    } catch (error, stack) {
      _report(error, stack);
    }
    if (_disposed) return outcome;
    _busy = false;
    _lastOutcome = outcome;
    if (outcome != LoginApprovalOutcome.failed) {
      _ignore(request.id);
      if (_current?.id == request.id) _clear();
    } else if (_current?.id == request.id) {
      // A failed call keeps the request for a retry, unless the request has
      // run out in the meantime or the user has signed out.
      if (!_started) {
        _clear();
      } else if (!request.expiresAt.isAfter(_clock())) {
        _ignore(request.id);
        _lastOutcome = LoginApprovalOutcome.expired;
        _clear();
      }
    }
    notifyListeners();
    return outcome;
  }

  void _expire(LoginApprovalRequest request) {
    _ignore(request.id);
    _lastOutcome = LoginApprovalOutcome.expired;
    _clear();
    notifyListeners();
  }

  /// Closes the sheet without deciding about the request [requestId].
  /// The request is not shown again.
  void dismiss({required String requestId}) {
    final request = _current;
    if (request == null || request.id != requestId || _busy || _disposed) return;
    _ignore(request.id);
    _clear();
    notifyListeners();
    unawaited(() async {
      try {
        await client.dismiss(request.id);
      } catch (error, stack) {
        _report(error, stack);
      }
    }());
  }

  void _clear() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _current = null;
    _shownAt = null;
  }

  void _ignore(String id) {
    _ignored.add(id);
    if (_ignored.length > _maxIgnored) _ignored.removeAt(0);
  }

  void _report(Object error, StackTrace stack) => onError?.call(error, stack);

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }
}

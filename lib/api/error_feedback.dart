import 'package:flutter/material.dart';

import 'api_exception.dart';

/// Shows the user-facing message and returns whether the caller should
/// re-enable its button right away.
bool reportApiError(BuildContext context, Object error, {VoidCallback? onRetry}) {
  final e = error is ApiException
      ? error
      : ApiException(kind: ApiErrorKind.server, message: '$error');

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(e.userMessage),
      duration: e.kind == ApiErrorKind.quotaExceeded
          ? const Duration(seconds: 12)
          : const Duration(seconds: 5),
      action: onRetry != null && e.retryable
          ? SnackBarAction(label: 'Retry', onPressed: onRetry)
          : null,
    ),
  );

  return e.retryable;
}

/// Three strikes of rate-limit/quota → the whole screen goes read-only until
/// the window passes, instead of hammering a Worker that is already out.
class BackendStatus extends ChangeNotifier {
  int _streak = 0;
  DateTime? _until;

  bool get degraded => _streak >= 3;

  Duration? get wait {
    final until = _until;
    if (until == null) return null;
    final left = until.difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  void record(Object error) {
    if (error is! ApiException) return;

    final limited = error.kind == ApiErrorKind.rateLimited ||
        error.kind == ApiErrorKind.quotaExceeded;

    if (limited) {
      _streak++;
      final retryAfter = error.retryAfter;
      if (retryAfter != null) _until = DateTime.now().add(retryAfter);
    } else if (error.kind != ApiErrorKind.network) {
      _streak = 0;
    }
    notifyListeners();
  }

  void recordSuccess() {
    if (_streak == 0 && _until == null) return;
    _streak = 0;
    _until = null;
    notifyListeners();
  }
}

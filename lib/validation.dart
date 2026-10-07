/// Client-side validators shared by the auth screens.
final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

/// Error message when [value] is not a usable email, otherwise null.
String? validateEmail(String value) {
  final v = value.trim();
  if (v.isEmpty) return 'Email is required';
  if (!_emailPattern.hasMatch(v)) return 'Enter a valid email address';
  return null;
}

/// Error message when [value] is not an acceptable password, otherwise null.
/// Set [enforceLength] for registration (Appwrite's default minimum is 8).
/// The 256-char cap always applies — Appwrite rejects longer values too.
String? validatePassword(String value, {bool enforceLength = false}) {
  if (value.isEmpty) return 'Password is required';
  if (value.length > 256) return 'Password must be 256 characters or fewer';
  if (enforceLength && value.length < 8) return 'Use at least 8 characters';
  return null;
}

/// Rewrites raw backend messages into copy a user can act on.
/// Anything unmapped is passed through unchanged.
String friendlyAuthError(String rawMessage, {required String fallback}) {
  final raw = rawMessage.trim();
  if (raw.isEmpty) return fallback;
  final m = raw.toLowerCase();
  if (m.contains('param must be between') ||
      (m.contains('invalid password') && m.contains('8'))) {
    return 'Password must be between 8 and 256 characters';
  }
  if (m.contains('already exist')) {
    return 'An account with this email already exists';
  }
  if (m.contains('invalid credential')) {
    return 'Incorrect email or password';
  }
  if (m.contains('user blocked')) {
    return 'This account has been blocked';
  }
  if (m.contains('too many') || m.contains('rate limit')) {
    return 'Too many attempts — wait a moment and try again';
  }
  return raw;
}

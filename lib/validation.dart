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
/// Set [enforceLength] for registration (the Worker's minimum is 8).
/// The 256-char cap always applies — the server rejects longer values too.
String? validatePassword(String value, {bool enforceLength = false}) {
  if (value.isEmpty) return 'Password is required';
  if (value.length > 256) return 'Password must be 256 characters or fewer';
  if (enforceLength && value.length < 8) return 'Use at least 8 characters';
  return null;
}

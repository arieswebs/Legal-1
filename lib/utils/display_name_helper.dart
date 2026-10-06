/// Centralized display-name helper for staff / user emails.
///
/// Keeps a small overrides map so we can fix spellings without touching
/// the Cognito user-pool.
class DisplayNameHelper {
  DisplayNameHelper._();

  /// Email-prefix → corrected display name.
  /// Add entries here whenever a Cognito username has a typo.
  static const Map<String, String> _overrides = {
    'muhammed.aslam.pa': 'Mohammed Aslam PA',
  };

  /// Direct name overrides (case-insensitive).
  /// Use this when the name stored in the Users table has a typo.
  static const Map<String, String> _nameOverrides = {
    'muhammed aslam pa': 'Mohammed Aslam PA',
  };

  /// Convert an email like `muhammed.aslam.pa@domain.com` into a
  /// human-readable name such as `Mohammed Aslam PA`.
  ///
  /// 1. Checks the overrides table first.
  /// 2. Falls back to title-casing each dot-separated segment.
  static String fromEmail(String email) {
    final prefix = email.split('@')[0].toLowerCase().trim();

    if (_overrides.containsKey(prefix)) {
      return _overrides[prefix]!;
    }

    // Default: title-case each dot-separated token
    return prefix
        .split('.')
        .map((s) => s.isEmpty ? '' : '${s[0].toUpperCase()}${s.substring(1)}')
        .join(' ');
  }

  /// Apply spelling corrections to a name fetched from the database.
  /// Returns the corrected name if an override exists, otherwise the original.
  static String overrideName(String name) {
    final key = name.toLowerCase().trim();
    return _nameOverrides[key] ?? name;
  }
}

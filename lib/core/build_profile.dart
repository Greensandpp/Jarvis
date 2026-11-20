import 'package:flutter/services.dart' show appFlavor;

/// Which Android build this is. One codebase, two installable apps:
///
/// * `standard`  – Play-Protect-friendly. No accessibility service, floating
///   overlay, contacts, all-package listing, usage stats, WRITE_SETTINGS,
///   storage-wide access or Shizuku. Those features are hidden/disabled and
///   say so honestly instead of failing silently.
/// * `full`      – "Full Control" build with the original JARVIS permissions.
///
/// Builds without a flavor (unit tests, `flutter run` without --flavor) keep
/// the original behaviour (= full) so nothing existing changes.
class BuildProfile {
  BuildProfile._();

  static String get flavor => appFlavor ?? 'full';
  static bool get isStandard => flavor == 'standard';
  static bool get fullControl => !isStandard;

  static String get label => isStandard ? 'STANDARD BUILD' : 'FULL CONTROL BUILD';

  static const standardNotice =
      'Standard build: screen automation (accessibility), the floating bubble, contacts, '
      'app-usage stats, system-settings writes and Shizuku are not included, so Play Protect '
      'has nothing high-risk to flag. Install the separate "JARVIS Full Control" build if you '
      'want those features.';

  static String unavailable(String feature) =>
      '$feature is not available in the Standard build. It needs the separate JARVIS Full Control build.';
}

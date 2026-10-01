import 'package:flutter/services.dart';

/// One vocabulary for touch feedback, shared with the Customer App so the two
/// apps answer a tap the same way.
class AppHaptics {
  AppHaptics._();

  /// Normal Button / Primary Action
  static Future<void> lightImpact() async {
    await HapticFeedback.lightImpact();
  }

  /// Important Confirmation Actions, Success States, Errors, Destructive Actions (confirmed)
  static Future<void> mediumImpact() async {
    await HapticFeedback.mediumImpact();
  }

  /// Very strong reason / rare heavy action
  static Future<void> heavyImpact() async {
    await HapticFeedback.heavyImpact();
  }

  /// Selection Controls (filters, options, date/time picker, bottom sheet items)
  static Future<void> selectionClick() async {
    await HapticFeedback.selectionClick();
  }

  /// Alias for success matching mediumImpact
  static Future<void> success() async {
    await mediumImpact();
  }

  /// Alias for error matching mediumImpact
  static Future<void> error() async {
    await mediumImpact();
  }
}

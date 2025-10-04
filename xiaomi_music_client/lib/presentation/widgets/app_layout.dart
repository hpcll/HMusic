import 'package:flutter/material.dart';

/// Shared layout utilities related to the floating bottom navigation overlay.
class AppLayout {
  const AppLayout._();

  /// Total vertical space occupied by the floating bottom navigation overlay,
  /// including its top margin and bottom safe-area margin.
  static double bottomOverlayHeight(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewPadding.bottom;
    final gestureInset = mediaQuery.systemGestureInsets.bottom;
    final hasGesture = gestureInset > 0 || bottomInset > 0;
    const double navHeight = 68.0; // matches _buildModernBottomNav
    const double navTopMargin = 10.0;
    const double baseBottomMargin = 24.0;
    final double navBottomMargin = hasGesture ? (baseBottomMargin - 15.0) : baseBottomMargin;

    return navHeight + navTopMargin + navBottomMargin;
  }

  /// Suggested content bottom padding so the last item scrolls above the nav.
  static double contentBottomPadding(
    BuildContext context, {
    double extra = 12,
  }) {
    return bottomOverlayHeight(context) + extra;
  }
}

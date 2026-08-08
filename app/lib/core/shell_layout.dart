/// Responsive shell layout selection.
///
/// Three explicit layouts rather than a stretched phone UI:
///  - [phone]:   compact width → bottom navigation, primary destinations only.
///  - [tablet]:  expanded width → navigation rail with all destinations
///               (personal-iPad planning posture).
///  - [kitchen]: Kitchen Device Mode enabled → simplified large-format shell
///               (big targets, reduced navigation, dashboard-first).
///
/// Kitchen Mode is a DEVICE preference (see `kitchen_mode.dart`); it wins over
/// width so the mode is predictable on whatever device it was enabled on.
library;

enum ShellLayout { phone, tablet, kitchen }

/// Material 3 "expanded" breakpoint: >= 840 logical px is tablet-class.
const double tabletBreakpoint = 840;

ShellLayout resolveShellLayout({
  required double width,
  required bool kitchenMode,
}) {
  if (kitchenMode) return ShellLayout.kitchen;
  return width >= tabletBreakpoint ? ShellLayout.tablet : ShellLayout.phone;
}

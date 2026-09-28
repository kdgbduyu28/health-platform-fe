import 'package:flutter/material.dart';

extension ReadableTone on Color {
  /// This colour, lifted toward white on a dark theme. The status colours
  /// are mid-tones picked for a light surface; on a dark one they turn
  /// muddy (purple "Waiting", grey "No-show"). Matches [remarkColor].
  Color readableIn(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Color.lerp(this, Colors.white, 0.45)!
          : this;
}

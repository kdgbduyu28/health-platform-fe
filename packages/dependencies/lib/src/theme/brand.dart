import 'package:flutter/material.dart';

/// D-Touch brand constants — colour and logo assets in one place, so a brand
/// change is a change here rather than a hunt through four apps.
class Brand {
  const Brand._();

  /// Sampled straight from the logo artwork (`#654F3B`), not eyeballed.
  static const brown = Color(0xFF654F3B);

  /// The package that owns the asset bundle. Assets shipped inside a package
  /// need this on every lookup, or Flutter resolves them against the app.
  static const package = 'api_sdk';

  /// Full lockup: "D-Touch DENTAL CLINIC" plus the mark.
  static const wordmarkAsset = 'assets/brand/dtouch_wordmark.png';

  /// The mark on its own — tooth cradled in a hand.
  static const markAsset = 'assets/brand/dtouch_mark.png';
}

/// The D-Touch lockup, sized by height.
///
/// Both files are transparent PNGs, so they sit on any background without the
/// white box a flattened export would bring.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.height = 72, this.color});

  final double height;

  /// Tints the artwork — needed on the coloured gradients, where the brown
  /// would otherwise disappear into the background.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      Brand.wordmarkAsset,
      package: Brand.package,
      height: height,
      color: color,
      fit: BoxFit.contain,
      // Named for screen readers, which cannot read pixels.
      semanticLabel: 'D-Touch Dental Clinic',
    );
  }
}

/// The mark alone, for tight spaces — app bars, avatars, empty states.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      Brand.markAsset,
      package: Brand.package,
      height: size,
      width: size,
      color: color,
      fit: BoxFit.contain,
      semanticLabel: 'D-Touch',
    );
  }
}


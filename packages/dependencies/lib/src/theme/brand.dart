import 'package:flutter/material.dart';

import '../models/clinic.dart';

/// Platform-level brand constants.
///
/// Clinic branding comes from each clinic's row at runtime. These are what
/// shows when there is no clinic yet — the sign-in screen, before anyone is
/// known — and what a clinic falls back to when it has not set its own.
class Brand {
  const Brand._();

  /// A deliberately neutral default. It is NOT any client's colour: the sign-in
  /// screen is shared by every clinic on the platform, and D-Touch's brown
  /// there would brand every other clinic's login as D-Touch. D-Touch keeps its
  /// brown from its own clinic row once signed in.
  static const platformSeed = Color(0xFF3D5A80);

  /// The package that owns the asset bundle. Assets shipped inside a package
  /// need this on every lookup, or Flutter resolves them against the app.
  static const package = 'api_sdk';

  /// Prefix for a clinic's `logo_url` / `wordmark_url` meaning "bundled in this
  /// package" rather than a hosted file. A stopgap for artwork that predates
  /// logo uploads (D-Touch's lockup ships this way); hosted URLs are the
  /// normal path for a new clinic.
  static const bundledAssetScheme = 'asset:';
}

/// A clinic's square mark: its logo if it has one, otherwise its vertical's
/// icon on the theme colour. With no clinic, the platform's generic mark.
class ClinicMark extends StatelessWidget {
  const ClinicMark({super.key, this.clinic, this.size = 48});

  final Clinic? clinic;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = _IconTile(
      icon: clinic?.icon ?? Icons.local_hospital_outlined,
      size: size,
    );
    final url = clinic?.logoUrl;
    if (url == null || url.isEmpty) return fallback;

    return SizedBox.square(
      dimension: size,
      child: _ClinicImage(
        url: url,
        // Named for screen readers, which cannot read pixels.
        semanticLabel: clinic!.name,
        fallback: fallback,
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(icon, size: size * 0.5, color: cs.onPrimary),
    );
  }
}

/// Loads a clinic image from the bundle or the network, and shows [fallback]
/// if it cannot — a broken or unreachable logo URL must not leave a hole in
/// the app bar.
class _ClinicImage extends StatelessWidget {
  const _ClinicImage({
    required this.url,
    required this.semanticLabel,
    required this.fallback,
  });

  final String url;
  final String semanticLabel;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    Widget onError(BuildContext _, Object __, StackTrace? ___) => fallback;

    if (url.startsWith(Brand.bundledAssetScheme)) {
      return Image.asset(
        url.substring(Brand.bundledAssetScheme.length),
        package: Brand.package,
        fit: BoxFit.contain,
        semanticLabel: semanticLabel,
        errorBuilder: onError,
      );
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      semanticLabel: semanticLabel,
      errorBuilder: onError,
    );
  }
}

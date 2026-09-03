import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/assets.dart';
import '../app/theme/app_colors.dart';
import 'safe_asset.dart';

/// The warm cream ground every screen sits on.
///
/// Three layers: the gradient, the zodiac-wheel artwork, and a few sparkles. The gradient is
/// drawn in code rather than shipped as an image so it fills any screen size exactly and costs
/// nothing to decode; only the ornament is an asset, and it is decoration — the screens read
/// correctly with or without it.
class AstralBackground extends StatelessWidget {
  const AstralBackground({super.key, required this.child, this.showOrnament = true});

  final Widget child;

  /// Off for the onboarding screen, where a sheet covers the lower half and the artwork sits
  /// in the device-framed hero instead.
  final bool showOrnament;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.backdrop),
      child: Stack(
        children: [
          if (showOrnament) ...[
            // Anchored top-right, matching the sun burst's position in the renders, and
            // deliberately allowed to bleed off both edges.
            Positioned(
              top: -60,
              right: -80,
              child: IgnorePointer(
                child: SafeImage(
                  Img.backdrop,
                  width: 420,
                  fit: BoxFit.contain,
                  fallback: const _SunBurst(),
                ),
              ),
            ),
            const Positioned.fill(child: IgnorePointer(child: _Sparkles())),
          ],
          child,
        ],
      ),
    );
  }
}

/// Stands in for the zodiac artwork until it is exported.
///
/// Not an attempt to reproduce the illustration — it is a soft radial glow in the same place,
/// so the composition reads the same and nothing shifts when the real file arrives.
class _SunBurst extends StatelessWidget {
  const _SunBurst();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 420,
      height: 420,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [AppColors.ornament, Color(0x00E0A93B)],
          stops: [0.0, 0.72],
        ),
      ),
    );
  }
}

/// The scattered four-point stars. Positions are fixed fractions, not random, so the layout is
/// identical on every build and in every screenshot test.
class _Sparkles extends StatelessWidget {
  const _Sparkles();

  static const _points = <(double dx, double dy, double size)>[
    (0.06, 0.04, 12),
    (0.17, 0.11, 7),
    (0.90, 0.30, 9),
    (0.08, 0.55, 8),
    (0.13, 0.93, 13),
    (0.83, 0.88, 8),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            for (final (dx, dy, size) in _points)
              Positioned(
                left: constraints.maxWidth * dx,
                top: constraints.maxHeight * dy,
                child: CustomPaint(size: Size.square(size), painter: _SparklePainter()),
              ),
          ],
        );
      },
    );
  }
}

class _SparklePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / 2;
    // A four-point star: straight tips, waisted at the centre. Quadratics pulled toward the
    // middle are what give it the pinch — straight lines would read as a plus sign.
    final path = Path()
      ..moveTo(c, 0)
      ..quadraticBezierTo(c * 1.12, c * 0.88, size.width, c)
      ..quadraticBezierTo(c * 1.12, c * 1.12, c, size.height)
      ..quadraticBezierTo(c * 0.88, c * 1.12, 0, c)
      ..quadraticBezierTo(c * 0.88, c * 0.88, c, 0)
      ..close();

    canvas.drawPath(path, Paint()..color = AppColors.gold.withValues(alpha: 0.45));
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) => false;
}

/// The faint zodiac ring used behind the birth screen's picker.
///
/// Kept separate from [AstralBackground] because it is centred on its own content rather than
/// on the screen.
class ZodiacRing extends StatelessWidget {
  const ZodiacRing({super.key, this.diameter = 260});

  final double diameter;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.square(diameter),
        painter: _RingPainter(),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.gold.withValues(alpha: 0.18);

    canvas.drawCircle(centre, size.width / 2, stroke);
    canvas.drawCircle(centre, size.width / 2.35, stroke);

    // Twelve ticks, one per sign.
    for (var i = 0; i < 12; i++) {
      final angle = i * math.pi / 6;
      final outer = size.width / 2;
      final inner = size.width / 2.35;
      canvas.drawLine(
        centre + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        centre + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => false;
}

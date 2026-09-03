import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/assets.dart';
import '../app/theme/app_colors.dart';
import 'safe_asset.dart';

/// Which exported ground a screen sits on.
///
/// Two distinct files, not one tinted two ways: the onboarding ground is nearly white
/// (`#FFFAF2`), the home ground markedly warmer (`#FEF1DC`). Using one for the other is
/// immediately visible.
enum AstralSurface {
  /// Onboarding and the birth screen.
  onboarding,

  /// Home and the paywall.
  home,
}

/// The warm ground every screen sits on.
///
/// The exported artwork already contains the zodiac wheel, sun burst, sparkles and warm blobs,
/// so nothing is drawn on top of it — an earlier version painted its own sun and sparkles, and
/// with the real file in place those doubled up.
///
/// A gradient sits underneath as the fallback. It shows only if the image is missing, and is
/// sampled from the same export so that case still reads as deliberate.
class AstralBackground extends StatelessWidget {
  const AstralBackground({
    super.key,
    required this.child,
    this.surface = AstralSurface.onboarding,
  });

  final Widget child;
  final AstralSurface surface;

  @override
  Widget build(BuildContext context) {
    final (image, gradient) = switch (surface) {
      AstralSurface.onboarding => (Img.bgOnboarding, AppColors.backdrop),
      AstralSurface.home => (Img.bgHome, AppColors.backdropWarm),
    };

    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // `cover` rather than `fill`: the export is a fixed 824x1834, and stretching it to a
          // squatter screen visibly distorts the zodiac wheel into an ellipse.
          IgnorePointer(child: SafeImage(image, fit: BoxFit.cover)),
          child,
        ],
      ),
    );
  }
}

/// A faint zodiac ring, drawn rather than exported.
///
/// Used only by the onboarding hero's placeholder, which stands in for a device mockup that has
/// not been exported. Not part of any real screen's ground.
class ZodiacRing extends StatelessWidget {
  const ZodiacRing({super.key, this.diameter = 260});

  final double diameter;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(size: Size.square(diameter), painter: _RingPainter()),
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

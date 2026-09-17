import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/assets.dart';
import '../app/theme/app_colors.dart';
import 'safe_asset.dart';

/// A slowly turning ring of the twelve rashis around the om — the kundali waiting screen's centre.
///
/// One turn a minute: slow enough to read as calm rather than as a spinner. Still when the system
/// asks for reduced motion, which also keeps widget tests free of a ticker that never settles.
class ZodiacWheel extends StatefulWidget {
  const ZodiacWheel({super.key, this.size = 200});

  final double size;

  @override
  State<ZodiacWheel> createState() => _ZodiacWheelState();
}

class _ZodiacWheelState extends State<ZodiacWheel> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(seconds: 60));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return Semantics(
      label: 'The zodiac turning while your Kundali is prepared',
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            RotationTransition(
              turns: _turn,
              child: CustomPaint(size: Size.square(size), painter: _WheelPainter()),
            ),
            Container(
              width: size * 0.34,
              height: size * 0.34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface,
                border: Border.all(color: AppColors.gold, width: 1.5),
                boxShadow: const [AppColors.floatingShadow],
              ),
              padding: EdgeInsets.all(size * 0.06),
              child: SafeImage(
                Brand.mark,
                fit: BoxFit.contain,
                fallback: Center(
                  child: Text('ॐ', style: TextStyle(fontSize: size * 0.14, color: AppColors.goldDeep)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  static const _glyphs = ['♈', '♉', '♊', '♋', '♌', '♍', '♎', '♏', '♐', '♑', '♒', '♓'];

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final outer = size.width / 2;
    final inner = outer * 0.72;

    canvas.drawCircle(
      centre,
      outer,
      Paint()
        ..shader = RadialGradient(
          colors: [AppColors.goldWash, AppColors.goldWash.withValues(alpha: 0.2)],
        ).createShader(Rect.fromCircle(center: centre, radius: outer)),
    );

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = AppColors.gold.withValues(alpha: 0.7);
    canvas.drawCircle(centre, outer - 1, ring);
    canvas.drawCircle(centre, inner, ring);

    for (var i = 0; i < 12; i++) {
      final angle = -math.pi / 2 + i * math.pi / 6;
      final spoke = angle + math.pi / 12;
      canvas.drawLine(
        centre + Offset(math.cos(spoke), math.sin(spoke)) * inner,
        centre + Offset(math.cos(spoke), math.sin(spoke)) * (outer - 1),
        ring,
      );

      final glyph = TextPainter(
        text: TextSpan(
          text: _glyphs[i],
          style: TextStyle(fontSize: size.width * 0.075, color: AppColors.goldDeep),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final at = centre + Offset(math.cos(angle), math.sin(angle)) * ((outer + inner) / 2);
      glyph.paint(canvas, at - Offset(glyph.width / 2, glyph.height / 2));
    }

    // Rays between the inner ring and the om.
    final ray = Paint()
      ..strokeWidth = 1
      ..color = AppColors.gold.withValues(alpha: 0.35);
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi / 12;
      canvas.drawLine(
        centre + Offset(math.cos(angle), math.sin(angle)) * (outer * 0.4),
        centre + Offset(math.cos(angle), math.sin(angle)) * (inner * (i.isEven ? 0.95 : 0.8)),
        ray,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) => false;
}

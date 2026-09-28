import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chat_palette.dart';

/// WhatsApp's beige ground with its faint doodles — here, the sky: stars, crescents, a ringed
/// planet, a scatter of dots.
///
/// Drawn, not an image: it tiles to any screen without a seam, costs no asset, and stays faint
/// enough ([ChatPalette.doodle]) that it is felt rather than read. Behind a [RepaintBoundary], so
/// scrolling the conversation never repaints it.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ChatPalette.wallpaper,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(child: CustomPaint(painter: _Doodles())),
          child,
        ],
      ),
    );
  }
}

class _Doodles extends CustomPainter {
  const _Doodles();

  /// One tile's worth; the pattern repeats every [_tile] points in both directions.
  static const _tile = 132.0;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = ChatPalette.doodle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = ChatPalette.doodle;

    for (var y = -_tile / 2; y < size.height + _tile; y += _tile) {
      for (var x = -_tile / 2; x < size.width + _tile; x += _tile) {
        // Every other row shifted half a tile, so the grid does not read as a grid.
        final row = ((y + _tile / 2) / _tile).round();
        final ox = x + (row.isOdd ? _tile / 2 : 0);
        _sparkle(canvas, Offset(ox + 22, y + 26), 7, stroke);
        _crescent(canvas, Offset(ox + 88, y + 30), 9, stroke);
        _planet(canvas, Offset(ox + 54, y + 84), 7, stroke);
        _sparkle(canvas, Offset(ox + 108, y + 98), 4.5, stroke);
        canvas.drawCircle(Offset(ox + 16, y + 102), 1.6, fill);
        canvas.drawCircle(Offset(ox + 70, y + 52), 1.3, fill);
        canvas.drawCircle(Offset(ox + 120, y + 64), 1.1, fill);
      }
    }
  }

  /// A four-pointed star.
  void _sparkle(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r);
    canvas.drawPath(path, paint);
  }

  void _crescent(Canvas canvas, Offset c, double r, Paint paint) {
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(rect, math.pi * 0.35, math.pi * 1.3, false, paint);
    canvas.drawArc(
      Rect.fromCircle(center: c.translate(r * 0.45, -r * 0.1), radius: r * 0.8),
      math.pi * 0.45,
      math.pi * 1.1,
      false,
      paint,
    );
  }

  void _planet(Canvas canvas, Offset c, double r, Paint paint) {
    canvas.drawCircle(c, r, paint);
    canvas.drawOval(Rect.fromCenter(center: c, width: r * 3.4, height: r * 1.1), paint);
  }

  @override
  bool shouldRepaint(_Doodles old) => false;
}

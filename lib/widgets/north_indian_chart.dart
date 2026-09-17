import 'package:flutter/material.dart';

import '../app/assets.dart';
import '../app/theme/app_colors.dart';
import '../data/models/kundali.dart';
import 'safe_asset.dart';

/// The North Indian kundali: a square, its two diagonals and the diamond through its midpoints,
/// which between them cut twelve houses.
///
/// The first house is the top diamond, and the houses count **anticlockwise** from it — the second
/// is the triangle to its upper left. The houses stay where they are; what moves from chart to
/// chart is which rashi each one holds, printed as its number (Mesha is 1). That is how every
/// printed kundali in North India reads, so it is how this one reads.
class NorthIndianChart extends StatelessWidget {
  const NorthIndianChart({super.key, required this.chart, this.maxSize = 340});

  final KundaliChart chart;
  final double maxSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = [constraints.maxWidth, maxSize].reduce((a, b) => a < b ? a : b);
        final houses = houseGeometry(side);
        final labelWidth = side * 0.2;

        return Semantics(
          label: _describe(),
          child: SizedBox.square(
            dimension: side,
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _ChartLines())),
                // The om at the centre, where the four inner houses meet.
                Center(
                  child: Container(
                    width: side * 0.16,
                    height: side * 0.16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.goldWash,
                      border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
                    ),
                    padding: EdgeInsets.all(side * 0.025),
                    child: SafeImage(
                      Brand.mark,
                      fit: BoxFit.contain,
                      fallback: Center(
                        child: Text('ॐ', style: TextStyle(fontSize: side * 0.06, color: AppColors.goldDeep)),
                      ),
                    ),
                  ),
                ),
                for (final house in chart.houses)
                  Positioned(
                    left: houses[house.house - 1].label.dx - labelWidth / 2,
                    top: houses[house.house - 1].label.dy - side * 0.07,
                    width: labelWidth,
                    height: side * 0.14,
                    child: _HouseLabel(
                      rashiNumber: house.rashiIndex + 1,
                      isLagna: house.house == 1,
                      planets: [
                        for (final key in house.occupants) ?chart.planet(key),
                      ],
                      scale: side / 340,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _describe() {
    final lines = <String>['Kundali chart. Lagna in ${chart.lagna.rashi}.'];
    for (final house in chart.houses) {
      if (house.occupants.isEmpty) continue;
      final names = [for (final key in house.occupants) chart.planet(key)?.english ?? key];
      lines.add('House ${house.house}, ${house.rashi}: ${names.join(', ')}.');
    }
    return lines.join(' ');
  }
}

/// One house's polygon and where its label sits.
@immutable
class HouseShape {
  const HouseShape({required this.house, required this.points, required this.label});

  final int house;
  final List<Offset> points;

  /// The centroid, nudged toward the open side of the narrow triangles so text has room.
  final Offset label;
}

/// The twelve houses of a North Indian chart [side] points square, house 1 first. Pure, so the
/// layout can be tested without pumping a widget.
List<HouseShape> houseGeometry(double side) {
  final s = side;
  final tl = Offset.zero;
  final tr = Offset(s, 0);
  final br = Offset(s, s);
  final bl = Offset(0, s);
  final t = Offset(s / 2, 0);
  final r = Offset(s, s / 2);
  final b = Offset(s / 2, s);
  final l = Offset(0, s / 2);
  final c = Offset(s / 2, s / 2);
  final p1 = Offset(s / 4, s / 4);
  final p2 = Offset(3 * s / 4, s / 4);
  final p3 = Offset(3 * s / 4, 3 * s / 4);
  final p4 = Offset(s / 4, 3 * s / 4);

  Offset centroid(List<Offset> points) {
    var x = 0.0;
    var y = 0.0;
    for (final p in points) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / points.length, y / points.length);
  }

  final polygons = <List<Offset>>[
    [t, p2, c, p1], // 1  top diamond
    [tl, t, p1], // 2  top-left
    [tl, p1, l], // 3  left-top
    [l, p1, c, p4], // 4  left diamond
    [l, p4, bl], // 5  left-bottom
    [bl, p4, b], // 6  bottom-left
    [b, p4, c, p3], // 7  bottom diamond
    [b, p3, br], // 8  bottom-right
    [br, p3, r], // 9  right-bottom
    [r, p3, c, p2], // 10 right diamond
    [r, p2, tr], // 11 right-top
    [tr, p2, t], // 12 top-right
  ];

  return [
    for (var i = 0; i < 12; i++)
      HouseShape(
        house: i + 1,
        points: polygons[i],
        // A diamond's centre is half-covered by the om in the inner corner, so its label rides a
        // little outward; a triangle's centroid is already clear.
        label: polygons[i].length == 4
            ? Offset.lerp(centroid(polygons[i]), polygons[i].first, 0.28)!
            : centroid(polygons[i]),
      ),
  ];
}

/// The colour each graha is printed in, from the design.
Color planetColor(String key) => switch (key) {
      'sun' => const Color(0xFFE8A317),
      'moon' => const Color(0xFF2F6FDB),
      'mars' => const Color(0xFFD7263D),
      'mercury' => const Color(0xFF1E8E3E),
      'jupiter' => const Color(0xFFE38B00),
      'venus' => const Color(0xFFD6336C),
      'saturn' => const Color(0xFF3355A5),
      'rahu' => const Color(0xFF7A3E12),
      'ketu' => const Color(0xFF8C6D1F),
      _ => AppColors.navy,
    };

class _HouseLabel extends StatelessWidget {
  const _HouseLabel({required this.rashiNumber, required this.isLagna, required this.planets, required this.scale});

  final int rashiNumber;
  final bool isLagna;
  final List<ChartPlanet> planets;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final small = TextStyle(fontSize: 10 * scale, fontWeight: FontWeight.w600, color: AppColors.navy, height: 1.1);
    final planet = TextStyle(fontSize: 12.5 * scale, fontWeight: FontWeight.w700, height: 1.1);

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 3 * scale,
            children: [
              for (final p in planets)
                Text(
                  p.showRetrograde ? '${p.abbr}℞' : p.abbr,
                  style: planet.copyWith(color: planetColor(p.key)),
                ),
            ],
          ),
          Text('$rashiNumber', style: small),
          if (isLagna) Text('Asc', style: small.copyWith(color: AppColors.goldDeep, fontSize: 11 * scale)),
        ],
      ),
    );
  }
}

class _ChartLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rect = Offset.zero & size;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(0.5), const Radius.circular(10)),
      Paint()..color = const Color(0xFFFFF8EA),
    );

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = AppColors.gold;

    canvas.drawRRect(RRect.fromRectAndRadius(rect.deflate(0.7), const Radius.circular(10)), line);
    canvas.drawLine(Offset.zero, Offset(s, s), line);
    canvas.drawLine(Offset(s, 0), Offset(0, s), line);
    canvas.drawPath(
      Path()
        ..moveTo(s / 2, 0)
        ..lineTo(s, s / 2)
        ..lineTo(s / 2, s)
        ..lineTo(0, s / 2)
        ..close(),
      line,
    );

    // A soft glow behind the centre, where the om sits.
    canvas.drawCircle(
      Offset(s / 2, s / 2),
      s * 0.16,
      Paint()
        ..shader = RadialGradient(
          colors: [AppColors.gold.withValues(alpha: 0.22), AppColors.gold.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: Offset(s / 2, s / 2), radius: s * 0.16)),
    );
  }

  @override
  bool shouldRepaint(covariant _ChartLines oldDelegate) => false;
}

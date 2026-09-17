import 'package:astrolok/app/theme/app_theme.dart';
import 'package:astrolok/data/fake/fake_kundali_chart.dart';
import 'package:astrolok/data/models/kundali.dart';
import 'package:astrolok/widgets/north_indian_chart.dart';
import 'package:astrolok/widgets/safe_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The chart diagram. Its geometry is fixed by the tradition — house 1 the top diamond, counting
/// anticlockwise — and a mistake there draws a plausible chart with every graha in the wrong house.
void main() {
  setUp(SafeSvg.resetProbeCache);

  bool inside(Offset p, List<Offset> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) && p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  test('twelve houses, each label inside its own house', () {
    final houses = houseGeometry(300);
    expect(houses.map((h) => h.house), [for (var i = 1; i <= 12; i++) i]);
    for (final h in houses) {
      expect(inside(h.label, h.points), isTrue, reason: 'house ${h.house} label at ${h.label}');
    }
  });

  test('house 1 is the top diamond and the houses run anticlockwise', () {
    final label = {for (final h in houseGeometry(300)) h.house: h.label};
    expect(label[1]!.dy, lessThan(150));
    expect((label[1]!.dx - 150).abs(), lessThan(1));
    // 2 and 3 upper left, 4 the left diamond, 7 the bottom diamond, 10 the right diamond.
    expect(label[2]!.dx, lessThan(150));
    expect(label[2]!.dy, lessThan(label[3]!.dy));
    expect(label[4]!.dx, lessThan(150));
    expect((label[4]!.dy - 150).abs(), lessThan(1));
    expect(label[7]!.dy, greaterThan(150));
    expect(label[10]!.dx, greaterThan(150));
    expect(label[12]!.dx, greaterThan(150));
    expect(label[12]!.dy, lessThan(label[11]!.dy));
  });

  testWidgets('every graha is drawn, with Asc in the first house and rashi numbers', (tester) async {
    final chart = KundaliChart.fromServer(fakeKundaliChart)!;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Center(child: SizedBox(width: 340, child: NorthIndianChart(chart: chart)))),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (final planet in chart.planets) {
      expect(find.textContaining(planet.abbr), findsWidgets, reason: planet.abbr);
    }
    expect(find.text('Asc'), findsOneWidget);
    // Vrishabha rising: the first house prints rashi 2.
    expect(find.text('${chart.houses.first.rashiIndex + 1}'), findsWidgets);
    expect(find.text('Ma℞'), findsOneWidget);
  });
}

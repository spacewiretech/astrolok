import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_text_raster.dart';
import 'reading_pdf.dart';

/// The downloadable kundali report.
///
/// Primitives only, for the same reason as [ReadingPdfRequest]: the composition runs under
/// `compute`, and nothing that reaches a background isolate may hold a model, a `Color` or an asset
/// path. The mapping from a [KundaliReading] lives in `kundali_pdf_requests.dart`.
///
/// Everything the model wrote goes through [KundaliPdfRequest.runs] with the size and width it is
/// set at, so a reading in Hindi or Tamil is drawn by Flutter's shaper and pasted in; the chart, the
/// tables and the headings are the app's own Latin text and stay real text.

class KundaliPdfPlanet {
  const KundaliPdfPlanet({
    required this.abbr,
    required this.english,
    required this.name,
    required this.sign,
    required this.rashi,
    required this.degree,
    required this.nakshatra,
    required this.pada,
    required this.house,
    required this.retrograde,
    required this.dignity,
    required this.colour,
    required this.line,
  });

  final String abbr;
  final String english;
  final String name;
  final String sign;
  final String rashi;
  final double degree;
  final String nakshatra;
  final int pada;
  final int house;
  final bool retrograde;
  final String dignity;
  final int colour;

  /// The model's one line about it.
  final String line;
}

class KundaliPdfHouse {
  const KundaliPdfHouse({
    required this.house,
    required this.rashiNumber,
    required this.sign,
    required this.lord,
    required this.occupants,
    required this.theme,
  });

  final int house;
  final int rashiNumber;
  final String sign;
  final String lord;

  /// Abbreviations, for the chart, with their colours.
  final List<(String, int)> occupants;
  final String theme;
}

class KundaliPdfInsight {
  const KundaliPdfInsight({required this.title, required this.summary, required this.detail, required this.tip});

  final String title;
  final String summary;
  final String detail;
  final String tip;
}

class KundaliPdfDasha {
  const KundaliPdfDasha({required this.label, required this.years, required this.current});

  final String label;
  final String years;
  final bool current;
}

class KundaliPdfRequest {
  const KundaliPdfRequest({
    required this.regular,
    required this.bold,
    required this.kundaliId,
    required this.title,
    required this.birthLine,
    required this.lagnaLine,
    required this.moonLine,
    required this.headline,
    required this.planets,
    required this.houses,
    required this.insights,
    required this.dasha,
    required this.dashaNow,
    required this.disclaimer,
    this.mark,
    this.invocation = '',
    this.dashaSummary = '',
    this.blessing = '',
    this.rasters = const {},
  });

  final Uint8List regular;
  final Uint8List bold;
  final Uint8List? mark;
  final String kundaliId;
  final String title;
  final String birthLine;
  final String lagnaLine;
  final String moonLine;
  final String invocation;
  final String headline;
  final List<KundaliPdfPlanet> planets;
  final List<KundaliPdfHouse> houses;
  final List<KundaliPdfInsight> insights;
  final List<KundaliPdfDasha> dasha;
  final String dashaNow;
  final String dashaSummary;
  final String blessing;
  final String disclaimer;
  final Map<String, PdfRaster> rasters;

  /// Named per kundali, so a re-cast does not overwrite the last export in someone's Files.
  String get fileName {
    final compact = kundaliId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return 'astrolok-kundali-${compact.length > 8 ? compact.substring(0, 8) : compact}.pdf';
  }

  /// Every run of the model's words, at the size and width the composition sets it.
  List<PdfTextRun> get runs => [
        PdfTextRun(title, size: 22, heavy: true, colour: 0xFF000C2B, height: 1.2),
        PdfTextRun(invocation, size: 11, colour: 0xFFE2A21D, height: 1.5),
        PdfTextRun(headline, size: 14, heavy: true, colour: 0xFF000C2B, height: 1.35),
        for (final p in planets) PdfTextRun(p.line, size: 9.5, width: pdfBulletWidth - 70),
        for (final i in insights) ...[
          PdfTextRun(i.summary, size: 10, colour: 0xFF6E7280),
          PdfTextRun(i.detail, size: 10),
          PdfTextRun(i.tip, size: 9.5, width: pdfContentWidth - 30),
        ],
        for (final h in houses) PdfTextRun(h.theme, size: 9.5, width: _themeWidth),
        PdfTextRun(dashaSummary, size: 10),
        PdfTextRun(blessing, size: 11.5, colour: 0xFFE2A21D, height: 1.5),
      ];

  KundaliPdfRequest rasterised(Map<String, PdfRaster> drawn) => KundaliPdfRequest(
        regular: regular,
        bold: bold,
        mark: mark,
        kundaliId: kundaliId,
        title: title,
        birthLine: birthLine,
        lagnaLine: lagnaLine,
        moonLine: moonLine,
        invocation: invocation,
        headline: headline,
        planets: planets,
        houses: houses,
        insights: insights,
        dasha: dasha,
        dashaNow: dashaNow,
        dashaSummary: dashaSummary,
        blessing: blessing,
        disclaimer: disclaimer,
        rasters: drawn,
      );
}

/// The houses table's theme column: the content width less the three fixed columns (164pt) and the
/// cell's own padding. The rasteriser lays text out to exactly this, so it cannot overflow the cell.
const _themeWidth = pdfContentWidth - 172;

const _navy = PdfColor.fromInt(0xFF000C2B);
const _gold = PdfColor.fromInt(0xFFF4B835);
const _goldDeep = PdfColor.fromInt(0xFFE2A21D);
const _body = PdfColor.fromInt(0xFF44506B);
const _muted = PdfColor.fromInt(0xFF6E7280);
const _rule = PdfColor.fromInt(0xFFE7E0D2);
const _cream = PdfColor.fromInt(0xFFFFF8EA);

/// The house labels' anchor points on a chart [s] points square, house 1 first. Mirrors
/// `houseGeometry` in `north_indian_chart.dart`, kept free of `dart:ui` for the isolate.
List<(double, double)> _houseAnchors(double s) {
  const polygons = [
    [(0.5, 0.0), (0.75, 0.25), (0.5, 0.5), (0.25, 0.25)],
    [(0.0, 0.0), (0.5, 0.0), (0.25, 0.25)],
    [(0.0, 0.0), (0.25, 0.25), (0.0, 0.5)],
    [(0.0, 0.5), (0.25, 0.25), (0.5, 0.5), (0.25, 0.75)],
    [(0.0, 0.5), (0.25, 0.75), (0.0, 1.0)],
    [(0.0, 1.0), (0.25, 0.75), (0.5, 1.0)],
    [(0.5, 1.0), (0.25, 0.75), (0.5, 0.5), (0.75, 0.75)],
    [(0.5, 1.0), (0.75, 0.75), (1.0, 1.0)],
    [(1.0, 1.0), (0.75, 0.75), (1.0, 0.5)],
    [(1.0, 0.5), (0.75, 0.75), (0.5, 0.5), (0.75, 0.25)],
    [(1.0, 0.5), (0.75, 0.25), (1.0, 0.0)],
    [(1.0, 0.0), (0.75, 0.25), (0.5, 0.0)],
  ];
  return [
    for (final polygon in polygons)
      () {
        var x = 0.0;
        var y = 0.0;
        for (final (px, py) in polygon) {
          x += px;
          y += py;
        }
        x /= polygon.length;
        y /= polygon.length;
        if (polygon.length == 4) {
          x += (polygon.first.$1 - x) * 0.28;
          y += (polygon.first.$2 - y) * 0.28;
        }
        return (x * s, y * s);
      }(),
  ];
}

Future<Uint8List> buildKundaliPdf(KundaliPdfRequest request) async {
  final regular = pw.Font.ttf(request.regular.buffer.asByteData());
  final bold = pw.Font.ttf(request.bold.buffer.asByteData());
  final document = pw.Document(title: 'Astrolok Kundali');

  pw.TextStyle style(double size, {PdfColor colour = _body, bool heavy = false, double spacing = 0, double height = 1.45}) =>
      pw.TextStyle(font: heavy ? bold : regular, fontSize: size, color: colour, letterSpacing: spacing, height: height);

  pw.Widget txt(String text, {required double size, PdfColor colour = _body, bool heavy = false, double height = 1.45, double width = pdfContentWidth}) {
    final raster = request.rasters[rasterKey(text, size: size, width: width)];
    if (raster != null) {
      return pw.Image(pw.MemoryImage(raster.png), width: raster.width, height: raster.height);
    }
    return pw.Text(text, style: style(size, colour: colour, heavy: heavy, height: height));
  }

  pw.Widget heading(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 8),
        child: pw.Text(text, style: style(14, colour: _navy, heavy: true)),
      );

  pw.Widget hairline() => pw.Container(height: 0.7, color: _rule, margin: const pw.EdgeInsets.symmetric(vertical: 10));

  const chartSide = 250.0;
  final anchors = _houseAnchors(chartSide);

  final chart = pw.Center(
    child: pw.SizedBox(
      width: chartSide,
      height: chartSide,
      child: pw.Stack(
        children: [
          pw.Positioned.fill(
            child: pw.CustomPaint(
              size: const PdfPoint(chartSide, chartSide),
              painter: (canvas, size) {
                // PDF space runs bottom-up; every y below is flipped.
                final s = size.x;
                canvas
                  ..setFillColor(_cream)
                  ..drawRect(0, 0, s, s)
                  ..fillPath()
                  ..setStrokeColor(_gold)
                  ..setLineWidth(1)
                  ..drawRect(0.5, 0.5, s - 1, s - 1)
                  ..moveTo(0, s)
                  ..lineTo(s, 0)
                  ..moveTo(s, s)
                  ..lineTo(0, 0)
                  ..moveTo(s / 2, s)
                  ..lineTo(s, s / 2)
                  ..lineTo(s / 2, 0)
                  ..lineTo(0, s / 2)
                  ..closePath()
                  ..strokePath();
              },
            ),
          ),
          for (final house in request.houses)
            pw.Positioned(
              left: anchors[house.house - 1].$1 - 26,
              top: anchors[house.house - 1].$2 - 16,
              child: pw.SizedBox(
                width: 52,
                height: 32,
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    if (house.occupants.isNotEmpty)
                      pw.Wrap(
                        alignment: pw.WrapAlignment.center,
                        spacing: 2,
                        children: [
                          for (final (abbr, colour) in house.occupants)
                            pw.Text(abbr, style: style(8, colour: PdfColor.fromInt(colour), heavy: true, height: 1.1)),
                        ],
                      ),
                    pw.Text('${house.rashiNumber}', style: style(7, colour: _navy, height: 1.1)),
                    if (house.house == 1) pw.Text('Asc', style: style(7, colour: _goldDeep, heavy: true, height: 1.1)),
                  ],
                ),
              ),
            ),
          if (request.mark != null)
            pw.Positioned(
              left: chartSide / 2 - 14,
              top: chartSide / 2 - 14,
              child: pw.Image(pw.MemoryImage(request.mark!), width: 28, height: 28),
            ),
        ],
      ),
    ),
  );

  pw.TableRow row(List<String> cells, {bool header = false, bool shade = false}) => pw.TableRow(
        decoration: pw.BoxDecoration(color: header ? _navy : (shade ? _cream : null)),
        children: [
          for (final cell in cells)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              child: pw.Text(cell, style: style(8.5, colour: header ? PdfColors.white : _body, heavy: header, height: 1.2)),
            ),
        ],
      );

  document.addPage(
    pw.MultiPage(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 40, 48, 46),
      header: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 18),
        padding: const pw.EdgeInsets.only(bottom: 10),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _rule))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(children: [
              if (request.mark != null) ...[
                pw.Image(pw.MemoryImage(request.mark!), width: 16, height: 16),
                pw.SizedBox(width: 7),
              ],
              pw.Text('Astrolok', style: style(14, colour: _navy, heavy: true)),
            ]),
            pw.Text('Kundali Report', style: style(10, colour: _muted)),
          ],
        ),
      ),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.center,
        margin: const pw.EdgeInsets.only(top: 14),
        child: pw.Text(
          '${request.disclaimer}   ·   ${context.pageNumber} of ${context.pagesCount}',
          style: style(8, colour: _muted, height: 1.3),
        ),
      ),
      build: (context) => [
        txt(request.title, size: 22, colour: _navy, heavy: true, height: 1.2),
        pw.SizedBox(height: 5),
        pw.Text(request.birthLine, style: style(9.5, colour: _muted)),
        pw.Text('${request.lagnaLine}   ·   ${request.moonLine}', style: style(9.5, colour: _muted)),
        if (request.invocation.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          txt(request.invocation, size: 11, colour: _goldDeep, height: 1.5),
        ],
        pw.SizedBox(height: 10),
        txt(request.headline, size: 14, colour: _navy, heavy: true, height: 1.35),
        pw.SizedBox(height: 16),
        chart,
        pw.SizedBox(height: 6),
        pw.Center(child: pw.Text('North Indian chart · sidereal (Lahiri) · whole-sign houses', style: style(8, colour: _muted))),

        heading('The nine grahas'),
        pw.Table(
          border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _rule, width: 0.5)),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.6),
            1: pw.FlexColumnWidth(1.9),
            2: pw.FlexColumnWidth(0.9),
            3: pw.FlexColumnWidth(2.2),
            4: pw.FlexColumnWidth(0.8),
            5: pw.FlexColumnWidth(1.4),
          },
          children: [
            row(['Graha', 'Sign', 'Degree', 'Nakshatra', 'House', 'Note'], header: true),
            for (var i = 0; i < request.planets.length; i++)
              row(
                [
                  '${request.planets[i].english} (${request.planets[i].name})',
                  '${request.planets[i].rashi} · ${request.planets[i].sign}',
                  '${request.planets[i].degree.toStringAsFixed(1)}°',
                  '${request.planets[i].nakshatra} ${request.planets[i].pada}',
                  '${request.planets[i].house}',
                  [
                    if (request.planets[i].retrograde) 'Retrograde',
                    if (request.planets[i].dignity.isNotEmpty) request.planets[i].dignity,
                  ].join(', '),
                ],
                shade: i.isOdd,
              ),
          ],
        ),
        pw.SizedBox(height: 12),
        for (final p in request.planets)
          if (p.line.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(width: 82, child: pw.Text(p.english, style: style(9.5, colour: PdfColor.fromInt(p.colour), heavy: true))),
                  pw.Expanded(child: txt(p.line, size: 9.5, width: pdfBulletWidth - 70)),
                ],
              ),
            ),

        heading('Key life insights'),
        for (final insight in request.insights) ...[
          pw.Text(insight.title, style: style(12, colour: _navy, heavy: true)),
          pw.SizedBox(height: 3),
          if (insight.summary.isNotEmpty) txt(insight.summary, size: 10, colour: _muted),
          pw.SizedBox(height: 4),
          txt(insight.detail, size: 10),
          if (insight.tip.isNotEmpty) ...[
            pw.SizedBox(height: 5),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(width: 30, child: pw.Text('Tip.', style: style(9.5, colour: _goldDeep, heavy: true))),
                pw.Expanded(child: txt(insight.tip, size: 9.5, width: pdfContentWidth - 30)),
              ],
            ),
          ],
          hairline(),
        ],

        heading('Vimshottari dasha'),
        pw.Text(request.dashaNow, style: style(10, colour: _navy, heavy: true)),
        pw.SizedBox(height: 6),
        if (request.dashaSummary.isNotEmpty) ...[txt(request.dashaSummary, size: 10), pw.SizedBox(height: 8)],
        pw.Table(
          border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _rule, width: 0.5)),
          children: [
            row(['Mahadasha', 'Years'], header: true),
            for (final d in request.dasha) row(['${d.label}${d.current ? '   (now)' : ''}', d.years], shade: d.current),
          ],
        ),

        heading('The twelve houses'),
        pw.Table(
          border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _rule, width: 0.5)),
          columnWidths: const {0: pw.FixedColumnWidth(36), 1: pw.FixedColumnWidth(70), 2: pw.FixedColumnWidth(58), 3: pw.FlexColumnWidth()},
          children: [
            row(['House', 'Sign', 'Lord', 'Theme'], header: true),
            for (final h in request.houses)
              pw.TableRow(
                decoration: pw.BoxDecoration(color: h.house.isEven ? _cream : null),
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${h.house}', style: style(8.5, height: 1.2))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(h.sign, style: style(8.5, height: 1.2))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(h.lord, style: style(8.5, height: 1.2))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: txt(h.theme, size: 9.5, width: _themeWidth)),
                ],
              ),
          ],
        ),

        if (request.blessing.isNotEmpty) ...[
          pw.SizedBox(height: 18),
          pw.Text('A blessing for you', style: style(8, colour: _muted, heavy: true, spacing: 0.8)),
          pw.SizedBox(height: 6),
          txt(request.blessing, size: 11.5, colour: _goldDeep, height: 1.5),
        ],
      ],
    ),
  );

  return document.save();
}

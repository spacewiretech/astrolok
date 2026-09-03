import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/palm_reading.dart';
import 'palm_copy.dart';

/// Everything [buildPalmPdf] needs, gathered on the UI isolate before the work moves off it.
///
/// The fonts arrive as bytes rather than being loaded inside: `rootBundle` is not available on
/// a background isolate, and the export runs on one.
class PalmPdfRequest {
  const PalmPdfRequest({
    required this.reading,
    required this.regular,
    required this.bold,
    this.handImage,
    this.name,
  });

  final PalmReading reading;

  /// TTF bytes. The `pdf` package's built-in Helvetica has no glyph for ₹ or ॐ and renders
  /// them as blanks with no warning, so the document carries its own faces.
  final Uint8List regular;
  final Uint8List bold;

  /// Null after a reinstall, or on a device that never took the photo. The document is laid
  /// out without it rather than leaving a gap.
  final Uint8List? handImage;

  final String? name;
}

/// Composes the reading as a PDF.
///
/// A pure function taking bytes and returning bytes — no BuildContext, no plugin calls — so it
/// runs under `compute()` and inside a test without a device.
Future<Uint8List> buildPalmPdf(PalmPdfRequest request) async {
  final reading = request.reading;
  final regular = pw.Font.ttf(request.regular.buffer.asByteData());
  final bold = pw.Font.ttf(request.bold.buffer.asByteData());

  const navy = PdfColor.fromInt(0xFF000C2B);
  const gold = PdfColor.fromInt(0xFFF4B835);
  const body = PdfColor.fromInt(0xFF44506B);
  const muted = PdfColor.fromInt(0xFF6E7280);
  const border = PdfColor.fromInt(0xFFF1EBE0);

  final theme = pw.ThemeData.withFont(base: regular, bold: bold);
  final document = pw.Document(title: 'Astrolok Palm Reading');

  pw.Widget heading(String text, {double size = 13, PdfColor colour = navy}) =>
      pw.Text(
        text,
        style: pw.TextStyle(font: bold, fontSize: size, color: colour),
      );

  document.addPage(
    pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 44),
      header: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 18),
        padding: const pw.EdgeInsets.only(bottom: 10),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: border)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Astrolok',
              style: pw.TextStyle(font: bold, fontSize: 15, color: navy),
            ),
            pw.Text(
              'Palm Reading',
              style: pw.TextStyle(font: regular, fontSize: 11, color: muted),
            ),
          ],
        ),
      ),
      // On every page, not just the last: a PDF gets forwarded, and each page has to carry
      // its own framing rather than relying on the reader having seen page one.
      footer: (context) => pw.Container(
        alignment: pw.Alignment.center,
        margin: const pw.EdgeInsets.only(top: 12),
        child: pw.Text(
          '${PalmCopy.disclaimer}   ·   ${context.pageNumber} of ${context.pagesCount}',
          style: pw.TextStyle(font: regular, fontSize: 8, color: muted),
        ),
      ),
      build: (context) => [
        pw.Text(
          request.name == null || request.name!.isEmpty
              ? 'Your Palm Reading'
              : 'Palm Reading for ${request.name}',
          style: pw.TextStyle(font: bold, fontSize: 24, color: navy),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '${_formatDate(reading.createdAt)}   ·   ${reading.focus.label}',
          style: pw.TextStyle(font: regular, fontSize: 10, color: muted),
        ),

        if (reading.headline.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Text(
            reading.headline,
            style: pw.TextStyle(font: bold, fontSize: 13, color: gold),
          ),
        ],

        pw.SizedBox(height: 18),

        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (request.handImage != null) ...[
              pw.ClipRRect(
                horizontalRadius: 8,
                verticalRadius: 8,
                child: pw.Image(
                  pw.MemoryImage(request.handImage!),
                  width: 150,
                  height: 150,
                  fit: pw.BoxFit.cover,
                ),
              ),
              pw.SizedBox(width: 16),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (!reading.strongestTrait.isEmpty) ...[
                    heading(PalmCopy.strongestTrait, size: 10, colour: muted),
                    pw.SizedBox(height: 4),
                    heading(reading.strongestTrait.title, size: 15),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      reading.strongestTrait.detail,
                      style: pw.TextStyle(font: regular, fontSize: 10, color: body),
                    ),
                  ],
                  if (reading.hand.chips.isNotEmpty) ...[
                    pw.SizedBox(height: 10),
                    pw.Text(
                      reading.hand.chips.join('  ·  '),
                      style: pw.TextStyle(font: regular, fontSize: 9, color: muted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 24),
        heading(PalmCopy.linesHeading, size: 16),
        pw.SizedBox(height: 6),

        for (final line in reading.lines)
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 14),
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: border),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    heading(line.title, size: 13),
                    pw.SizedBox(width: 8),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromInt(line.status.color.toARGB32())
                            .shade(0.9),
                        borderRadius: pw.BorderRadius.circular(999),
                      ),
                      child: pw.Text(
                        line.status.label,
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 8,
                          color: PdfColor.fromInt(line.status.color.toARGB32()),
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  line.detail,
                  style: pw.TextStyle(font: regular, fontSize: 10, color: body),
                ),
                if (line.meaning.isNotEmpty) ...[
                  pw.SizedBox(height: 8),
                  for (final bullet in line.meaning)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 3),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            '·  ',
                            style: pw.TextStyle(font: regular, fontSize: 10, color: muted),
                          ),
                          pw.Expanded(
                            child: pw.Text(
                              bullet,
                              style: pw.TextStyle(
                                font: regular,
                                fontSize: 10,
                                color: body,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (line.tip.isNotEmpty) ...[
                  pw.SizedBox(height: 8),
                  pw.Text(
                    '${PalmCopy.tip}: ${line.tip}',
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: 9,
                      color: gold,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    ),
  );

  return document.save();
}

String _formatDate(DateTime date) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The reading, composed as a PDF. Shared by palm and face.
///
/// ## Why this is a flat document rather than a set of cards
///
/// The first version drew each section as a bordered `pw.Container`. A `Container` is not a
/// splittable widget, so `MultiPage` can only ever move a whole one to the next page — with
/// eight sections that left a ragged white gutter at the foot of most pages, and a section that
/// grew past the printable height threw outright. Here almost every piece of a section is its
/// own top-level child of `build`, so a page break falls *between two paragraphs of the same
/// section* and the document simply flows.
///
/// There is exactly one bound group, [sectionOpening], which keeps a heading with its first
/// paragraph so it cannot strand at the foot of a page. It is safe to bind because it is
/// bounded — the server clamps those fields — and it is the only thing in the document that is
/// taller than a paragraph. Adding a second such group means doing that arithmetic again.
///
/// A few smaller rules follow from the same wish for a document that is plain and cannot break:
///
///  * **No `PdfColor.shade()`.** In pdf 3.13.0 `shade(s)` is `lightness * (1.5 - s)`, so the
///    `shade(0.9)` that was meant to make a pale chip wash actually multiplied lightness by 0.6
///    and produced a dark fill under near-identical dark text. Status is set as letter-spaced
///    caps in the accent colour instead: no fill to get wrong, and it prints better.
///  * **No `FontStyle.italic`.** Only Poppins Regular and SemiBold are bundled, so asking for an
///    italic face got a synthetic fallback that did not match the rest of the page.
///  * **Any script, but not by this engine.** Readings are written in the user's language now,
///    and `pdf` cannot set an Indic one: it maps codepoints straight to glyphs and ships a
///    shaper for Arabic alone, so Devanagari loses its conjuncts and hangs its matras in the
///    wrong place. Anything above U+0589 is therefore laid out by Flutter, which has a real
///    shaper, and pasted in as a picture — see `pdf_text_raster.dart` and
///    [ReadingPdfRequest.rasters]. Latin readings are untouched by all of it and stay real,
///    selectable text.
///  * **Colours arrive as ints, not `Color`.** Along with every other field being a primitive,
///    that keeps [ReadingPdfRequest] trivially sendable to a background isolate, which is what
///    finally lets [buildReadingPdf] run under `compute()` rather than hitching the UI thread.

/// One block of text, already laid out and drawn by Flutter.
///
/// [width] and [height] are in PDF points, so the image drops into the layout occupying exactly
/// the space the text would have. The bytes are a PNG with a transparent ground, rendered at
/// [rasterScale] times this size so it stays sharp in print.
class PdfRaster {
  const PdfRaster({required this.png, required this.width, required this.height});

  final Uint8List png;
  final double width;
  final double height;
}

/// How many device pixels are drawn per PDF point. 3 is about 216 DPI — sharp on paper, and a
/// third of the bytes of the 6 that would match a retina screen.
const rasterScale = 3.0;

/// A4 less the 48pt side margins below. The one number both the rasteriser and the composition
/// have to agree on: text is laid out to this width on one side and drawn at it on the other, so
/// a disagreement is a line break in a different place.
const pdfContentWidth = 595.28 - 96;

/// A bullet's text column: the content width less the dot, its margin and the row's indent.
const pdfBulletWidth = pdfContentWidth - 12;

/// Where a rasterised block is found in [ReadingPdfRequest.rasters].
///
/// Keyed on the three things that decide the pixels — the words, the size they are set at and
/// the column they are wrapped to. Computed by this one function on both sides of the isolate,
/// so the composition cannot look up a key the rasteriser never wrote.
String rasterKey(String text, {required double size, required double width}) =>
    '${size.toStringAsFixed(1)}|${width.round()}|$text';

/// One section of the reading — a palm line, or a feature of a face.
class ReadingPdfSection {
  const ReadingPdfSection({
    required this.title,
    required this.statusLabel,
    required this.statusColor,
    this.sanskrit = '',
    this.summary = '',
    this.detail = '',
    this.meaning = const [],
    this.tip = '',
    this.blessing = '',
  });

  final String title;

  /// The tradition's name, transliterated. Set beside the title in the accent colour.
  final String sanskrit;

  final String statusLabel;

  /// ARGB, not a `Color`: see the note on isolates above.
  final int statusColor;

  final String summary;
  final String detail;
  final List<String> meaning;
  final String tip;
  final String blessing;
}

/// Everything [buildReadingPdf] needs, gathered on the UI isolate before the work moves off it.
class ReadingPdfRequest {
  const ReadingPdfRequest({
    required this.documentTitle,
    required this.createdAt,
    required this.focusLabel,
    required this.sectionsHeading,
    required this.heroKicker,
    required this.disclaimer,
    required this.regular,
    required this.bold,
    this.name,
    this.invocation = '',
    this.headline = '',
    this.blessing = '',
    this.heroTitle = '',
    this.heroSummary = '',
    this.heroDetail = '',
    this.chips = const [],
    this.observations = const [],
    this.sections = const [],
    this.image,
    this.mark,
    this.rasters = const {},
  });

  /// "Palm Reading" or "Face Reading". Used in the header, the title and the filename.
  final String documentTitle;

  final DateTime createdAt;
  final String focusLabel;

  /// "Your Palm lines" / "Your Face Reveals".
  final String sectionsHeading;

  /// "Your Strongest Trait" / "Your core Trait".
  final String heroKicker;

  final String disclaimer;

  /// TTF bytes. The `pdf` package's built-in Helvetica has no glyph for ₹ and renders it as a
  /// blank with no warning, so the document carries its own faces.
  ///
  /// They arrive as bytes rather than being loaded inside: `rootBundle` is not available on a
  /// background isolate, and the composition runs on one.
  final Uint8List regular;
  final Uint8List bold;

  final String? name;
  final String invocation;
  final String headline;
  final String blessing;

  final String heroTitle;
  final String heroSummary;
  final String heroDetail;

  /// The short observation chips — "Soft hands", "Calm expression".
  final List<String> chips;

  /// The two to four grounding sentences. Present in the export because they are the evidence
  /// the whole reading is written against, and a document that omits them reads as generic.
  final List<String> observations;

  final List<ReadingPdfSection> sections;

  /// Null after a reinstall, or on a device that never took the photo. The document is laid out
  /// without it rather than leaving a gap.
  final Uint8List? image;

  /// The oṃ mark, drawn beside the wordmark in the header. Optional for the same reason.
  final Uint8List? mark;

  /// Pictures of the text, for readings the PDF engine cannot set correctly.
  ///
  /// Empty for every Latin-script reading, which is the common case and still goes through the
  /// real text path — selectable, searchable and a few kilobytes. It fills only when the reading
  /// is in a script the engine cannot shape: `pdf` maps characters to glyphs through the font's
  /// cmap and ships a bespoke shaper for Arabic and nothing else, so Devanagari comes out with
  /// its matras beside the consonants instead of around them and no conjuncts at all.
  ///
  /// Flutter has a real shaper, so the fix is to let it lay the text out and paste the result in.
  /// See `pdf_text_raster.dart`, which fills this on the UI isolate before the composition moves
  /// off it — the same reason the fonts arrive here as bytes.
  final Map<String, PdfRaster> rasters;

  /// The same request with [rasters] filled in.
  ///
  /// Written out field by field rather than through a general `copyWith` so that adding a field
  /// to this class and forgetting it here is a compile error rather than a silently empty export.
  ReadingPdfRequest rasterised(Map<String, PdfRaster> rasters) => ReadingPdfRequest(
        documentTitle: documentTitle,
        createdAt: createdAt,
        focusLabel: focusLabel,
        sectionsHeading: sectionsHeading,
        heroKicker: heroKicker,
        disclaimer: disclaimer,
        regular: regular,
        bold: bold,
        name: name,
        invocation: invocation,
        headline: headline,
        blessing: blessing,
        heroTitle: heroTitle,
        heroSummary: heroSummary,
        heroDetail: heroDetail,
        chips: chips,
        observations: observations,
        sections: sections,
        image: image,
        mark: mark,
        rasters: rasters,
      );

  /// A stable, readable filename. Distinct per reading so two exports cannot collide in the
  /// temp directory, which the old fixed name did every time.
  String fileName(String id) {
    final kind = documentTitle.toLowerCase().replaceAll(' ', '-');
    final short = id.replaceAll('-', '');
    return 'astrolok-$kind-${short.substring(0, short.length < 8 ? short.length : 8)}.pdf';
  }
}

const _navy = PdfColor.fromInt(0xFF000C2B);
const _gold = PdfColor.fromInt(0xFFF4B835);
const _body = PdfColor.fromInt(0xFF44506B);
const _muted = PdfColor.fromInt(0xFF6E7280);
const _rule = PdfColor.fromInt(0xFFE7E0D2);

/// Composes the reading as a PDF.
///
/// A pure function taking bytes and returning bytes — no BuildContext, no plugin calls — so it
/// runs under `compute()` and inside a test without a device.
Future<Uint8List> buildReadingPdf(ReadingPdfRequest request) async {
  final regular = pw.Font.ttf(request.regular.buffer.asByteData());
  final bold = pw.Font.ttf(request.bold.buffer.asByteData());

  final theme = pw.ThemeData.withFont(base: regular, bold: bold);
  final document = pw.Document(title: 'Astrolok ${request.documentTitle}');

  pw.TextStyle style(
    double size, {
    PdfColor colour = _body,
    bool heavy = false,
    double spacing = 0,
    double height = 1.45,
  }) =>
      pw.TextStyle(
        font: heavy ? bold : regular,
        fontSize: size,
        color: colour,
        letterSpacing: spacing,
        height: height,
      );

  /// The drawn version of a block, when the reading is in a script this engine cannot set.
  ///
  /// Null for every Latin reading, and for anything the rasteriser skipped — so a miss here is
  /// always a fallback to real text rather than a gap. See `pdf_text_raster.dart`.
  pw.Widget? drawn(String text, double size, double width) {
    final raster = request.rasters[rasterKey(text, size: size, width: width)];
    if (raster == null) return null;
    return pw.Image(
      pw.MemoryImage(raster.png),
      width: raster.width,
      height: raster.height,
    );
  }

  /// A run of the model's words: the picture of it if one was drawn, otherwise real text.
  pw.Widget txt(
    String text, {
    required double size,
    PdfColor colour = _body,
    bool heavy = false,
    double spacing = 0,
    double height = 1.45,
    double width = pdfContentWidth,
  }) =>
      drawn(text, size, width) ??
      pw.Text(
        text,
        style: style(size, colour: colour, heavy: heavy, spacing: spacing, height: height),
      );

  /// A paragraph, with the space below it built in. Its own child of `build`, never nested, so
  /// a page break can fall before or after it.
  pw.Widget para(String text, {double size = 10, PdfColor colour = _body, double gap = 8}) =>
      pw.Padding(
        padding: pw.EdgeInsets.only(bottom: gap),
        child: txt(text, size: size, colour: colour),
      );

  pw.Widget bullet(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4, left: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 3,
              height: 3,
              margin: const pw.EdgeInsets.only(top: 5, right: 7),
              decoration: const pw.BoxDecoration(color: _gold, shape: pw.BoxShape.circle),
            ),
            pw.Expanded(child: txt(text, size: 10, width: pdfBulletWidth)),
          ],
        ),
      );

  /// The section's title line: name, traditional term, and the status as caps in its own colour.
  ///
  /// `Expanded` around the title is what stops a long one running into the status — the old
  /// version had a bare `Row` and relied on the server's 40-character clamp to save it.
  pw.Widget sectionTitle(ReadingPdfSection section) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            // The title and its Sanskrit name are one drawn line when the reading is shaped,
            // because they wrap together; the status beside them is a closed English vocabulary
            // and stays real text either way.
            child: drawn(section.title, 13, pdfContentWidth) ??
                pw.RichText(
                  text: pw.TextSpan(
                    children: [
                      pw.TextSpan(
                        text: section.title,
                        style: style(13, colour: _navy, heavy: true, height: 1.2),
                      ),
                      if (section.sanskrit.isNotEmpty)
                        pw.TextSpan(
                          text: '   ${section.sanskrit}',
                          style: style(9, colour: _gold, height: 1.2),
                        ),
                    ],
                  ),
                ),
          ),
          pw.SizedBox(width: 10),
          pw.Text(
            section.statusLabel.toUpperCase(),
            style: style(
              8,
              colour: PdfColor.fromInt(section.statusColor),
              heavy: true,
              spacing: 0.8,
              height: 1.2,
            ),
          ),
        ],
      );

  /// The title, the summary and the opening paragraph, bound into one child.
  ///
  /// The only deliberately unsplittable block in the document, and it is a narrow exception to
  /// the flat rule above. Without it a heading strands at the foot of a page with its paragraph
  /// overleaf, which is the one thing left that read as a layout bug rather than as flow.
  ///
  /// It is safe to bind precisely because it is bounded: the server clamps a summary to 120
  /// characters and a detail to 900, so the very worst case is about twenty lines — roughly a
  /// third of a page. The bullets, tip and blessing stay separate children, so the break falls
  /// after this block rather than before it.
  pw.Widget sectionOpening(ReadingPdfSection section) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          sectionTitle(section),
          if (section.summary.isNotEmpty) ...[
            pw.SizedBox(height: 5),
            txt(section.summary, size: 10, colour: _muted),
          ],
          if (section.detail.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            txt(section.detail, size: 10),
          ],
          pw.SizedBox(height: 8),
        ],
      );

  pw.Widget hairline({double top = 0, double bottom = 10}) => pw.Container(
        height: 0.7,
        color: _rule,
        margin: pw.EdgeInsets.only(top: top, bottom: bottom),
      );

  final title = request.name == null || request.name!.isEmpty
      ? 'Your ${request.documentTitle}'
      : '${request.documentTitle} for ${request.name}';

  document.addPage(
    pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 40, 48, 46),
      header: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 20),
        padding: const pw.EdgeInsets.only(bottom: 10),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _rule)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Row(
              children: [
                if (request.mark != null) ...[
                  pw.Image(pw.MemoryImage(request.mark!), width: 16, height: 16),
                  pw.SizedBox(width: 7),
                ],
                pw.Text('Astrolok', style: style(14, colour: _navy, heavy: true)),
              ],
            ),
            pw.Text(request.documentTitle, style: style(10, colour: _muted)),
          ],
        ),
      ),
      // On every page, not just the last: a PDF gets forwarded, and each page has to carry
      // its own framing rather than relying on the reader having seen page one.
      footer: (context) => pw.Container(
        alignment: pw.Alignment.center,
        margin: const pw.EdgeInsets.only(top: 14),
        child: pw.Text(
          '${request.disclaimer}   ·   ${context.pageNumber} of ${context.pagesCount}',
          textAlign: pw.TextAlign.center,
          style: style(8, colour: _muted, height: 1.3),
        ),
      ),
      build: (context) => [
        txt(title, size: 23, colour: _navy, heavy: true, height: 1.2),
        pw.SizedBox(height: 5),
        pw.Text(
          '${_formatDate(request.createdAt)}   ·   ${request.focusLabel}',
          style: style(9.5, colour: _muted),
        ),

        if (request.invocation.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          txt(request.invocation, size: 11, colour: _gold, height: 1.5),
        ],

        // Centred and alone rather than inside a Row beside the trait. The Row was the other
        // place this document could not break: an image of fixed height next to a column of
        // unpredictable height is a child that has to fit on one page or fail.
        if (request.image != null) ...[
          pw.SizedBox(height: 18),
          pw.Center(
            child: pw.ClipRRect(
              horizontalRadius: 10,
              verticalRadius: 10,
              child: pw.Image(
                pw.MemoryImage(request.image!),
                width: 150,
                height: 150,
                fit: pw.BoxFit.cover,
              ),
            ),
          ),
        ],

        if (request.headline.isNotEmpty) ...[
          pw.SizedBox(height: 18),
          txt(request.headline, size: 14, colour: _navy, heavy: true, height: 1.35),
        ],

        if (request.heroTitle.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          txt(
            request.heroKicker.toUpperCase(),
            size: 8,
            colour: _muted,
            heavy: true,
            spacing: 0.8,
          ),
          pw.SizedBox(height: 4),
          txt(request.heroTitle, size: 15, colour: _navy, heavy: true),
          pw.SizedBox(height: 6),
          if (request.heroSummary.isNotEmpty) para(request.heroSummary, gap: 4),
          if (request.heroDetail.isNotEmpty) para(request.heroDetail),
        ],

        if (request.chips.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          txt(request.chips.join('   ·   '), size: 9, colour: _muted),
        ],

        if (request.observations.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Text(
            'What we could see',
            style: style(8, colour: _muted, heavy: true, spacing: 0.8),
          ),
          pw.SizedBox(height: 6),
          for (final observation in request.observations) bullet(observation),
        ],

        if (request.sections.isNotEmpty) ...[
          pw.SizedBox(height: 26),
          txt(request.sectionsHeading, size: 16, colour: _navy, heavy: true),
          hairline(top: 8, bottom: 16),
        ],

        // Flat, deliberately. Each of these is a separate child of `build`, so the page break
        // lands between two of them rather than pushing a whole section to the next page.
        for (final section in request.sections) ...[
          sectionOpening(section),
          for (final line in section.meaning) bullet(line),
          if (section.tip.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            // Drawn as one picture when shaped: "Tip." and the tip share a line and wrap
            // together, so they cannot be two separate images.
            drawn(section.tip, 9.5, pdfContentWidth) ??
                pw.RichText(
                  text: pw.TextSpan(
                    children: [
                      pw.TextSpan(
                        text: 'Tip.  ',
                        style: style(9.5, colour: _gold, heavy: true),
                      ),
                      pw.TextSpan(text: section.tip, style: style(9.5, colour: _body)),
                    ],
                  ),
                ),
          ],
          if (section.blessing.isNotEmpty) ...[
            pw.SizedBox(height: 5),
            txt(section.blessing, size: 9.5, colour: _gold),
          ],
          hairline(top: 14, bottom: 14),
        ],

        if (request.blessing.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            'A blessing for you',
            style: style(8, colour: _muted, heavy: true, spacing: 0.8),
          ),
          pw.SizedBox(height: 6),
          txt(request.blessing, size: 11.5, colour: _gold, height: 1.5),
        ],
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

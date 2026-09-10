import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

import 'reading_pdf.dart';

/// Draws a reading's text with Flutter, so the PDF can paste in what it cannot set itself.
///
/// ## Why this exists
///
/// The `pdf` package turns characters into glyphs through the font's `cmap` and positions them
/// left to right. That is all a Latin script needs. An Indic one needs *shaping*: `कि` is stored
/// as क then ि but drawn with the matra first, and `क्ष` is three codepoints that become one
/// glyph. The package ships a bespoke shaper for Arabic and nothing else, so Hindi comes out
/// with its vowel signs stranded and its conjuncts unformed — legible, and visibly wrong.
///
/// Flutter has a real shaper already, because it draws the reading on screen correctly. So the
/// text is laid out and painted here, and the PDF places the picture where the words would have
/// gone. It costs selectable text in the export, which is why it is used only where it is needed.
///
/// ## Where it runs
///
/// The UI isolate, always. `ui.PictureRecorder` and `Picture.toImage` need the engine, which a
/// `compute()` isolate does not have — the same constraint that already makes the caller load
/// fonts before handing the request over.

/// Whether [text] contains anything the PDF's own text path would set wrongly.
///
/// Not simply "anything non-ASCII". The document is *already* full of characters above the Latin
/// block and has to stay that way: the em dashes and curly quotes the readings are written with
/// are the whole reason the bundled Poppins is there instead of the built-in Helvetica, and
/// `pdf` sets them correctly. Treating those as needing a picture would rasterise every English
/// reading in the app.
///
/// What actually breaks is the scripts that need *shaping* or reordering — the Indic block and
/// its neighbours, Arabic, Hebrew, the South-East Asian scripts, and anything with no glyph in
/// the font at all. Those are enumerated below; everything else is left as real text.
///
/// Deliberately a property of the *text* rather than of the user's language setting: a reading is
/// exported long after it was written, the setting may have changed since, and what matters is
/// what is actually on the page.
bool needsShaping(String text) {
  for (final rune in text.runes) {
    // Latin and its accents, Greek, Cyrillic — simple scripts the engine sets left to right.
    if (rune < 0x0590) continue;

    // General punctuation through the symbol blocks: dashes, quotes, the rupee sign, arrows.
    // Poppins carries these and they need no shaping.
    if (rune >= 0x2000 && rune <= 0x2BFF) continue;

    return true;
  }
  return false;
}

/// True when any of the reading's own words need shaping.
///
/// Checked across the whole document rather than per block: a reading with a Hindi body and one
/// Latin heading should not have that heading set in a subtly different face from the rest.
bool readingNeedsShaping(ReadingPdfRequest request) =>
    _blocksOf(request).any((block) => needsShaping(block.text));

/// The reading's text, drawn.
///
/// Returns an empty map when nothing needs shaping, which leaves the export exactly as it was:
/// real text, a few kilobytes, selectable. Call it on the UI isolate and pass the result to
/// [ReadingPdfRequest.rasterised] before handing the request to `compute`.
Future<Map<String, PdfRaster>> rasteriseReading(ReadingPdfRequest request) async {
  if (!readingNeedsShaping(request)) return const {};

  final rasters = <String, PdfRaster>{};

  for (final block in _blocksOf(request)) {
    if (block.text.trim().isEmpty) continue;

    final key = rasterKey(block.text, size: block.size, width: block.width);
    if (rasters.containsKey(key)) continue;

    try {
      rasters[key] = await _draw(block);
    } catch (error) {
      // One block that would not draw must not cost the user the whole export. The composition
      // falls back to `pw.Text` for anything missing from the map, which for a shaped script is
      // wrong but present — better than a share sheet that never opens.
      debugPrint('[pdf] could not rasterise a block: $error');
    }
  }

  return rasters;
}

/// Lays [block] out at [rasterScale] and paints it onto a transparent PNG.
Future<PdfRaster> _draw(_Block block) async {
  final painter = TextPainter(
    text: TextSpan(
      children: [
        if (block.prefix != null)
          TextSpan(text: block.prefix!.text, style: _style(block.prefix!)),
        TextSpan(text: block.text, style: _style(block)),
        if (block.suffix != null)
          TextSpan(text: block.suffix!.text, style: _style(block.suffix!)),
      ],
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: block.width * rasterScale);

  // Ceil, or the last row of anti-aliased pixels is clipped off the descenders.
  final width = painter.width.ceil();
  final height = painter.height.ceil();

  final recorder = ui.PictureRecorder();
  painter.paint(ui.Canvas(recorder), Offset.zero);

  final image = await recorder.endRecording().toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('the block encoded to nothing');

    return PdfRaster(
      png: data.buffer.asUint8List(),
      width: width / rasterScale,
      height: height / rasterScale,
    );
  } finally {
    image.dispose();
  }
}

/// Poppins, the face the rest of the document is set in.
///
/// Google Fonts' Poppins carries Devanagari, so Hindi matches the Latin text around it. For a
/// script it does not carry — Tamil, say — Flutter falls back per glyph to whatever the device
/// has, which is the whole reason this approach handles languages nobody has added yet.
TextStyle _style(_Styled styled) => GoogleFonts.poppins(
      fontSize: styled.size * rasterScale,
      height: styled.height,
      letterSpacing: styled.spacing * rasterScale,
      fontWeight: styled.heavy ? FontWeight.w600 : FontWeight.w400,
      color: Color(styled.colour),
    );

/// The style half of a block, shared with the optional [_Block.prefix] run.
class _Styled {
  const _Styled({
    required this.text,
    required this.size,
    required this.colour,
    this.heavy = false,
    this.height = 1.45,
    this.spacing = 0,
  });

  final String text;
  final double size;

  /// ARGB, matching how `ReadingPdfSection.statusColor` already travels.
  final int colour;

  final bool heavy;
  final double height;
  final double spacing;
}

/// One drawable run, optionally preceded by a differently styled one on the same line.
class _Block extends _Styled {
  const _Block({
    required super.text,
    required super.size,
    required super.colour,
    required this.width,
    super.heavy,
    super.height,
    super.spacing,
    this.prefix,
    this.suffix,
  });

  final double width;

  /// Runs set before and after [text] on the same line — "Tip." ahead of a tip, a Sanskrit name
  /// behind a section title. Drawn into the same picture because they share a line and have to
  /// wrap as one. [text] itself is always the run the block is keyed on, so it must never be the
  /// empty one: a section with no Sanskrit name still has a title to draw.
  final _Styled? prefix;
  final _Styled? suffix;
}

// The colours the composition uses, repeated here because `PdfColor` belongs to the pdf package
// and this file draws with Flutter. Kept in the same order as the constants in `reading_pdf.dart`
// so the two are easy to diff by eye.
const _navy = 0xFF000C2B;
const _gold = 0xFFF4B835;
const _body = 0xFF44506B;
const _muted = 0xFF6E7280;

/// Every run of model-written text in the document, with the size and column it is set in.
///
/// This list and the composition in `reading_pdf.dart` have to agree, and the thing that keeps
/// them honest is [rasterKey]: it is computed from the same three values on both sides, so a
/// block described here at the wrong size simply is not found, and that block falls back to real
/// text rather than being drawn wrongly.
///
/// The app's own English furniture — the wordmark, "What we could see", the footer disclaimer,
/// the page numbers — is deliberately absent. It is Latin whatever the reading is written in,
/// and leaving it as real text keeps the header and footer selectable.
List<_Block> _blocksOf(ReadingPdfRequest request) {
  final title = request.name == null || request.name!.isEmpty
      ? 'Your ${request.documentTitle}'
      : '${request.documentTitle} for ${request.name}';

  return [
    _Block(text: title, size: 23, colour: _navy, heavy: true, height: 1.2, width: pdfContentWidth),

    if (request.invocation.isNotEmpty)
      _Block(
        text: request.invocation,
        size: 11,
        colour: _gold,
        height: 1.5,
        width: pdfContentWidth,
      ),

    if (request.headline.isNotEmpty)
      _Block(
        text: request.headline,
        size: 14,
        colour: _navy,
        heavy: true,
        height: 1.35,
        width: pdfContentWidth,
      ),

    if (request.heroTitle.isNotEmpty) ...[
      _Block(
        text: request.heroKicker.toUpperCase(),
        size: 8,
        colour: _muted,
        heavy: true,
        spacing: 0.8,
        width: pdfContentWidth,
      ),
      _Block(
        text: request.heroTitle,
        size: 15,
        colour: _navy,
        heavy: true,
        width: pdfContentWidth,
      ),
      if (request.heroSummary.isNotEmpty)
        _Block(text: request.heroSummary, size: 10, colour: _body, width: pdfContentWidth),
      if (request.heroDetail.isNotEmpty)
        _Block(text: request.heroDetail, size: 10, colour: _body, width: pdfContentWidth),
    ],

    if (request.chips.isNotEmpty)
      _Block(
        text: request.chips.join('   ·   '),
        size: 9,
        colour: _muted,
        width: pdfContentWidth,
      ),

    for (final observation in request.observations)
      _Block(text: observation, size: 10, colour: _body, width: pdfBulletWidth),

    if (request.sections.isNotEmpty)
      _Block(
        text: request.sectionsHeading,
        size: 16,
        colour: _navy,
        heavy: true,
        width: pdfContentWidth,
      ),

    for (final section in request.sections) ...[
      // The title and its Sanskrit name share a line, so they share a picture. The status label
      // beside them is a closed vocabulary the server sets in English and stays real text.
      _Block(
        text: section.title,
        size: 13,
        colour: _navy,
        heavy: true,
        height: 1.2,
        width: pdfContentWidth,
        suffix: section.sanskrit.isEmpty
            ? null
            : _Styled(
                text: '   ${section.sanskrit}',
                size: 9,
                colour: _gold,
                height: 1.2,
              ),
      ),
      if (section.summary.isNotEmpty)
        _Block(text: section.summary, size: 10, colour: _muted, width: pdfContentWidth),
      if (section.detail.isNotEmpty)
        _Block(text: section.detail, size: 10, colour: _body, width: pdfContentWidth),
      for (final line in section.meaning)
        _Block(text: line, size: 10, colour: _body, width: pdfBulletWidth),
      if (section.tip.isNotEmpty)
        _Block(
          text: section.tip,
          size: 9.5,
          colour: _body,
          width: pdfContentWidth,
          prefix: const _Styled(text: 'Tip.  ', size: 9.5, colour: _gold, heavy: true),
        ),
      if (section.blessing.isNotEmpty)
        _Block(text: section.blessing, size: 9.5, colour: _gold, width: pdfContentWidth),
    ],

    if (request.blessing.isNotEmpty)
      _Block(
        text: request.blessing,
        size: 11.5,
        colour: _gold,
        height: 1.5,
        width: pdfContentWidth,
      ),
  ];
}

import 'package:astrolok/data/fake/fake_face_reading.dart';
import 'package:astrolok/data/fake/fake_palm_reading.dart';
import 'package:astrolok/data/models/face_reading.dart';
import 'package:astrolok/data/models/palm_reading.dart';
import 'package:astrolok/data/pdf/pdf_text_raster.dart';
import 'package:astrolok/data/pdf/reading_pdf.dart';
import 'package:astrolok/data/pdf/reading_pdf_requests.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The export, for both readings.
///
/// Two things here are worth more than the rest.
///
/// The **font check**: the `pdf` package's built-in Helvetica has no glyph for a curly quote or
/// an en dash, so the document carries its own faces — and a renamed or unbundled TTF would
/// otherwise surface as a crash on a user's device the first time they tapped download.
///
/// The **page-break tests**: the previous export drew each section as a `pw.Container`, which
/// `MultiPage` cannot split, so a long reading either left ragged white gutters or threw
/// "Widget won't fit into the page". The maximum-length cases below are the regression guard
/// for that, and they are the reason this file builds a reading at the server's clamp limits
/// rather than only the tidy canned one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List regular;
  late Uint8List bold;

  setUpAll(() async {
    regular = (await rootBundle.load('assets/fonts/Poppins-Regular.ttf'))
        .buffer
        .asUint8List();
    bold = (await rootBundle.load('assets/fonts/Poppins-SemiBold.ttf'))
        .buffer
        .asUint8List();
  });

  /// A real 8×8 JPEG, encoded rather than hand-written.
  ///
  /// The export only ever scales the photo into a fixed 150pt box, so the content does not
  /// matter — but the bytes have to be a JPEG the `pdf` package can actually parse, and a
  /// hand-assembled header is very easy to get subtly wrong.
  Uint8List tinyJpeg() => img.encodeJpg(img.Image(width: 8, height: 8));

  String magic(Uint8List bytes) => String.fromCharCodes(bytes.sublist(0, 5));

  /// Counts `/Type /Page` objects. Crude, but it is the only thing in the file that answers
  /// "did this actually paginate" without pulling in a PDF parser.
  int pageCount(Uint8List bytes) =>
      RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length;

  // ---------------------------------------------------------------- the bundle

  test('the fonts the export needs are actually in the bundle', () {
    expect(regular.lengthInBytes, greaterThan(10000));
    expect(bold.lengthInBytes, greaterThan(10000));
    // TrueType magic — catches a file that downloaded as an HTML error page, which is exactly
    // how one of these arrived the first time.
    expect(regular.sublist(0, 4), [0x00, 0x01, 0x00, 0x00]);
    expect(bold.sublist(0, 4), [0x00, 0x01, 0x00, 0x00]);
  });

  // ---------------------------------------------------------------- palm

  group('palm export', () {
    test('builds from a full reading', () async {
      final bytes = await buildReadingPdf(
        fakePalmReading(PalmFocus.love)
            .toPdfRequest(regular: regular, bold: bold, name: 'Asha'),
      );

      expect(magic(bytes), '%PDF-');
      expect(bytes.lengthInBytes, greaterThan(1000));
    });

    test('builds with a photo', () async {
      final bytes = await buildReadingPdf(
        fakePalmReading(PalmFocus.love)
            .toPdfRequest(regular: regular, bold: bold, image: tinyJpeg()),
      );

      expect(magic(bytes), '%PDF-');
    });

    test('builds without a photo or a name', () async {
      // The ordinary case after a reinstall or on a second device: the reading text outlives
      // its picture, and the document has to lay out without a gap where the image was.
      final bytes = await buildReadingPdf(
        fakePalmReading(PalmFocus.career).toPdfRequest(regular: regular, bold: bold),
      );

      expect(magic(bytes), '%PDF-');
    });

    test('builds from a sparse reading with no bullets and no tip', () async {
      // The server ships a reading with as few as six lines rather than failing, and a line can
      // arrive with no bullets and no tip. The export must not assume a full one.
      final full = fakePalmReading(PalmFocus.personality);
      final sparse = PalmReading(
        id: full.id,
        createdAt: full.createdAt,
        focus: full.focus,
        lines: [
          PalmLine(
            kind: PalmLineKind.heart,
            title: 'Heart Line',
            status: ReadingStatus.balanced,
            summary: '',
            detail: full.lines.first.detail,
          ),
        ],
      );

      expect(
        magic(await buildReadingPdf(
          sparse.toPdfRequest(regular: regular, bold: bold),
        )),
        '%PDF-',
      );
    });

    test('handles typography the built-in fonts would drop', () async {
      // Curly quotes, an em dash and an ellipsis are all things a language model writes freely,
      // and all things Helvetica renders as blanks.
      final full = fakePalmReading(PalmFocus.lifePath);
      final fancy = PalmReading(
        id: full.id,
        createdAt: full.createdAt,
        focus: full.focus,
        invocation: 'Come — sit awhile…',
        headline: 'You’re steady — quietly so…',
        blessing: 'May you keep what you’ve built.',
        lines: [
          const PalmLine(
            kind: PalmLineKind.heart,
            title: 'Heart Line',
            sanskrit: 'Hridaya Rekha',
            status: ReadingStatus.strong,
            summary: 'You’re warm.',
            detail: 'Hands like yours — smooth, unmarked — “hold steady”…',
            meaning: ['You’re patient.'],
            tip: 'Don’t rush it.',
            blessing: 'May your warmth be met in kind.',
          ),
        ],
      );

      expect(
        magic(await buildReadingPdf(
          fancy.toPdfRequest(regular: regular, bold: bold),
        )),
        '%PDF-',
      );
    });
  });

  // ---------------------------------------------------------------- face

  group('face export', () {
    test('builds from a full reading', () async {
      final bytes = await buildReadingPdf(
        fakeFaceReading(PalmFocus.love)
            .toPdfRequest(regular: regular, bold: bold, name: 'Asha'),
      );

      expect(magic(bytes), '%PDF-');
      expect(bytes.lengthInBytes, greaterThan(1000));
    });

    test('builds with a photo and without one', () async {
      for (final image in [tinyJpeg(), null]) {
        final bytes = await buildReadingPdf(
          fakeFaceReading(PalmFocus.career)
              .toPdfRequest(regular: regular, bold: bold, image: image),
        );
        expect(magic(bytes), '%PDF-');
      }
    });

    test('builds from a reading with no traits and one bare section', () async {
      final full = fakeFaceReading(PalmFocus.money);
      final sparse = FaceReading(
        id: full.id,
        createdAt: full.createdAt,
        focus: full.focus,
        parts: [
          FacePart(
            kind: FacePartKind.eyes,
            title: 'Eyes',
            status: ReadingStatus.balanced,
            summary: '',
            detail: full.parts.first.detail,
          ),
        ],
      );

      expect(
        magic(await buildReadingPdf(
          sparse.toPdfRequest(regular: regular, bold: bold),
        )),
        '%PDF-',
      );
    });
  });

  // ---------------------------------------------------------------- pagination

  group('a maximum-length reading', () {
    /// Every string at the ceiling `normalisePalmReading` clamps to: a 900-character detail,
    /// three 200-character bullets and a 220-character tip, eight times over. This is the
    /// longest document the server can produce, and it is what used to throw.
    PalmReading enormousPalm() {
      String filler(int length) {
        const word = 'sentence ';
        return (word * (length ~/ word.length + 1)).substring(0, length).trim();
      }

      return PalmReading(
        id: 'enormous',
        createdAt: DateTime(2026, 9, 4),
        focus: PalmFocus.lifePath,
        invocation: filler(200),
        headline: filler(120),
        blessing: filler(240),
        strongestTrait: PalmTrait(
          title: filler(60),
          summary: filler(160),
          detail: filler(600),
        ),
        hand: HandTraits(
          whichHand: 'right',
          skinTexture: 'smooth',
          firmness: 'soft',
          palmShape: 'broad',
          fingerLength: 'long',
          observations: [filler(180), filler(180), filler(180), filler(180)],
        ),
        lines: [
          for (final kind in PalmLineKind.values)
            PalmLine(
              kind: kind,
              title: filler(40),
              sanskrit: filler(32),
              status: ReadingStatus.strong,
              summary: filler(110),
              detail: filler(900),
              meaning: [filler(200), filler(200), filler(200)],
              tip: filler(220),
              blessing: filler(180),
            ),
        ],
      );
    }

    test('lays out without throwing, and runs to several pages', () async {
      final bytes = await buildReadingPdf(
        enormousPalm().toPdfRequest(
          regular: regular,
          bold: bold,
          image: tinyJpeg(),
          name: 'Someone With A Rather Long Name Indeed',
        ),
      );

      expect(magic(bytes), '%PDF-');
      // The whole point of the flat layout: it paginates rather than failing.
      expect(pageCount(bytes), greaterThan(1));
    });

    test('a single unbroken 900-character paragraph still fits', () async {
      // The failure mode the bordered-card layout had: one child taller than the printable
      // area, with no seam for MultiPage to break on.
      final wall = 'x' * 900;
      final reading = PalmReading(
        id: 'wall',
        createdAt: DateTime(2026, 9, 4),
        focus: PalmFocus.lifePath,
        lines: [
          for (final kind in PalmLineKind.values)
            PalmLine(
              kind: kind,
              title: 'A line title that is deliberately long enough to wrap',
              status: ReadingStatus.faint,
              summary: wall,
              detail: wall,
            ),
        ],
      );

      expect(
        magic(await buildReadingPdf(
          reading.toPdfRequest(regular: regular, bold: bold),
        )),
        '%PDF-',
      );
    });
  });

  // ---------------------------------------------------------------- filenames

  group('filenames', () {
    test('are distinct per reading, so two exports cannot collide', () {
      final palm = fakePalmReading(PalmFocus.love)
          .toPdfRequest(regular: regular, bold: bold);
      final face = fakeFaceReading(PalmFocus.love)
          .toPdfRequest(regular: regular, bold: bold);

      expect(palm.fileName('11111111-2222-3333'), 'astrolok-palm-reading-11111111.pdf');
      expect(face.fileName('11111111-2222-3333'), 'astrolok-face-reading-11111111.pdf');
      expect(
        palm.fileName('aaaaaaaa-bbbb'),
        isNot(palm.fileName('cccccccc-dddd')),
      );
    });

    test('survive an id shorter than the slice they take', () {
      final palm = fakePalmReading(PalmFocus.love)
          .toPdfRequest(regular: regular, bold: bold);

      expect(palm.fileName('abc'), 'astrolok-palm-reading-abc.pdf');
    });
  });

  // ---------------------------------------------------------------- shaped scripts

  group('a reading in a script the engine cannot set', () {
    // The failure being guarded: `pdf` maps codepoints straight to glyphs and ships a shaper for
    // Arabic alone. Devanagari drawn that way loses its conjuncts and hangs its matras beside the
    // consonant instead of around it. So anything above U+0589 is laid out by Flutter and pasted
    // in as a picture; everything Latin stays real text.

    test('Latin text is left as text, with nothing drawn', () {
      final request = fakePalmReading(PalmFocus.love)
          .toPdfRequest(regular: regular, bold: bold, name: 'Asha');

      expect(readingNeedsShaping(request), isFalse);
      expect(needsShaping('Aapka Chandra Mesha rashi mein hai'), isFalse);
      // Hinglish is the default and is Roman: the common case must not pay for this at all.
      expect(request.rasters, isEmpty);
    });

    test('the punctuation the bundled font exists for stays as text', () {
      // The first version of this rule said "anything above U+0589", which is wrong in the most
      // expensive way: every reading in the app is written with em dashes and curly quotes, and
      // the whole reason Poppins is bundled instead of the built-in Helvetica is that it sets
      // them. That rule would have turned all 174 users' English exports into pictures.
      expect(needsShaping('A reading — with quotes, an ellipsis… and \u20b9249'), isFalse);
      expect(needsShaping('Naive, resume, cafe: accents like naïve and café'), isFalse);
    });

    test('Devanagari and Tamil are recognised as needing it', () {
      expect(needsShaping('आपका चंद्र मेष राशि में है'), isTrue);
      expect(needsShaping('உங்கள் சந்திரன்'), isTrue);
      // Mixed is still shaped — one Devanagari word in an English sentence is enough to break.
      expect(needsShaping('Your Chandra sits in मेष'), isTrue);
    });

    test('a rasterised block is found by the key the composition looks up', () async {
      // The one thing that can silently break this: the rasteriser and the composition compute
      // the key from the same three values, so a drift in either would show up as an export that
      // quietly fell back to broken text rather than as a failure.
      final key = rasterKey('आपका चंद्र', size: 10, width: pdfBulletWidth);
      expect(key, rasterKey('आपका चंद्र', size: 10.0, width: pdfBulletWidth));
      expect(key, isNot(rasterKey('आपका चंद्र', size: 10, width: pdfContentWidth)));
      expect(key, isNot(rasterKey('आपका चंद्र', size: 13, width: pdfBulletWidth)));
    });

    test('the export still builds when a block was drawn', () async {
      // A hand-made raster stands in for the real one, since `dart:ui` painting needs a live
      // engine. What is under test is the composition: it has to place the picture and still
      // produce a valid, paginated document.
      final base = fakePalmReading(PalmFocus.love)
          .toPdfRequest(regular: regular, bold: bold, name: 'Asha');

      final png = Uint8List.fromList(img.encodePng(img.Image(width: 60, height: 12)));
      final request = base.rasterised({
        rasterKey(base.headline, size: 14, width: pdfContentWidth):
            PdfRaster(png: png, width: 200, height: 14),
      });

      final bytes = await buildReadingPdf(request);
      expect(magic(bytes), '%PDF-');
      expect(pageCount(bytes), greaterThan(0));
    });
  });
}

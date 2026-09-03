import 'package:astrolok/data/fake/fake_palm_reading.dart';
import 'package:astrolok/data/models/palm_reading.dart';
import 'package:astrolok/features/palm/palm_pdf.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The export.
///
/// The most valuable thing here is the font check: the `pdf` package's built-in Helvetica has
/// no glyph for a curly quote or an en dash, so the document carries its own faces — and a
/// renamed or unbundled TTF would otherwise surface as a crash on a user's device the first
/// time they tapped download.
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

  test('the fonts the export needs are actually in the bundle', () {
    expect(regular.lengthInBytes, greaterThan(10000));
    expect(bold.lengthInBytes, greaterThan(10000));
    // TrueType magic — catches a file that downloaded as an HTML error page, which is exactly
    // how one of these arrived the first time.
    expect(regular.sublist(0, 4), [0x00, 0x01, 0x00, 0x00]);
    expect(bold.sublist(0, 4), [0x00, 0x01, 0x00, 0x00]);
  });

  test('builds a PDF from a full reading', () async {
    final bytes = await buildPalmPdf(
      PalmPdfRequest(
        reading: fakePalmReading(PalmFocus.love),
        regular: regular,
        bold: bold,
        name: 'Asha',
      ),
    );

    expect(bytes.lengthInBytes, greaterThan(1000));
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
  });

  test('builds without a photo', () async {
    // The ordinary case after a reinstall or on a second device: the reading text outlives its
    // picture, and the document has to lay out without a gap where the image was.
    final bytes = await buildPalmPdf(
      PalmPdfRequest(
        reading: fakePalmReading(PalmFocus.career),
        regular: regular,
        bold: bold,
      ),
    );

    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
  });

  test('builds without a name', () async {
    final bytes = await buildPalmPdf(
      PalmPdfRequest(
        reading: fakePalmReading(PalmFocus.money),
        regular: regular,
        bold: bold,
      ),
    );

    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
  });

  test('builds from a reading with only one line and no bullets', () async {
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
          status: PalmLineStatus.balanced,
          summary: '',
          detail: full.lines.first.detail,
        ),
      ],
    );

    final bytes = await buildPalmPdf(
      PalmPdfRequest(reading: sparse, regular: regular, bold: bold),
    );

    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
  });

  test('handles typography the built-in fonts would drop', () async {
    // Curly quotes, an em dash and an ellipsis are all things a language model writes freely,
    // and all things Helvetica renders as blanks.
    final full = fakePalmReading(PalmFocus.lifePath);
    final fancy = PalmReading(
      id: full.id,
      createdAt: full.createdAt,
      focus: full.focus,
      headline: 'You’re steady — quietly so…',
      lines: [
        PalmLine(
          kind: PalmLineKind.heart,
          title: 'Heart Line',
          status: PalmLineStatus.strong,
          summary: 'You’re warm.',
          detail: 'Hands like yours — smooth, unmarked — “hold steady”…',
          meaning: const ['You’re patient.'],
          tip: 'Don’t rush it.',
        ),
      ],
    );

    final bytes = await buildPalmPdf(
      PalmPdfRequest(reading: fancy, regular: regular, bold: bold),
    );

    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
  });
}

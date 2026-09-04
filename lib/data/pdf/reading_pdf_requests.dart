import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../app/assets.dart';
import '../models/face_reading.dart';
import '../models/palm_reading.dart';
import 'reading_pdf.dart';

/// Turns a reading into the primitive-only request the PDF builder takes.
///
/// Kept out of `reading_pdf.dart` on purpose: that file must not import a model or a `Color`,
/// because everything it touches has to survive being sent to a background isolate. The mapping
/// lives here, on the app side of that line.
///
/// The copy in these functions — "Your Palm lines", "Your Strongest Trait" — is duplicated from
/// `PalmCopy` and `FaceCopy` rather than imported, so the data layer does not reach up into a
/// feature folder. It is four strings, and they change together with the export, not with the
/// screen.

const _disclaimer =
    'Astrolok · For guidance and reflection. Not medical, legal or financial advice.';

/// The bundled bytes both exports need, read on the UI isolate.
///
/// `rootBundle` is not available on a background isolate, so this has to happen before the
/// composition moves off one — which is the whole reason [ReadingPdfRequest] carries bytes
/// rather than asset paths.
class ReadingPdfAssets {
  const ReadingPdfAssets({required this.regular, required this.bold, this.mark});

  final Uint8List regular;
  final Uint8List bold;

  /// Null when the mark is missing from the bundle. The header lays out without it, in keeping
  /// with the rest of the app: a dropped asset costs its own box and nothing else.
  final Uint8List? mark;

  static Future<ReadingPdfAssets> load() async {
    final regular = await rootBundle.load('assets/fonts/Poppins-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Poppins-SemiBold.ttf');

    Uint8List? mark;
    try {
      mark = (await rootBundle.load(Brand.mark)).buffer.asUint8List();
    } catch (error) {
      debugPrint('[pdf] the oṃ mark is missing from the bundle: $error');
    }

    return ReadingPdfAssets(
      regular: regular.buffer.asUint8List(),
      bold: bold.buffer.asUint8List(),
      mark: mark,
    );
  }
}

extension PalmReadingPdf on PalmReading {
  ReadingPdfRequest toPdfRequest({
    required Uint8List regular,
    required Uint8List bold,
    Uint8List? image,
    Uint8List? mark,
    String? name,
  }) {
    return ReadingPdfRequest(
      documentTitle: 'Palm Reading',
      createdAt: createdAt,
      focusLabel: focus.label,
      sectionsHeading: 'Your Palm Lines',
      heroKicker: 'Your Strongest Trait',
      disclaimer: _disclaimer,
      regular: regular,
      bold: bold,
      name: name,
      invocation: invocation,
      headline: headline,
      blessing: blessing,
      heroTitle: strongestTrait.title,
      heroSummary: strongestTrait.summary,
      heroDetail: strongestTrait.detail,
      chips: hand.chips,
      observations: hand.observations,
      image: image,
      mark: mark,
      sections: [
        for (final line in lines)
          ReadingPdfSection(
            title: line.title,
            sanskrit: line.sanskrit,
            statusLabel: line.status.label,
            // ARGB int, not the Color itself — see the note in reading_pdf.dart.
            statusColor: line.status.color.toARGB32(),
            summary: line.summary,
            detail: line.detail,
            meaning: line.meaning,
            tip: line.tip,
            blessing: line.blessing,
          ),
      ],
    );
  }
}

extension FaceReadingPdf on FaceReading {
  ReadingPdfRequest toPdfRequest({
    required Uint8List regular,
    required Uint8List bold,
    Uint8List? image,
    Uint8List? mark,
    String? name,
  }) {
    return ReadingPdfRequest(
      documentTitle: 'Face Reading',
      createdAt: createdAt,
      focusLabel: focus.label,
      sectionsHeading: 'Your Face Reveals',
      heroKicker: 'Your Core Trait',
      disclaimer: _disclaimer,
      regular: regular,
      bold: bold,
      name: name,
      invocation: invocation,
      headline: headline,
      blessing: blessing,
      heroTitle: coreTrait.title,
      heroSummary: coreTrait.summary,
      heroDetail: coreTrait.detail,
      // The four trait chips read as observations in print, where there is no room for the
      // icon that carries them on screen.
      chips: [
        ...traits.map((trait) => trait.label),
        ...face.chips,
      ],
      observations: face.observations,
      image: image,
      mark: mark,
      sections: [
        for (final part in parts)
          ReadingPdfSection(
            title: part.title,
            sanskrit: part.sanskrit,
            statusLabel: part.status.label,
            statusColor: part.status.color.toARGB32(),
            summary: part.summary,
            detail: part.detail,
            meaning: part.meaning,
            tip: part.tip,
            blessing: part.blessing,
          ),
      ],
    );
  }
}

import 'package:astrolok/data/fake/fake_kundali_chart.dart';
import 'package:astrolok/data/fake/fake_kundali_repository.dart';
import 'package:astrolok/data/models/kundali.dart';
import 'package:astrolok/data/pdf/kundali_pdf.dart';
import 'package:astrolok/data/pdf/kundali_pdf_requests.dart';
import 'package:astrolok/data/pdf/pdf_text_raster.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The downloadable kundali report.
///
/// What would break on a user's phone: a table or a paragraph that `MultiPage` cannot split
/// ("Widget won't fit into the page"), and model text in an Indic script that the PDF engine would
/// set wrongly because no one listed it for the rasteriser.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List regular;
  late Uint8List bold;

  setUpAll(() async {
    regular = (await rootBundle.load('assets/fonts/Poppins-Regular.ttf')).buffer.asUint8List();
    bold = (await rootBundle.load('assets/fonts/Poppins-SemiBold.ttf')).buffer.asUint8List();
  });

  KundaliReading reading({Map<String, Object?>? report}) => KundaliReading.fromServer({
        'id': '8a1f5c2e-0000-4000-8000-000000000001',
        'state': 'ready',
        'requested_at': '2026-09-16T00:00:00Z',
        'unlock_at': '2026-09-17T00:00:00Z',
        'server_now': '2026-09-17T01:00:00Z',
        'birth': {'dob': '1995-03-21', 'birth_time': '10:30', 'place_label': 'Tirupati, Andhra Pradesh, India', 'time_zone_id': 'Asia/Kolkata'},
        'teaser': {'moon_rashi': 'Vrischika'},
        'stages': [],
        'viewed': true,
        'regenerations_left': 2,
        'chart': fakeKundaliChart,
        'report': report ?? fakeKundaliReport,
        'language': 'English',
      })!;

  String magic(Uint8List bytes) => String.fromCharCodes(bytes.sublist(0, 5));
  int pages(Uint8List bytes) => RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length;

  test('the report builds, with the chart, tables and insights, across pages', () async {
    final request = reading().toPdfRequest(regular: regular, bold: bold, name: 'Asha');
    expect(request.title, 'Kundali for Asha');
    expect(request.planets, hasLength(9));
    expect(request.houses, hasLength(12));
    expect(request.insights, hasLength(4));
    expect(request.dasha.where((d) => d.current), hasLength(1));
    expect(request.fileName, 'astrolok-kundali-8a1f5c2e.pdf');

    final bytes = await buildKundaliPdf(request);
    expect(magic(bytes), '%PDF-');
    expect(pages(bytes), greaterThanOrEqualTo(2));
  });

  test('a report at the server clamp limits still paginates', () async {
    final long = String.fromCharCodes(List.filled(880, 'word '.codeUnitAt(0))).replaceAll('w', 'word ');
    final report = Map<String, Object?>.from(fakeKundaliReport)
      ..['insights'] = {
        for (final key in KundaliInsightKey.all)
          key: {'evidence': ['moon_h7'], 'summary': long.substring(0, 170), 'detail': long.substring(0, 880), 'tip': long.substring(0, 170)},
      }
      ..['houses'] = [for (var i = 1; i <= 12; i++) {'house': i, 'theme': long.substring(0, 118)}];

    final bytes = await buildKundaliPdf(reading(report: report).toPdfRequest(regular: regular, bold: bold));
    expect(magic(bytes), '%PDF-');
    expect(pages(bytes), greaterThanOrEqualTo(3));
  });

  test('every run of model text is listed for the rasteriser, so Hindi is shaped', () {
    final hindi = Map<String, Object?>.from(fakeKundaliReport)..['headline'] = 'धैर्य और प्रेम से भरा एक स्थिर हृदय';
    final request = reading(report: hindi).toPdfRequest(regular: regular, bold: bold);
    final texts = request.runs.map((r) => r.text).toSet();

    expect(texts, contains('धैर्य और प्रेम से भरा एक स्थिर हृदय'));
    for (final insight in request.insights) {
      expect(texts, containsAll([insight.summary, insight.detail, insight.tip]));
    }
    for (final planet in request.planets) {
      expect(texts, contains(planet.line));
    }
    expect(request.runs.any((r) => needsShaping(r.text)), isTrue);
    expect(needsShaping(request.lagnaLine), isFalse, reason: 'the app’s own Latin furniture stays real text');
  });
}

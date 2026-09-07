// Starts the phone app.
//
// Resolved at compile time, not at runtime: the app tree reaches `dart:io` in seven places
// (`edge_functions.dart`, `fast2sms_client.dart`, `reading_camera.dart`, `reading_speech.dart`,
// `reading_image_store.dart`, and both reading viewmodels), and dart2js rejects that import
// before tree-shaking ever gets a chance to drop it. A plain `if (kIsWeb)` in `main.dart` would
// still compile the whole tree, so the web build has to be unable to see it at all.
export 'mobile_boot_stub.dart' if (dart.library.io) 'mobile_boot_io.dart';

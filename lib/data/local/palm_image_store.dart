import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The captured palm photographs, kept on the device and nowhere else.
///
/// The server never stores the image — it goes to the model and is dropped — so this is the
/// only copy that outlives a reading, and it is what lets the results screen show the hand it
/// is talking about.
///
/// Everything here is best-effort. A reading whose photo cannot be written, or has since been
/// deleted, is still a perfectly good reading; the screens fall back to the palm artwork. So no
/// method throws, and a failure costs the image and nothing else.
class PalmImageStore {
  PalmImageStore();

  static const _folder = 'palm';

  /// Written before the reading is requested, when there is no id yet to name the file after.
  static const _pendingName = 'pending.jpg';

  /// Old readings are still readable as text; only their pictures age out. Ten is a couple of
  /// megabytes at the sizes this app produces.
  static const _keep = 10;

  Directory? _dir;

  Future<Directory?> _directory() async {
    if (_dir != null) return _dir;
    try {
      final documents = await getApplicationDocumentsDirectory();
      final dir = Directory('${documents.path}/$_folder');
      if (!await dir.exists()) await dir.create(recursive: true);
      return _dir = dir;
    } catch (error) {
      debugPrint('[palm] could not open the image directory: $error');
      return null;
    }
  }

  /// Resolves a stored file *name* against the current documents directory.
  ///
  /// Names are stored rather than absolute paths on purpose: iOS rewrites the application
  /// container path on reinstall and on restore from backup, so a persisted absolute path is a
  /// broken image on every restored device.
  Future<File?> file(String? name) async {
    if (name == null || name.isEmpty) return null;
    final dir = await _directory();
    if (dir == null) return null;

    final file = File('${dir.path}/$name');
    return await file.exists() ? file : null;
  }

  /// Stashes the capture before the reading is requested.
  Future<void> savePending(Uint8List bytes) async {
    final dir = await _directory();
    if (dir == null) return;
    try {
      await File('${dir.path}/$_pendingName').writeAsBytes(bytes, flush: true);
    } catch (error) {
      debugPrint('[palm] could not save the capture: $error');
    }
  }

  /// Renames the pending capture to the reading it turned out to be, and returns the name to
  /// store on the reading. Null if there was nothing to rename.
  Future<String?> commitPending(String readingId) async {
    final dir = await _directory();
    if (dir == null) return null;

    final pending = File('${dir.path}/$_pendingName');
    if (!await pending.exists()) return null;

    final name = '$readingId.jpg';
    try {
      await pending.rename('${dir.path}/$name');
      await _prune();
      return name;
    } catch (error) {
      debugPrint('[palm] could not commit the capture: $error');
      return null;
    }
  }

  /// Drops a capture that never became a reading — a rejected photo, or an abandoned scan.
  Future<void> discardPending() async {
    final dir = await _directory();
    if (dir == null) return;
    try {
      final pending = File('${dir.path}/$_pendingName');
      if (await pending.exists()) await pending.delete();
    } catch (error) {
      debugPrint('[palm] could not discard the capture: $error');
    }
  }

  /// Everything, on sign-out. The next person to use this device must not find the last one's
  /// hand in it.
  Future<void> clear() async {
    final dir = await _directory();
    if (dir == null) return;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
      _dir = null;
    } catch (error) {
      debugPrint('[palm] could not clear the images: $error');
    }
  }

  /// Keeps the newest [_keep] photos. Called after a successful commit.
  Future<void> _prune() async {
    final dir = await _directory();
    if (dir == null) return;

    try {
      final files = <File>[
        for (final entry in dir.listSync())
          if (entry is File && entry.path.endsWith('.jpg')) entry,
      ];
      if (files.length <= _keep) return;

      files.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );
      for (final stale in files.skip(_keep)) {
        await stale.delete();
      }
    } catch (error) {
      debugPrint('[palm] could not prune old images: $error');
    }
  }
}

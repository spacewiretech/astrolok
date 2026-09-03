import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

/// Turns a camera capture into something worth sending to the model.
///
/// Three things happen here, and each one earns its place:
///
///  * **Downscale to 1024².** Gemini tiles images at 768², so below roughly 1536 the token
///    cost is a flat minimum — 1024 is effectively free next to 768 and keeps fine palm
///    creases resolvable, which is the entire read. Larger buys detail the model does not use
///    and a slower upload on an Indian mobile connection.
///  * **Crop to the square the user actually framed.** The viewfinder is square; the sensor is
///    not. An uncropped capture carries a strip of room the user never saw, which both dilutes
///    the read and wastes image tokens.
///  * **Strip EXIF.** A palm photograph tagged with the user's home coordinates, forwarded to
///    Google, is not a trade to make silently.
class PalmImage {
  const PalmImage({required this.bytes, required this.width, required this.height});

  final Uint8List bytes;
  final int width;
  final int height;

  int get sizeInKb => (bytes.lengthInBytes / 1024).round();
}

/// The edge length sent to the model.
const _target = 1024;

/// JPEG quality for the encode that actually goes to the model.
///
/// Not lower. The whole read is the fine creases across the palm, and JPEG spends its bit
/// budget on exactly the low-contrast, high-frequency detail those creases are made of — at
/// quality 10 the palm arrives as smooth blocks and the model has nothing to read.
const _quality = 82;

/// Prepares a capture for the model. Null when the bytes could not be turned into an image.
///
/// **The downscale runs on the root isolate on purpose.** [FlutterImageCompress] is a plugin,
/// so it talks over a platform channel, and a background isolate has no channels — calling it
/// inside `compute()` throws `BackgroundIsolateBinaryMessenger` before it does any work. That
/// failure looked exactly like an oversized photo from the outside, which is why lowering the
/// quality appeared to change nothing. Only the pure-Dart crop moves off the isolate.
///
/// The crop takes the centre square, which needs no knowledge of the preview: the capture
/// screen shows the sensor image `cover`-fitted into a square box, and cover on a square box
/// scales the shorter edge to fill and crops the longer one — so the centre square *is*
/// exactly what the user framed. If that box ever stops being square, this has to change with
/// it.
Future<PalmImage?> preparePalmImage(Uint8List raw) async {
  Uint8List downscaled;

  try {
    // Native, and already off the platform thread. EXIF is dropped here, which is what keeps
    // the user's home coordinates out of a photo bound for Google.
    downscaled = await FlutterImageCompress.compressWithList(
      raw,
      minWidth: _target,
      minHeight: _target,
      quality: _quality,
      keepExif: false,
      format: CompressFormat.jpeg,
    );
  } catch (error) {
    // A plugin that is missing, or a format it cannot read. The pure-Dart path below can
    // still decode an ordinary JPEG or PNG, so this is a degraded route rather than a dead
    // end — slower, but it produces the same result.
    debugPrint('[palm] native downscale unavailable, falling back to Dart: $error');
    downscaled = raw;
  }

  try {
    return await compute(_cropToSquare, downscaled);
  } catch (error) {
    debugPrint('[palm] could not prepare the capture: $error');
    return null;
  }
}

/// Centre-crops to a square and re-encodes. Pure Dart — no plugins, no channels — so this is
/// the part that is safe to run on a background isolate.
PalmImage? _cropToSquare(Uint8List bytes) {
  var decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  final edge = decoded.width < decoded.height ? decoded.width : decoded.height;
  if (decoded.width != decoded.height) {
    decoded = img.copyCrop(
      decoded,
      x: (decoded.width - edge) ~/ 2,
      y: (decoded.height - edge) ~/ 2,
      width: edge,
      height: edge,
    );
  }

  // Also the resize that matters when the native pass was skipped and this is a full-size
  // camera frame.
  if (decoded.width > _target) {
    decoded = img.copyResize(decoded, width: _target, height: _target);
  }

  final encoded = img.encodeJpg(decoded, quality: _quality);

  // No size ceiling here. A 1024² JPEG lands around 150-250KB, an order of magnitude under
  // anything the request could not carry, so a local gate only ever produced false refusals.
  // The server still bounds the body it will accept.
  return PalmImage(
    bytes: Uint8List.fromList(encoded),
    width: decoded.width,
    height: decoded.height,
  );
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Asset loaders that render something sensible when the file is not there yet.
///
/// The artwork is still being exported from Figma, so every screen has to lay out correctly
/// without it. These two widgets are how: a missing file costs its own box and nothing else,
/// rather than a red error screen or a thrown exception during layout.
///
/// This is not only scaffolding for today. An asset renamed or dropped from `pubspec.yaml`
/// later fails exactly the same way — one blank box — instead of taking a screen down.

/// [Image.asset] with a fallback for a file that is not in the bundle.
class SafeImage extends StatelessWidget {
  const SafeImage(
    this.path, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.fallback,
    this.semanticLabel,
  });

  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Where the image sits when [fit] leaves spare room — `contain` in a taller box, say.
  final Alignment alignment;

  /// Drawn in place of the image when it is missing. Null renders nothing at all, which is
  /// right for decoration and wrong for anything load-bearing.
  final Widget? fallback;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      path,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      semanticLabel: semanticLabel,
      // Runs for a missing bundle entry as well as a corrupt one, which is exactly the case
      // being handled here.
      errorBuilder: (context, error, stack) {
        if (kDebugMode) debugPrint('[assets] missing image: $path');
        return SizedBox(
          width: width,
          height: height,
          child: fallback ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

/// [SvgPicture.asset] with the same fallback.
///
/// flutter_svg throws while loading rather than offering an `errorBuilder`, so existence is
/// probed against the asset bundle first. The probe is cached per path — this runs inside list
/// rows and would otherwise hit the bundle on every rebuild.
class SafeSvg extends StatefulWidget {
  const SafeSvg(
    this.path, {
    super.key,
    this.width,
    this.height,
    this.color,
    this.fallback,
    this.semanticLabel,
  });

  final String path;
  final double? width;
  final double? height;

  /// Tints a single-colour glyph. Leave null for multi-colour artwork.
  final Color? color;

  final Widget? fallback;
  final String? semanticLabel;

  static final Map<String, Future<bool>> _exists = {};

  static Future<bool> _probe(String path) {
    return _exists.putIfAbsent(path, () async {
      try {
        await rootBundle.load(path);
        return true;
      } catch (_) {
        if (kDebugMode) debugPrint('[assets] missing svg: $path');
        return false;
      }
    });
  }

  /// Drops the cache. Only useful in tests, which otherwise inherit a probe result from an
  /// earlier case that had a different bundle.
  @visibleForTesting
  static void resetProbeCache() => _exists.clear();

  @override
  State<SafeSvg> createState() => _SafeSvgState();
}

class _SafeSvgState extends State<SafeSvg> {
  late Future<bool> _found = SafeSvg._probe(widget.path);

  @override
  void didUpdateWidget(covariant SafeSvg oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _found = SafeSvg._probe(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _found,
      builder: (context, snapshot) {
        final box = SizedBox(
          width: widget.width,
          height: widget.height,
          child: snapshot.data == false ? widget.fallback : null,
        );

        // Reserve the space while probing so a list row does not resize under the user's
        // finger the moment the answer arrives.
        if (snapshot.data != true) return box;

        return SvgPicture.asset(
          widget.path,
          width: widget.width,
          height: widget.height,
          semanticsLabel: widget.semanticLabel,
          colorFilter: widget.color == null
              ? null
              : ColorFilter.mode(widget.color!, BlendMode.srcIn),
        );
      },
    );
  }
}

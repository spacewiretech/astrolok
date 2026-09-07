import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_typography.dart';

/// "By continuing you agree to our Terms of Service and Privacy Policy."
///
/// Both links must actually open something before launch — an agreement pointing at nothing is
/// not an agreement, and both stores reject a signup flow whose policy link is dead.
///
/// The URLs are passed in rather than held here: they live in the `app_config` table so they
/// can be corrected without an app release, with `defaultAppConfig` carrying the fallbacks that
/// ship in the build. Nothing under `lib/widgets/` reads a provider, so the caller resolves
/// them — see `lib/features/onboarding/onboarding_view.dart`.
class TermsFooter extends StatefulWidget {
  const TermsFooter({
    super.key,
    required this.termsUrl,
    required this.privacyUrl,
    this.lead = 'By continuing you agree to our',
  });

  final String termsUrl;
  final String privacyUrl;
  final String lead;

  @override
  State<TermsFooter> createState() => _TermsFooterState();
}

class _TermsFooterState extends State<TermsFooter> {
  /// Recognisers hold gesture state, so they are built once and disposed — rebuilding them
  /// inside `build` leaks one per frame.
  ///
  /// The URL is read through `widget` at tap time rather than captured here, so config
  /// arriving after the first frame is picked up without rebuilding the recognisers.
  late final _terms = TapGestureRecognizer()..onTap = () => _open(widget.termsUrl);
  late final _privacy = TapGestureRecognizer()..onTap = () => _open(widget.privacyUrl);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = AppText.legal.copyWith(
      color: AppColors.gold,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.gold,
    );

    return Text.rich(
      TextSpan(
        style: AppText.legal,
        children: [
          TextSpan(text: '${widget.lead} '),
          TextSpan(text: 'Terms of Service', style: link, recognizer: _terms),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

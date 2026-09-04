import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_typography.dart';

/// "By continuing you agree to our Terms of Service and Privacy Policy."
///
/// Both links must actually open something before launch — an agreement pointing at nothing is
/// not an agreement, and both stores reject a signup flow whose policy link is dead. The URLs
/// are constants here so there is one place to set them.
class TermsFooter extends StatefulWidget {
  const TermsFooter({super.key, this.lead = 'By continuing you agree to our'});

  final String lead;

  /// The site these point at is built from `lib/website/`, and `test/website_test.dart`
  /// asserts that every path here is a route it actually serves — so a link cannot go dead
  /// without a test failing.
  static const siteUrl = 'https://astrolok.app';

  static const termsUrl = '$siteUrl/terms';
  static const privacyUrl = '$siteUrl/privacy';
  static const helpUrl = '$siteUrl/help';

  /// Also what the site's contact page and footer print, so support reaches one inbox.
  static const supportEmail = 'contact@astrolok.app';

  @override
  State<TermsFooter> createState() => _TermsFooterState();
}

class _TermsFooterState extends State<TermsFooter> {
  /// Recognisers hold gesture state, so they are built once and disposed — rebuilding them
  /// inside `build` leaks one per frame.
  late final _terms = TapGestureRecognizer()..onTap = () => _open(TermsFooter.termsUrl);
  late final _privacy = TapGestureRecognizer()..onTap = () => _open(TermsFooter.privacyUrl);

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

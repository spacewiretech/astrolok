import 'package:flutter/material.dart' show IconData, Icons;

import '../app/assets.dart';

/// Everything on the site that is a business fact rather than a design decision.
///
/// Check these — and only these — before the site goes live; nothing else in `lib/website/`
/// hard-codes an address, an email or a store URL.
abstract final class SitePlaceholders {
  static const legalEntity = 'Spacewire Tech';
  static const address =
      '15th Cross Rd, 6th Sector, HSR Layout, Bengaluru, Karnataka 560102';

  /// Also the address `lib/features/profile/profile_view.dart` opens from "Contact us", so the
  /// two are kept the same on purpose.
  static const supportEmail = 'contact@astrolok.app';

  /// TODO(astrolok): a real number before launch. Cashfree's merchant checklist asks for one,
  /// and the contact page hides the row while this is null rather than printing a placeholder.
  static const String? supportPhone = null;

  static const siteDomain = 'astrolok.app';

  /// Set either to a real listing URL and every download button on the site goes live —
  /// no other edit. Null renders the "coming soon" state instead.
  static const String? playStoreUrl = null;
  static const String? appStoreUrl = null;

  /// Shown at the top of each policy page.
  static const lastUpdated = '4 September 2026';
  static const copyrightYear = '2026';
}

/// Marketing copy for the home page.
///
/// The voice follows the app: warm, plain, second-person, and honest about what does not exist
/// yet. Chat with Astro is named as coming soon here for the same reason Home shows a snackbar
/// rather than a dead chevron.
abstract final class SiteCopy {
  static const appName = 'Astrolok';
  static const tagline = 'Palm, face and astrology readings in your pocket';

  static const heroEyebrow = 'Made in India';
  static const heroHeadline = 'Namaste. What would you like to discover?';
  static const heroSub =
      'Astrolok reads your palm and your face, and reads the result back to you in a '
      'pandit’s voice. Personal, private, and yours to keep as a PDF.';

  /// Mirrors the paywall defaults in `lib/data/repositories/app_config_repository.dart`
  /// (`trial_price_label`, `plan_price_label`, `cashfree_trial_days`). Those are the real
  /// source of truth — the server can override them at runtime — so if they change there,
  /// change them here too. `website_test.dart` pins the two together.
  static const trialPrice = '₹3';
  static const planPrice = '₹249';
  static const trialDays = 1;

  static const priceLine =
      '$trialPrice for a $trialDays-day trial · then $planPrice/month · cancel anytime';

  static const features = <FeatureCopy>[
    FeatureCopy(
      image: Img.readingPalm,
      icon: Icons.back_hand_outlined,
      title: 'Palm Reading',
      body: 'Hold your palm up to the camera. Astrolok maps the life, heart, head and fate '
          'lines, then explains what each one says about you.',
    ),
    FeatureCopy(
      image: Img.readingFace,
      icon: Icons.face_outlined,
      title: 'Face Reading',
      body: 'Your eyes, face shape, nose and lips each carry a trait. One photo, and you get '
          'a reading of the features that make you you.',
    ),
    FeatureCopy(
      image: Img.readingChat,
      icon: Icons.chat_bubble_outline_rounded,
      title: 'Chat with Astro',
      body: 'Ask anything about your life, love, career or future. In the works — it is not '
          'in the app yet, and we would rather say so than pretend.',
      comingSoon: true,
    ),
  ];

  /// The four the paywall names, kept in the same order and wording.
  static const highlights = <String>[
    'Personalized readings',
    'Face & palm insights',
    'Love & career insights',
    'Unlimited astro guidance',
  ];

  static const steps = <StepCopy>[
    StepCopy(
      title: 'Verify your number',
      body: 'One OTP on your phone number. No passwords, no email, no social login.',
    ),
    StepCopy(
      title: 'Add your date of birth',
      body: 'The one detail every reading is grounded in. Nothing else is asked for.',
    ),
    StepCopy(
      title: 'Hold up your palm or face',
      body: 'A single photo inside the frame. Your reading comes back in about a minute, '
          'read aloud and saved to your downloads.',
    ),
  ];

  static const faqs = <FaqCopy>[
    FaqCopy(
      question: 'What happens to my photos?',
      answer:
          'Your palm or face photo is sent over an encrypted connection, used to produce that '
          'one reading, and then deleted from our servers. It is never shown to another user, '
          'never sold, and never used to train anything. You can delete a saved reading, or '
          'your whole account, at any time from the app.',
    ),
    FaqCopy(
      question: 'Is this real astrology?',
      answer:
          'Astrolok draws on Samudrik Shastra — the traditional Indian reading of the palm and '
          'the face — and writes it up in plain language. It is for guidance and reflection, '
          'and it is not a substitute for medical, legal, financial or psychological advice. '
          'Please do not make a serious decision on the strength of a reading alone.',
    ),
    FaqCopy(
      question: 'What does it cost?',
      answer:
          '$trialPrice authorises a UPI Autopay mandate and opens a $trialDays-day trial. '
          'After that $planPrice is auto-debited every month. Cancel any time before the '
          'trial ends and nothing further is charged.',
    ),
    FaqCopy(
      question: 'What is UPI Autopay?',
      answer:
          'A standing instruction you approve once inside your own UPI app. Your bank shows '
          'you the amount and the frequency before you approve it, and you can cancel the '
          'mandate from your UPI app or by writing to us whenever you like.',
    ),
    FaqCopy(
      question: 'How do I cancel?',
      answer:
          'Cancel the mandate in your own UPI app — look under AutoPay or Mandates — or write '
          'to ${SitePlaceholders.supportEmail} and we will cancel it for you. Access continues '
          'until the end of the period you have already paid for.',
    ),
    FaqCopy(
      question: 'Do I need an internet connection?',
      answer:
          'To produce a reading, yes. Once it is saved you can reopen it, have it read aloud '
          'and export the PDF offline — the voice is your phone’s own, so nothing is streamed.',
    ),
    FaqCopy(
      question: 'How do I delete my account?',
      answer:
          'From the account deletion page on this site, or by writing to '
          '${SitePlaceholders.supportEmail}. Your profile, your readings and the date of birth '
          'you gave us are erased.',
    ),
  ];
}

class FeatureCopy {
  const FeatureCopy({
    required this.image,
    required this.icon,
    required this.title,
    required this.body,
    this.comingSoon = false,
  });

  /// The thumbnail already bundled for Home's Explore Readings rows.
  final String image;

  /// Drawn when [image] is missing. A real `IconData` rather than a code point, so
  /// `--tree-shake-icons` can still see which glyphs the build uses.
  final IconData icon;

  final String title;
  final String body;

  /// Renders a "Coming soon" chip, and keeps the card from reading as a shipped feature.
  final bool comingSoon;
}

class StepCopy {
  const StepCopy({required this.title, required this.body});

  final String title;
  final String body;
}

class FaqCopy {
  const FaqCopy({required this.question, required this.answer});

  final String question;
  final String answer;
}

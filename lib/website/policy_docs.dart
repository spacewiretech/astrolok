import 'site_copy.dart';

/// One legal page. Rendered by `pages/policy_page.dart`.
class PolicyDoc {
  const PolicyDoc({
    required this.slug,
    required this.title,
    required this.intro,
    required this.sections,
    this.shortTitle,
  });

  /// Path segment, without the leading slash. Matches `SiteRoutes`.
  final String slug;

  /// The heading on the page itself.
  final String title;

  /// Set only where the page heading is too long to sit in a footer column.
  final String? shortTitle;

  /// How the page is named in the footer and in cross-links.
  String get navLabel => shortTitle ?? title;

  /// Standfirst under the title.
  final String intro;

  final List<PolicySection> sections;
}

class PolicySection {
  const PolicySection({
    required this.heading,
    this.paragraphs = const [],
    this.bullets = const [],
  });

  final String heading;
  final List<String> paragraphs;

  /// Rendered under [paragraphs] as a dotted list.
  final List<String> bullets;
}

const _entity = SitePlaceholders.legalEntity;
const _email = SitePlaceholders.supportEmail;

/// The five legal pages.
///
/// Written to describe what the app actually does — phone-number OTP through Fast2SMS, a date
/// of birth, palm and face photos processed into a reading, storage in Supabase, payments
/// through Cashfree UPI Autopay, on-device speech, no advertising SDKs and no third-party
/// analytics. Every business-specific detail comes from [SitePlaceholders].
///
/// These are drafts written to be accurate, not legal advice. Have them reviewed before
/// publishing — particularly the photo-handling sections, which is where the real exposure is.
abstract final class PolicyDocs {
  static const all = [privacy, terms, refund, shipping, deleteAccount];

  static PolicyDoc? bySlug(String slug) {
    for (final doc in all) {
      if (doc.slug == slug) return doc;
    }
    return null;
  }

  // ---------------------------------------------------------------------------------------
  static const privacy = PolicyDoc(
    slug: 'privacy',
    title: 'Privacy Policy',
    intro:
        'Astrolok asks for two sensitive things — a photo of your palm or face, and your date '
        'of birth. This page explains exactly what we collect, why, how long we keep it, and '
        'how to make it stop.',
    sections: [
      PolicySection(
        heading: 'Who we are',
        paragraphs: [
          'Astrolok ("the app") is operated by $_entity, ${SitePlaceholders.address}. In this '
              'policy "we" and "us" mean $_entity, and "you" means the person using the app.',
          'If you have a question about anything here, write to $_email.',
        ],
      ),
      PolicySection(
        heading: 'What we collect',
        paragraphs: [
          'Only what a reading needs. There is no profile to fill in, no email address, no '
              'social login and no contact-list access.',
        ],
        bullets: [
          'Your mobile number, to sign you in. Verification is by OTP.',
          'Your name, as you type it, so a reading can be addressed to you.',
          'Your date of birth, which every reading is grounded in.',
          'A photo of your palm or your face, when you choose to take one.',
          'The readings produced for you, so you can reopen them from Downloads.',
          'Your subscription status and the payment reference returned by our payment '
              'processor. We never see or store your card, bank or UPI credentials.',
          'Basic technical information — app version, device model, and error reports — used '
              'to fix crashes.',
        ],
      ),
      PolicySection(
        heading: 'Your photos, specifically',
        paragraphs: [
          'This is the part that matters most, so it is spelled out rather than summarised.',
          'A photo is taken only when you press the shutter or pick a file. The app asks for '
              'camera access at that moment and not before, and it never captures in the '
              'background.',
          'The image is resized on your device, sent to our server over an encrypted (TLS) '
              'connection, and passed to the model that produces your reading. Once the '
              'reading is written, the image is deleted from our servers. We keep the text of '
              'the reading, not the picture.',
          'Your photo is never shown to another user, never published, never sold, never used '
              'for advertising, and never used to train a model. We do not run face '
              'recognition, we do not attempt to identify you from an image, and we do not '
              'match your photo against any database.',
          'A copy stays on your own phone so the reading screen can show it back to you. '
              'Deleting the reading in the app deletes that copy.',
        ],
      ),
      PolicySection(
        heading: 'Why we are allowed to hold it',
        paragraphs: [
          'Under India’s Digital Personal Data Protection Act, 2023, we process your personal '
              'data on the basis of the consent you give when you sign up and when you choose '
              'to take a photo. You may withdraw that consent at any time by deleting your '
              'account, and doing so is as easy as giving it was.',
          'Where you are covered by the GDPR or a similar law, our lawful bases are your '
              'consent for the photograph and the performance of our contract with you for the '
              'rest.',
        ],
      ),
      PolicySection(
        heading: 'Who else sees it',
        paragraphs: [
          'We do not sell your data, and we do not share it for anyone else’s marketing. It '
              'reaches a small number of processors, each doing one job:',
        ],
        bullets: [
          'Supabase — hosts our database and server functions, where your account and your '
              'readings are stored.',
          'Fast2SMS — delivers the one-time password to your mobile number.',
          'Cashfree Payments — takes the payment and manages the UPI Autopay mandate. They '
              'handle your payment credentials directly; we never receive them.',
          'The AI provider that generates the reading text from your photograph, under terms '
              'that forbid retaining it or training on it.',
        ],
      ),
      PolicySection(
        heading: 'How long we keep it',
        bullets: [
          'Photographs — deleted from our servers as soon as the reading is produced.',
          'Readings, your name and date of birth — until you delete them or close your '
              'account.',
          'Payment records — as long as tax and accounting law requires us to keep them, '
              'typically eight years, regardless of account deletion.',
        ],
      ),
      PolicySection(
        heading: 'Your rights',
        paragraphs: [
          'You can ask us to show you the data we hold about you, correct it, or erase it. '
              'Write to $_email and we will respond within 30 days. If you are not satisfied '
              'with our answer, you may complain to the Data Protection Board of India.',
        ],
      ),
      PolicySection(
        heading: 'Children',
        paragraphs: [
          'Astrolok is not for anyone under 18. We do not knowingly collect data from a child. '
              'If you believe a child has given us data, write to $_email and we will erase it.',
        ],
      ),
      PolicySection(
        heading: 'Security',
        paragraphs: [
          'Traffic is encrypted in transit. Your session token is held in your phone’s '
              'Keychain or Keystore rather than in ordinary app storage. Access to production '
              'data is limited to the people who need it. No system is perfect, and we will '
              'tell you and the Data Protection Board promptly if a breach affects you.',
        ],
      ),
      PolicySection(
        heading: 'Changes',
        paragraphs: [
          'If this policy changes materially we will say so in the app before the change takes '
              'effect. The date at the top of this page is always the date of the current '
              'version.',
        ],
      ),
    ],
  );

  // ---------------------------------------------------------------------------------------
  static const terms = PolicyDoc(
    slug: 'terms',
    title: 'Terms & Conditions',
    shortTitle: 'Terms & Conditions',
    intro:
        'The agreement between you and $_entity for the use of Astrolok. Please read the '
        'section on what a reading is — it is the one that most often surprises people.',
    sections: [
      PolicySection(
        heading: 'Agreeing to these terms',
        paragraphs: [
          'By creating an account you agree to these terms. If you do not agree, please do not '
              'use the app. You must be 18 or older.',
        ],
      ),
      PolicySection(
        heading: 'What a reading is, and what it is not',
        paragraphs: [
          'Astrolok produces readings in the tradition of Samudrik Shastra — the reading of '
              'the palm and the face — written up in plain language with the help of software.',
          'Readings are provided for guidance, reflection and entertainment. They are not '
              'facts, not predictions, and not professional advice of any kind. Nothing in a '
              'reading is medical, psychological, legal, financial or career advice, and it '
              'must not be treated as a diagnosis or a recommendation.',
          'Please do not make an important decision — about your health, your money, your '
              'relationships or your work — on the strength of a reading. If something in a '
              'reading worries you, speak to a qualified professional.',
          'Because a reading is interpretive, we cannot and do not warrant that any part of it '
              'is accurate, and no outcome is promised or guaranteed.',
        ],
      ),
      PolicySection(
        heading: 'Your account',
        paragraphs: [
          'Your account is tied to your mobile number and is for you alone. Keep access to '
              'your number secure — anyone who can receive your OTP can reach your readings. '
              'Tell us at $_email if you think someone else has got in.',
        ],
      ),
      PolicySection(
        heading: 'What you may not do',
        bullets: [
          'Upload a photograph of someone else without their knowledge and permission.',
          'Upload anything unlawful, or any image of a child.',
          'Resell, republish or commercially redistribute readings produced by the app.',
          'Attempt to reverse-engineer the app, break its security, or access another user’s '
              'account or data.',
          'Use the app to make decisions about another person — hiring, lending, renting or '
              'anything similar. It is not built for that and must not be used that way.',
        ],
      ),
      PolicySection(
        heading: 'Subscription and payment',
        paragraphs: [
          'Astrolok is a paid subscription. ${SiteCopy.trialPrice} authorises a UPI Autopay '
              'mandate and opens a ${SiteCopy.trialDays}-day trial; after the trial '
              '${SiteCopy.planPrice} is auto-debited every month until you cancel. Payments '
              'are processed by Cashfree Payments.',
          'Prices are in Indian rupees and include applicable taxes. We may change the price, '
              'and if we do we will tell you before the change applies to you — you can cancel '
              'the mandate rather than accept it.',
          'Cancellation and refunds are covered on the Cancellation & Refund page.',
        ],
      ),
      PolicySection(
        heading: 'Features change',
        paragraphs: [
          'We add and remove features. Some are described in the app as coming soon and may '
              'never ship. Nothing on this website or in the app is a promise that a particular '
              'feature will exist by a particular date.',
        ],
      ),
      PolicySection(
        heading: 'Your content',
        paragraphs: [
          'Your photographs and your readings remain yours. You give us only the permission we '
              'need to produce, store and show you your reading — nothing wider, and it ends '
              'when you delete the content or your account.',
        ],
      ),
      PolicySection(
        heading: 'Ending the agreement',
        paragraphs: [
          'You can stop at any time by cancelling your mandate and deleting your account. We '
              'may suspend or close an account that breaks these terms, and where it is fair '
              'to do so we will tell you why first.',
        ],
      ),
      PolicySection(
        heading: 'Liability',
        paragraphs: [
          'We provide the app with reasonable care and skill, but as it is an interpretive '
              'service it is provided "as is". To the extent the law allows, we are not liable '
              'for any decision you take on the basis of a reading, nor for indirect or '
              'consequential loss. Our total liability to you is limited to the amount you '
              'have paid us in the twelve months before the claim.',
          'Nothing here limits liability that cannot lawfully be limited.',
        ],
      ),
      PolicySection(
        heading: 'Governing law',
        paragraphs: [
          'These terms are governed by the laws of India, and the courts at Bengaluru, '
              'Karnataka have exclusive jurisdiction.',
        ],
      ),
      PolicySection(
        heading: 'How to reach us',
        paragraphs: ['Questions about these terms go to $_email.'],
      ),
    ],
  );

  // ---------------------------------------------------------------------------------------
  static const refund = PolicyDoc(
    slug: 'refund',
    title: 'Cancellation & Refund Policy',
    shortTitle: 'Cancellation & Refund',
    intro:
        'How to stop being charged, and when we give money back. The short version: cancel '
        'before the trial ends and nothing further is taken.',
    sections: [
      PolicySection(
        heading: 'The trial',
        paragraphs: [
          'Your first payment of ${SiteCopy.trialPrice} authorises a UPI Autopay mandate and '
              'opens a ${SiteCopy.trialDays}-day trial. If you cancel before the trial ends, '
              'no monthly charge is taken. The ${SiteCopy.trialPrice} itself is a charge for '
              'the trial and is not refundable.',
        ],
      ),
      PolicySection(
        heading: 'How to cancel',
        paragraphs: [
          'The mandate lives in your own UPI app, so that is the fastest place to stop it:',
        ],
        bullets: [
          'Open your UPI app — GPay, PhonePe, Paytm, BHIM or your bank’s app.',
          'Find AutoPay, Mandates or Subscriptions in its menu.',
          'Find the Astrolok mandate and cancel or pause it.',
          'Or write to $_email from your registered number and we will cancel it for you '
              'within two working days.',
        ],
      ),
      PolicySection(
        heading: 'What happens after you cancel',
        paragraphs: [
          'Access continues to the end of the period you have already paid for, and then '
              'stops. Your saved readings stay in the app until you delete them or close your '
              'account. Cancelling does not delete your account — see the account deletion '
              'page for that.',
        ],
      ),
      PolicySection(
        heading: 'Refunds',
        paragraphs: [
          'A monthly subscription is charged for a period of access, so we do not generally '
              'refund part of a month you have already used. We do refund in full where:',
        ],
        bullets: [
          'You were charged after cancelling your mandate.',
          'You were charged twice for the same period.',
          'A technical fault on our side stopped you using the app for most of the period, and '
              'we could not fix it.',
        ],
      ),
      PolicySection(
        heading: 'Asking for a refund',
        paragraphs: [
          'Write to $_email from your registered mobile number within 7 days of the charge, '
              'with the date and amount. We reply within 3 working days. An approved refund '
              'goes back to the account it came from, usually within 5 to 7 working days, '
              'depending on your bank.',
          'A reading you disagree with is not by itself grounds for a refund — readings are '
              'interpretive, which the Terms explain in full.',
        ],
      ),
    ],
  );

  // ---------------------------------------------------------------------------------------
  static const shipping = PolicyDoc(
    slug: 'shipping',
    title: 'Shipping & Delivery Policy',
    shortTitle: 'Shipping & Delivery',
    intro:
        'Astrolok is a digital service. Nothing is posted to you — but our payment processor '
        'requires this page, so here is exactly how delivery works.',
    sections: [
      PolicySection(
        heading: 'Nothing is shipped',
        paragraphs: [
          'There are no physical goods. We will never ask for a postal address, and we do not '
              'charge shipping, handling or delivery fees of any kind.',
        ],
      ),
      PolicySection(
        heading: 'How your purchase is delivered',
        paragraphs: [
          'Access is granted to your account immediately once the payment is confirmed — in '
              'practice within a few seconds. Nothing needs to be downloaded or redeemed, and '
              'there is no code to enter. Sign in with the same mobile number on any supported '
              'phone and your subscription is there.',
        ],
      ),
      PolicySection(
        heading: 'Your readings',
        paragraphs: [
          'A palm or face reading is produced in about a minute and appears in the app as soon '
              'as it is ready. It is saved to Downloads, can be read aloud, and can be '
              'exported as a PDF and shared from your phone.',
        ],
      ),
      PolicySection(
        heading: 'If access does not arrive',
        paragraphs: [
          'If a payment has left your account and the app has not unlocked, first reopen the '
              'app — the check runs again on launch. If it is still locked, write to $_email '
              'with the UPI reference number and we will sort it out within one working day.',
        ],
      ),
    ],
  );

  // ---------------------------------------------------------------------------------------
  static const deleteAccount = PolicyDoc(
    slug: 'delete-account',
    title: 'Delete Your Account',
    shortTitle: 'Delete Account',
    intro:
        'You can close your Astrolok account and have your data erased. Here is what to do and '
        'exactly what goes.',
    sections: [
      PolicySection(
        heading: 'Cancel your mandate first',
        paragraphs: [
          'Deleting your account does not by itself stop a UPI Autopay mandate — that lives '
              'with your bank, not with us. Cancel it in your UPI app first, or ask us to, so '
              'you are not charged after your account is gone. The Cancellation & Refund page '
              'has the steps.',
        ],
      ),
      PolicySection(
        heading: 'How to delete',
        bullets: [
          'In the app: open Profile and choose to delete your account, then confirm.',
          'Or write to $_email from your registered mobile number with the subject "Delete my '
              'account". We complete the deletion within 7 working days and confirm by reply.',
        ],
      ),
      PolicySection(
        heading: 'What is erased',
        bullets: [
          'Your mobile number, your name and your date of birth.',
          'Every reading produced for you, and the copies held on your device.',
          'Your subscription status and your session tokens.',
        ],
      ),
      PolicySection(
        heading: 'What we have to keep',
        paragraphs: [
          'Payment and tax records are kept for as long as Indian tax and accounting law '
              'requires, typically eight years. These are financial records — they contain the '
              'amount, the date and the transaction reference, not your readings or your '
              'photographs.',
          'Your photographs are not on this list: they are deleted as soon as a reading is '
              'produced, long before you close your account.',
        ],
      ),
      PolicySection(
        heading: 'This cannot be undone',
        paragraphs: [
          'Deletion is permanent. Your readings cannot be recovered afterwards, so export any '
              'you want to keep as a PDF first. Signing up again later starts an empty account.',
        ],
      ),
    ],
  );
}

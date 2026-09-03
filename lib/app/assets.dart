/// Every bundled asset path, in one place.
///
/// Each is loaded through a widget that degrades when the file is missing — [SafeImage]'s
/// `errorBuilder`, or [SafeSvg]'s bundle probe — so a renamed or dropped file costs its own box
/// and nothing else, rather than taking a screen down.
abstract final class Img {
  static const _base = 'assets/images';

  /// Full-bleed grounds. Two distinct exports: the onboarding one is nearly white
  /// (`#FFFAF2`), the home one markedly warmer (`#FEF1DC`). They carry the zodiac wheel, sun
  /// burst, sparkles and warm blobs, so nothing else should draw those on top.
  static const bgOnboarding = '$_base/bg_onboarding.png';
  static const bgHome = '$_base/bg_home.png';

  /// The device-framed mockups behind the onboarding sheet. The hero slides through these
  /// while only the sheet below changes.
  static const onboard1 = '$_base/onboard_1.png';
  static const onboard2 = '$_base/onboard_2.png';
  static const onboard3 = '$_base/onboard_3.png';

  static const onboardHero = [onboard1, onboard2, onboard3];

  /// Home's promo card, exported flattened — artwork, heading and button are all pixels, so
  /// the card carries its own Semantics label.
  static const promoChatAstro = '$_base/promo_chat_astro.png';

  /// Thumbnails for the Explore Readings rows, cropped from the home render at a common
  /// 190px square so all three render at the same scale in a 64pt box.
  static const readingChat = '$_base/reading_chat.png';
  static const readingPalm = '$_base/reading_palm.png';
  static const readingFace = '$_base/reading_face.png';

  /// Shown in the paywall's video card until the player is ready, and instead of it when
  /// `paywall_video_url` is empty. Not yet exported.
  static const paywallPoster = '$_base/paywall_poster.png';

  /// Source for `flutter_launcher_icons`.
  static const appIcon = '$_base/app_icon.png';
}

/// The brand marks. Raster exports, so they load through [SafeImage], not [SafeSvg].
abstract final class Brand {
  static const _base = 'assets/icons';

  /// The navy disc with the gold oṃ.
  static const mark = '$_base/om_mark.png';

  /// The full lockup: disc plus "Astrolok" in two tones.
  static const wordmark = '$_base/wordmark.png';
}

/// Vector assets. Still to be exported — every reference falls back to a Material icon, which
/// is why the paywall and Home read correctly without them.
abstract final class Svg {
  static const _base = 'assets/icons';

  static const profile = '$_base/profile.svg';
  static const chevronRight = '$_base/chevron_right.svg';
  static const soundOn = '$_base/sound_on.svg';
  static const soundOff = '$_base/sound_off.svg';

  static const featurePersonalized = '$_base/feature_personalized.svg';
  static const featureFacePalm = '$_base/feature_face_palm.svg';
  static const featureLove = '$_base/feature_love.svg';
  static const featureUnlimited = '$_base/feature_unlimited.svg';
}

/// Every bundled asset path, in one place.
///
/// None of these files exist yet — the artwork is still being exported from Figma. Each one is
/// loaded through a widget that degrades when the file is missing (`Image.asset`'s
/// `errorBuilder`, or [SafeSvg]), so the app builds and every screen lays out correctly today
/// and simply gains the artwork as each file lands. A screen that only looks right once an
/// asset exists would break again the day one is renamed.
abstract final class Img {
  static const _base = 'assets/images';

  /// The cream ground's zodiac wheel, sun burst and sparkles, drawn over the gradient.
  static const backdrop = '$_base/bg_astral.png';

  /// The astrologer artwork on Home's promo card.
  static const promoChatAstro = '$_base/hero_chat_astro.png';

  /// Thumbnails for the Explore Readings rows.
  static const readingChat = '$_base/reading_chat.png';
  static const readingPalm = '$_base/reading_palm.png';
  static const readingFace = '$_base/reading_face.png';

  /// Device-framed screenshots behind the onboarding sheet. The hero slides through these
  /// while only the sheet below changes.
  static const onboardHome = '$_base/onboard_home.png';
  static const onboardPalm = '$_base/onboard_palm.png';
  static const onboardFace = '$_base/onboard_face.png';

  /// Shown in the paywall's video card until the player is ready, and instead of it when
  /// `paywall_video_url` is empty.
  static const paywallPoster = '$_base/paywall_poster.png';
}

abstract final class Svg {
  static const _base = 'assets/icons';

  /// The navy disc with the gold oṃ. Paired with a drawn wordmark in [BrandLogo].
  static const omMark = '$_base/om_mark.svg';

  static const profile = '$_base/profile.svg';
  static const chevronRight = '$_base/chevron_right.svg';
  static const soundOn = '$_base/sound_on.svg';
  static const soundOff = '$_base/sound_off.svg';

  /// The paywall's four feature discs.
  static const featurePersonalized = '$_base/feature_personalized.svg';
  static const featureFacePalm = '$_base/feature_face_palm.svg';
  static const featureLove = '$_base/feature_love.svg';
  static const featureUnlimited = '$_base/feature_unlimited.svg';
}

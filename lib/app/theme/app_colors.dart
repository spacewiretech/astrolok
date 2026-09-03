import 'package:flutter/material.dart';

/// The app palette, read off the Figma renders.
///
/// A warm cream ground with a navy/gold pair: navy carries headings and the logo disc, gold
/// carries every call to action. Screens reference these names rather than raw hex, so a
/// correction to the design is an edit to this file alone.
abstract final class AppColors {
  /// The brand colour. Filled buttons, focus rings, chevrons, the selected wheel row, and the
  /// accent word in a two-tone heading ("Astro**lok**", "Read Your **Palm**").
  static const gold = Color(0xFFF4B835);

  /// A shade down, for the pressed state and the gold gradient's far end.
  static const goldDeep = Color(0xFFE2A21D);

  /// Behind gold icons — the paywall's feature discs, the chevron circles.
  static const goldWash = Color(0xFFFDF1DC);

  /// Headings, the logo disc, and the dark filled buttons on the reading screens. Sampled
  /// from the exported logo rather than guessed — it is nearly black, not a mid navy.
  static const navy = Color(0xFF000C2B);

  /// [gold] under its old name. `PrimaryButton` and the OTP focus ring read this.
  static const brand = gold;

  static const heading = navy;
  static const body = Color(0xFF44506B);
  static const muted = Color(0xFF6E7280);

  // ---------------------------------------------------------------- ground

  /// Fallback grounds, sampled from the two background exports. The real screens render those
  /// images; these show only if a file is missing, and are tuned so that case still looks
  /// deliberate rather than broken.
  ///
  /// Onboarding is nearly white; home is markedly warmer. Two distinct grounds, not one.
  static const cream = Color(0xFFFFFAF2);
  static const creamMid = Color(0xFFFFFCFA);
  static const creamDeep = Color(0xFFFFF6E4);

  static const homeCream = Color(0xFFFEF1DC);
  static const homeCreamMid = Color(0xFFFEF9F1);
  static const homeCreamDeep = Color(0xFFFEE5B5);

  /// Strength of the drawn ornaments used only in the onboarding hero placeholder.
  static const ornament = Color(0x33E0A93B);

  // ---------------------------------------------------------------- surfaces

  static const surface = Color(0xFFFFFFFF);

  /// Kept as the Scaffold colour for screens that do not use [cream]'s gradient.
  static const scaffold = cream;

  /// Card and sheet outlines — barely there, which is what the design uses instead of shadow.
  static const border = Color(0xFFF1EBE0);

  /// A stronger outline for a field at rest, before it takes focus.
  static const fieldBorder = Color(0xFFD9D2C4);

  /// The date-of-birth picker card. Sampled from the render, where it is a single uniform
  /// fill top to bottom — there is no selection band behind the chosen row.
  static const wheelCard = Color(0xFFFEFAF0);

  /// The dark promo card on Home, behind the astrologer artwork.
  static const promoInk = Color(0xFF120C06);

  static const divider = Color(0xFFEFE8DC);

  /// Fills the soft card backgrounds — the billing warning, the paywall toast.
  static const cardSoft = Color(0xFFFDF6E8);

  // ---------------------------------------------------------------- semantic

  static const success = Color(0xFF16A34A);
  static const danger = Color(0xFFE5484D);
  static const warning = gold;

  /// The four reading categories, used by the Palm and Face screens.
  static const love = Color(0xFFE5484D);
  static const career = Color(0xFF8B5CF6);
  static const personality = gold;
  static const money = Color(0xFF16A34A);

  /// The fifth, added for the palm lines. The head line reads blue in the design and none of
  /// the four above is one — gold and red are spoken for, and tinting it purple would make it
  /// read as a second fate line.
  static const insight = Color(0xFF3B82F6);

  /// Behind modal bottom sheets.
  static const scrim = Color(0x660B1739);

  /// Lifts cards and sheets off the cream ground. Soft and warm rather than grey — a neutral
  /// shadow reads as dirt against this background.
  static const floatingShadow = BoxShadow(
    color: Color(0x14A9752A),
    blurRadius: 24,
    offset: Offset(0, 8),
  );

  /// The sheet that covers the lower half of the onboarding screen.
  static const sheetShadow = BoxShadow(
    color: Color(0x1F8A6320),
    blurRadius: 32,
    offset: Offset(0, -6),
  );

  /// Fallback ground for the onboarding and birth screens.
  static const backdrop = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [cream, creamMid, creamDeep],
    stops: [0.0, 0.55, 1.0],
  );

  /// Fallback ground for home and the paywall.
  static const backdropWarm = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [homeCream, homeCreamMid, homeCreamDeep],
    stops: [0.0, 0.55, 1.0],
  );

  /// The gold on a filled button, very slightly graded as in the renders.
  static const goldFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [gold, goldDeep],
  );
}

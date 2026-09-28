import 'package:flutter/material.dart';

/// The chat's own colours: WhatsApp's, so the screen is familiar before a word is read.
///
/// Apart from `AppColors` on purpose. The rest of the app is cream, navy and gold; this one screen
/// borrows the look people already chat in every day, and the two palettes should not be mixed up
/// by someone reaching for "the green" elsewhere. Light only — the app has no dark theme.
abstract final class ChatPalette {
  /// The bar across the top, and the round send button's neighbour.
  static const appBar = Color(0xFF008069);
  static const onAppBar = Colors.white;
  static const onAppBarMuted = Color(0xDDFFFFFF);

  /// Behind the conversation, and the faint doodles drawn over it.
  static const wallpaper = Color(0xFFEFEAE2);
  static const doodle = Color(0x1A7A6A55);

  /// Astro's messages, and the person's own.
  static const incoming = Colors.white;
  static const outgoing = Color(0xFFD9FDD3);

  static const text = Color(0xFF111B21);

  /// Times, ticks at rest, the "typing…" dots.
  static const meta = Color(0xFF667781);

  /// Two ticks, read.
  static const tick = Color(0xFF53BDEB);

  static const send = Color(0xFF00A884);

  /// The reply buttons under Astro's newest message — WhatsApp's own teal link colour.
  static const button = Color(0xFF008069);

  /// The day's chip ("Today"), and the yellow note at the top of a conversation.
  static const chip = Color(0xF2FFFFFF);
  static const onChip = Color(0xFF54656F);
  static const notice = Color(0xFFFFEECD);
  static const onNotice = Color(0xFF54656F);

  static const shadow = Color(0x21000000);
}

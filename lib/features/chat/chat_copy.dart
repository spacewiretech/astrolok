/// Every word the chat says, in one place.
///
/// Kept apart from the layouts so that rewording — which happens often, and often by someone
/// who is not editing widgets that day — never touches a Column.
abstract final class ChatCopy {
  static const titleLead = 'Chat with';
  static const titleAccent = 'Astro';

  // ---------------------------------------------------------------- opening

  static const openingGreeting = 'What would you like to ask?';
  static const openingSubtitle =
      'Astro reads your chart, your palm and your face — and remembers what you tell it.';

  // ---------------------------------------------------------------- composer

  static const placeholder = 'Ask Astro';
  static const send = 'Send';

  /// Shown in the composer's place once the day's questions are gone. A standing condition, not
  /// an error: there is nothing to retry, so the field closes rather than inviting another try.
  static const exhausted = "You've asked Astro everything for today. Come back tomorrow.";

  // ---------------------------------------------------------------- waiting

  /// Under the oṃ disc while the reply is in flight. In the sage's own register, because a
  /// spinner would break the one thing this screen is trying to be.
  static const thinking = 'Consulting the stars…';

  // ---------------------------------------------------------------- asking back

  static const birthTimePrompt = 'Set the hour you were born';
  static const birthTimeAction = 'Choose a time';
  static const birthTimeUnknown = 'I do not know';

  static const birthPlacePrompt = 'Where were you born?';
  static const birthPlaceHint = 'City or town';

  // ---------------------------------------------------------------- narration

  static const listen = 'Listen';
  static const stopListening = 'Stop';

  // ---------------------------------------------------------------- failures

  static const sendFailed = 'That did not reach Astro. Please try again.';

  // ---------------------------------------------------------------- memory

  static const memoryHeading = 'What Astro remembers';
  static const memorySubtitle =
      'Things you have told Astro. It uses these to read for you.';
  static const memoryEmpty =
      'Nothing yet. What you tell Astro in conversation will appear here.';
  static const forgetAll = 'Forget everything';
  static const forgetAllTitle = 'Forget everything?';
  static const forgetAllBody =
      'Astro will lose everything it has learned about you. Your conversation stays.';
  static const forgetAllConfirm = 'Forget it all';
  static const forgetAllDismiss = 'Keep it';
  static const forgetFailed = "Couldn't update what Astro remembers.";
}

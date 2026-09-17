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

  // ---------------------------------------------------------------- rating

  static const ratingPrompt = 'How is your chat with Astro so far?';
  static const ratingThanks = 'Thank you — this helps Astro read better for you.';
  static const ratingDismiss = 'Not now';
  static const ratingSubmit = 'Submit';

  /// Placeholder in the text box under the faces. It says "optional" in the box itself, because an
  /// unlabelled field reads as required, and a required essay is how a two-second rating is
  /// abandoned.
  static const feedbackHint = 'Your thoughts (optional)';

  /// Worst to best, read by a screen reader in place of each face.
  static const ratingLabels = ['Very bad', 'Not good', 'Okay', 'Good', 'Loved it'];

  // ---------------------------------------------------------------- waiting

  /// Under the oṃ disc while the reply is in flight. In the sage's own register, because a
  /// spinner would break the one thing this screen is trying to be.
  static const thinking = 'Consulting the stars…';

  // ---------------------------------------------------------------- asking back

  static const birthTimeAction = 'Share my birth time';

  /// Sent as the user's own words, so it stays a sentence rather than a button label.
  static const birthTimeUnknown = 'I do not know';

  static const birthPlacePrompt = 'Where were you born?';
  static const birthPlaceHint = 'City or town';
  static const birthPlaceAction = 'Type my birthplace';

  // The note under the verdict. The question itself is written at the foot of the reply, which is
  // exactly where a reader who stopped at the answer never gets to.
  static const askTimeHeading = 'Astro is asking for your birth time';
  static const askTimeReason =
      'Your exact hour reveals your nakshatra, and sharpens every answer that follows.';
  static const askPlaceHeading = 'Astro is asking where you were born';
  static const askPlaceReason = 'Your birthplace tunes the chart to the sky you were born under.';

  // ---------------------------------------------------------------- the birth time sheet

  static const timeSheetTitle = 'The moment you arrived';
  static const timeSheetWhy =
      'The hour you were born decides your nakshatra — the star you were born beneath.';
  static const timeSheetWhere =
      'Look on your birth certificate or janam patri, or ask your mother or family.';
  static const timeSheetStepDay = 'When in the day were you born?';

  static const partEarlyMorning = 'Early morning';
  static const partEarlyMorningRange = '4 – 8 AM';
  static const partMorning = 'Morning';
  static const partMorningRange = '8 AM – 12 noon';
  static const partAfternoon = 'Afternoon';
  static const partAfternoonRange = '12 – 4 PM';
  static const partEvening = 'Evening';
  static const partEveningRange = '4 – 8 PM';
  static const partNight = 'Night';
  static const partNightRange = '8 PM – 12 midnight';
  static const partAfterMidnight = 'After midnight';
  static const partAfterMidnightRange = '12 – 4 AM';

  static const timeSheetStepExact = 'Now turn to the exact hour and minute';
  static const timeSheetHour = 'Hour';
  static const timeSheetMinute = 'Minute';
  static const timeSheetPeriod = 'AM/PM';

  /// Until a part of the day is chosen there is no time to confirm, and the button says so rather
  /// than offering one the user never picked.
  static const timeSheetPickFirst = 'Choose a part of the day';
  static String timeSheetConfirm(String time) => 'Confirm $time';
  static const timeSheetUnknown = "I don't know my birth time";

  // ---------------------------------------------------------------- narration

  static const listen = 'Listen';
  static const stopListening = 'Stop';

  /// Astro's name over each reply, beside the listen control.
  static const speaker = 'Astro';

  // ---------------------------------------------------------------- conversations

  static const conversations = 'Your conversations';
  static const newChat = 'New chat';
  static const openConversations = 'Your conversations';

  /// For a conversation whose first reply never landed, so the server never named it.
  static const untitledThread = 'New conversation';

  static const threadsEmpty =
      'Nothing here yet. Every conversation you start with Astro is kept.';

  static const renameThread = 'Rename';
  static const renameThreadTitle = 'Rename this conversation';
  static const renameThreadHint = 'What to call it';
  static const renameThreadConfirm = 'Rename';

  static const deleteThread = 'Delete';
  static const deleteThreadTitle = 'Delete this conversation?';

  /// Says plainly what survives, because it is not obvious and the difference matters: the
  /// transcript goes, the memory does not.
  static const deleteThreadBody =
      'This conversation goes for good. What Astro remembers about you stays.';
  static const deleteThreadConfirm = 'Delete it';
  static const deleteThreadDismiss = 'Keep it';
  static const deleteThreadFailed = "Couldn't delete that conversation.";

  // The four buckets the sidebar groups conversations into.
  static const ageToday = 'Today';
  static const ageYesterday = 'Yesterday';
  static const ageWeek = 'Previous 7 days';
  static const ageOlder = 'Older';

  // ---------------------------------------------------------------- failures

  static const sendFailed = 'That did not reach Astro. Please try again.';

  /// The conversation was deleted elsewhere, or aged out. Not a retry — the screen opens a new
  /// one, and this explains why what they tapped is not what they got.
  static const threadGone = 'That conversation is no longer here. Starting a new one.';

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

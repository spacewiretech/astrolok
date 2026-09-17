/// Every string the kundali screens show.
///
/// One rule runs through the waiting copy: the reading is *revealed* at a time. The chart is cast in
/// milliseconds and the reading written within minutes, so nothing here claims the calculation
/// takes a day — it says when the Kundali will be revealed, which is true.
abstract final class KundaliCopy {
  // ---------------------------------------------------------------- home card

  static const cardTitle = 'Kundali Chart';
  static const cardSubtitle = 'Discover your life path through your birth chart.';
  static const cardReady = 'Ready ✨';
  static const cardReadySubtitle = 'Your Kundali has been revealed. Tap to view.';
  static const cardAlmost = 'Almost ready';
  static const cardFailed = 'Tap to try again';
  static String cardWaiting(String left) => 'Ready in $left';
  static const cardWaitingSubtitle = 'Your birth chart is being prepared.';

  // ---------------------------------------------------------------- form

  static const formTitleLead = 'Your';
  static const formTitleAccent = 'Kundali';
  static const formSubtitle =
      'Enter your birth details to generate your personalized Kundali and get accurate insights.';
  static const dobTitle = 'Date of Birth';
  static const dobHint = 'DD/MM/YYYY';
  static const timeTitle = 'Time of Birth';
  static const timeHint = 'eg: 10:30';
  static const timeHelp = 'Enter the exact time as per your birth certificate (for more accurate results).';
  static const placeTitle = 'Birth Place';
  static const placeHint = 'eg: Tirupati';
  static const placeUnavailable = 'Place search is unavailable right now. Please try again shortly.';
  static const generate = 'Generate';
  static const update = 'Re-cast my Kundali';
  static const pickDob = 'Choose your date of birth';
  static const done = 'Done';
  static const missingDob = 'Please choose your date of birth.';
  static const missingTime = 'Please choose your time of birth.';
  static const missingPlace = 'Please choose your birth place from the list.';
  static const requestFailed = 'Could not start your Kundali. Please try again.';

  static const regenerateTitle = 'Re-cast your Kundali?';
  static String regenerateBody(int left) =>
      'A new chart will be cast from these details and revealed after a fresh wait. '
      'You can do this $left more ${left == 1 ? 'time' : 'times'}.';
  static const regenerateConfirm = 'Re-cast';
  static const cancel = 'Cancel';

  // ---------------------------------------------------------------- waiting

  static const waitingTitleLead = 'Your Kundali is';
  static const waitingTitleAccent = 'being prepared';
  static String waitingSubtitle(String when) =>
      'Your chart is being cast from the exact moment and place of your birth. It will be revealed $when.';
  static const revealedIn = 'Revealed in';
  static const almostTitle = 'Almost ready';
  static const almostBody = 'The finishing touches are taking a little longer than usual. We will check again shortly.';
  static const failedTitle = 'We could not finish your Kundali';
  static const failedBody = 'Something went wrong while preparing your reading. Try again — it will not use up a re-cast.';
  static const failedAction = 'Try again';

  static const teaserKicker = 'A FIRST GLIMPSE';
  static String teaser(String rashi, String? sign) => 'Your Chandra — the Moon — is in $rashi${sign == null ? '' : ' ($sign)'}';
  static String teaserNakshatra(String nakshatra, int? pada) =>
      '$nakshatra nakshatra${pada == null ? '' : ', pada $pada'}';

  static const stagesTitle = 'What is being prepared';
  static const stagePositions = 'Planetary positions cast';
  static const stageLagna = 'Lagna & 12 houses mapped';
  static const stageDasha = 'Dasha periods traced';
  static const stageInsights = 'Your life insights written';
  static const stageActiveDetail = 'In progress…';

  static const notifyMe = 'Notify me when ready';
  static const notifyOn = "We'll notify you the moment it's ready";
  static const notifyBlocked = 'Notifications are off for Astrolok. Turn them on in Settings to be told when it is ready.';

  static const whileYouWait = 'While you wait';
  static const editDetails = 'Edit birth details';

  // ---------------------------------------------------------------- report

  static const reportTitleLead = 'Detailed';
  static const reportTitleAccent = 'Kundali';
  static const reportSubtitle = 'Explore the cosmic blueprint of your life';
  static const chartTitle = 'Kundali Chart';
  static const highlightsTitle = 'Planetary Highlights';
  static const insightsTitle = 'Key Life Insights';
  static const dashaTitle = 'Your Dasha Periods';
  static const housesTitle = 'The 12 Houses';
  static const download = 'Download Full Kundali Report';
  static const pdfFailed = 'Could not create the PDF. Please try again.';
  static const loadFailed = 'Could not open your Kundali. Please try again.';
  static const retry = 'Try again';
  static const askAstroTitle = 'Ask Astro about your Kundali';
  static const askAstroSubtitle = 'Go deeper into any house, graha or period.';
  static const tip = 'Tip';
  static const readFrom = 'Read from';
  static const lagna = 'Lagna';
  static const now = 'Now';

  static String planetIn(String english, String sign) => '$english in $sign';

  static String insightTitle(String key) => switch (key) {
        'love' => 'Love & Relationships',
        'career' => 'Career & Profession',
        'finance' => 'Finance & Wealth',
        'year_ahead' => 'Year Ahead',
        _ => key,
      };

  static String phase(String phase) => switch (phase) {
        'early' => 'early',
        'middle' => 'midway',
        'late' => 'late',
        _ => phase,
      };

  static String askAstroOpener(String lagna) =>
      'I just read my Kundali — my lagna is $lagna. What does my chart say about the season I am in?';
}

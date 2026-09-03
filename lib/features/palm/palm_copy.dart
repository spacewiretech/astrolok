/// Every word the palm flow says, in one place.
///
/// Kept apart from the layouts so that rewording — which happens often, and often by someone
/// who is not editing widgets that day — never touches a Column.
abstract final class PalmCopy {
  static const steps = ['Capture', 'Scan', 'Reading'];

  // ---------------------------------------------------------------- capture

  static const captureTitleLead = 'Show us your';
  static const captureTitleAccent = 'Palm';
  static const captureSubtitle = 'Place your palm inside the frame';

  /// Before a capture nothing on the device has looked at the frame, so this says what to do
  /// rather than claiming a detection that has not happened.
  static const framePrompt = 'Fill the frame with your palm';
  static const frameDetected = 'Hand Detected';

  static const scanAction = 'Scan Palm';
  static const galleryAction = 'Upload from gallery';
  static const privacyNote = 'Your images are private and secure';

  static const tipLighting = 'Good\nLighting';
  static const tipOpenHand = 'Open your\nhand';
  static const tipSharpPhoto = 'Avoid blurry\nphotos';

  static const cameraDenied = 'Astrolok needs camera access to read your palm.';
  static const cameraDeniedForever =
      'Camera access is off for Astrolok. Turn it on in Settings to read your palm.';
  static const cameraUnavailable =
      "This device's camera isn't available. You can upload a photo instead.";
  static const allowCamera = 'Allow camera';
  static const openSettings = 'Open Settings';

  static const captureFailed = "That photo didn't come through. Please try again.";

  /// Shown when the bytes could not be turned into an image at all.
  ///
  /// Not "too large", which is what this used to say: every preparation failure came out
  /// under that one message, so a plugin error read as a size problem and sent people off
  /// shrinking photos that were never the issue. An error message that names the wrong cause
  /// is worse than a vague one.
  static const imageUnreadable =
      "We couldn't read that photo. Try taking it again.";

  // ---------------------------------------------------------------- scan

  static const scanTitleLead = 'Analysing your';
  static const scanTitleAccent = 'Palm';
  static const scanSubtitle =
      'Our AI is reading the lines and patterns to reveal your insights.';
  static const scanFooter = 'This may take a few seconds';

  static const stageDetecting = 'Detecting\nlines';
  static const stageTraits = 'Analysing\nTraits';
  static const stagePatterns = 'Reading\npatterns';
  static const stageInsights = 'Preparing\ninsights';

  /// Advanced by elapsed time and then held on the last one — see `PalmScanState.statusLine`.
  /// Wrapping back to the first would read as the scan having restarted.
  static const statusLines = [
    'Looking at your palm…',
    'Mapping the major lines…',
    'Following your life line…',
    'Reading your heart line…',
    'Weighing the mounts and the skin…',
    'Reading your head line…',
    'Pulling the threads together…',
    'Almost there…',
  ];

  static const didYouKnow = 'Did you know?';

  /// Cycled and allowed to wrap — these are ambient, not progress.
  static const facts = [
    'Your palm lines can change over time as you grow and experience life.',
    'No two palms are alike — even identical twins have different lines.',
    'Palmistry is thousands of years old and reached Europe from India.',
    'The hand you write with is read for who you have become; the other, for what you were born with.',
    'The mounts — the pads below each finger — matter as much as the lines.',
    'Fine, densely drawn lines often belong to people who think in detail.',
  ];

  static const cancelTitle = 'Cancel this reading?';
  static const cancelBody = "Your palm is still being read. Leaving now will discard it.";
  static const cancelConfirm = 'Discard';
  static const cancelDismiss = 'Keep reading';

  static const slowTitle = "That's taking longer than usual.";
  static const slowBody = 'Your palm is still with our reader. You can wait, or try again.';
  static const tryAgain = 'Try again';
  static const useAnotherPhoto = 'Use another photo';

  // ---------------------------------------------------------------- reading

  static const readingTitleLead = 'Your Palm has a';
  static const readingTitleAccent = 'Story';
  static const readingSubtitle = "Here's what your palm reveals";
  static const strongestTrait = 'Your Strongest Trait';
  static const linesHeading = 'Your Palm lines';
  static const handHeading = 'What your hand shows';
  static const moreHeading = 'Want to know more?';

  static const askAstroTitle = 'Ask Astro about your palm';
  static const askAstroSubtitle = 'Get personalised answers for all your questions';

  static const meansForYou = 'What it means for you';
  static const tip = 'Tip';

  static const listen = 'Listen';
  static const stopListening = 'Stop';
  static const download = 'Download as PDF';

  static const pdfFailed = "Couldn't create the PDF. Please try again.";
  static const readingMissing =
      "We couldn't find that reading. Try reading your palm again.";

  /// Printed at the foot of every page of the export, because a PDF gets forwarded and has to
  /// carry its own framing.
  static const disclaimer =
      'Astrolok · For guidance and reflection. Not medical, legal or financial advice.';

  static String focusLabel(String label) => 'Focus: $label';
}

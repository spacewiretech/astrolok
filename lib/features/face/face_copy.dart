/// Every word the face flow says, in one place.
///
/// Kept apart from the layouts so that rewording — which happens often, and often by someone
/// who is not editing widgets that day — never touches a Column.
abstract final class FaceCopy {
  static const steps = ['Capture', 'Analysing', 'Reading'];

  // ---------------------------------------------------------------- capture

  static const captureTitleLead = 'Show us your';
  static const captureTitleAccent = 'Face';
  static const captureSubtitle = 'Place your Face inside the frame';

  /// Before a capture nothing on the device has looked at the frame, so this says what to do
  /// rather than claiming a detection that has not happened.
  static const framePrompt = 'Fill the frame with your face';
  static const frameDetected = 'Face Detected';

  static const takePhotoAction = 'Take a photo';
  static const galleryAction = 'Upload from gallery';
  static const privacyNote = 'Your images are private and secure';

  static const tipLighting = 'Good\nLighting';
  static const tipLookStraight = 'Look\nStraight';
  static const tipSharpPhoto = 'Avoid blurry\nphotos';

  static const cameraDenied = 'Astrolok needs camera access to read your face.';
  static const cameraDeniedForever =
      'Camera access is off for Astrolok. Turn it on in Settings to read your face.';
  static const cameraUnavailable =
      "This device's camera isn't available. You can upload a photo instead.";
  static const allowCamera = 'Allow camera';
  static const openSettings = 'Open Settings';

  static const captureFailed = "That photo didn't come through. Please try again.";

  /// Shown when the bytes could not be turned into an image at all — a plugin failure, or a
  /// format nothing on the device can decode. Deliberately not "too large": naming the wrong
  /// cause sends people off shrinking photos that were never the problem.
  static const imageUnreadable = "We couldn't read that photo. Try taking it again.";

  // ---------------------------------------------------------------- scan

  static const scanTitleLead = 'Analysing your';
  static const scanTitleAccent = 'Face';
  static const scanSubtitle = 'Discovering the patterns that make you unique';
  static const scanFooter = 'This may take a few seconds';

  /// The four checklist rows. Unlike the palm screen's chips these are a vertical list with a
  /// tick each, matching the design — and each names something a reader would actually do.
  static const stageShape = 'Analyzing face shape';
  static const stageEyes = 'Reading eyes & expression';
  static const stageMapping = 'Mapping facial features';
  static const stagePreparing = 'Preparing your reading';

  static const stageInProgress = 'In progress';

  /// Advanced by elapsed time and then held on the last one — see `FaceScanState.statusLine`.
  /// Wrapping back to the first would read as the reading having restarted.
  static const statusLines = [
    'Settling in with your photograph…',
    'Taking in the shape of your face…',
    'Reading your eyes…',
    'Weighing the brow and the forehead…',
    'Noting the set of your mouth…',
    'Listening to what the features agree on…',
    'Drawing the threads together…',
    'Almost there…',
  ];

  static const didYouKnow = 'Did you know?';

  /// Cycled and allowed to wrap — these are ambient, not progress.
  static const facts = [
    'Samudrika Shastra, the science of reading the body, is described in texts over two thousand years old.',
    'The old readers divided the face into three zones — brow, mid-face and jaw — and read the balance between them.',
    'The eyes are traditionally called the lamps of the soul, and are read first.',
    'A face is never read for beauty. It is read for temperament, and the two have nothing to do with each other.',
    'Your expression at rest is read more closely than your smile — it is the one you wear most.',
    'No two faces are alike, and neither are the two halves of your own.',
  ];

  static const cancelTitle = 'Cancel this reading?';
  static const cancelBody = 'Your face is still being read. Leaving now will discard it.';
  static const cancelConfirm = 'Discard';
  static const cancelDismiss = 'Keep reading';

  static const slowTitle = "That's taking longer than usual.";
  static const slowBody = 'Your photo is still with our reader. You can wait, or try again.';

  /// Shown instead of [slowTitle] when the reading failed too quickly to blame the wait.
  static const failedTitle = "We couldn't finish that reading.";
  static const tryAgain = 'Try again';
  static const useAnotherPhoto = 'Use another photo';

  // ---------------------------------------------------------------- reading

  static const readingTitleLead = 'Your';
  static const readingTitleAccent = 'Face';
  static const readingTitleTail = ' Readings';
  static const readingSubtitle = "Here's what your face reveals about you.";

  static const coreTrait = 'Your core Trait';
  static const partsHeading = 'Your Face Reveals';
  static const observationsHeading = 'What we could see';
  static const moreHeading = 'Want to know more?';

  static const askAstroTitle = 'Ask Astro about your face';
  static const askAstroSubtitle = 'Get personalised answers for all your questions';

  static const meansForYou = 'What it means for you';
  static const tip = 'Tip';

  /// The label above the closing ashirvad, on the results screen and in the export.
  static const blessingHeading = 'A blessing for you';

  static const listen = 'Listen';
  static const stopListening = 'Stop';
  static const download = 'Download as PDF';

  static const pdfFailed = "Couldn't create the PDF. Please try again.";
  static const readingMissing =
      "We couldn't find that reading. Try reading your face again.";

  static String askAstroAbout(String part) => 'Ask Astro about your $part';

  static String focusLabel(String label) => 'Focus: $label';
}

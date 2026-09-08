/// Every event name and property key the app can send.
///
/// Constants rather than string literals at the call sites, for one reason that matters more than
/// tidiness: a typo in an event name does not fail, it *forks*. `Palm Focus Selected` and
/// `Palm focus selected` become two unrelated columns in Mixpanel, both half-populated, and the
/// only symptom is a funnel that quietly under-counts. The compiler cannot check a string; it can
/// check these.
///
/// Naming: events are Title Case past tense — the thing already happened by the time it is
/// recorded. Properties are snake_case, which is what Mixpanel's own breakdowns expect.
library;

/// Event names.
abstract final class Ev {
  // ---------------------------------------------------------------- lifecycle

  static const appLaunched = 'App Launched';
  static const sessionStarted = 'Session Started';
  static const sessionEnded = 'Session Ended';
  static const appForegrounded = 'App Foregrounded';
  static const appBackgrounded = 'App Backgrounded';
  static const appTerminated = 'App Terminated';
  static const appCrashed = 'App Crashed';

  /// Bracket the trip out to a UPI app. The gap between them is time the user spent in GPay or
  /// PhonePe, which would otherwise read as time spent staring at our paywall.
  static const upiAppOpened = 'UPI App Opened';
  static const upiAppReturned = 'UPI App Returned';

  // ---------------------------------------------------------------- navigation

  static const screenViewed = 'Screen Viewed';
  static const screenExited = 'Screen Exited';
  static const backPressed = 'Back Pressed';

  /// Every tap on a shared widget. The screen it happened on is filled in by the observer, so no
  /// call site passes it.
  static const elementTapped = 'Element Tapped';

  /// Anything the user was shown as a failure, wherever it came from.
  static const errorShown = 'Error Shown';

  /// A backend call that did not succeed. Fired from the one chokepoint every Edge Function call
  /// passes through, so backend health needs no per-feature instrumentation.
  static const edgeCallFailed = 'Edge Call Failed';

  // ---------------------------------------------------------------- splash

  static const splashResolved = 'Splash Resolved';

  // ---------------------------------------------------------------- onboarding

  static const phoneEntryStarted = 'Phone Entry Started';
  static const phoneNumberEntered = 'Phone Number Entered';
  static const otpEntryStarted = 'OTP Entry Started';
  static const otpRequested = 'OTP Requested';
  static const otpRequestFailed = 'OTP Request Failed';
  static const otpResendBlocked = 'OTP Resend Blocked';
  static const otpResendRequested = 'OTP Resend Requested';
  static const otpSubmitted = 'OTP Submitted';
  static const otpVerified = 'OTP Verified';
  static const otpVerificationFailed = 'OTP Verification Failed';
  static const otpAttemptsExhausted = 'OTP Attempts Exhausted';
  static const nameEntryStarted = 'Name Entry Started';
  static const nameSubmitted = 'Name Submitted';
  static const nameSaveFailed = 'Name Save Failed';
  static const signupCompleted = 'Signup Completed';
  static const signedOut = 'Signed Out';

  // ---------------------------------------------------------------- birth

  static const birthEntryStarted = 'Birth Entry Started';
  static const birthWheelChanged = 'Birth Wheel Changed';
  static const birthDateSubmitted = 'Birth Date Submitted';
  static const birthSaveFailed = 'Birth Save Failed';

  // ---------------------------------------------------------------- paywall

  static const paywallViewed = 'Paywall Viewed';
  static const paywallOfferLoaded = 'Paywall Offer Loaded';
  static const paywallOfferLoadFailed = 'Paywall Offer Load Failed';
  static const promoVideoToggled = 'Promo Video Toggled';

  static const upiPickerOpened = 'UPI Picker Opened';
  static const upiPickerDismissed = 'UPI Picker Dismissed';
  static const upiAppPreselected = 'UPI App Preselected';
  static const upiAppChanged = 'UPI App Changed';
  static const upiAppsDiscovered = 'UPI Apps Discovered';
  static const upiDiscoveryFailed = 'UPI Discovery Failed';

  static const subscribeTapped = 'Subscribe Tapped';
  static const subscribeTapIgnored = 'Subscribe Tap Ignored';
  static const mandateStartRequested = 'Mandate Start Requested';
  static const mandateStartSucceeded = 'Mandate Start Succeeded';
  static const mandateStartRefused = 'Mandate Start Refused';
  static const mandateAlreadyEntitled = 'Mandate Already Entitled';
  static const upiIntentLaunched = 'UPI Intent Launched';

  static const checkoutVerifiedCallback = 'Checkout Verified Callback';
  static const checkoutFailedCallback = 'Checkout Failed Callback';
  static const checkoutOrphanCallback = 'Checkout Orphan Callback';
  static const checkoutRestarted = 'Checkout Restarted';
  static const checkoutLaunchFailed = 'Checkout Launch Failed';
  static const checkoutTimedOut = 'Checkout Timed Out';

  static const entitlementPollStarted = 'Entitlement Poll Started';
  static const entitlementPollFailed = 'Entitlement Poll Failed';
  static const entitlementLapsed = 'Entitlement Lapsed';

  /// The one event with money on it. Timed with the SDK's own stopwatch, so `$duration` survives
  /// the app being backgrounded for the whole UPI hand-off.
  static const paymentCompleted = 'Payment Completed';

  static const paymentStatusViewed = 'Payment Status Viewed';
  static const paymentStatusChecked = 'Payment Status Checked';
  static const paymentConfirmedLate = 'Payment Confirmed Late';
  static const paymentStatusExhausted = 'Payment Status Exhausted';
  static const retryPaymentTapped = 'Retry Payment Tapped';

  // ---------------------------------------------------------------- home

  static const homeViewed = 'Home Viewed';
  static const promoSlideViewed = 'Promo Slide Viewed';
  static const readingCardTapped = 'Reading Card Tapped';
  static const billingIssueShown = 'Billing Issue Shown';
  static const manageBillingTapped = 'Manage Billing Tapped';

  // ---------------------------------------------------------------- readings
  //
  // Palm and face share one vocabulary, separated by [P.feature]. The two flows are exact code
  // mirrors — capture, scan, reading, detail — so one funnel answers "how many captures become
  // readings" across both *and* per feature. Two parallel vocabularies would mean building every
  // reading funnel twice and keeping them in step forever.

  static const readingCaptureOpened = 'Reading Capture Opened';
  static const cameraPermissionResult = 'Camera Permission Result';
  static const readingPhotoCaptured = 'Reading Photo Captured';
  static const readingPhotoPicked = 'Reading Photo Picked';
  static const readingCaptureFailed = 'Reading Capture Failed';
  static const readingScanStarted = 'Reading Scan Started';
  static const readingSucceeded = 'Reading Succeeded';
  static const readingFailed = 'Reading Failed';
  static const readingViewed = 'Reading Viewed';
  static const readingDetailOpened = 'Reading Detail Opened';
  static const readingNarrated = 'Reading Narrated';
  static const readingNarrationStopped = 'Reading Narration Stopped';
  static const readingPdfExported = 'Reading PDF Exported';
  static const readingShared = 'Reading Shared';

  /// The bridge between a reading and the chat. Worth its own event because it is the app's main
  /// cross-sell, and the only way to tell an organic chat from a prompted one.
  static const askAstroTapped = 'Ask Astro Tapped';

  /// Palm only — the face flow has no focus picker.
  static const palmFocusSelected = 'Palm Focus Selected';

  // ---------------------------------------------------------------- chat

  static const chatOpened = 'Chat Opened';
  static const chatTopicTapped = 'Chat Topic Tapped';
  static const chatMessageSent = 'Chat Message Sent';
  static const chatReplyReceived = 'Chat Reply Received';
  static const chatReplyFailed = 'Chat Reply Failed';
  static const chatQuickReplyTapped = 'Chat Quick Reply Tapped';
  static const chatDrawerOpened = 'Chat Drawer Opened';
  static const chatThreadCreated = 'Chat Thread Created';
  static const chatThreadSwitched = 'Chat Thread Switched';
  static const chatThreadRenamed = 'Chat Thread Renamed';
  static const chatThreadDeleted = 'Chat Thread Deleted';

  // ---------------------------------------------------------------- profile

  static const profileViewed = 'Profile Viewed';
  static const downloadsViewed = 'Downloads Viewed';
  static const downloadOpened = 'Download Opened';
  static const memoryViewed = 'Memory Viewed';
  static const memoryFactForgotten = 'Memory Fact Forgotten';
  static const memoryCleared = 'Memory Cleared';
  static const supportLinkOpened = 'Support Link Opened';
  static const renewTapped = 'Renew Tapped';
}

/// Property keys.
///
/// **What is deliberately absent.** Device model, manufacturer, OS and version, screen size,
/// carrier, app version string, library version, and the city/region/country Mixpanel derives from
/// the request IP are all attached by the native SDK without being asked. Adding them here would
/// not add a field — it would add a *second* field under a non-standard name, invisible to every
/// built-in Mixpanel report, and the two would drift the first time one device reported one and
/// not the other.
abstract final class P {
  // ---------------------------------------------------------------- context

  /// Which rung of the repository ladder is live: `supabase`, `fast2sms` or `fake`. Without it,
  /// a developer running against the fakes pollutes production funnels with free subscriptions.
  static const backendMode = 'backend_mode';
  static const env = 'env';
  static const buildMode = 'build_mode';
  static const appVersion = 'app_version';
  static const buildNumber = 'build_number';
  static const appLanguage = 'app_language';
  static const appLocale = 'app_locale';
  static const utcOffsetMinutes = 'utc_offset_minutes';

  /// Survives sign-out, unlike Mixpanel's `$device_id`, which `reset()` remints. This is what
  /// makes "two accounts on one handset" answerable at all.
  static const installId = 'install_id';
  static const daysSinceInstall = 'days_since_install';
  static const isNewUser = 'is_new_user';
  static const previousVersion = 'previous_version';
  static const sessionId = 'session_id';

  /// How long an event sat in the queue waiting for the token to arrive. Present only when
  /// non-zero, so a delayed event is never mistaken for a slow user.
  static const queuedLagMs = 'queued_lag_ms';

  // ---------------------------------------------------------------- identity

  static const isSignedIn = 'is_signed_in';
  static const paymentType = 'payment_type';
  static const entitled = 'entitled';
  static const inTrial = 'in_trial';
  static const hasEverSubscribed = 'has_ever_subscribed';
  static const billingState = 'billing_state';
  static const hasName = 'has_name';
  static const hasBirthDate = 'has_birth_date';
  static const birthYear = 'birth_year';
  static const ageYears = 'age_years';

  // ---------------------------------------------------------------- navigation

  static const screen = 'screen';
  static const previousScreen = 'previous_screen';
  static const routePath = 'route_path';
  static const navType = 'nav_type';
  static const exitType = 'exit_type';
  static const isModal = 'is_modal';
  static const secondsOnScreen = 'seconds_on_screen';
  static const screensViewed = 'screens_viewed';
  static const blocked = 'blocked';
  static const destination = 'destination';
  static const source = 'source';

  static const elementId = 'element_id';
  static const label = 'label';

  // ---------------------------------------------------------------- lifecycle

  static const isFirstLaunch = 'is_first_launch';
  static const coldStart = 'cold_start';
  static const secondsSinceLastOpen = 'seconds_since_last_open';
  static const secondsBackgrounded = 'seconds_backgrounded';
  static const sessionSeconds = 'session_seconds';
  static const durationSeconds = 'duration_seconds';
  static const error = 'error';
  static const stackHead = 'stack_head';
  static const fatal = 'fatal';

  // ---------------------------------------------------------------- generic

  static const ms = 'ms';
  static const state = 'state';
  static const reason = 'reason';
  static const message = 'message';
  static const code = 'code';
  static const count = 'count';
  static const trigger = 'trigger';
  static const outcome = 'outcome';
  static const result = 'result';
  static const attempt = 'attempt';
  static const position = 'position';

  // ---------------------------------------------------------------- onboarding

  static const valid = 'valid';
  static const entryMethod = 'entry_method';
  static const attemptsUsed = 'attempts_used';
  static const attemptsLeft = 'attempts_left';
  static const resendsUsed = 'resends_used';
  static const secondsRemaining = 'seconds_remaining';
  static const secondsToVerify = 'seconds_to_verify';
  static const nameLength = 'name_length';
  static const field = 'field';

  // ---------------------------------------------------------------- payments

  /// Ties every event in one checkout attempt together — the tap, the mandate, the UPI launch,
  /// the poll and the outcome. Without it a user who tries three times is one indistinguishable
  /// smear of events.
  static const paymentAttemptId = 'payment_attempt_id';
  static const attemptNumber = 'attempt_number';
  static const appId = 'app_id';
  static const appName = 'app_name';
  static const fromAppId = 'from_app_id';
  static const toAppId = 'to_app_id';
  static const availableCount = 'available_count';
  static const positionInList = 'position_in_list';
  static const appIds = 'app_ids';
  static const offerType = 'offer_type';
  static const amount = 'amount';
  static const flow = 'flow';
  static const trialPrice = 'trial_price';
  static const planPrice = 'plan_price';
  static const trialDays = 'trial_days';
  static const trialAvailable = 'trial_available';
  static const upiAppCount = 'upi_app_count';
  static const subscriptionId = 'subscription_id';
  static const environment = 'environment';
  static const sdkVerified = 'sdk_verified';
  static const pollAttempts = 'poll_attempts';
  static const maxAttempts = 'max_attempts';
  static const totalSeconds = 'total_seconds';
  static const secondsInCheckout = 'seconds_in_checkout';
  static const secondsInUpiApp = 'seconds_in_upi_app';
  static const secondsSinceCheckout = 'seconds_since_checkout';
  static const cfStatus = 'cf_status';
  static const cfCode = 'cf_code';
  static const cfType = 'cf_type';
  static const previousPaymentType = 'previous_payment_type';
  static const muted = 'muted';

  // ---------------------------------------------------------------- readings

  /// `palm` or `face`. The one property that keeps the two mirrored flows in a single funnel.
  static const feature = 'feature';
  static const readingId = 'reading_id';
  static const focus = 'focus';
  static const previousFocus = 'previous_focus';
  static const bytes = 'bytes';
  static const msToCapture = 'ms_to_capture';
  static const lineCount = 'line_count';
  static const sectionCount = 'section_count';
  static const detail = 'detail';
  static const permission = 'permission';
  static const cameraReady = 'camera_ready';
  static const ageDays = 'age_days';
  static const surface = 'surface';

  // ---------------------------------------------------------------- chat

  static const threadId = 'thread_id';
  static const threadCount = 'thread_count';
  static const topic = 'topic';
  static const chars = 'chars';
  static const turnIndex = 'turn_index';
  static const hasVerdict = 'has_verdict';
  static const optionCount = 'option_count';
  static const optionIndex = 'option_index';
  static const askFor = 'ask_for';
  static const hasOpener = 'has_opener';

  // ---------------------------------------------------------------- profile

  static const palmCount = 'palm_count';
  static const faceCount = 'face_count';
  static const factCount = 'fact_count';
  static const link = 'link';
  static const function = 'function';
  static const slide = 'slide';
}

/// How a screen was left, for [P.exitType].
abstract final class ExitType {
  static const pop = 'pop';
  static const replaced = 'replaced';
  static const removed = 'removed';
}

/// How a screen was reached, for [P.navType].
abstract final class NavType {
  static const push = 'push';
  static const replace = 'replace';
  static const pop = 'pop';
}

/// Which repository ladder rung is live, for [P.backendMode].
abstract final class BackendMode {
  static const supabase = 'supabase';
  static const fast2sms = 'fast2sms';
  static const fake = 'fake';
}

/// Which of the two mirrored reading flows an event belongs to, for [P.feature].
///
/// Named `ReadingFeature` rather than `Feature` because `Feature` is already a widget in
/// `lib/widgets/feature_pills.dart`, and the paywall imports both.
abstract final class ReadingFeature {
  static const palm = 'palm';
  static const face = 'face';

  /// Not a reading, but narration and the "Ask Astro" bridge are shared with the chat, and those
  /// events want one vocabulary across all three surfaces.
  static const chat = 'chat';
}

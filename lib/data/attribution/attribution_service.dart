import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:play_install_referrer/play_install_referrer.dart';

import '../analytics/analytics.dart';
import '../analytics/analytics_events.dart';
import '../repositories/referral_repository.dart';
import 'attribution.dart';
import 'attribution_store.dart';
import 'referral_links.dart';

/// Works out where this install came from, and tells the backend once there is somebody to tell
/// it about.
///
/// ## The shape of the problem
///
/// Attribution arrives early — in the first milliseconds of a cold launch, from a link or from
/// the Play Store — and can only be *recorded* late, after the user has an account. Those two
/// moments are minutes apart, with a paywall and an OTP in between, and the app is routinely
/// killed somewhere in the middle. So this is a two-phase thing, built the same way
/// [MixpanelAnalytics] is: resolve what it can immediately, persist it, and drain the pending
/// work when the backend finally becomes reachable.
///
/// ## Android, through the Play Store
///
/// An invite is a Play Store link carrying `referrer=ref_code=<CODE>`, which Google returns
/// verbatim through the Install Referrer API on first launch. That is the whole mechanism: no web
/// page, no domain verification, no App Link. A referred user does not have the app yet, so there
/// is nothing for a link to open.
///
/// `app_links` is still listened to, by hand, for the `astrolok://` scheme — but an incoming link
/// is treated as **data, not a destination**. `flutter_deeplinking_enabled` stays false on both
/// platforms: letting the engine route a link straight to a screen would walk a user past the
/// splash, the one place that resolves the session and decides where they belong.
class AttributionService {
  AttributionService({
    AttributionStore? store,
    @visibleForTesting AppLinks Function()? linkProvider,
    @visibleForTesting Future<String?> Function()? readInstallReferrer,
  })  : _store = store ?? AttributionStore(),
        _linkProvider = linkProvider ?? AppLinks.new,
        _readInstallReferrer = readInstallReferrer ?? _platformInstallReferrer;

  final AttributionStore _store;

  /// A factory rather than an instance, so that constructing the service touches no platform
  /// channel — the global below is built at import time, long before the binding exists.
  final AppLinks Function() _linkProvider;
  final Future<String?> Function() _readInstallReferrer;

  AppLinks? _links;

  ReferralRepository? _backend;
  StreamSubscription<Uri>? _subscription;

  /// Guards against two drains overlapping — a link arriving while a sign-in is already draining,
  /// which would claim the same pending attribution twice. Harmless on the backend, which is
  /// idempotent, but it would emit two events for one referral.
  bool _draining = false;

  Attribution? _resolved;

  /// The [Attribution.signature] most recently accepted by the backend, so a resume does not
  /// re-report something that has not changed. In memory only — see the note in [drain].
  String? _reportedSignature;

  @visibleForTesting
  Attribution? get resolved => _resolved;

  /// Phase one: everything that can be known without a network or a session.
  ///
  /// Called from `bootMobileApp` after `installAnalytics` and before `runApp`, so the super
  /// properties this registers are already attached to `App Launched` — the denominator of every
  /// acquisition funnel, and the one event that must never be unattributed.
  ///
  /// Never throws and never blocks on anything slow. A device where the link plugin or the Play
  /// Store service will not answer still launches; it simply launches unattributed.
  Future<void> start() async {
    // What an earlier launch already worked out, restored before anything else.
    //
    // Both sources of a fresh attribution are one-shot — a link arrives once, and the Play
    // referrer is read once per install — so without this, `_resolved` is null on every launch
    // after the first and no acquisition super properties are registered at all. The native
    // Mixpanel SDK persists super properties itself, which hides the problem right up until
    // `reset()` on a sign-out wipes them and nothing puts them back.
    _resolved = await _store.readPending() ?? await _store.readFirstTouch();

    try {
      final links = _links ??= _linkProvider();

      // A link that started this launch. `getInitialLink` answers null on a normal cold start,
      // which is the overwhelmingly common case.
      final initial = await links.getInitialLink();
      if (initial != null) await _onLink(initial, cold: true);

      // And links that arrive while the app is already running — the warm case, where the user
      // taps an invite while Astrolok is in the background.
      _subscription ??= links.uriLinkStream.listen(
        (uri) => _onLink(uri, cold: false),
        onError: (Object error) => debugPrint('[attribution] link stream failed: $error'),
      );
    } catch (error) {
      debugPrint('[attribution] could not start link handling: $error');
    }

    await _publish();

    // Only when a link did not already answer the question — a link is deterministic and already
    // in hand, whereas the install referrer says the same thing at best.
    //
    // Deliberately **not** awaited. Reading it binds a Play Store service, which on a cold first
    // launch is a few hundred milliseconds of somebody staring at a splash screen, and no part of
    // attribution is worth that. It publishes its own super properties when it lands, and the
    // durable record is written server-side regardless — so the only cost of it arriving late is
    // that `App Launched` on a first organic launch may not carry a campaign, which the
    // `Attribution Resolved` event that follows it does.
    if (_resolved == null) unawaited(_readReferrerOnce());
  }

  /// Phase two: the backend is reachable. Drains whatever is pending.
  ///
  /// Called from a provider once the repository exists, mirroring how `analyticsBootstrapProvider`
  /// hands Mixpanel its token after the config resolves.
  Future<void> attachBackend(ReferralRepository backend) async {
    _backend = backend;
    await drain();
  }

  /// Called whenever the signed-in user is resolved — from the same hook that calls
  /// `analytics.identify`, so a claim is attempted at exactly the moment a session first exists.
  Future<void> onUserResolved() => drain();

  /// A code the user typed in.
  ///
  /// The fallback for the one case the Play referrer cannot cover: a user who was sent an invite
  /// but reached the store some other way — sideloaded, restored from a backup, or installed on a
  /// device that had already seen the listing — so Google had no referrer to hand back.
  ///
  /// Returns the outcome so the screen can say something useful; every other path here is silent.
  Future<ReferralClaim> submitManualCode(String raw) async {
    final code = normaliseReferralCode(raw);
    if (code == null) {
      return const ReferralClaim(ReferralClaimStatus.invalidCode);
    }

    analytics.track(Ev.inviteCodeSubmitted, {P.referralCode: code});

    final attribution = resolveAttribution(
      const {},
      channel: 'manual_code',
      referralCode: code,
    );
    // Persisted before the call, like every other path here: a manual code typed on a flaky
    // connection is still a code the user gave us, and it should survive being retried.
    await _store.writePending(attribution);
    _resolved = attribution;
    await _publish();

    final backend = _backend;
    if (backend == null) return const ReferralClaim(ReferralClaimStatus.failed);

    return _claim(backend, attribution);
  }

  /// Sends anything outstanding: a pending referral claim, and the attribution report.
  @visibleForTesting
  Future<void> drain() async {
    final backend = _backend;
    if (backend == null || _draining) return;
    _draining = true;

    try {
      final pending = await _store.readPending();
      _resolved ??= pending;

      // Only a code can be claimed. An ad install and an organic one carry none, and an earlier
      // version called `referral-claim` for those too — a round trip on every single install to
      // be told what the absence of a code already said.
      if (pending?.referralCode != null && !await _store.isClaimSettled()) {
        await _claim(backend, pending!);
      }

      // Reported after the claim, so a referral that was just accepted is already the truth by
      // the time the acquisition row is written.
      //
      // Guarded by a signature rather than sent every time. `drain` runs from the identity hook,
      // which re-resolves on every resume and on a six-hourly timer, so an unguarded report here
      // would be a network call every time the user came back to the app — to say something that
      // by definition had not changed.
      //
      // In memory only, deliberately: a fresh process re-reports once, which costs one request
      // and repairs anything a previous launch failed to send. A flag on disk would make that
      // failure permanent.
      final current = _resolved ?? await _store.readFirstTouch();
      if (current != null && _reportedSignature != current.signature) {
        final authoritative = await backend.reportAttribution(current);
        if (authoritative != null) {
          _reportedSignature = current.signature;
          _resolved = authoritative;
          analytics.registerSuper(authoritative.properties);
        }
      }
    } catch (error) {
      debugPrint('[attribution] drain failed: $error');
    } finally {
      _draining = false;
    }
  }

  Future<ReferralClaim> _claim(ReferralRepository backend, Attribution attribution) async {
    final result = await backend.claim(
      code: attribution.referralCode,
      attributionType: attribution.channel,
    );

    if (result.isTerminal) {
      // Settled one way or another — accepted, refused, or a code that names nobody. The client
      // stops asking, which is what stops an invalid code being retried on every launch forever.
      await _store.markClaimSettled();
      await _store.clearPending();
    }

    switch (result.status) {
      case ReferralClaimStatus.created:
        // Deliberately **not** tracked from here. `Referral Attributed` is raised server-side by
        // `referral-claim`, keyed on `ref:{user_id}` so it can only ever be counted once. Firing
        // a client event of the same name beside it would not be deduplicated — client SDK events
        // carry no `$insert_id` — so every referral would appear twice, and the one number a
        // referral programme is judged on would be double.
        //
        // Re-resolved from the code the backend confirmed, rather than from what was sent up, so
        // a normalised code (`ILOU` typed, `110V` stored) ends up consistent everywhere.
        _resolved = resolveAttribution(
          attribution.params,
          channel: attribution.channel,
          referralCode: result.code ?? attribution.referralCode,
        );
        await _publish();

      case ReferralClaimStatus.invalidCode:
      case ReferralClaimStatus.selfReferral:
      case ReferralClaimStatus.notEligible:
        analytics.track(Ev.referralClaimFailed, {
          P.reason: result.status.name,
          P.referralCode: attribution.referralCode,
          P.attributionType: attribution.channel,
        });

      // Nothing to report. `noAttribution` is the ordinary answer for an install that carried no
      // code at all, and counting it would drown the funnel.
      case ReferralClaimStatus.alreadyReferred:
      case ReferralClaimStatus.noAttribution:
      case ReferralClaimStatus.disabled:
      case ReferralClaimStatus.failed:
        break;
    }

    return result;
  }

  Future<void> _onLink(Uri uri, {required bool cold}) async {
    final code = referralCodeFromUri(uri);
    final params = paramsFromUri(uri);

    // A link with neither a code nor a *campaign* parameter is not ours to attribute.
    //
    // The test used to be `params.isEmpty`, which was wrong in the one case that actually
    // reaches here: the Cashfree return is `astrolok://payment?sub=...`, whose query is not empty,
    // so every web-fallback payment fired a bogus `Referral Link Opened` and overwrote last-touch
    // attribution with an organic deep link. The comment claimed otherwise, which is how it
    // survived review. Asking whether anything here *is* a campaign parameter is the question
    // that was meant.
    if (code == null && !hasCampaignParams(params)) return;

    analytics.track(Ev.referralLinkOpened, {
      P.referralCode: code,
      P.coldStart: cold,
      P.source: uri.scheme,
    });

    final attribution = resolveAttribution(params, channel: 'deep_link', referralCode: code);

    await _accept(attribution);
  }

  Future<void> _readReferrerOnce() async {
    if (!_isInstallReferrerPlatform) return;
    if (await _store.hasReadInstallReferrer()) return;

    try {
      final raw = await _readInstallReferrer();
      // Marked read whatever came back. The Play API returns the same string for the life of the
      // install, so a retry next launch would re-read the same thing — and an install with a
      // genuinely empty referrer is an answer, not a failure to get one.
      await _store.markInstallReferrerRead();

      final params = paramsFromReferrerString(raw);
      if (params.isEmpty) return;

      await _accept(resolveAttribution(params, channel: 'install_referrer'));
    } catch (error) {
      // No Play Services, a sideloaded build, an emulator without the store. All ordinary, and
      // none of them may interrupt a launch.
      debugPrint('[attribution] install referrer unavailable: $error');
      await _store.markInstallReferrerRead();
    }
  }

  /// Takes an attribution on board, unless we already have a better one.
  ///
  /// "Better" is only ever about the *current* session's last touch — first touch is settled
  /// separately and permanently. A referral outranks a bare campaign because it is an explicit
  /// statement that a named person sent this user; otherwise the newer signal wins, since a user
  /// who clicked a fresh ad genuinely did arrive through it this time.
  Future<void> _accept(Attribution attribution) async {
    final existing = _resolved;
    if (existing != null && existing.isReferral && !attribution.isReferral) return;

    _resolved = attribution;

    // Written before anything is sent anywhere. If the process dies on the next line, the next
    // launch finds this and retries — which is the whole reason the claim endpoint is idempotent.
    await _store.writePending(attribution);
    await _publish();

    // A link that arrives while the app is already running, after the backend was attached, has
    // a session waiting for it and should not sit until the next launch.
    unawaited(drain());
  }

  /// Registers the current attribution as super properties, and records first touch locally.
  Future<void> _publish() async {
    final attribution = _resolved;
    if (attribution == null) return;

    final isFirst = await _store.recordFirstTouchIfAbsent(attribution);

    // Last touch only. The `initial_*` People properties are written by the backend with
    // `setOnce`, deliberately not from here: the client cannot know whether a first touch already
    // exists on an account that was signed into on another device, and guessing would be the one
    // way to overwrite the value this whole design exists to protect.
    analytics.registerSuper(attribution.properties);

    if (isFirst) {
      analytics.track(Ev.attributionResolved, {
        ...attribution.properties,
        P.isFirstTouch: true,
        P.attributionType: attribution.channel,
      });
    }
  }

  bool get _isInstallReferrerPlatform {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}

/// The real Play Install Referrer read, kept out of the class so a test can supply its own.
///
/// Throws on iOS and wherever Play Services is missing, which is why every caller is inside a
/// try/catch and a platform guard.
Future<String?> _platformInstallReferrer() async {
  final details = await PlayInstallReferrer.installReferrer;
  return details.installReferrer;
}

/// The one service, resolved in `bootMobileApp` — matching `analyticsContext` and
/// `analyticsSession` next door, which are globals for the same reason: boot runs before any
/// `ProviderScope` exists, and the first events are launch events.
final attributionService = AttributionService();

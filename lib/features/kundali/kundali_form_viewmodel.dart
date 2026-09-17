import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../data/analytics/analytics.dart';
import '../../data/analytics/analytics_events.dart';
import '../../data/entitlement.dart';
import '../../data/kundali_summary.dart';
import '../../data/models/app_user.dart';
import '../../data/models/birth_place.dart';
import '../../data/models/kundali.dart';
import '../../data/providers.dart';
import '../../data/repositories/app_config_repository.dart';
import '../../data/repositories/kundali_repository.dart';
import '../../data/repositories/place_repository.dart';
import 'kundali_copy.dart';
import 'kundali_form_state.dart';

/// The birth-details form. Keyed on whether it is editing an existing kundali.
class KundaliFormViewModel extends AutoDisposeFamilyNotifier<KundaliFormState, bool> {
  final _searchSessions = <String>{};

  @override
  KundaliFormState build(bool edit) {
    final user = ref.read(entitlementProvider);
    final existing = ref.read(kundaliSummaryProvider).valueOrNull;
    final config = ref.read(appConfigProvider).valueOrNull ?? shippedAppConfig;

    // An existing kundali's own details win: they are what the chart on screen was cast from. The
    // account's saved place only fills in when it is the same place, since the summary carries no
    // coordinates of its own.
    final birthDate = existing?.birth.birthDate ?? user?.birthDate;
    final birthTime = existing?.birth.birthTime ?? user?.birthTime;
    final savedPlace = user?.birthPlace;
    final place = existing == null || savedPlace?.label == existing.birth.placeLabel ? savedPlace : null;

    analytics.track(Ev.kundaliFormViewed, {
      P.isEdit: edit,
      P.prefilledDob: birthDate != null,
      P.prefilledTime: birthTime != null,
      P.prefilledPlace: place != null,
    });

    return KundaliFormState(
      birthDate: birthDate,
      birthTime: birthTime,
      place: place,
      existing: existing,
      isEdit: edit,
      placeSearchEnabled: config.configFlag(placeSearchEnabledKey),
    );
  }

  void setBirthDate(DateTime date) => state = state.copyWith(birthDate: date, clearError: true);

  void setBirthTime(String time) => state = state.copyWith(birthTime: time, clearError: true);

  void clearPlace() => state = state.copyWith(clearPlace: true, clearError: true);

  Future<List<PlaceSuggestion>> searchPlaces(String query, String sessionToken) async {
    if (_searchSessions.add(sessionToken)) analytics.track(Ev.placeSearchStarted);
    try {
      return await ref.read(placeRepositoryProvider).autocomplete(query, sessionToken: sessionToken);
    } on PlaceException catch (error) {
      analytics.track(Ev.placeSearchFailed, {P.code: error.runtimeType.toString()});
      rethrow;
    }
  }

  Future<void> choosePlace(PlaceSuggestion suggestion, String sessionToken, int rank, int count) async {
    final started = DateTime.now();
    try {
      final place = await ref.read(placeRepositoryProvider).details(
            suggestion,
            sessionToken: sessionToken,
            birthDate: state.birthDate,
            birthTime: state.birthTime,
          );
      state = state.copyWith(place: place, clearError: true);
      analytics.track(Ev.placeSelected, {
        P.resultRank: rank,
        P.suggestionCount: count,
        P.timeZone: place.timeZoneId,
        P.ms: DateTime.now().difference(started).inMilliseconds,
      });
    } on PlaceException catch (error) {
      analytics.track(Ev.placeSearchFailed, {P.code: error.runtimeType.toString()});
      rethrow;
    }
  }

  /// Casts the kundali. Returns where to go next, or null when it did not go through (the reason is
  /// in [KundaliFormState.error]).
  Future<String?> submit() async {
    if (state.busy) return null;
    final birthDate = state.birthDate;
    final birthTime = state.birthTime;
    final place = state.place;
    if (birthDate == null) return _refuse(KundaliCopy.missingDob);
    if (birthTime == null) return _refuse(KundaliCopy.missingTime);
    if (place == null) return _refuse(KundaliCopy.missingPlace);

    final regeneration = state.changesExisting;
    state = state.copyWith(busy: true, clearError: true);

    try {
      final summary = await ref.read(kundaliRepositoryProvider).request(
            birthDate: birthDate,
            birthTime: birthTime,
            place: place,
          );
      await ref.read(kundaliSummaryProvider.notifier).set(summary);

      // The server saved these to the account as well; mirror them so Profile and the next form
      // agree without waiting for the next `me`.
      final user = ref.read(entitlementProvider);
      if (user != null) {
        ref.read(entitlementProvider.notifier).set(
              user.copyWith(birthDate: birthDate, birthTime: birthTime, birthPlace: place),
            );
      }

      analytics.track(Ev.kundaliRequested, {
        P.kundaliId: summary.id,
        P.isRegeneration: regeneration,
        P.regenerationsLeft: summary.regenerationsLeft,
        P.timeZone: place.timeZoneId,
        P.unlockHours: summary.unlockHours,
        P.instant: summary.isInstant,
      });

      state = state.copyWith(busy: false);
      return summary.state == KundaliState.ready ? Routes.kundaliReport : Routes.kundaliWaiting;
    } on KundaliException catch (error) {
      analytics.track(Ev.kundaliRequestFailed, {P.code: error.runtimeType.toString(), P.message: error.message});
      state = state.copyWith(busy: false, error: error.message);
      return null;
    } catch (error) {
      analytics.track(Ev.kundaliRequestFailed, {P.error: '$error'});
      state = state.copyWith(busy: false, error: KundaliCopy.requestFailed);
      return null;
    }
  }

  /// Whether a re-cast chart is revealed after another wait, which only a trial's is. The server
  /// decides; the confirmation only has to say the same thing it will do.
  bool get recastWaits => ref.read(entitlementProvider)?.paymentType == PaymentType.trial;

  String? _refuse(String message) {
    state = state.copyWith(error: message);
    return null;
  }
}

final kundaliFormViewModelProvider =
    AutoDisposeNotifierProviderFamily<KundaliFormViewModel, KundaliFormState, bool>(KundaliFormViewModel.new);

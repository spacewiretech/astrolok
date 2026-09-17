import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';
import '../data/models/birth_place.dart';

/// A version-4 UUID, the session token shape Google recommends for Places.
String newPlaceSessionToken([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Type-ahead search for a birth place, with the suggestions listed inline beneath the field.
///
/// Inline rather than in an overlay: the form scrolls, the keyboard is up, and an overlay anchored
/// to a field that is scrolling under it is the usual source of suggestion lists floating over the
/// wrong thing.
///
/// Knows nothing about where suggestions come from. [search] and [onChosen] do the work; this owns
/// only the typing — the debounce, the minimum length, and the session token that bills a whole
/// search and the pick that ends it as one Google session. The token is rotated after a pick, and
/// after [sessionIdle] without a keystroke, which is the window Google allows.
class PlaceSearchField extends StatefulWidget {
  const PlaceSearchField({
    super.key,
    required this.search,
    required this.onChosen,
    required this.onCleared,
    this.selectedLabel,
    this.hint = 'eg: Tirupati',
    this.enabled = true,
    this.unavailableMessage,
    this.debounce = const Duration(milliseconds: 350),
    this.sessionIdle = const Duration(minutes: 3),
    this.tokenFactory,
  });

  final Future<List<PlaceSuggestion>> Function(String query, String sessionToken) search;

  /// Resolves the chosen row. Completes when the place is known, or throws with a message to show.
  final Future<void> Function(PlaceSuggestion suggestion, String sessionToken, int rank, int count) onChosen;

  final VoidCallback onCleared;

  /// What is already chosen — shown in place of the text field.
  final String? selectedLabel;
  final String hint;
  final bool enabled;

  /// Shown instead of the field when search is switched off.
  final String? unavailableMessage;
  final Duration debounce;
  final Duration sessionIdle;

  @visibleForTesting
  final String Function()? tokenFactory;

  @override
  State<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends State<PlaceSearchField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  Timer? _debounce;
  String? _token;
  DateTime? _lastKeystroke;
  int _generation = 0;

  List<PlaceSuggestion> _suggestions = const [];
  bool _searching = false;
  bool _resolving = false;
  String? _error;

  String _sessionToken() {
    final now = DateTime.now();
    final stale = _lastKeystroke != null && now.difference(_lastKeystroke!) > widget.sessionIdle;
    if (_token == null || stale) _token = (widget.tokenFactory ?? newPlaceSessionToken)();
    _lastKeystroke = now;
    return _token!;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final query = text.trim();
    if (query.length < 2) {
      setState(() {
        _suggestions = const [];
        _searching = false;
        _error = null;
      });
      return;
    }
    final token = _sessionToken();
    _debounce = Timer(widget.debounce, () => _run(query, token));
  }

  Future<void> _run(String query, String token) async {
    final generation = ++_generation;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await widget.search(query, token);
      if (!mounted || generation != _generation) return;
      setState(() {
        _suggestions = results;
        _searching = false;
        _error = results.isEmpty ? 'No matching places. Try the nearest town or city.' : null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _suggestions = const [];
        _searching = false;
        _error = error is Exception ? _messageOf(error) : 'Search is not available right now.';
      });
    }
  }

  Future<void> _choose(PlaceSuggestion suggestion, int rank) async {
    final token = _token ?? _sessionToken();
    setState(() {
      _resolving = true;
      _error = null;
    });
    try {
      await widget.onChosen(suggestion, token, rank, _suggestions.length);
      if (!mounted) return;
      _focus.unfocus();
      setState(() {
        _resolving = false;
        _suggestions = const [];
        _controller.clear();
        // A pick ends the billed session; the next search starts a new one.
        _token = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = error is Exception ? _messageOf(error) : 'Could not load that place. Please try again.';
      });
    }
  }

  String _messageOf(Exception error) {
    try {
      final message = (error as dynamic).message;
      if (message is String && message.isNotEmpty) return message;
    } catch (_) {
      // Not one of ours; fall through.
    }
    return 'Search is not available right now.';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.unavailableMessage != null) {
      return _Box(child: Text(widget.unavailableMessage!, style: AppText.meta));
    }

    final selected = widget.selectedLabel;
    if (selected != null && selected.isNotEmpty) {
      return _Box(
        child: Row(
          children: [
            const Icon(Icons.place_rounded, size: 18, color: AppColors.goldDeep),
            const SizedBox(width: 8),
            Expanded(child: Text(selected, style: AppText.input.copyWith(fontSize: 16))),
            IconButton(
              tooltip: 'Change birth place',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted),
              onPressed: widget.enabled
                  ? () {
                      widget.onCleared();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _focus.requestFocus();
                      });
                    }
                  : null,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Box(
          focused: _focus.hasFocus,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  enabled: widget.enabled && !_resolving,
                  onChanged: _onChanged,
                  textInputAction: TextInputAction.search,
                  textCapitalization: TextCapitalization.words,
                  style: AppText.input.copyWith(fontSize: 16),
                  cursorColor: AppColors.gold,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    hintText: widget.hint,
                    hintStyle: AppText.input.copyWith(fontSize: 16, color: AppColors.muted),
                  ),
                ),
              ),
              if (_searching || _resolving)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                ),
            ],
          ),
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppShape.control,
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _suggestions.length; i++)
                  InkWell(
                    onTap: _resolving ? null : () => _choose(_suggestions[i], i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.place_outlined, size: 18, color: AppColors.muted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_suggestions[i].primary, style: AppText.title.copyWith(fontSize: 15)),
                                if (_suggestions[i].secondary.isNotEmpty)
                                  Text(_suggestions[i].secondary, style: AppText.meta.copyWith(fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Required by Google's terms wherever Places results are shown without a map.
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('Powered by Google', style: AppText.legal.copyWith(fontSize: 11)),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: AppText.meta.copyWith(fontSize: 13, color: AppColors.danger)),
        ],
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child, this.focused = false});

  final Widget child;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppShape.control,
        border: Border.all(color: focused ? AppColors.gold : AppColors.fieldBorder, width: focused ? 1.4 : 1),
      ),
      child: child,
    );
  }
}

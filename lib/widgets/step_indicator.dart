import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_typography.dart';

/// The numbered 1 — 2 — 3 strip at the top of a multi-step flow.
///
/// A step is filled gold once it is reached and outlined grey before that, joined by a hairline
/// that also turns gold behind the reached ones. Passing a [current] past the last index draws
/// every step complete, which is what the results screen shows.
class StepIndicator extends StatelessWidget {
  const StepIndicator({
    super.key,
    required this.labels,
    required this.current,
  });

  final List<String> labels;

  /// Zero-based. Steps at or before this are gold.
  final int current;

  static const _disc = 36.0;

  /// The narrowest a connector is allowed to get before the labels start giving way instead.
  /// Below this the strip stops reading as a progression and starts looking broken.
  static const _minConnector = 12.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // The discs and connectors are decoration; this is the whole meaning of the strip.
      label: 'Step ${(current + 1).clamp(1, labels.length)} of ${labels.length}, '
          '${labels[current.clamp(0, labels.length - 1)]}',
      excludeSemantics: true,
      // The labels have to be bounded, or a long one pushes the whole Row past the screen —
      // an unconstrained Text in a Row grows to its intrinsic width and the connectors, being
      // Expanded, cannot give back more than they have. That overflowed at 360pt the first
      // time a step was called something longer than "Scan".
      child: LayoutBuilder(
        builder: (context, constraints) {
          final connectors = (labels.length - 1) * _minConnector;
          final perLabel =
              ((constraints.maxWidth - connectors) / labels.length).clamp(_disc, 400.0);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0)
                  Expanded(
                    child: Padding(
                      // Sits on the discs' centre line, not the column's, so it does not drift
                      // down when a label wraps to two lines.
                      padding: const EdgeInsets.only(top: _disc / 2),
                      child: Container(
                        height: 1,
                        color: i <= current ? AppColors.gold : AppColors.fieldBorder,
                      ),
                    ),
                  ),
                _Step(
                  index: i,
                  label: labels[i],
                  reached: i <= current,
                  maxLabelWidth: perLabel,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.index,
    required this.label,
    required this.reached,
    required this.maxLabelWidth,
  });

  final int index;
  final String label;
  final bool reached;
  final double maxLabelWidth;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: StepIndicator._disc,
          height: StepIndicator._disc,
          decoration: BoxDecoration(
            color: reached ? AppColors.gold : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: reached ? AppColors.gold : AppColors.fieldBorder,
              width: 1.4,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '${index + 1}',
            style: AppText.title.copyWith(
              fontSize: 15,
              color: reached ? Colors.white : AppColors.muted,
            ),
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxLabelWidth),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.meta.copyWith(
              fontSize: 13,
              color: reached ? AppColors.gold : AppColors.muted,
              fontWeight: reached ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

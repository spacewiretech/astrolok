import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';

/// One scrollable column of a date picker.
///
/// A [ListWheelScrollView] rather than a dropdown: the year column is over a hundred entries,
/// and three wheels side by side is the shape the design uses.
///
/// [values] can change while the wheel is on screen — picking February shortens the day
/// column — so the widget re-clamps its controller rather than assuming a stable length.
class DateWheel<T> extends StatefulWidget {
  const DateWheel({
    super.key,
    required this.label,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  final String label;
  final List<T> values;
  final T? selected;
  final String Function(T value) labelFor;
  final ValueChanged<T> onSelected;

  @override
  State<DateWheel<T>> createState() => _DateWheelState<T>();
}

class _DateWheelState<T> extends State<DateWheel<T>> {
  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(initialItem: _indexOfSelected());

  static const _itemExtent = 44.0;

  int _indexOfSelected() {
    final selected = widget.selected;
    // `indexOf(null as T)` throws for a non-nullable T, so the null case is handled before the
    // lookup rather than relying on the cast.
    if (selected == null) return 0;
    final index = widget.values.indexOf(selected);
    return index < 0 ? 0 : index;
  }

  @override
  void didUpdateWidget(covariant DateWheel<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    // The day column shrinks from 31 to 28 when the month changes. Without this the controller
    // would still be parked on an index the list no longer has.
    final index = _indexOfSelected();
    if (_controller.hasClients && _controller.selectedItem != index) {
      _controller.jumpToItem(index);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label, style: AppText.meta, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.cardSoft,
              borderRadius: AppShape.control,
            ),
            child: ListWheelScrollView.useDelegate(
              controller: _controller,
              itemExtent: _itemExtent,
              // Keeps the wheel from spinning past the ends on a hard fling, which on a
              // 125-entry year column is otherwise a long ride back.
              physics: const FixedExtentScrollPhysics(),
              diameterRatio: 1.6,
              overAndUnderCenterOpacity: 0.4,
              onSelectedItemChanged: (i) {
                if (i >= 0 && i < widget.values.length) {
                  widget.onSelected(widget.values[i]);
                }
              },
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: widget.values.length,
                builder: (context, i) => Center(
                  child: Text(
                    widget.labelFor(widget.values[i]),
                    style: AppText.input,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

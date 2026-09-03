import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';

/// The date-of-birth picker: three labelled wheels inside one card.
///
/// The card and the headers belong to this widget rather than to each column, because the
/// design draws one card around all three.
class DatePickerCard extends StatelessWidget {
  const DatePickerCard({super.key, required this.columns, this.height = 150});

  final List<DateWheelColumn> columns;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.wheelCard,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 18),
      child: Column(
        children: [
          Row(
            children: [
              for (final column in columns)
                Expanded(
                  flex: column.flex,
                  child: Text(
                    column.label,
                    textAlign: TextAlign.center,
                    style: AppText.title,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // No selection band. Sampling a vertical strip through the card in the render shows
          // a single uniform fill top to bottom — the chosen row is picked out by gold type
          // alone, and a tinted band behind it is an invention.
          SizedBox(
            height: height,
            child: Row(
              children: [
                for (final column in columns)
                  Expanded(flex: column.flex, child: column.build()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One column's data. Generic over the value type, so day/month/year all use ints while the
/// month column can still render names if the design ever calls for them.
class DateWheelColumn<T> {
  const DateWheelColumn({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
    this.flex = 1,
  });

  final String label;
  final List<T> values;
  final T? selected;
  final String Function(T value) labelFor;
  final ValueChanged<T> onSelected;
  final int flex;

  Widget build() => DateWheel<T>(
        key: ValueKey(label),
        values: values,
        selected: selected,
        labelFor: labelFor,
        onSelected: onSelected,
      );
}

/// One scrollable column.
///
/// A [ListWheelScrollView] rather than a dropdown: the year column runs to a hundred-odd
/// entries, and three side-by-side wheels is the shape the design uses.
///
/// [values] can change while the wheel is on screen — picking February shortens the day
/// column — so the controller is re-clamped rather than assumed stable.
class DateWheel<T> extends StatefulWidget {
  const DateWheel({
    super.key,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  final List<T> values;
  final T? selected;
  final String Function(T value) labelFor;
  final ValueChanged<T> onSelected;

  /// Three rows at this extent fill the card's 150pt, which is what the render shows: one
  /// above the selection and one below.
  static const itemExtent = 50.0;

  @override
  State<DateWheel<T>> createState() => _DateWheelState<T>();
}

class _DateWheelState<T> extends State<DateWheel<T>> {
  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(initialItem: _indexOfSelected());

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
    final selectedIndex = _indexOfSelected();

    return ListWheelScrollView.useDelegate(
      controller: _controller,
      itemExtent: DateWheel.itemExtent,
      // Keeps the wheel from spinning past the ends on a hard fling, which on a 125-entry year
      // column is otherwise a long ride back.
      physics: const FixedExtentScrollPhysics(),
      diameterRatio: 1.8,
      // The design fades neighbours rather than hiding them; the styling below carries the
      // rest of the contrast, so this stays gentle.
      overAndUnderCenterOpacity: 0.55,
      onSelectedItemChanged: (i) {
        if (i >= 0 && i < widget.values.length) widget.onSelected(widget.values[i]);
      },
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: widget.values.length,
        builder: (context, i) {
          final isSelected = i == selectedIndex;
          return Center(
            child: Text(
              widget.labelFor(widget.values[i]),
              style: isSelected ? AppText.wheelSelected : AppText.wheelIdle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      ),
    );
  }
}

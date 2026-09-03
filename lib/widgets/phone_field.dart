import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';

/// Country code + 10-digit number, in the bordered box from the design.
class PhoneField extends StatelessWidget {
  const PhoneField({
    super.key,
    required this.controller,
    this.dialCode = '+91',
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String dialCode;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return _FocusBox(
      builder: (node) => Row(
        children: [
          const _IndiaFlag(),
          const SizedBox(width: 8),
          Text(dialCode, style: AppText.input),
          const SizedBox(width: 10),
          const _Divider(),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: node,
              keyboardType: TextInputType.phone,
              style: AppText.input,
              cursorColor: AppColors.gold,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: onSubmitted,
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
                isCollapsed: true,
                hintText: '00000 00000',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single-line text field in the same box — used for the name step.
class TextFieldBox extends StatelessWidget {
  const TextFieldBox({
    super.key,
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.autofocus = true,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return _FocusBox(
      autofocus: autofocus,
      builder: (node) => TextField(
        controller: controller,
        focusNode: node,
        keyboardType: keyboardType,
        textCapitalization: TextCapitalization.words,
        style: AppText.input,
        cursorColor: AppColors.gold,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          hintText: hint,
          hintStyle: AppText.input.copyWith(color: AppColors.muted),
        ),
      ),
    );
  }
}

/// The bordered box, owning the focus node its field reads.
///
/// Both fields used to hardcode their border state — the phone field was permanently gold, the
/// name field permanently grey — so neither reacted to being focused and the name step gave no
/// sign of where to type.
///
/// It also takes focus itself rather than relying on the field's `autofocus`. These sheets are
/// swapped in by an `AnimatedSwitcher`, which keeps the outgoing sheet mounted through the
/// transition: its field still holds focus when the new one asks, and the new one loses. The
/// user then arrives at a field with no keyboard and no caret.
class _FocusBox extends StatefulWidget {
  const _FocusBox({required this.builder, this.autofocus = true});

  final Widget Function(FocusNode node) builder;
  final bool autofocus;

  @override
  State<_FocusBox> createState() => _FocusBoxState();
}

class _FocusBoxState extends State<_FocusBox> {
  final _node = FocusNode();

  @override
  void initState() {
    super.initState();
    _node.addListener(() => setState(() {}));

    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _node.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppShape.inputHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppShape.control,
        border: Border.all(
          color: _node.hasFocus ? AppColors.gold : AppColors.fieldBorder,
          width: _node.hasFocus ? 1.6 : 1,
        ),
      ),
      child: Center(child: widget.builder(_node)),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 24, color: AppColors.fieldBorder);
  }
}

/// The tricolour, drawn rather than shipped as an asset — three bands and a chakra outline.
class _IndiaFlag extends StatelessWidget {
  const _IndiaFlag();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: 26,
        height: 18,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Column(
              children: [
                Expanded(child: ColoredBox(color: Color(0xFFFF9933), child: SizedBox.expand())),
                Expanded(child: ColoredBox(color: Colors.white, child: SizedBox.expand())),
                Expanded(child: ColoredBox(color: Color(0xFF138808), child: SizedBox.expand())),
              ],
            ),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF000080), width: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

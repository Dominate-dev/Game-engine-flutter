import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/play_game_strings.dart';

class CountAnswerDialog extends ConsumerStatefulWidget {
  const CountAnswerDialog({
    super.key,
    this.selected,
    this.min = 1,
    this.max = 30,
  });

  final int? selected;
  final int min;
  final int max;

  @override
  ConsumerState<CountAnswerDialog> createState() => _CountAnswerDialogState();
}

class _CountAnswerDialogState extends ConsumerState<CountAnswerDialog> {
  static const _pickerHeight = 180.0;
  static const _itemExtent = 36.0;
  static const _unselectedColor = Color(0xCB6A6A6A);

  late int _value;
  late final FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _value = _clamp(widget.selected ?? widget.min);
    _controller = FixedExtentScrollController(
      initialItem: _value - widget.min,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _clamp(int value) {
    return value.clamp(widget.min, widget.max);
  }

  int get _itemCount => widget.max - widget.min + 1;

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(playGameStringsProvider);

    return GameDialog(
      child: GameDialogCard(
        borderWidth: 8,
        borderRadius: 25,
        innerBorderRadius: 20,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: _pickerHeight,
                    child: _pickerUi(),
                  ),
                  const SizedBox(height: 10),
                  GameButton(
                    label: strings.choose,
                    fontWeight: AppFontWeight.medium,
                    onPressed: () => Navigator.of(context).pop(_value),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            PositionedDirectional(
              top: 16,
              end: 16,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: AppImageView(
                    assetPath: AppAssets.closeIcon,
                    package: AppAssets.packageName,
                    size: 18,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickerUi() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: ListWheelScrollView.useDelegate(
            controller: _controller,
            itemExtent: _itemExtent,
            physics: const FixedExtentScrollPhysics(),
            perspective: 0.003,
            diameterRatio: 1.5,
            overAndUnderCenterOpacity: 0.35,
            onSelectedItemChanged: (index) {
              setState(() => _value = widget.min + index);
            },
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: _itemCount,
              builder: (context, index) {
                final number = widget.min + index;
                final isSelected = number == _value;
                return Center(
                  child: AppNumberTextView(
                    '$number',
                    fontSize: 20,
                    color: isSelected ? AppColors.purple : _unselectedColor,
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          ),
        ),
        IgnorePointer(
          child: Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.only(top: _itemExtent),
              child: Container(
                width: 64,
                height: 5,
                color: AppColors.button,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

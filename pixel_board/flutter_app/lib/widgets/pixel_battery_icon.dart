import 'package:flutter/material.dart';

/// Ícono de "torre de bloques" que indica pixeles disponibles.
/// Bloques llenos = value, bloques vacíos = max - value.
class PixelBatteryIcon extends StatelessWidget {
  const PixelBatteryIcon({
    super.key,
    required this.value,
    required this.max,
    this.blockSize = 8,
  });

  final int value;
  final int max;
  final double blockSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (int i = 0; i < max; i++)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Container(
              width: blockSize,
              height: blockSize * (i + 1),
              decoration: BoxDecoration(
                color: i < value ? const Color(0xFFFFD700) : Colors.transparent,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}
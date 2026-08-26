import 'package:flutter/material.dart';

import '../models/pixel_state.dart';

/// Lienzo de pixeles: dibuja el grid con un único CustomPainter
/// (nunca widgets individuales por pixel, por performance).
class PixelCanvas extends StatelessWidget {
  const PixelCanvas({
    super.key,
    required this.state,
    required this.onTapPixel,
  });

  final PixelState state;

  /// Callback con las coordenadas de grid (x, y) tocadas.
  final void Function(int x, int y) onTapPixel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final cell = side / state.size;

        return GestureDetector(
          onTapDown: (details) {
            final local = details.localPosition;
            final x = (local.dx / cell).floor();
            final y = (local.dy / cell).floor();
            if (state.inBounds(x, y)) {
              onTapPixel(x, y);
            }
          },
          child: ListenableBuilder(
            listenable: state,
            builder: (context, _) => CustomPaint(
              size: Size.square(side),
              painter: _GridPainter(state: state),
            ),
          ),
        );
      },
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.state});

  final PixelState state;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / state.size;

    for (int y = 0; y < state.size; y++) {
      for (int x = 0; x < state.size; x++) {
        final paint = Paint()
          ..color = state.parseColor(state.colorAt(x, y));
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell, cell),
          paint,
        );
      }
    }

    final gridPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (int i = 0; i <= state.size; i++) {
      final p = i * cell;
      canvas.drawLine(Offset(p, 0), Offset(p, size.height), gridPaint);
      canvas.drawLine(Offset(0, p), Offset(size.width, p), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => true;
}
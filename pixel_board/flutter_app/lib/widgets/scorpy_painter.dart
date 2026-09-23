import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Estados de la mascota Scorpy.
enum ScorpyState {
  /// Estado por defecto: bombilla apagada, tenazas abajo.
  idle,

  /// Bombilla encendida dando un consejo/pista.
  tipOn,

  /// Tenazas elevadas en celebración, bombilla encendida.
  celebrating,
}

/// Pinta al escorpión **Scorpy** pixel a pixel siguiendo exactamente
/// la hoja de especificaciones "CUTE SCORPION MASCOT: THE IDEA HELPER".
class ScorpyPainter extends CustomPainter {
  ScorpyPainter({required this.state, this.animValue = 0.0});

  final ScorpyState state;
  final double animValue;

  // ── Paleta de colores oficial (Pixel Palette) ──────────────────────
  static const _yellowBulb = Color(0xFFF9BB30); // Bombilla/Brillo
  static const _amberBody = Color(0xFFB86F2C);  // Cuerpo Base
  static const _brownShadow = Color(0xFF6F411C); // Sombra Base
  static const _whiteEyeHi = Color(0xFFFFFFFF);  // Blanco Ojos/Brillo
  static const _blackEye = Color(0xFF100D09);    // Casi Negro Ojos/Contorno
  static const _beigeLight = Color(0xFFFFD8A8);  // Beige Segmentos Claros
  static const _orangeBulbShade = Color(0xFFE69E58); // Naranja Shading Bombilla

  // ── Grid Lógico 24 x 22 ───────────────────────────────────────────
  static const int _cols = 24;
  static const int _rows = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final pxW = size.width / _cols;
    final pxH = size.height / _rows;
    final px = pxW < pxH ? pxW : pxH;

    final offsetX = (size.width - px * _cols) / 2;
    final offsetY = (size.height - px * _rows) / 2;

    final sprite = _buildSprite();

    for (int r = 0; r < _rows; r++) {
      final line = sprite[r];
      for (int c = 0; c < _cols; c++) {
        final color = _colorFor(line[c]);
        if (color == null) continue;
        canvas.drawRect(
          Rect.fromLTWH(offsetX + c * px, offsetY + r * px, px, px),
          Paint()..color = color,
        );
      }
    }

    // Halo/Glow si la bombilla está encendida
    if (state == ScorpyState.tipOn || state == ScorpyState.celebrating) {
      _paintBulbGlow(canvas, offsetX, offsetY, px);
    }
  }

  Color? _colorFor(String code) {
    switch (code) {
      case 'Y': return _yellowBulb;
      case 'A': return _amberBody;
      case 'S': return _brownShadow;
      case 'W': return _whiteEyeHi;
      case 'K': return _blackEye;
      case 'L': return _beigeLight;
      case 'O': return _orangeBulbShade;
      default:  return null;
    }
  }

  void _paintBulbGlow(Canvas canvas, double ox, double oy, double px) {
    final centerX = ox + 15.5 * px;
    final centerY = oy + 4.5 * px;
    final pulse = 0.35 + 0.35 * math.sin(animValue * 2 * math.pi);
    final radius = px * 3.5;

    final gradient = RadialGradient(
      colors: [
        _yellowBulb.withValues(alpha: pulse * 0.7),
        _yellowBulb.withValues(alpha: 0.0),
      ],
    );

    canvas.drawCircle(
      Offset(centerX, centerY),
      radius,
      Paint()..shader = gradient.createShader(
        Rect.fromCircle(center: Offset(centerX, centerY), radius: radius),
      ),
    );
  }

  @override
  bool shouldRepaint(covariant ScorpyPainter old) =>
      old.state != state || old.animValue != animValue;

  List<List<String>> _buildSprite() {
    final isCelebrating = state == ScorpyState.celebrating;
    final bulbLit = state == ScorpyState.tipOn || isCelebrating;

    final grid = List.generate(_rows, (_) => List.filled(_cols, '.'));

    void p(int r, int c, String code) {
      if (r >= 0 && r < _rows && c >= 0 && c < _cols) {
        grid[r][c] = code;
      }
    }

    // ── 1. BOMBILLA DE LA IDEA (Filas 2..6, Cols 14..17) ────────────
    final bCol = bulbLit ? 'Y' : 'O';
    // Contorno bombilla
    p(2, 15, 'K'); p(2, 16, 'K');
    p(3, 14, 'K'); p(3, 17, 'K');
    p(4, 14, 'K'); p(4, 17, 'K');
    p(5, 14, 'K'); p(5, 17, 'K');
    p(6, 15, 'K'); p(6, 16, 'K');

    // Relleno bombilla
    p(3, 15, bulbLit ? 'W' : bCol); p(3, 16, bCol);
    p(4, 15, bCol);                p(4, 16, bCol);
    p(5, 15, 'O');                p(5, 16, 'O');

    // Base/Rosca bombilla
    p(6, 15, 'S'); p(6, 16, 'S');

    // ── 2. COLA CURVADA (Filas 0..10) ──────────────────────────────────
    // Arco superior de la cola
    p(1, 15, 'K'); p(1, 16, 'K'); p(1, 17, 'K'); p(1, 18, 'K');
    p(0, 16, 'K'); p(0, 17, 'K');
    p(1, 16, 'A'); p(1, 17, 'L');

    p(2, 18, 'K'); p(2, 19, 'K');
    p(2, 17, 'A'); p(2, 18, 'L');

    p(3, 19, 'K'); p(3, 20, 'K');
    p(3, 18, 'A'); p(3, 19, 'S');

    p(4, 20, 'K'); p(4, 21, 'K');
    p(4, 19, 'A'); p(4, 20, 'S');

    // Cola descendente en curva hacia el cuerpo
    p(5, 20, 'K'); p(5, 21, 'K');
    p(5, 19, 'A'); p(5, 20, 'S');

    p(6, 19, 'K'); p(6, 20, 'K');
    p(6, 18, 'A'); p(6, 19, 'S');

    p(7, 18, 'K'); p(7, 19, 'K');
    p(7, 17, 'A'); p(7, 18, 'S');

    p(8, 17, 'K'); p(8, 18, 'K');
    p(8, 16, 'A'); p(8, 17, 'S');

    p(9, 16, 'K'); p(9, 17, 'K');
    p(9, 15, 'A'); p(9, 16, 'S');

    p(10, 15, 'K'); p(10, 16, 'K');
    p(10, 14, 'A'); p(10, 15, 'S');

    // ── 3. CUERPO KAWAII Y CABEZA (Filas 9..18, Cols 5..16) ───────────
    // Cabeza redondeada frontal (filas 9..17)
    // Fila 9: tope de la cabeza
    for (int c = 7; c <= 13; c++) { p(9, c, 'K'); }
    for (int c = 8; c <= 12; c++) { p(10, c, 'A'); }
    p(10, 7, 'K'); p(10, 13, 'K');

    // Filas 11..16 cuerpo ancho kawaii
    for (int r = 11; r <= 16; r++) {
      p(r, 5, 'K'); p(r, 15, 'K');
      for (int c = 6; c <= 14; c++) {
        p(r, c, 'A');
      }
    }

    // Luces/Sombras en cuerpo
    for (int c = 6; c <= 14; c++) {
      p(11, c, 'L'); // Brillo superior
    }
    for (int c = 6; c <= 14; c++) {
      p(16, c, 'S'); // Sombra inferior cuerpo
    }

    // Fila 17: base del cuerpo
    p(17, 6, 'K'); p(17, 14, 'K');
    for (int c = 7; c <= 13; c++) { p(17, c, 'S'); }
    for (int c = 7; c <= 13; c++) { p(18, c, 'K'); }

    // ── 4. OJOS GRANDES KAWAII CON BRILLO ─────────────────────────────
    // Ojo Izquierdo (Cols 7..9, Filas 12..14)
    p(12, 7, 'K'); p(12, 8, 'K'); p(12, 9, 'K');
    p(13, 7, 'K'); p(13, 8, 'W'); p(13, 9, 'K'); // Brillo blanco en ojo izq
    p(14, 7, 'K'); p(14, 8, 'K'); p(14, 9, 'K');

    // Ojo Derecho (Cols 11..13, Filas 12..14)
    p(12, 11, 'K'); p(12, 12, 'K'); p(12, 13, 'K');
    p(13, 11, 'K'); p(13, 12, 'W'); p(13, 13, 'K'); // Brillo blanco en ojo der
    p(14, 11, 'K'); p(14, 12, 'K'); p(14, 13, 'K');

    // Sonrisa tierna entre los ojos
    p(15, 10, 'K');

    // ── 5. TENAZAS (CLAWS) KAWAII ────────────────────────────────────
    final clawYOffset = isCelebrating ? -2 : 0;

    // Tenaza Izquierda
    int rL = 15 + clawYOffset;
    p(rL, 1, 'K'); p(rL, 2, 'K'); p(rL, 3, 'K');
    p(rL + 1, 0, 'K'); p(rL + 1, 1, 'A'); p(rL + 1, 2, 'L'); p(rL + 1, 3, 'K');
    p(rL + 2, 0, 'K'); p(rL + 2, 1, 'A'); p(rL + 2, 2, 'S'); p(rL + 2, 3, 'K'); p(rL + 2, 4, 'K');
    p(rL + 3, 1, 'K'); p(rL + 3, 2, 'K'); p(rL + 3, 3, 'K'); p(rL + 3, 4, 'A'); p(rL + 3, 5, 'K');

    // Tenaza Derecha
    int rR = 15 + clawYOffset;
    p(rR, 17, 'K'); p(rR, 18, 'K'); p(rR, 19, 'K');
    p(rR + 1, 16, 'K'); p(rR + 1, 17, 'L'); p(rR + 1, 18, 'A'); p(rR + 1, 19, 'K');
    p(rR + 2, 15, 'K'); p(rR + 2, 16, 'K'); p(rR + 2, 17, 'S'); p(rR + 2, 18, 'A'); p(rR + 2, 19, 'K');
    p(rR + 3, 14, 'K'); p(rR + 3, 15, 'A'); p(rR + 3, 16, 'K'); p(rR + 3, 17, 'K'); p(rR + 3, 18, 'K');

    // ── 6. PATAS SEGMENTADAS (PATITAS) ────────────────────────────────
    // Patas lado izquierdo
    // Pata L1
    p(17, 4, 'K'); p(18, 3, 'K'); p(18, 4, 'A'); p(19, 2, 'K'); p(19, 3, 'S'); p(20, 2, 'K');
    // Pata L2
    p(17, 5, 'K'); p(18, 5, 'A'); p(19, 4, 'K'); p(19, 5, 'S'); p(20, 4, 'K');
    // Pata L3
    p(17, 6, 'K'); p(18, 6, 'S'); p(19, 6, 'K'); p(20, 6, 'K');

    // Patas lado derecho
    // Pata R1
    p(17, 16, 'K'); p(18, 16, 'A'); p(18, 17, 'K'); p(19, 17, 'S'); p(19, 18, 'K'); p(20, 18, 'K');
    // Pata R2
    p(17, 15, 'K'); p(18, 15, 'A'); p(19, 15, 'S'); p(19, 16, 'K'); p(20, 16, 'K');
    // Pata R3
    p(17, 14, 'K'); p(18, 14, 'S'); p(19, 14, 'K'); p(20, 14, 'K');

    return grid;
  }
}


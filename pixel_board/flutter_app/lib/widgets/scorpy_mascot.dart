import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'scorpy_painter.dart';

/// Widget que muestra la mascota virtual **Scorpy** junto a un bocadillo de texto.
///
/// El escorpión se renderiza con [`ScorpyPainter`] (CustomPainter pixel art)
/// escalado con Nearest-Neighbor implícito. El bocadillo sigue el estilo
/// retro de la aplicación: fondo crema, borde negro grueso y sombra sin
/// difuminado.
///
/// Soporta tres estados visuales ([`ScorpyState`]) con animación:
/// - `idle`: bombilla apagada, pose neutral, leve rebote.
/// - `tipOn`: bombilla encendida con halo pulsante, escala oscilante.
/// - `celebrating`: tenazas elevadas, bombilla encendida, rebote fuerte.
class ScorpyMascot extends StatefulWidget {
  /// Texto que aparecerá dentro del bocadillo.
  final String message;

  /// Estado visual de la mascota.
  final ScorpyState state;

  /// Tamaño en píxeles lógicos del lado del escorpión (default 64).
  final double size;

  const ScorpyMascot({
    super.key,
    required this.message,
    this.state = ScorpyState.idle,
    this.size = 64,
  });

  @override
  State<ScorpyMascot> createState() => _ScorpyMascotState();
}

class _ScorpyMascotState extends State<ScorpyMascot>
    with TickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final AnimationController _bounceCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _updateAnimation();
  }

  @override
  void didUpdateWidget(covariant ScorpyMascot old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _updateAnimation();
  }

  void _updateAnimation() {
    switch (widget.state) {
      case ScorpyState.idle:
        _animCtrl.stop();
        _animCtrl.value = 0;
        _bounceCtrl.stop();
        _bounceCtrl.value = 0;
        break;
      case ScorpyState.tipOn:
        _animCtrl.repeat(reverse: true);
        _bounceCtrl.repeat(reverse: true);
        break;
      case ScorpyState.celebrating:
        _animCtrl.repeat(reverse: true);
        _bounceCtrl.repeat(reverse: true);
        break;
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _bounceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spriteWidth = widget.size;
    final spriteHeight = widget.size * 1.25;
    final boxSize = spriteWidth * 1.5;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Escorpión pixel art sobre fondo cuadrado redondeado cream
        AnimatedBuilder(
          animation: _bounceCtrl,
          builder: (context, child) {
            final bounceOffset = widget.state == ScorpyState.celebrating
                ? math.sin(_bounceCtrl.value * math.pi) * -4.0
                : math.sin(_bounceCtrl.value * math.pi) * -1.5;
            return Transform.translate(
              offset: Offset(0, bounceOffset),
              child: child,
            );
          },
          child: SizedBox(
            width: boxSize,
            height: boxSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Fondo cuadrado redondeado cream con borde negro
                Container(
                  width: boxSize,
                  height: boxSize,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3D6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black, width: 3),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black,
                        offset: Offset(4, 4),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                ),
                // Escorpión pixel art con animación de glow
                AnimatedBuilder(
                  animation: _animCtrl,
                  builder: (context, _) {
                    return CustomPaint(
                      size: Size(spriteWidth, spriteHeight),
                      painter: ScorpyPainter(
                        state: widget.state,
                        animValue: _animCtrl.value,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Bocadillo de texto retro
        Container(
          constraints: const BoxConstraints(maxWidth: 240),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3D6),
            border: Border.all(color: Colors.black, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black,
                offset: Offset(4, 4),
                blurRadius: 0,
              ),
            ],
          ),
          child: Text(
            widget.message,
            textAlign: TextAlign.center,
            style: GoogleFonts.pressStart2p(
              fontSize: 8,
              color: Colors.black,
            ),
          ),
        ),
      ],
    );
  }
}

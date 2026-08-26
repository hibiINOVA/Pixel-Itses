import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Texto pixel con borde grueso, reutilizable para timer y contador.
class RetroCounter extends StatelessWidget {
  const RetroCounter({
    super.key,
    required this.text,
    this.fontSize = 16,
    this.color = Colors.white,
  });

  final String text;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.pressStart2p(
        fontSize: fontSize,
        color: color,
        shadows: const [
          Shadow(color: Colors.black, offset: Offset(2, 0)),
          Shadow(color: Colors.black, offset: Offset(-2, 0)),
          Shadow(color: Colors.black, offset: Offset(0, 2)),
          Shadow(color: Colors.black, offset: Offset(0, -2)),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RetroButton extends StatelessWidget {
  const RetroButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = const Color(0xFFD62828),
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: Colors.black, width: 4),
          boxShadow: const [
            BoxShadow(
              color: Colors.black,
              offset: Offset(6, 6),
              blurRadius: 0,
            ),
          ],
        ),
        child: Text(
          label,
          style: GoogleFonts.pressStart2p(
            fontSize: 14,
            color: const Color(0xFFFFF3D6),
          ),
        ),
      ),
    );
  }
}
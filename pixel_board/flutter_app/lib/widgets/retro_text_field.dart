import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class RetroTextField extends StatelessWidget {
  const RetroTextField({
    super.key,
    required this.hint,
    required this.controller,
    this.maxLength = 16,
    this.onSubmitted,
  });

  final String hint;
  final TextEditingController controller;
  final int maxLength;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3D6),
        border: Border.all(color: Colors.black, width: 4),
        boxShadow: const [
          BoxShadow(
            color: Colors.black,
            offset: Offset(6, 6),
            blurRadius: 0,
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        maxLength: maxLength,
        textCapitalization: TextCapitalization.characters,
        onSubmitted: onSubmitted,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_\-\s]')),
        ],
        style: GoogleFonts.pressStart2p(fontSize: 14, color: Colors.black),
        decoration: InputDecoration(
          hintText: hint,
          counterText: '',
          hintStyle: GoogleFonts.pressStart2p(
            fontSize: 14,
            color: const Color(0xFF8A8A8A),
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        ),
      ),
    );
  }
}
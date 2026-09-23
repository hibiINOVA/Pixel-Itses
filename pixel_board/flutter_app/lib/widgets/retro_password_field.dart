import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class RetroPasswordField extends StatefulWidget {
  const RetroPasswordField({
    super.key,
    required this.hint,
    required this.controller,
    this.focusNode,
    this.onSubmitted,
  });

  final String hint;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;

  @override
  State<RetroPasswordField> createState() => _RetroPasswordFieldState();
}

class _RetroPasswordFieldState extends State<RetroPasswordField> {
  bool _obscure = true;

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
        controller: widget.controller,
        focusNode: widget.focusNode,
        obscureText: _obscure,
        maxLength: 64,
        onSubmitted: widget.onSubmitted,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9!@#$%^&*()_\- ]')),
        ],
        style: GoogleFonts.pressStart2p(fontSize: 14, color: Colors.black),
        decoration: InputDecoration(
          hintText: widget.hint,
          counterText: '',
          hintStyle: GoogleFonts.pressStart2p(
            fontSize: 14,
            color: const Color(0xFF8A8A8A),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          suffixIcon: GestureDetector(
            onTap: () => setState(() => _obscure = !_obscure),
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                _obscure ? Icons.visibility_off : Icons.visibility,
                color: Colors.black87,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

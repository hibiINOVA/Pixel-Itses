import 'package:flutter/material.dart';

/// Paleta fija de colores del mockup (coincide con el backend).
const kPalette = <String>[
  '#D3D3D3', // gris claro
  '#4A4A4A', // gris oscuro
  '#FFD700', // amarillo
  '#FF8C42', // naranja claro
  '#FF6B35', // naranja oscuro
  '#FF4136', // rojo
  '#D62828', // rojo oscuro
  '#800000', // granate
];

/// Selector de colores fijo con borde blanco para el color activo.
class ColorPalette extends StatelessWidget {
  const ColorPalette({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.white, width: 4),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final color in kPalette) ...[
              PixelSwatch(
                color: color,
                selected: color == selected,
                onTap: () => onSelect(color),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// Un color individual de la paleta.
class PixelSwatch extends StatelessWidget {
  const PixelSwatch({
    super.key,
    required this.color,
    required this.onTap,
    this.selected = false,
  });

  final String color;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final parsed = Color(int.parse(color.substring(1), radix: 16) | 0xFF000000);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: parsed,
          border: Border.all(
            color: selected ? Colors.white : Colors.black,
            width: selected ? 4 : 2,
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Estado del canvas del jugador. ChangeNotifier para repintar eficientemente.
class PixelState extends ChangeNotifier {
  PixelState({this.size = 32})
      : _canvas = List.generate(size, (_) => List.filled(size, '#FFFFFF'));

  int size;
  late List<List<String>> _canvas;

  int? pixelsRemaining;
  int? cooldownEndsAt;

  List<List<String>> get canvas => _canvas;

  bool inBounds(int x, int y) => x >= 0 && x < size && y >= 0 && y < size;

  String colorAt(int x, int y) => _canvas[y][x];

  Color parseColor(String hex) {
    return Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
  }

  void applySnapshot(List<List<String>> snapshot) {
    if (snapshot.isEmpty) return;
    _canvas = snapshot;
    size = snapshot.length;
    notifyListeners();
  }

  void applyPixelUpdate(int x, int y, String color) {
    if (!inBounds(x, y)) return;
    _canvas[y][x] = color;
    notifyListeners();
  }

  void applyCooldown({required int pixelsRemaining, required int? cooldownEndsAt}) {
    this.pixelsRemaining = pixelsRemaining;
    this.cooldownEndsAt = cooldownEndsAt;
    notifyListeners();
  }

  void reset() {
    _canvas = List.generate(size, (_) => List.filled(size, '#FFFFFF'));
    notifyListeners();
  }
}

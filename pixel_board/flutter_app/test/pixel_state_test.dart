import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_board/models/pixel_state.dart';

void main() {
  group('PixelState', () {
    test('arranca en blanco 32x32', () {
      final state = PixelState();
      expect(state.size, 32);
      expect(state.colorAt(0, 0), '#FFFFFF');
      expect(state.colorAt(31, 31), '#FFFFFF');
    });

    test('applySnapshot deriva el tamaño de las filas', () {
      final state = PixelState();
      final snapshot = List.generate(16, (_) => List.filled(16, '#FF6B35'));
      state.applySnapshot(snapshot);

      expect(state.size, 16);
      expect(state.colorAt(5, 5), '#FF6B35');
    });

    test('applyPixelUpdate cambia solo esa celda y notifica', () {
      final state = PixelState();
      var notificaciones = 0;
      state.addListener(() => notificaciones++);

      state.applyPixelUpdate(3, 4, '#D62828');

      expect(notificaciones, 1);
      expect(state.colorAt(3, 4), '#D62828');
      expect(state.colorAt(4, 3), '#FFFFFF');
    });

    test('applyPixelUpdate fuera de rango no notifica ni crashea', () {
      final state = PixelState();
      var notificaciones = 0;
      state.addListener(() => notificaciones++);

      state.applyPixelUpdate(-1, 0, '#D62828');
      state.applyPixelUpdate(0, 99, '#D62828');

      expect(notificaciones, 0);
    });

    test('parseColor convierte hex a Color opaco', () {
      final state = PixelState();
      expect(state.parseColor('#FF6B35').toARGB32(), 0xFFFF6B35);
    });

    test('applyCooldown guarda el estado del servidor', () {
      final state = PixelState();
      state.applyCooldown(pixelsRemaining: 2, cooldownEndsAt: 123456);

      expect(state.pixelsRemaining, 2);
      expect(state.cooldownEndsAt, 123456);

      state.applyCooldown(pixelsRemaining: 5, cooldownEndsAt: null);
      expect(state.pixelsRemaining, 5);
      expect(state.cooldownEndsAt, isNull);
    });
  });
}
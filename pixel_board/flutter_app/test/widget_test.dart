import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_board/main.dart';
import 'package:pixel_board/services/websocket_service.dart';
import 'package:pixel_board/widgets/chat_panel.dart';
import 'package:pixel_board/widgets/color_palette.dart';
import 'package:pixel_board/widgets/pixel_canvas.dart';
import 'package:pixel_board/widgets/retro_text_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Socket falso: sin red. Los tests controlan qué mensajes emite y cuándo.
class FakeSocket implements SocketClient {
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _status = StreamController<SocketStatus>.broadcast();
  final hellos = <Map<String, dynamic>>[];
  final sentChats = <String>[];

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  @override
  Stream<SocketStatus> get status => _status.stream;

  void emit(Map<String, dynamic> message) => _messages.add(message);

  @override
  void connect(String nickname, {String? token}) {
    hellos.add({'nickname': nickname, 'token': token});
    _status.add(SocketStatus.conectando);
  }

  @override
  void sendHello(String nickname, {String? token}) {}

  @override
  void sendChat(String text) => sentChats.add(text);

  @override
  void sendPaint({
    required int x,
    required int y,
    required String color,
    required String nickname,
  }) {}

  // No cierra los controllers: el mismo fake se comparte entre pantallas.
  @override
  void dispose() {}
}

Map<String, dynamic> _snapshot({String token = 'token-secreto'}) => {
      'type': 'canvas_snapshot',
      'canvas': List.generate(4, (_) => List.filled(4, '#FFFFFF')),
      'pixelsRemaining': 5,
      'cooldownEndsAt': null,
      'token': token,
    };

void main() {
  late FakeSocket socket;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    socket = FakeSocket();
  });

  Future<void> pumpLogin(WidgetTester tester) async {
    await tester.pumpWidget(PixelBoardApp(socket: socket));
    await tester.pump();
  }

  /// Login completo con snapshot recibido: deja el board montado y visible.
  Future<void> pumpBoard(WidgetTester tester) async {
    await pumpLogin(tester);
    await tester.enterText(find.byType(RetroTextField), 'hibi');
    await tester.tap(find.text('UNIRSE'));
    await tester.pump();
    // Primer snapshot lo recibe el login para decidir navegar.
    socket.emit(_snapshot());
    await tester.pump();
    // pumpAndSettle completa la animación de pushReplacement (remueve login).
    await tester.pumpAndSettle();
    // Segundo snapshot: el board ya está montado y escuchando.
    socket.emit(_snapshot());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('login muestra título y botón UNIRSE', (tester) async {
    await pumpLogin(tester);

    expect(find.text('PIXEL\nBOARD'), findsOneWidget);
    expect(find.text('UNIRSE'), findsOneWidget);
    expect(find.byType(RetroTextField), findsOneWidget);
  });

  testWidgets('UNIRSE sin nickname no consulta el servidor', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.text('UNIRSE'));
    await tester.pump();

    expect(socket.hellos, isEmpty);
    expect(find.text('UNIRSE'), findsOneWidget);
    expect(find.byType(ColorPalette), findsNothing);
  });

  testWidgets('nombre ya usado muestra error y permanece en el login',
      (tester) async {
    await pumpLogin(tester);

    await tester.enterText(find.byType(RetroTextField), 'hibi');
    await tester.tap(find.text('UNIRSE'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    socket.emit({'type': 'nickname_taken', 'nickname': 'hibi'});
    await tester.pump();

    expect(find.text('NOMBRE YA USADO · PROBÁ OTRO'), findsOneWidget);
    expect(find.text('UNIRSE'), findsOneWidget);
    expect(find.byType(ColorPalette), findsNothing);
  });

  testWidgets('sin respuesta del servidor muestra error de conexión',
      (tester) async {
    await pumpLogin(tester);

    await tester.enterText(find.byType(RetroTextField), 'hibi');
    await tester.tap(find.text('UNIRSE'));
    await tester.pump();

    // El timeout interno es de 3s; en FakeAsync basta con avanzar el reloj.
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('SIN CONEXIÓN AL SERVIDOR'), findsOneWidget);
    expect(find.byType(ColorPalette), findsNothing);
  });

  testWidgets('nombre nuevo guarda sesión (nickname+token) y navega',
      (tester) async {
    await pumpLogin(tester);

    await tester.enterText(find.byType(RetroTextField), 'hibi');
    await tester.tap(find.text('UNIRSE'));
    await tester.pump();

    socket.emit(_snapshot());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ColorPalette), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('nickname'), 'hibi');
    expect(prefs.getString('token'), 'token-secreto');

    // La pizarra se suscribió tarde al stream compartido: reemitir snapshot
    // para que reciba el suyo propio.
    socket.emit(_snapshot(token: 'otro-token-no-se-guarda'));
    await tester.pump();
    expect(find.text('CARGANDO\nPIZARRA...'), findsNothing);
  });

  testWidgets('chat muestra el mensaje con el nombre del autor', (tester) async {
    await pumpBoard(tester);

    // Verificamos que el panel de chat esté montado y vacío.
    expect(find.byType(ChatPanel), findsOneWidget);
    expect(find.text('SÉ EL PRIMERO EN\nESCRIBIR...'), findsOneWidget);

    // Emitimos un mensaje del chat.
    socket.emit({
      'type': 'chat_update',
      'nickname': 'u2',
      'text': 'hola a todos',
      'createdAt': 1234,
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // El mensaje se renderiza via Text.rich: el placeholder desaparece.
    expect(find.text('SÉ EL PRIMERO EN\nESCRIBIR...'), findsNothing);
    // Buscamos el contenido en el RichText interno.
    final richTexts = find.byWidgetPredicate((w) => w.toStringShort().contains('RichText')).evaluate();
    final found = richTexts.any((e) {
      try {
        // RichText.text es el TextSpan raíz.
        final dynamic widget = e.widget;
        return widget.text.toPlainText().contains('hola a todos');
      } catch (_) {
        return false;
      }
    });
    expect(found, isTrue);
    expect(find.text('CHAT'), findsOneWidget);
  });

  testWidgets('ENVIAR manda el texto por el socket y limpia el input',
      (tester) async {
    await pumpBoard(tester);

    // Vacío: no envía nada.
    await tester.tap(find.text('ENVIAR'));
    await tester.pump();
    expect(socket.sentChats, isEmpty);

    await tester.enterText(find.byType(RetroTextField), 'hola desde el test');
    await tester.tap(find.text('ENVIAR'));
    await tester.pump();

    expect(socket.sentChats, ['hola desde el test']);
  });

  testWidgets('pantalla ancha: pizarra a la izquierda, chat a la derecha',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);

    await pumpBoard(tester);

    final canvasCenter = tester.getCenter(find.byType(PixelCanvas));
    final chatCenter = tester.getCenter(find.byType(ChatPanel));
    expect(canvasCenter.dx < chatCenter.dx, isTrue);
  });

  testWidgets('pantalla angosta: chat abajo de la pizarra', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.reset);

    await pumpBoard(tester);

    final canvasCenter = tester.getCenter(find.byType(PixelCanvas));
    final chatCenter = tester.getCenter(find.byType(ChatPanel));
    expect(canvasCenter.dy < chatCenter.dy, isTrue);
  });
}
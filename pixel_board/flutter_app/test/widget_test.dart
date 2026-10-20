import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_board/main.dart';
import 'package:pixel_board/screens/login_screen.dart';
import 'package:pixel_board/screens/matchmaking_screen.dart';
import 'package:pixel_board/screens/game_screen.dart';
import 'package:pixel_board/services/user_store.dart';
import 'package:pixel_board/services/websocket_service.dart';
import 'package:pixel_board/widgets/chat_panel.dart';
import 'package:pixel_board/widgets/color_palette.dart';
import 'package:pixel_board/widgets/pixel_canvas.dart';
import 'package:pixel_board/widgets/retro_text_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSocket implements SocketClient {
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _status = StreamController<SocketStatus>.broadcast();
  final hellos = <Map<String, dynamic>>[];
  final sentChats = <String>[];
  final sentPaints = <Map<String, dynamic>>[];
  int sentFinishTurns = 0;
  int sentNextGames = 0;
  int sentStartMatchmakings = 0;

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  @override
  Stream<SocketStatus> get status => _status.stream;

  void emit(Map<String, dynamic> message) => _messages.add(message);

  @override
  void connect(String nickname, {String? token}) {
    hellos.add({'nickname': nickname, 'token': token});
    Future.microtask(() {
      _status.add(SocketStatus.conectando);
      Future.microtask(() => _status.add(SocketStatus.conectado));
    });
  }

  @override
  void sendHello(String nickname) {}

  @override
  void sendChat(String text) => sentChats.add(text);

  @override
  void sendPaint({required int x, required int y, required String color, required String nickname}) {
    sentPaints.add({'x': x, 'y': y, 'color': color, 'nickname': nickname});
  }

  @override
  void sendFinishTurn() { sentFinishTurns++; }

  @override
  void sendNextGame() { sentNextGames++; }

  @override
  void sendStartMatchmaking() { sentStartMatchmakings++; }

  @override
  void dispose() {}
}

Map<String, dynamic> _authOk({
  String token = 'token-secreto',
  int wins = 0,
  int losses = 0,
  int draws = 0,
}) => {
      'type': 'auth_ok',
      'token': token,
      'wins': wins,
      'losses': losses,
      'draws': draws,
    };

Map<String, dynamic> _gameStart({
  String player1 = 'alice',
  String player2 = 'bob',
  String opponent = 'bob',
  int previewSeconds = 15,
  int drawSeconds = 60,
}) => {
      'type': 'game_start',
      'roomId': 'room_1',
      'player1': player1,
      'player2': player2,
      'opponent': opponent,
      'previewSeconds': previewSeconds,
      'drawSeconds': drawSeconds,
      'referenceImage': List.generate(32, (_) => List.filled(32, '#FFFFFF')),
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
    await tester.pump();
    await tester.pump();
  }

  Future<void> pumpMatchmaking(WidgetTester tester) async {
    await pumpLogin(tester);
    await tester.enterText(find.byType(RetroTextField).first, 'alice');
    await tester.tap(find.text('UNIRSE'));
    await tester.pump();
    socket.emit(_authOk());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pumpGame(WidgetTester tester) async {
    await pumpMatchmaking(tester);
    expect(find.byType(MatchmakingScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 50));
    socket.emit(_gameStart());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  // ─── Login ─────────────────────────────────────────────

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
  });

  testWidgets('nombre ya usado muestra alerta y permanece en el login', (tester) async {
    await pumpLogin(tester);
    await tester.enterText(find.byType(RetroTextField).first, 'hibi');
    await tester.tap(find.text('UNIRSE'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));
    socket.emit({'type': 'nickname_taken', 'nickname': 'hibi'});
    await tester.pump();
    expect(find.text('NOMBRE YA USADO · ELEGÍ OTRO'), findsOneWidget);
    expect(find.text('UNIRSE'), findsOneWidget);
  });

  testWidgets('sin respuesta del servidor muestra error de conexión', (tester) async {
    await pumpLogin(tester);
    await tester.enterText(find.byType(RetroTextField).first, 'hibi');
    await tester.tap(find.text('UNIRSE'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('SIN CONEXIÓN AL SERVIDOR'), findsOneWidget);
  });

  testWidgets('nombre nuevo guarda sesión y navega a matchmaking', (tester) async {
    await pumpLogin(tester);
    await tester.enterText(find.byType(RetroTextField).first, 'hibi');
    await tester.tap(find.text('UNIRSE'));
    await tester.pump();
    socket.emit(_authOk());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    expect(find.byType(MatchmakingScreen), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('nickname'), 'hibi');
  });

  // ─── Token de reconexión (bug de lockout) ─────────────

  Future<void> pumpLoginScreen(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: LoginScreen(socket: socket)));
    await tester.pump();
  }

  testWidgets('login envía el token guardado y persiste el nuevo', (tester) async {
    SharedPreferences.setMockInitialValues({
      'nickname': 'hibi',
      'token': 'token-viejo',
    });
    await pumpLoginScreen(tester);
    await tester.enterText(find.byType(RetroTextField).first, 'hibi');
    await tester.tap(find.text('UNIRSE'));
    await tester.pump();
    await tester.pump();
    expect(socket.hellos.last['nickname'], 'hibi');
    expect(socket.hellos.last['token'], 'token-viejo');
    socket.emit(_authOk(token: 'token-nuevo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('token'), 'token-nuevo');
  });

  testWidgets('login con otro nickname no reusa el token ajeno', (tester) async {
    SharedPreferences.setMockInitialValues({
      'nickname': 'hibi',
      'token': 'token-viejo',
    });
    await pumpLoginScreen(tester);
    await tester.enterText(find.byType(RetroTextField).first, 'otro');
    await tester.tap(find.text('UNIRSE'));
    await tester.pump();
    await tester.pump();
    expect(socket.hellos.last['nickname'], 'otro');
    expect(socket.hellos.last['token'], isNull);
  });

  testWidgets('nickname_taken en matchmaking vuelve al login y limpia sesión', (tester) async {
    await pumpMatchmaking(tester);
    expect(find.byType(MatchmakingScreen), findsOneWidget);
    socket.emit({'type': 'nickname_taken', 'nickname': 'alice'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(MatchmakingScreen), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('nickname'), isNull);
    expect(prefs.getString('token'), isNull);
  });

  testWidgets('UserStore persiste y borra el token de sesión', (tester) async {
    final store = UserStore();
    await store.saveToken('tok-123');
    expect(await store.getToken(), 'tok-123');
    await store.clearSession();
    expect(await store.getToken(), isNull);
  });

  testWidgets('matchmaking muestra stats del jugador', (tester) async {
    await pumpMatchmaking(tester);
    expect(find.text('ALICE'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    expect(find.text('V'), findsOneWidget);
    expect(find.text('D'), findsOneWidget);
    expect(find.text('E'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('matchmaking recibe game_start y navega al juego', (tester) async {
    await pumpMatchmaking(tester);
    socket.emit(_gameStart());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('game_start muestra pantalla de preview', (tester) async {
    await pumpGame(tester);
    expect(find.text('MEMORIZÁ LA IMAGEN'), findsOneWidget);
    expect(find.byType(PixelCanvas), findsOneWidget);
  });

  testWidgets('draw_start muestra canvas, paleta y chat (dibujo simultáneo)', (tester) async {
    await pumpGame(tester);
    socket.emit({'type': 'draw_start', 'drawSeconds': 60});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('DIBUJÁ · AMBOS AL MISMO TIEMPO'), findsOneWidget);
    expect(find.byType(ColorPalette), findsOneWidget);
    expect(find.text('TERMINAR TURNO'), findsOneWidget);
    expect(find.byType(ChatPanel), findsOneWidget);
  });

  testWidgets('game_results muestra ganador y puntuaciones', (tester) async {
    await pumpGame(tester);
    socket.emit({
      'type': 'game_results',
      'winner': 'alice',
      'player1': 'alice',
      'player2': 'bob',
      'player1Score': 85,
      'player2Score': 70,
      'player1Canvas': List.generate(32, (_) => List.filled(32, '#FF0000')),
      'player2Canvas': List.generate(32, (_) => List.filled(32, '#00FF00')),
      'reference': List.generate(32, (_) => List.filled(32, '#FFFFFF')),
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('¡GANASTE!'), findsOneWidget);
    expect(find.text('85%'), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);
    expect(find.text('SIGUIENTE PARTIDA'), findsOneWidget);
  });

  testWidgets('game_results con empate muestra EMPATE', (tester) async {
    await pumpGame(tester);
    socket.emit({
      'type': 'game_results',
      'winner': 'tie',
      'player1': 'alice',
      'player2': 'bob',
      'player1Score': 80,
      'player2Score': 80,
      'player1Canvas': List.generate(32, (_) => List.filled(32, '#FF0000')),
      'player2Canvas': List.generate(32, (_) => List.filled(32, '#00FF00')),
      'reference': List.generate(32, (_) => List.filled(32, '#FFFFFF')),
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('EMPATE'), findsOneWidget);
  });

  testWidgets('game_results con derrota muestra PERDISTE', (tester) async {
    await pumpGame(tester);
    socket.emit({
      'type': 'game_results',
      'winner': 'bob',
      'player1': 'alice',
      'player2': 'bob',
      'player1Score': 50,
      'player2Score': 90,
      'player1Canvas': List.generate(32, (_) => List.filled(32, '#FF0000')),
      'player2Canvas': List.generate(32, (_) => List.filled(32, '#00FF00')),
      'reference': List.generate(32, (_) => List.filled(32, '#FFFFFF')),
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('PERDISTE'), findsOneWidget);
  });

  // ─── Chat ─────────────────────────────────────────────

  testWidgets('chat muestra el mensaje con el nombre del autor', (tester) async {
    await pumpGame(tester);
    socket.emit({'type': 'draw_start', 'drawSeconds': 60});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ChatPanel), findsOneWidget);
    expect(find.text('ESCRIBÍ ALGO...'), findsOneWidget);
    socket.emit({
      'type': 'chat_update',
      'nickname': 'bob',
      'text': 'hola',
      'createdAt': 1234,
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('ESCRIBÍ ALGO...'), findsNothing);
  });
}

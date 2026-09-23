import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/pixel_state.dart';
import '../services/user_store.dart';
import '../services/websocket_service.dart';
import '../widgets/chat_panel.dart';
import '../widgets/color_palette.dart';
import '../widgets/pixel_canvas.dart';
import '../widgets/scorpy_mascot.dart';
import '../widgets/scorpy_painter.dart';
import 'matchmaking_screen.dart';
import 'login_screen.dart';

/// Pantalla principal del juego: maneja las fases de memorización,
/// dibujo simultáneo y resultados.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.socket, required this.gameStart});

  final SocketClient? socket;
  final Map<String, dynamic> gameStart;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final UserStore _userStore = UserStore();
  late final SocketClient _socket = widget.socket ?? WebsocketService();
  StreamSubscription<Map<String, dynamic>>? _messagesSub;

  late final String _opponent = widget.gameStart['opponent'] as String;
  late final String _myNickname = widget.gameStart['player1'] == widget.gameStart['opponent']
      ? widget.gameStart['player2'] as String
      : widget.gameStart['player1'] as String;
  late final String _roomId = widget.gameStart['roomId'] as String;
  late final int _previewSeconds = (widget.gameStart['previewSeconds'] as num?)?.toInt() ?? 15;

  // Referencia
  List<List<String>> _referenceImage = [];
  late final PixelState _referenceState = PixelState();
  List<String> _dynamicPalette = [];

  // Canvas del jugador actual
  late final PixelState _myCanvas = PixelState();
  String _selectedColor = kPalette.first;

  // Canvas del oponente (para pantalla de resultados)
  List<List<String>> _opponentCanvas = [];
  int _myScore = 0;
  int _opponentScore = 0;
  String _winner = '';
  bool _forfeit = false;

  // Fase del juego: image_preview, drawing, waiting_results, results
  String _phase = 'image_preview';
  int _timeLeft = 0;
  Timer? _countdownTimer;
  bool _socketHandedOff = false;
  bool _opponentFinished = false;
  bool _myTurnFinished = false;
  bool _isNavigating = false;

  // ── Scorpy ─────────────────────────────────────────────────────────
  ScorpyState _scorpyState = ScorpyState.tipOn;
  String _scorpyMessage = '¡MEMORIZÁ TODO! SE BORRA EN...';
  Timer? _scorpyRotateTimer;
  int _scorpyMsgIndex = 0;

  static const _previewMessages = [
    '¡MEMORIZÁ TODO! SE BORRA EN...',
    'FIJATE EN LOS COLORES Y LAS FORMAS',
    'DIVIDÍ LA IMAGEN EN ZONAS',
    ' recordá los bordes primero',
    '¡CONCENTRATE, QUE YA LO TENÉS!',
  ];

  static const _drawingMessages = [
    '¡DIBUJÁ LO QUE RECUERDAS!',
    '¡DIBUJÁ CON CONFIANZA!',
    'NO TE PREOCUPES POR LOS DETALLES',
    '¡LO ESTÁS HACIENDO MUY BIEN!',
    'CENTRATE EN LAS FORMAS PRINCIPALES',
    '¡VAS COMO LOCO, SEGUÍ ASÍ!',
    '¡VOS PODÉS, DALE TODO!',
  ];

  static const _waitingMessages = [
    '¡TERMINASTE! ESPERANDO RESULTADOS...',
    '¡BUEN TRABAJO! ESPERANDO AL OPONENTE...',
    'TU DIBUJO ESTUVO GENIAL',
    'EL RESULTADO ESTÁ EN MANOS DEL JUEGO',
    '¡ESPERÁ, QUE YA SALE!',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _updateDynamicPalette() {
    final colors = <String>{};
    for (final row in _referenceImage) {
      for (final color in row) {
        if (color.toUpperCase() != '#FFFFFF') {
          colors.add(color.toUpperCase());
        }
      }
    }
    if (colors.isEmpty) {
      _dynamicPalette = List.from(kPalette);
    } else {
      _dynamicPalette = colors.toList();
    }
    if (!_dynamicPalette.contains(_selectedColor.toUpperCase())) {
      _selectedColor = _dynamicPalette.first;
    }
  }

  void _init() {
    // Cargar imagen de referencia
    final raw = widget.gameStart['referenceImage'] as List?;
    if (raw != null) {
      _referenceImage = raw
          .map((row) => (row as List).map((c) => c as String).toList())
          .toList();
      _referenceState.applySnapshot(_referenceImage);
      _updateDynamicPalette();
    }

    _messagesSub = _socket.messages.listen(_handleMessage);

    // Empezar countdown de preview
    _phase = 'image_preview';
    _timeLeft = _previewSeconds;
    _startCountdown();
    _startScorpyRotation(_previewMessages);
  }

  void _startScorpyRotation(List<String> messages) {
    _stopScorpyRotation();
    _scorpyMsgIndex = 0;
    _scheduleNextScorpyMessage(messages);
  }

  void _scheduleNextScorpyMessage(List<String> messages) {
    final delay = 5000 + math.Random().nextInt(10001); // 5-15 segundos
    _scorpyRotateTimer = Timer(Duration(milliseconds: delay), () {
      if (!mounted) return;
      setState(() {
        _scorpyMsgIndex = (_scorpyMsgIndex + 1) % messages.length;
        _scorpyMessage = messages[_scorpyMsgIndex];
      });
      _scheduleNextScorpyMessage(messages);
    });
  }

  void _stopScorpyRotation() {
    _scorpyRotateTimer?.cancel();
    _scorpyRotateTimer = null;
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        _timeLeft--;
        if (_timeLeft <= 0) {
          timer.cancel();
          // El servidor se encarga de avanzar la fase
        }
      });
    });
  }

  void _handleMessage(Map<String, dynamic> message) {
    switch (message['type']) {
      case 'draw_start':
        final drawSec = (message['drawSeconds'] as num?)?.toInt() ?? 60;
        setState(() {
          _phase = 'drawing';
          _myTurnFinished = false;
          _opponentFinished = false;
          _timeLeft = drawSec;
          _scorpyState = ScorpyState.tipOn;
          _scorpyMessage = '¡DIBUJÁ LO QUE RECUERDAS!';
        });
        _countdownTimer?.cancel();
        _startCountdown();
        _startScorpyRotation(_drawingMessages);
        break;

      case 'pixel_update':
        // Recibir pixeles del oponente mientras dibuja
        final x = (message['x'] as num?)?.toInt();
        final y = (message['y'] as num?)?.toInt();
        final color = message['color'] as String?;
        if (x != null && y != null && color != null && _phase == 'drawing') {
          _opponentCanvas.isNotEmpty ? _opponentCanvas[y][x] = color : null;
        }
        break;

      case 'player_finished':
        setState(() {
          _opponentFinished = true;
          _scorpyState = ScorpyState.idle;
          _scorpyMessage = '¡EL OTRO JUGADOR TERMINÓ!';
        });
        break;

      case 'game_results':
        _countdownTimer?.cancel();
        _stopScorpyRotation();
        final winner = message['winner'] as String? ?? '';
        final p1Score = (message['player1Score'] as num?)?.toInt() ?? 0;
        final p2Score = (message['player2Score'] as num?)?.toInt() ?? 0;
        final p1Canvas = (message['player1Canvas'] as List?)
            ?.map((row) => (row as List).map((c) => c as String).toList())
            .toList();
        final p2Canvas = (message['player2Canvas'] as List?)
            ?.map((row) => (row as List).map((c) => c as String).toList())
            .toList();
        final forfeit = message['forfeit'] as bool? ?? false;

        final resultPlayer1 = message['player1'] as String;
        final myCanvasData = _myNickname == resultPlayer1 ? p1Canvas : p2Canvas;
        if (myCanvasData != null && myCanvasData.isNotEmpty) {
          _myCanvas.applySnapshot(myCanvasData);
        }

        setState(() {
          _phase = 'results';
          _winner = winner;
          _myScore = _myNickname == resultPlayer1 ? p1Score : p2Score;
          _opponentScore = _myNickname == resultPlayer1 ? p2Score : p1Score;
          _opponentCanvas = (_myNickname == resultPlayer1 ? p2Canvas : p1Canvas) ?? [];
          _forfeit = forfeit;

          // Actualizar Scorpy según resultado
          final didWin = winner == _myNickname;
          final isTie = winner == 'tie';
          if (didWin || forfeit) {
            _scorpyState = ScorpyState.celebrating;
            _scorpyMessage = '¡GANASTE! ¡ERES UN CRACK!';
          } else if (isTie) {
            _scorpyState = ScorpyState.idle;
            _scorpyMessage = '¡EMPATE! PARTIDA ÉPICA';
          } else {
            _scorpyState = ScorpyState.tipOn;
            _scorpyMessage = '¡NO RINDAS, VOLVÉ A INTENTARLO!';
          }
        });

        // Actualizar canvas de referencia para mostrar en resultados
        final refRaw = message['reference'] as List?;
        if (refRaw != null && refRaw.isNotEmpty) {
          _referenceImage = refRaw
              .map((row) => (row as List).map((c) => c as String).toList())
              .toList();
          _referenceState.applySnapshot(_referenceImage);
          _updateDynamicPalette();
        }
        break;

      case 'stats_update':
        final wins = (message['wins'] as num?)?.toInt() ?? 0;
        final losses = (message['losses'] as num?)?.toInt() ?? 0;
        final draws = (message['draws'] as num?)?.toInt() ?? 0;
        _userStore.saveStats(wins: wins, losses: losses, draws: draws);
        break;

      case 'game_start':
        if (!mounted) return;
        _socketHandedOff = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => GameScreen(
              socket: _socket,
              gameStart: message,
            ),
          ),
        );
        break;

      case 'matchmaking_status':
        // Re-encolado: navegar a matchmaking
        if (!mounted) return;
        _socketHandedOff = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MatchmakingScreen(socket: _socket),
          ),
        );
        break;
    }
  }

  void _paintPixel(int x, int y) {
    if (_phase != 'drawing' || _myTurnFinished) return;
    final color = _selectedColor;
    if (_myCanvas.inBounds(x, y) && _myCanvas.colorAt(x, y).toUpperCase() == color.toUpperCase()) return;
    _myCanvas.applyPixelUpdate(x, y, color);
    _socket.sendPaint(x: x, y: y, color: color, nickname: _myNickname);
  }

  void _finishTurn() {
    if (_phase != 'drawing' || _myTurnFinished) return;
    _countdownTimer?.cancel();
    _myTurnFinished = true;
    _socket.sendFinishTurn();
    setState(() {
      _phase = 'waiting_results';
      _scorpyState = ScorpyState.idle;
      _scorpyMessage = '¡TERMINASTE! ESPERANDO RESULTADOS...';
    });
    _startScorpyRotation(_waitingMessages);
  }

  void _nextGame() {
    if (_isNavigating) return;
    _isNavigating = true;
    _socketHandedOff = true;
    // Navegar a matchmaking primero, MatchmakingScreen enviará next_game cuando esté listo
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MatchmakingScreen(socket: _socket, fromNextGame: true),
      ),
    );
  }

  Future<void> _logout() async {
    _socketHandedOff = true;
    _countdownTimer?.cancel();
    _socket.dispose();
    await _userStore.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _stopScorpyRotation();
    _countdownTimer?.cancel();
    _messagesSub?.cancel();
    if (widget.socket == null && !_socketHandedOff) _socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Layout principal: juego a la izquierda, chat a la derecha
            Row(
              children: [
                // Área del juego
                Expanded(
                  child: _buildPhase(),
                ),
                // Chat siempre visible a la derecha
                if (_phase != 'results')
                  SizedBox(
                    width: 240,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: ChatPanel(socket: _socket, roomId: _roomId),
                    ),
                  ),
              ],
            ),
            // Scorpy en esquina inferior derecha del área del juego
            Positioned(
              bottom: 12,
              right: _phase != 'results' ? 248 : 12,
              child: ScorpyMascot(
                message: _scorpyMessage,
                state: _scorpyState,
                size: 56,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhase() {
    switch (_phase) {
      case 'image_preview':
        return _buildPreview();
      case 'drawing':
        return _buildDrawing();
      case 'waiting_results':
        return _buildWaitingResults();
      case 'results':
        return _buildResults();
      default:
        return const Center(child: CircularProgressIndicator());
    }
  }

  Widget _buildPreview() {
    return Column(
      children: [
        _buildHeader('MEMORIZÁ LA IMAGEN', _timeLeft),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: PixelCanvas(
                  state: _referenceState,
                  onTapPixel: (_, _) {},
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'SE VAN A BORRAR LOS LIENZOS\nY EMPEZÁ A DIBUJAR DE MEMORIA',
            textAlign: TextAlign.center,
            style: GoogleFonts.pressStart2p(
              fontSize: 8,
              height: 1.8,
              color: Colors.white38,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDrawing() {
    return Column(
      children: [
        _buildHeader('DIBUJÁ · AMBOS AL MISMO TIEMPO', _timeLeft),
        if (_opponentFinished)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: const Color(0xFFD62828).withValues(alpha: 0.3),
            child: Text(
              '¡EL OTRO JUGADOR TERMINÓ!',
              textAlign: TextAlign.center,
              style: GoogleFonts.pressStart2p(
                fontSize: 8,
                color: const Color(0xFFD62828),
              ),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: PixelCanvas(
                  state: _myCanvas,
                  onTapPixel: _paintPixel,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ColorPalette(
            selected: _selectedColor,
            palette: _dynamicPalette,
            onSelect: (c) => setState(() => _selectedColor = c),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: GestureDetector(
            onTap: _finishTurn,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFD62828),
                border: Border.all(color: Colors.black, width: 3),
                boxShadow: const [
                  BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
                ],
              ),
              child: Text(
                'TERMINAR TURNO',
                textAlign: TextAlign.center,
                style: GoogleFonts.pressStart2p(
                  fontSize: 11,
                  color: const Color(0xFFFFF3D6),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingResults() {
    return Column(
      children: [
        _buildHeader('ESPERANDO RESULTADOS', _timeLeft),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    color: const Color(0xFFFF8C42),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'TERMINASTE TU DIBUJO\nESPERANDO RESULTADOS...',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.pressStart2p(
                    fontSize: 10,
                    height: 1.8,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResults() {
    final didWin = _winner == _myNickname;
    final isTie = _winner == 'tie';

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Título
            Text(
              _forfeit
                  ? 'VICTORIA POR\nABANDONO'
                  : isTie
                      ? 'EMPATE'
                      : didWin
                          ? '¡GANASTE!'
                          : 'PERDISTE',
              textAlign: TextAlign.center,
              style: GoogleFonts.pressStart2p(
                fontSize: 16,
                height: 1.6,
                color: _forfeit || didWin
                    ? const Color(0xFF00E676)
                    : isTie
                        ? const Color(0xFFFFD700)
                        : const Color(0xFFD62828),
              ),
            ),
            const SizedBox(height: 24),
            // Scores
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: _ScoreColumn(
                    label: _myNickname.toUpperCase(),
                    score: _myScore,
                    color: didWin ? const Color(0xFF00E676) : Colors.white,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'VS',
                    style: GoogleFonts.pressStart2p(
                      fontSize: 14,
                      color: Colors.white38,
                    ),
                  ),
                ),
                Expanded(
                  child: _ScoreColumn(
                    label: _opponent.toUpperCase(),
                    score: _opponentScore,
                    color: !didWin && !isTie ? const Color(0xFFD62828) : Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Tres paneles: referencia | mi dibujo | dibujo oponente
            Text(
              'REFERENCIA',
              style: GoogleFonts.pressStart2p(fontSize: 8, color: Colors.white54),
            ),
            const SizedBox(height: 8),
            _buildMiniCanvas(_referenceImage),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'TU DIBUJO',
                        style: GoogleFonts.pressStart2p(fontSize: 7, color: Colors.white54),
                      ),
                      const SizedBox(height: 4),
                      _buildMiniCanvas(_myCanvas.canvas),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _opponent.toUpperCase(),
                          style: GoogleFonts.pressStart2p(fontSize: 7, color: Colors.white54),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildMiniCanvas(_opponentCanvas),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Botón siguiente partida
            GestureDetector(
              onTap: _nextGame,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8C42),
                  border: Border.all(color: Colors.black, width: 3),
                  boxShadow: const [
                    BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
                  ],
                ),
                child: Text(
                  'SIGUIENTE PARTIDA',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.pressStart2p(
                    fontSize: 11,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Botón cerrar sesión
            GestureDetector(
              onTap: _logout,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(color: Colors.white38, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.white24, offset: Offset(3, 3), blurRadius: 0),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.logout, color: Colors.white38, size: 13),
                    const SizedBox(width: 8),
                    Text(
                      'CERRAR SESIÓN',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.pressStart2p(
                        fontSize: 8,
                        color: Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String title, int timeLeft) {
    final minutes = (timeLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (timeLeft % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white, width: 2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: GoogleFonts.pressStart2p(
                  fontSize: 9,
                  color: const Color(0xFFFFF3D6),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Text(
              '$minutes:$seconds',
              style: GoogleFonts.pressStart2p(
                fontSize: 14,
                color: timeLeft <= 10 ? const Color(0xFFD62828) : const Color(0xFFFFF3D6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniCanvas(List<List<String>> canvas) {
    if (canvas.isEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Center(
          child: Text(
            'SIN DATOS',
            style: GoogleFonts.pressStart2p(fontSize: 8, color: Colors.white38),
          ),
        ),
      );
    }
    final state = PixelState();
    state.applySnapshot(canvas);
    return Container(
      height: 120,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: AspectRatio(
        aspectRatio: 1,
        child: PixelCanvas(state: state, onTapPixel: (_, _) {}),
      ),
    );
  }
}

class _ScoreColumn extends StatelessWidget {
  const _ScoreColumn({required this.label, required this.score, required this.color});

  final String label;
  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: GoogleFonts.pressStart2p(fontSize: 8, color: Colors.white54),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$score%',
          style: GoogleFonts.pressStart2p(fontSize: 20, color: color),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/user_store.dart';
import '../services/websocket_service.dart';
import '../widgets/scorpy_mascot.dart';
import '../widgets/scorpy_painter.dart';
import 'game_screen.dart';
import 'login_screen.dart';

/// Pantalla de matchmaking: espera un oponente y muestra stats.
class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({super.key, this.socket, this.fromNextGame = false});

  final SocketClient? socket;
  final bool fromNextGame;

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen> {
  final UserStore _userStore = UserStore();
  late final SocketClient _socket = widget.socket ?? WebsocketService();
  StreamSubscription<Map<String, dynamic>>? _messagesSub;
  StreamSubscription<SocketStatus>? _statusSub;

  String _nickname = '';
  int _wins = 0;
  int _losses = 0;
  int _draws = 0;
  SocketStatus _status = SocketStatus.conectando;
  bool _matched = false;
  bool _socketHandedOff = false;
  bool _wasMatchmaking = false;
  Timer? _matchmakingTimeout;

  // ── Scorpy ─────────────────────────────────────────────────────────
  ScorpyState _scorpyState = ScorpyState.tipOn;
  String _scorpyMessage = 'CONECTANDO AL SERVIDOR...';
  Timer? _scorpyRotateTimer;
  int _scorpyMsgIndex = 0;
  static const _scorpyMessages = [
    'BUSCANDO ALGUIEN PARA JUGAR...',
    '¡SEGUÍ BUSCANDO, YA CASI ESTÁS!',
    'CADA PARTIDA ES UNA NUEVA OPORTUNIDAD',
    'LOS MEJORES EMPEZARON COMO VOS',
    'MIENTRAS TANTO, PENSÁ EN ESTRATEGIAS',
    'LA PACIENCIA ES LA CLAVE DEL ÉXITO',
    'ALGUIEN SE VA A CONECTAR PRONTO...',
    '¡NO PARES, EL SIGUIENTE ES TUYO!',
  ];

  @override
  void initState() {
    super.initState();
    _messagesSub = _socket.messages.listen(_handleMessage);
    _statusSub = _socket.status.listen((s) {
      if (!mounted) return;
      setState(() {
        _status = s;
        if (s == SocketStatus.conectado) {
          _scorpyState = ScorpyState.idle;
          _scorpyMessage = 'BUSCANDO ALGUIEN PARA JUGAR...';
          _startScorpyRotation();
          // Si ya estaba en matchmaking antes de la desconexión, re-encolar
          if (_wasMatchmaking && !_matched) {
            _socket.sendStartMatchmaking();
            _startMatchmakingTimeout();
          }
        } else {
          _scorpyState = ScorpyState.tipOn;
          _scorpyMessage = 'CONECTANDO AL SERVIDOR...';
          _stopScorpyRotation();
          _stopMatchmakingTimeout();
        }
      });
    });
    _init();
  }

  Future<void> _init() async {
    final nickname = await _userStore.getNickname();
    final stats = await _userStore.getStats();
    if (!mounted) return;
    setState(() {
      _nickname = nickname ?? '';
      _wins = stats['wins'] ?? 0;
      _losses = stats['losses'] ?? 0;
      _draws = stats['draws'] ?? 0;
    });

    if (widget.socket == null && nickname != null) {
      // Arranque con sesión guardada: mandar el token propio o el servidor
      // respondería nickname_taken con nuestro propio nombre.
      final token = await _userStore.getToken();
      if (!mounted) return;
      _socket.connect(nickname, token: token);
    } else if (nickname != null) {
      // Socket ya conectado (pasado desde LoginScreen o GameScreen): solicitar matchmaking
      _wasMatchmaking = true;
      if (widget.fromNextGame) {
        _socket.sendNextGame();
      } else {
        _socket.sendStartMatchmaking();
      }
      _startMatchmakingTimeout();
    }
  }

  void _startScorpyRotation() {
    _stopScorpyRotation();
    _scheduleNextScorpyMessage();
  }

  void _scheduleNextScorpyMessage() {
    final delay = 5000 + math.Random().nextInt(10001); // 5-15 segundos
    _scorpyRotateTimer = Timer(Duration(milliseconds: delay), () {
      if (!mounted || _matched) return;
      setState(() {
        _scorpyMsgIndex = (_scorpyMsgIndex + 1) % _scorpyMessages.length;
        _scorpyMessage = _scorpyMessages[_scorpyMsgIndex];
      });
      _scheduleNextScorpyMessage();
    });
  }

  void _stopScorpyRotation() {
    _scorpyRotateTimer?.cancel();
    _scorpyRotateTimer = null;
  }

  static const _matchmakingTimeoutDuration = Duration(seconds: 15);

  void _startMatchmakingTimeout() {
    _stopMatchmakingTimeout();
    _matchmakingTimeout = Timer(_matchmakingTimeoutDuration, () {
      if (!mounted || _matched) return;
      // Si pasa el tiempo sin confirmación de emparejamiento válido, reiniciar búsqueda
      setState(() {
        _scorpyState = ScorpyState.tipOn;
        _scorpyMessage = 'REINTENTANDO EMPAREJAMIENTO...';
      });
      _socket.sendStartMatchmaking();
      _startMatchmakingTimeout();
    });
  }

  void _stopMatchmakingTimeout() {
    _matchmakingTimeout?.cancel();
    _matchmakingTimeout = null;
  }

  void _handleMessage(Map<String, dynamic> message) {
    switch (message['type']) {
      case 'auth_ok':
        final token = message['token'];
        if (token is String) {
          _userStore.saveToken(token);
        }
        final wins = (message['wins'] as num?)?.toInt() ?? 0;
        final losses = (message['losses'] as num?)?.toInt() ?? 0;
        final draws = (message['draws'] as num?)?.toInt() ?? 0;
        _userStore.saveStats(wins: wins, losses: losses, draws: draws);
        if (mounted) {
          setState(() {
            _wins = wins;
            _losses = losses;
            _draws = draws;
          });
        }
        // Ahora que el listener está activo, solicitar matchmaking
        _wasMatchmaking = true;
        _socket.sendStartMatchmaking();
        _startMatchmakingTimeout();
      case 'stats_update':
        final wins = (message['wins'] as num?)?.toInt() ?? 0;
        final losses = (message['losses'] as num?)?.toInt() ?? 0;
        final draws = (message['draws'] as num?)?.toInt() ?? 0;
        _userStore.saveStats(wins: wins, losses: losses, draws: draws);
        if (mounted) {
          setState(() {
            _wins = wins;
            _losses = losses;
            _draws = draws;
          });
        }
      case 'game_start':
        if (_matched) return;
        _matched = true;
        _stopScorpyRotation();
        _stopMatchmakingTimeout();
        if (!mounted) return;
        setState(() {
          _scorpyState = ScorpyState.celebrating;
          _scorpyMessage = '¡ENCONTRAMOS OPONENTE!';
        });
        _socketHandedOff = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => GameScreen(
              socket: _socket,
              gameStart: message,
            ),
          ),
        );
      case 'auth_error':
      case 'nickname_taken':
        // Sesión inválida o nombre tomado: volver al login sin quedarse varado.
        _stopMatchmakingTimeout();
        _stopScorpyRotation();
        _socketHandedOff = true;
        _socket.dispose();
        _userStore.clearSession();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
    }
  }

  Future<void> _logout() async {
    _socketHandedOff = true;
    _stopMatchmakingTimeout();
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
    _stopMatchmakingTimeout();
    _messagesSub?.cancel();
    _statusSub?.cancel();
    if (widget.socket == null && !_socketHandedOff) _socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF6B35), Color(0xFFD62828)],
          ),
        ),
        child: Stack(
          children: [
            const _GridOverlay(),
            // Botón cerrar sesión — esquina superior derecha
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Tooltip(
                    message: 'Cerrar sesión',
                    child: GestureDetector(
                      onTap: _logout,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          border: Border.all(
                            color: const Color(0xFFFFF3D6),
                            width: 2,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0xFFFFF3D6),
                              offset: Offset(2, 2),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.logout,
                              color: Color(0xFFFFF3D6),
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'SALIR',
                              style: GoogleFonts.pressStart2p(
                                fontSize: 7,
                                color: const Color(0xFFFFF3D6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _nickname.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.pressStart2p(
                              fontSize: 16,
                              color: const Color(0xFFFFF3D6),
                              shadows: const [
                                Shadow(
                                  color: Colors.black,
                                  offset: Offset(0, 3),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Stats en tarjeta retro
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3D6),
                          border: Border.all(color: Colors.black, width: 3),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black,
                              offset: Offset(4, 4),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _StatBox(
                              label: 'V',
                              value: _wins,
                              color: const Color(0xFF2E7D32),
                            ),
                            Container(width: 2, height: 32, color: Colors.black12),
                            _StatBox(
                              label: 'D',
                              value: _losses,
                              color: const Color(0xFFD62828),
                            ),
                            Container(width: 2, height: 32, color: Colors.black12),
                            _StatBox(
                              label: 'E',
                              value: _draws,
                              color: const Color(0xFFE6A100),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 48),
                      // Spinner animado
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          color: const Color(0xFFFFF3D6),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _status == SocketStatus.conectado
                            ? 'BUSCANDO OPONENTE...'
                            : 'CONECTANDO...',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.pressStart2p(
                          fontSize: 12,
                          color: const Color(0xFFFFF3D6),
                          shadows: const [
                            Shadow(
                              color: Colors.black,
                              offset: Offset(0, 2),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'ESPERÁ QUE ALGUIEN SE UNA',
                        style: GoogleFonts.pressStart2p(
                          fontSize: 8,
                          color: const Color(0xFFFFF3D6).withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Scorpy en esquina inferior derecha
            Positioned(
              bottom: 16,
              right: 16,
              child: ScorpyMascot(
                message: _scorpyMessage,
                state: _scorpyState,
                size: 64,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.pressStart2p(
            fontSize: 10,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$value',
          style: GoogleFonts.pressStart2p(
            fontSize: 18,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Fondo con cuadrícula tenue estilo cuaderno cuadriculado.
class _GridOverlay extends StatelessWidget {
  const _GridOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _GridPainter(),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..strokeWidth = 1;

    const cell = 24.0;
    for (double x = 0; x < size.width; x += cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

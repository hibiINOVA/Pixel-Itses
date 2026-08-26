import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/user_store.dart';
import '../services/websocket_service.dart';
import '../widgets/retro_button.dart';
import '../widgets/retro_text_field.dart';
import 'board_screen.dart';

/// Login con pre-cheque vía WebSocket: al tocar UNIRSE se abre una conexión
/// efímera y se espera la respuesta del backend. Si el nombre ya está
/// registrado y no somos su dueño, el server responde `nickname_taken` y
/// mostramos el cartel de error sin navegar.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.socket});

  /// Inyectable para tests (por defecto crea un WebsocketService real).
  final SocketClient? socket;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _timeout = Duration(seconds: 3);

  final UserStore _userStore = UserStore();
  final TextEditingController _nicknameController = TextEditingController();

  bool _checking = false;
  String? _error;
  SocketClient? _socket;
  StreamSubscription<Map<String, dynamic>>? _messagesSub;
  Timer? _timeoutTimer;
  bool _resolved = false;

  Future<void> _joinBoard() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty || _checking) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _checking = true;
      _error = null;
    });

    final socket = widget.socket ?? WebsocketService();
    _socket = socket;
    _resolved = false;

    _timeoutTimer = Timer(_timeout, () {
      if (_resolved) return;
      _resolved = true;
      _finishCheck('SIN CONEXIÓN AL SERVIDOR');
    });

    _messagesSub = socket.messages.listen((message) {
      if (_resolved) return;
      switch (message['type']) {
        case 'canvas_snapshot':
          _resolved = true;
          _timeoutTimer?.cancel();
          final token = message['token'];
          _enterBoard(nickname, token is String ? token : null);
        case 'nickname_taken':
          _resolved = true;
          _finishCheck('NOMBRE YA USADO · PROBÁ OTRO');
      }
    });

    socket.connect(nickname);
  }

  Future<void> _enterBoard(String nickname, String? token) async {
    await _userStore.saveNickname(nickname);
    if (token != null) {
      await _userStore.saveToken(token);
    }
    if (!mounted) return;
    setState(() => _checking = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BoardScreen(socket: widget.socket),
      ),
    );
  }

  /// Corta el intento: cierra la conexión efímera y muestra el error.
  void _finishCheck(String message) {
    _timeoutTimer?.cancel();
    _messagesSub?.cancel();
    _socket?.dispose();
    _socket = null;
    if (!mounted) return;
    setState(() {
      _checking = false;
      _error = message;
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _messagesSub?.cancel();
    _socket?.dispose();
    _nicknameController.dispose();
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
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'PIXEL\nBOARD',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.pressStart2p(
                          fontSize: 34,
                          height: 1.4,
                          color: const Color(0xFFFFF3D6),
                          shadows: const [
                            Shadow(
                              color: Colors.black,
                              offset: Offset(0, 6),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const _PixelSprite(),
                      const SizedBox(height: 24),
                      Text(
                        'LIENZO\nCOLABORATIVO',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.pressStart2p(
                          fontSize: 12,
                          height: 1.6,
                          color: const Color(0xFFFFF3D6),
                        ),
                      ),
                      const SizedBox(height: 40),
                      RetroTextField(
                        hint: 'USUARIO',
                        controller: _nicknameController,
                        onSubmitted: (_) => _joinBoard(),
                      ),
                      const SizedBox(height: 28),
                      if (_checking)
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            color: Color(0xFFFFF3D6),
                            strokeWidth: 4,
                          ),
                        )
                      else ...[
                        RetroButton(label: 'UNIRSE', onPressed: _joinBoard),
                        if (_error != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD62828),
                              border: Border.all(color: Colors.black, width: 3),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black,
                                  offset: Offset(4, 4),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.pressStart2p(
                                fontSize: 9,
                                height: 1.5,
                                color: const Color(0xFFFFF3D6),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Text(
                'inspirado en r/place',
                textAlign: TextAlign.center,
                style: GoogleFonts.pressStart2p(
                  fontSize: 8,
                  color: const Color(0xFFFFF3D6),
                ),
              ),
            ),
          ],
        ),
      ),
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

/// Mascota: fantasma pixelado de estilo 8-bit.
class _PixelSprite extends StatelessWidget {
  const _PixelSprite();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: const Color(0xFF8A2BE2),
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              color: const Color(0xFFFFD700),
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.black,
              margin: const EdgeInsets.all(12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              color: const Color(0xFFFFD700),
            ),
          ),
        ],
      ),
    );
  }
}
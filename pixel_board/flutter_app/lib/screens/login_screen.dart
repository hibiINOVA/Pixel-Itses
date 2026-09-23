import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/user_store.dart';
import '../services/websocket_service.dart';
import '../widgets/retro_button.dart';
import '../widgets/retro_password_field.dart';
import '../widgets/retro_text_field.dart';
import '../widgets/scorpy_mascot.dart';
import '../widgets/scorpy_painter.dart';
import 'matchmaking_screen.dart';
import 'register_screen.dart';

/// Login con username + password: al tocar UNIRSE se abre una conexión
/// y se espera la respuesta del backend.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.socket});

  final SocketClient? socket;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _timeout = Duration(seconds: 3);

  final UserStore _userStore = UserStore();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _nicknameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _checking = false;
  String? _error;
  SocketClient? _socket;
  StreamSubscription<Map<String, dynamic>>? _messagesSub;
  Timer? _timeoutTimer;
  bool _resolved = false;

  // ── Scorpy ─────────────────────────────────────────────────────────
  ScorpyState _scorpyState = ScorpyState.idle;
  String _scorpyMessage = '¡BIENVENIDO! EL JUEGO ESTÁ EN VIVO.';

  @override
  void initState() {
    super.initState();
    _nicknameController.addListener(() {
      if (_error != null) setState(() => _error = null);
    });
    _passwordController.addListener(() {
      if (_error != null) setState(() => _error = null);
    });
    _nicknameFocus.addListener(_onFocusChange);
    _passwordFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_checking) return;
    if (_passwordFocus.hasFocus) {
      setState(() {
        _scorpyState = ScorpyState.tipOn;
        _scorpyMessage = '¡CONTRASEÑA: AL MENOS 8 CARACTERES!';
      });
    } else if (_nicknameFocus.hasFocus) {
      setState(() {
        _scorpyState = ScorpyState.idle;
        _scorpyMessage = 'EJEMPLO: SUPERPIXEL!';
      });
    } else if (_error == null) {
      setState(() {
        _scorpyState = ScorpyState.idle;
        _scorpyMessage = '¡BIENVENIDO! EL JUEGO ESTÁ EN VIVO.';
      });
    }
  }

  void _updateScorpyForError(String error) {
    if (error.contains('PASSWORD INCORRECTO')) {
      setState(() {
        _scorpyState = ScorpyState.tipOn;
        _scorpyMessage = '¿OLVIDASTE TU CLAVE? HACÉ CLIC EN CREAR CUENTA';
      });
    } else if (error.contains('CUENTA NO EXISTE')) {
      setState(() {
        _scorpyState = ScorpyState.tipOn;
        _scorpyMessage = 'CREALA PRIMERO → CREAR CUENTA';
      });
    } else {
      setState(() {
        _scorpyState = ScorpyState.tipOn;
        _scorpyMessage = 'REVISÁ LOS CAMPOS Y VOLVÉ A INTENTAR';
      });
    }
  }

  Future<void> _joinBoard() async {
    final nickname = _nicknameController.text.trim();
    final password = _passwordController.text;

    if (nickname.isEmpty) {
      setState(() => _error = 'INGRESÁ TU USUARIO');
      return;
    }
    if (nickname.length > 16) {
      setState(() => _error = 'USUARIO MUY LARGO (MÁX. 16)');
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9_\- ]+$').hasMatch(nickname)) {
      setState(() => _error = 'CARACTERES INVÁLIDOS EN USUARIO');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'INGRESÁ TU PASSWORD');
      return;
    }
    if (password.length < 3) {
      setState(() => _error = 'PASSWORD MUY CORTO');
      return;
    }
    if (password.length > 64) {
      setState(() => _error = 'PASSWORD MUY LARGO');
      return;
    }
    if (_checking) return;

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
        case 'auth_ok':
          _resolved = true;
          _timeoutTimer?.cancel();
          final token = message['token'];
          final wins = (message['wins'] as num?)?.toInt() ?? 0;
          final losses = (message['losses'] as num?)?.toInt() ?? 0;
          final draws = (message['draws'] as num?)?.toInt() ?? 0;
          _enterBoard(nickname, token is String ? token : null,
              wins: wins, losses: losses, draws: draws);
        case 'nickname_taken':
          _resolved = true;
          _finishCheck('NOMBRE YA USADO · PROBÁ OTRO');
        case 'auth_error':
          _resolved = true;
          final err = message['error'] as String?;
          _finishCheck(_authErrorText(err));
      }
    });

    socket.connect(nickname, password: password);
  }

  String _authErrorText(String? error) {
    switch (error) {
      case 'wrong_password':
        return 'PASSWORD INCORRECTO';
      case 'not_found':
        return 'CUENTA NO EXISTE · CREALA PRIMERO';
      case 'invalid_password':
        return 'PASSWORD INVÁLIDO';
      case 'taken':
        return 'NOMBRE YA USADO · PROBÁ OTRO';
      default:
        return 'ERROR DE AUTENTICACIÓN';
    }
  }

  Future<void> _enterBoard(String nickname, String? token,
      {int wins = 0, int losses = 0, int draws = 0}) async {
    await _userStore.saveNickname(nickname);
    if (token != null) {
      await _userStore.saveToken(token);
    }
    await _userStore.saveStats(wins: wins, losses: losses, draws: draws);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _scorpyState = ScorpyState.celebrating;
      _scorpyMessage = '¡BIENVENIDO AL JUEGO!';
    });
    // Pequeña pausa para que se vea la animación antes de navegar
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    final socketToPass = _socket;
    _socket = null;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MatchmakingScreen(socket: socketToPass),
      ),
    );
  }

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
    _updateScorpyForError(message);
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _messagesSub?.cancel();
    if (widget.socket == null) {
      _socket?.dispose();
    }
    _nicknameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isUserError(String err) {
    return err.contains('USUARIO') ||
        err.contains('NOMBRE') ||
        err.contains('CUENTA NO EXISTE');
  }

  bool _isPasswordError(String err) {
    return err.contains('PASSWORD');
  }

  @override
  Widget build(BuildContext context) {
    final String? userError =
        _error != null && _isUserError(_error!) ? _error : null;
    final String? passwordError =
        _error != null && _isPasswordError(_error!) ? _error : null;
    final String? generalError = _error != null &&
            !_isUserError(_error!) &&
            !_isPasswordError(_error!)
        ? _error
        : null;

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
                      const SizedBox(height: 32),
                      Text(
                        'DIBUJÁ DE MEMORIA',
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
                      if (userError != null) ...[
                        const SizedBox(height: 8),
                        _RetroAlertBox(text: userError),
                      ],
                      const SizedBox(height: 16),
                      RetroPasswordField(
                        hint: 'PASSWORD',
                        controller: _passwordController,
                        onSubmitted: (_) => _joinBoard(),
                      ),
                      if (passwordError != null) ...[
                        const SizedBox(height: 8),
                        _RetroAlertBox(text: passwordError),
                      ],
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
                        const SizedBox(height: 16),
                        GestureDetector(
                          key: const Key('crear_cuenta_link'),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RegisterScreen(
                                socket: widget.socket,
                              ),
                            ),
                          ),
                          child: Text(
                            'CREAR CUENTA',
                            style: GoogleFonts.pressStart2p(
                              fontSize: 10,
                              color: const Color(0xFFFFF3D6),
                              decoration: TextDecoration.underline,
                              decorationColor: const Color(0xFFFFF3D6),
                            ),
                          ),
                        ),
                        if (generalError != null) ...[
                          const SizedBox(height: 20),
                          _RetroAlertBox(text: generalError),
                        ],
                      ],
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

class _RetroAlertBox extends StatelessWidget {
  const _RetroAlertBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFD62828),
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
        ],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.pressStart2p(
          fontSize: 9,
          height: 1.5,
          color: const Color(0xFFFFF3D6),
        ),
      ),
    );
  }
}

class _GridOverlay extends StatelessWidget {
  const _GridOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(size: Size.infinite, painter: _GridPainter()),
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

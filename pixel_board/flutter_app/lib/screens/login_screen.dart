import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/user_store.dart';
import '../services/websocket_service.dart';
import '../widgets/retro_button.dart';
import '../widgets/retro_text_field.dart';
import '../widgets/scorpy_mascot.dart';
import '../widgets/scorpy_painter.dart';
import 'matchmaking_screen.dart';

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
  final FocusNode _nicknameFocus = FocusNode();

  bool _checking = false;
  String? _error;
  SocketClient? _socket;
  StreamSubscription<Map<String, dynamic>>? _messagesSub;
  Timer? _timeoutTimer;
  bool _resolved = false;

  ScorpyState _scorpyState = ScorpyState.idle;
  String _scorpyMessage = '¡BIENVENIDO! EL JUEGO ESTÁ EN VIVO.';

  @override
  void initState() {
    super.initState();
    _nicknameController.addListener(() {
      if (_error != null) setState(() => _error = null);
    });
    _nicknameFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_checking) return;
    if (_nicknameFocus.hasFocus) {
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
    if (error.contains('NOMBRE YA USADO')) {
      setState(() {
        _scorpyState = ScorpyState.tipOn;
        _scorpyMessage = 'NOMBRE OCUPADO, ELEGÍ OTRO';
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
          _timeoutTimer?.cancel();
          _messagesSub?.cancel();
          _socket?.dispose();
          _socket = null;
          if (!mounted) return;
          setState(() {
            _checking = false;
            _error = 'NOMBRE YA USADO · ELEGÍ OTRO';
          });
          _updateScorpyForError(_error!);
        case 'auth_error':
          _resolved = true;
          _timeoutTimer?.cancel();
          _messagesSub?.cancel();
          _socket?.dispose();
          _socket = null;
          if (!mounted) return;
          setState(() {
            _checking = false;
            _error = 'ERROR DE CONEXIÓN';
          });
          _updateScorpyForError(_error!);
      }
    });

    // Reusar el token guardado solo si corresponde al mismo nickname,
    // así el servidor reconoce la reconexión en vez de devolver nickname_taken.
    final storedNickname = await _userStore.getNickname();
    final storedToken = await _userStore.getToken();
    final token = storedNickname == nickname ? storedToken : null;
    socket.connect(nickname, token: token);
  }

  Future<void> _enterBoard(String nickname, String? token,
      {int wins = 0, int losses = 0, int draws = 0}) async {
    await _userStore.saveNickname(nickname);
    if (token != null) {
      // Credencial de reconexión: sin ella el servidor niega el nickname propio.
      await _userStore.saveToken(token);
    }
    await _userStore.saveStats(wins: wins, losses: losses, draws: draws);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _scorpyState = ScorpyState.celebrating;
      _scorpyMessage = '¡BIENVENIDO AL JUEGO!';
    });
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
    _nicknameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? generalError = _error != null &&
            !_error!.contains('NOMBRE YA USADO') &&
            !_error!.contains('USUARIO') &&
            !_error!.contains('CARACTERES')
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
                        focusNode: _nicknameFocus,
                      ),
                      if (_error != null && _error!.contains('NOMBRE YA USADO')) ...[
                        const SizedBox(height: 8),
                        _RetroAlertBox(text: _error!),
                      ],
                      const SizedBox(height: 16),
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
                        if (generalError != null) ...[
                          _RetroAlertBox(text: generalError),
                          const SizedBox(height: 20),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
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

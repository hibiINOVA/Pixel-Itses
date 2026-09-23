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

enum _PasswordLevel { nada, debil, media, fuerte, muyFuerte }

_PasswordLevel _evaluatePassword(String p) {
  if (p.isEmpty) return _PasswordLevel.nada;
  final hasMin = p.length >= 8;
  final hasUpper = RegExp(r'[A-Z]').hasMatch(p);
  final hasLower = RegExp(r'[a-z]').hasMatch(p);
  final hasDigit = RegExp(r'[0-9]').hasMatch(p);
  final hasSpecial = RegExp(r'[!@#$%^&*()_\-]').hasMatch(p);
  final score = [hasUpper, hasLower, hasDigit, hasSpecial].where((b) => b).length;
  if (!hasMin) return _PasswordLevel.nada;
  if (score <= 1) return _PasswordLevel.debil;
  if (score == 2) return _PasswordLevel.media;
  if (score == 3) return _PasswordLevel.fuerte;
  return _PasswordLevel.muyFuerte;
}

/// Pantalla de registro con estilo retro alineado con el Login.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.socket});

  final SocketClient? socket;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const _timeout = Duration(seconds: 3);

  final UserStore _userStore = UserStore();
  final _nicknameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final FocusNode _nicknameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();

  bool _checking = false;
  String? _error;
  SocketClient? _socket;
  StreamSubscription<Map<String, dynamic>>? _messagesSub;
  Timer? _timeoutTimer;
  bool _resolved = false;

  // ── Scorpy ─────────────────────────────────────────────────────────
  ScorpyState _scorpyState = ScorpyState.idle;
  String _scorpyMessage = 'CREÁ TU CUENTA Y A JUGAR';

  @override
  void initState() {
    super.initState();
    _nicknameController.addListener(() => setState(() {}));
    _passwordController.addListener(_onPasswordChange);
    _confirmController.addListener(() => setState(() {}));
    _nicknameFocus.addListener(_onFocusChange);
    _passwordFocus.addListener(_onFocusChange);
    _confirmFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_checking) return;
    if (_passwordFocus.hasFocus) {
      _updateScorpyForPassword();
    } else if (_nicknameFocus.hasFocus) {
      setState(() {
        _scorpyState = ScorpyState.idle;
        _scorpyMessage = '3 A 16 CARACTERES · LETRAS, NÚMEROS, _ -';
      });
    } else if (_confirmFocus.hasFocus) {
      setState(() {
        _scorpyState = ScorpyState.tipOn;
        _scorpyMessage = 'CONFIRMÁ TU CONTRASEÑA';
      });
    } else if (_error == null) {
      setState(() {
        _scorpyState = ScorpyState.idle;
        _scorpyMessage = 'CREÁ TU CUENTA Y A JUGAR';
      });
    }
  }

  void _onPasswordChange() {
    setState(() {});
    if (_passwordFocus.hasFocus) _updateScorpyForPassword();
  }

  void _updateScorpyForPassword() {
    final lvl = _level;
    if (lvl == _PasswordLevel.muyFuerte) {
      setState(() {
        _scorpyState = ScorpyState.celebrating;
        _scorpyMessage = _passwordsMatch
            ? '¡TODO BIEN! CREÁ LA CUENTA'
            : '¡CONTRASEÑA PERFECTA!';
      });
    } else if (lvl == _PasswordLevel.fuerte) {
      setState(() {
        _scorpyState = ScorpyState.tipOn;
        _scorpyMessage = '¡CASI LO TENÉS!';
      });
    } else if (lvl != _PasswordLevel.nada) {
      setState(() {
        _scorpyState = ScorpyState.tipOn;
        _scorpyMessage = 'MUY DÉBIL... ¡SUMÁ REQUISITOS!';
      });
    } else {
      setState(() {
        _scorpyState = ScorpyState.tipOn;
        _scorpyMessage = '8+ CARACTERES · MAYÚS · MINÚS · NÚMERO · ESPECIAL';
      });
    }
  }

  _PasswordLevel get _level => _evaluatePassword(_passwordController.text);
  bool get _passwordsMatch =>
      _confirmController.text.isNotEmpty &&
      _passwordController.text == _confirmController.text;
  bool get _canSubmit =>
      _nicknameController.text.trim().length >= 3 &&
      _level == _PasswordLevel.muyFuerte &&
      !_checking;

  Future<void> _register() async {
    final nickname = _nicknameController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (nickname.isEmpty) {
      setState(() => _error = 'INGRESÁ UN USUARIO');
      return;
    }
    if (nickname.length < 3) {
      setState(() => _error = 'USUARIO MUY CORTO (MÍN. 3)');
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
      setState(() => _error = 'INGRESÁ UN PASSWORD');
      return;
    }
    if (_level != _PasswordLevel.muyFuerte) {
      setState(() => _error = 'LA CONTRASEÑA NO CUMPLE LAS CARACTERÍSTICAS');
      return;
    }
    if (confirm.isEmpty) {
      setState(() => _error = 'CONFIRMÁ EL PASSWORD');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'LAS CONTRASEÑAS NO COINCIDEN');
      return;
    }

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
        case 'auth_error':
          _resolved = true;
          final err = message['error'] as String?;
          _finishCheck(_authErrorText(err));
      }
    });

    socket.connect(nickname);
    socket.sendRegister(nickname, password);
  }

  String _authErrorText(String? error) {
    switch (error) {
      case 'taken':
        return 'ESE NOMBRE YA ESTÁ TOMADO';
      case 'invalid_password':
        return 'CONTRASEÑA INVÁLIDA';
      case 'weak_password':
        return 'CONTRASEÑA MUY DÉBIL';
      default:
        return 'ERROR DE REGISTRO';
    }
  }

  Future<void> _enterBoard(String nickname, String? token,
      {int wins = 0, int losses = 0, int draws = 0}) async {
    await _userStore.saveNickname(nickname);
    if (token != null) await _userStore.saveToken(token);
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
      _scorpyState = ScorpyState.tipOn;
      _scorpyMessage = 'REVISÁ LOS CAMPOS Y VOLVÉ A INTENTAR';
    });
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
    _confirmController.dispose();
    _nicknameFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Color _levelColor(_PasswordLevel l) {
    switch (l) {
      case _PasswordLevel.nada:
        return const Color(0xFF757575);
      case _PasswordLevel.debil:
        return const Color(0xFFD62828);
      case _PasswordLevel.media:
        return const Color(0xFFFF8C42);
      case _PasswordLevel.fuerte:
        return const Color(0xFFE6A100);
      case _PasswordLevel.muyFuerte:
        return const Color(0xFF2E7D32);
    }
  }

  String _levelLabel(_PasswordLevel l) {
    switch (l) {
      case _PasswordLevel.nada:
        return 'MÍNIMO 8 CARACTERES';
      case _PasswordLevel.debil:
        return 'DÉBIL (1/4 REQUISITOS)';
      case _PasswordLevel.media:
        return 'MEDIA (2/4 REQUISITOS)';
      case _PasswordLevel.fuerte:
        return 'FUERTE (3/4 REQUISITOS)';
      case _PasswordLevel.muyFuerte:
        return 'MUY FUERTE (4/4 ✓)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final nickText = _nicknameController.text.trim();
    final isNickTooShort = nickText.isNotEmpty && nickText.length < 3;
    final isNickInvalidChar = nickText.isNotEmpty &&
        !RegExp(r'^[a-zA-Z0-9_\- ]+$').hasMatch(nickText);
    final isNickValid =
        nickText.length >= 3 && nickText.length <= 16 && !isNickInvalidChar;

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
              child: Stack(
                children: [
                  Positioned(
                    top: 12,
                    left: 16,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3D6),
                          border: Border.all(color: Colors.black, width: 3),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black,
                              offset: Offset(3, 3),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.black,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 24,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 20),
                          Text(
                            'REGISTRATE\nEN PIXEL BOARD',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.pressStart2p(
                              fontSize: 22,
                              height: 1.4,
                              color: const Color(0xFFFFF3D6),
                              shadows: const [
                                Shadow(
                                  color: Colors.black,
                                  offset: Offset(0, 4),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Campo Usuario
                          RetroTextField(
                            hint: 'USUARIO',
                            controller: _nicknameController,
                            focusNode: _nicknameFocus,
                            maxLength: 16,
                            onSubmitted: (_) => _register(),
                          ),

                          // Alerta debajo del Campo Usuario
                          if (isNickTooShort) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD62828),
                                border: Border.all(color: Colors.black, width: 3),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black,
                                    offset: Offset(3, 3),
                                    blurRadius: 0,
                                  ),
                                ],
                              ),
                              child: Text(
                                'USUARIO MUY CORTO (MÍN. 3 CARACTERES)',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.pressStart2p(
                                  fontSize: 8,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ] else if (isNickInvalidChar) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD62828),
                                border: Border.all(color: Colors.black, width: 3),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black,
                                    offset: Offset(3, 3),
                                    blurRadius: 0,
                                  ),
                                ],
                              ),
                              child: Text(
                                'CARACTERES INVÁLIDOS EN USUARIO',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.pressStart2p(
                                  fontSize: 8,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ] else if (isNickValid) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2E7D32),
                                border: Border.all(color: Colors.black, width: 3),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black,
                                    offset: Offset(3, 3),
                                    blurRadius: 0,
                                  ),
                                ],
                              ),
                              child: Text(
                                'USUARIO VÁLIDO ✓',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.pressStart2p(
                                  fontSize: 8,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 16),

                          // Campo Password
                          RetroPasswordField(
                            hint: 'PASSWORD',
                            controller: _passwordController,
                            focusNode: _passwordFocus,
                            onSubmitted: (_) => _register(),
                          ),

                          // Alerta / Medidor debajo del Campo Password
                          if (_passwordController.text.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _levelColor(_level),
                                      border: Border.all(color: Colors.black, width: 2),
                                    ),
                                    child: Text(
                                      _levelLabel(_level),
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.pressStart2p(
                                        fontSize: 8,
                                        color: Colors.white,
                                        shadows: const [
                                          Shadow(
                                            color: Colors.black,
                                            offset: Offset(1, 1),
                                            blurRadius: 0,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _RequirementRow(
                                    label: '8+ CARACTERES',
                                    met: _passwordController.text.length >= 8,
                                  ),
                                  _RequirementRow(
                                    label: 'MAYÚSCULAS (A-Z)',
                                    met: RegExp(r'[A-Z]')
                                        .hasMatch(_passwordController.text),
                                  ),
                                  _RequirementRow(
                                    label: 'MINÚSCULAS (a-z)',
                                    met: RegExp(r'[a-z]')
                                        .hasMatch(_passwordController.text),
                                  ),
                                  _RequirementRow(
                                    label: 'NÚMEROS (0-9)',
                                    met: RegExp(r'[0-9]')
                                        .hasMatch(_passwordController.text),
                                  ),
                                  _RequirementRow(
                                    label: 'CARACTER ESPECIAL (!@#\$%&*)',
                                    met: RegExp(r'[!@#$%^&*()_\-]')
                                        .hasMatch(_passwordController.text),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 16),

                          // Campo Confirmar Password
                          RetroPasswordField(
                            hint: 'CONFIRMAR PASSWORD',
                            controller: _confirmController,
                            focusNode: _confirmFocus,
                            onSubmitted: (_) => _register(),
                          ),

                          // Alerta debajo del Campo Confirmar Password
                          if (_confirmController.text.isNotEmpty &&
                              !_passwordsMatch) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD62828),
                                border: Border.all(color: Colors.black, width: 3),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black,
                                    offset: Offset(3, 3),
                                    blurRadius: 0,
                                  ),
                                ],
                              ),
                              child: Text(
                                'LAS CONTRASEÑAS NO COINCIDEN',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.pressStart2p(
                                  fontSize: 8,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                          if (_passwordsMatch) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2E7D32),
                                border: Border.all(color: Colors.black, width: 3),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black,
                                    offset: Offset(3, 3),
                                    blurRadius: 0,
                                  ),
                                ],
                              ),
                              child: Text(
                                'CONTRASEÑAS COINCIDEN ✓',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.pressStart2p(
                                  fontSize: 8,
                                  color: Colors.white,
                                ),
                              ),
                            ),
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
                            Opacity(
                              opacity: _canSubmit ? 1.0 : 0.4,
                              child: RetroButton(
                                key: const Key('register_submit'),
                                label: 'CREAR CUENTA',
                                color: const Color(0xFFD62828),
                                onPressed: _canSubmit ? _register : null,
                              ),
                            ),
                            const SizedBox(height: 16),
                            GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
                              child: Text(
                                'VOLVER AL LOGIN',
                                style: GoogleFonts.pressStart2p(
                                  fontSize: 10,
                                  color: const Color(0xFFFFF3D6),
                                  decoration: TextDecoration.underline,
                                  decorationColor: const Color(0xFFFFF3D6),
                                ),
                              ),
                            ),
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
                ],
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

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_box : Icons.check_box_outline_blank,
            size: 16,
            color: met ? const Color(0xFF2E7D32) : Colors.black45,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.pressStart2p(
                fontSize: 7,
                color: met ? const Color(0xFF1B5E20) : Colors.black54,
              ),
            ),
          ),
        ],
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

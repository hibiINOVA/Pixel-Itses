import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/pixel_state.dart';
import '../services/user_store.dart';
import '../services/websocket_service.dart';
import '../widgets/chat_panel.dart';
import '../widgets/color_palette.dart';
import '../widgets/pixel_battery_icon.dart';
import '../widgets/pixel_canvas.dart';
import '../widgets/retro_counter.dart';
import 'login_screen.dart';

const _pixelsPerCycle = 5;

String _formatMmss(Duration timeLeft) {
  final minutes = timeLeft.inMinutes.toString().padLeft(2, '0');
  final seconds = (timeLeft.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Pizarra colaborativa conectada al backend por WebSocket.
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key, this.socket});

  /// Inyectable para tests (por defecto crea un WebsocketService real).
  final SocketClient? socket;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  final UserStore _userStore = UserStore();
  late final SocketClient _socket = widget.socket ?? WebsocketService();
  final PixelState _state = PixelState();

  String _nickname = '';
  String _selectedColor = kPalette.first;
  SocketStatus _status = SocketStatus.conectando;
  bool _snapshotRecibido = false;

  StreamSubscription<Map<String, dynamic>>? _messagesSub;
  StreamSubscription<SocketStatus>? _statusSub;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final nickname = await _userStore.getNickname();
    final token = await _userStore.getToken();
    if (!mounted) return;
    setState(() {
      _nickname = nickname ?? '';
    });

    _messagesSub = _socket.messages.listen(
      _handleMessage,
      onError: (Object _) {},
      cancelOnError: false,
    );
    _statusSub = _socket.status.listen((value) {
      if (mounted) setState(() => _status = value);
    });
    // Con socket inyectado (tests) no conectamos: el fake maneja la sesión.
    if (widget.socket == null && nickname != null) {
      _socket.connect(nickname, token: token);
    }
  }

  void _handleMessage(Map<String, dynamic> message) {
    switch (message['type']) {
      case 'canvas_snapshot':
        final raw = message['canvas'] as List;
        final snapshot = raw
            .map((row) => (row as List).map((c) => c as String).toList())
            .toList();
        _state.applySnapshot(snapshot);
        _state.applyCooldown(
          pixelsRemaining: (message['pixelsRemaining'] as num?)?.toInt() ?? _pixelsPerCycle,
          cooldownEndsAt: (message['cooldownEndsAt'] as num?)?.toInt(),
        );
        if (!mounted) return;
        setState(() {
          _snapshotRecibido = true;
          _status = SocketStatus.conectado;
        });
        _syncCooldownTimer();
        break;

      case 'pixel_update':
        // Solo repinta el canvas vía ListenableBuilder (sin setState global).
        _state.applyPixelUpdate(
          (message['x'] as num).toInt(),
          (message['y'] as num).toInt(),
          message['color'] as String,
        );
        break;

      case 'cooldown_update':
        _state.applyCooldown(
          pixelsRemaining: (message['pixelsRemaining'] as num?)?.toInt() ?? _pixelsPerCycle,
          cooldownEndsAt: (message['cooldownEndsAt'] as num?)?.toInt(),
        );
        if (mounted) setState(() {});
        _syncCooldownTimer();
        break;

      case 'nickname_taken':
        // Token vencido o sesión inválida: volver al login para reintentar.
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        break;
    }
  }

  /// Arranca el timer de recarga solo mientras hay cooldown activo.
  void _syncCooldownTimer() {
    _cooldownTimer?.cancel();
    if (_state.cooldownEndsAt == null) return;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _state.cooldownEndsAt == null) return;
      final remaining =
          _state.cooldownEndsAt! - DateTime.now().millisecondsSinceEpoch;
      setState(() {
        if (remaining <= 0) {
          // Recarga local: vuelve al tope hasta que confirme el servidor.
          _state.applyCooldown(
            pixelsRemaining: _pixelsPerCycle,
            cooldownEndsAt: null,
          );
        }
      });
    });
  }

  Duration get _timeLeft {
    final endsAt = _state.cooldownEndsAt;
    if (endsAt == null) return Duration.zero;
    final remaining = endsAt - DateTime.now().millisecondsSinceEpoch;
    return remaining > 0 ? Duration(milliseconds: remaining) : Duration.zero;
  }

  void _paintPixel(int x, int y) {
    // Chequeo local solo de UX; la validación real es del servidor.
    if (_nickname.isEmpty) return;
    if ((_state.pixelsRemaining ?? 0) <= 0) {
      if (_state.cooldownEndsAt != null) {
        _showRechargeAlert();
      }
      return;
    }
    _socket.sendPaint(
      x: x,
      y: y,
      color: _selectedColor,
      nickname: _nickname,
    );
  }

  /// Alerta retro (sin diálogo modal, no interrumpe el ritmo de pintado).
  void _showRechargeAlert() {
    ScaffoldMessenger.of(context)
      ..clearSnackBars() // anti-spam: toques repetidos no apilan alertas
      ..showSnackBar(
        SnackBar(
          content: Text(
            'ESPERA LA RECARGA · ${_formatMmss(_timeLeft)}',
            textAlign: TextAlign.center,
            style: GoogleFonts.pressStart2p(
              fontSize: 9,
              color: Colors.black,
            ),
          ),
          backgroundColor: const Color(0xFFFFF3D6),
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          duration: const Duration(seconds: 2),
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero, // estilo pixel: esquinas rectas
            side: const BorderSide(color: Colors.black, width: 3),
          ),
        ),
      );
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _messagesSub?.cancel();
    _statusSub?.cancel();
    _socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        // Ancho: pizarra a la izquierda + chat a la derecha.
        // Angosto (celular): chat como franja abajo.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 700;
            final board = Column(
              children: [
                _Header(nickname: _nickname, status: _status),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _CooldownBar(
                    pixelsRemaining:
                        _state.pixelsRemaining ?? _pixelsPerCycle,
                    pixelsPerCycle: _pixelsPerCycle,
                    timeLeft: _timeLeft,
                  ),
                ),
                const Divider(color: Colors.white, thickness: 2, height: 1),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: PixelCanvas(
                          state: _state,
                          onTapPixel: _paintPixel,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ColorPalette(
                    selected: _selectedColor,
                    onSelect: (color) =>
                        setState(() => _selectedColor = color),
                  ),
                ),
              ],
            );
            final chat = wide
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                    child: SizedBox(
                      width: 300,
                      child: ChatPanel(socket: _socket),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: SizedBox(height: 220, child: ChatPanel(socket: _socket)),
                  );
            return Stack(
              children: [
                wide
                    ? Row(children: [Expanded(child: board), chat])
                    : Column(
                        children: [Expanded(child: board), chat],
                      ),
                if (!_snapshotRecibido) const _LoadingOverlay(),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Tapa la pizarra hasta recibir el snapshot inicial.
class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: Container(
        color: Colors.black.withValues(alpha: 0.9),
        alignment: Alignment.center,
        child: Text(
          'CARGANDO\nPIZARRA...',
          textAlign: TextAlign.center,
          style: GoogleFonts.pressStart2p(
            fontSize: 12,
            height: 2,
            color: const Color(0xFFFFF3D6),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.nickname, required this.status});

  final String nickname;
  final SocketStatus status;

  String get _statusText {
    switch (status) {
      case SocketStatus.conectado:
        return 'EN LÍNEA';
      case SocketStatus.conectando:
        return 'CONECTANDO...';
      case SocketStatus.desconectado:
        return 'SIN CONEXIÓN';
    }
  }

  Color get _statusColor {
    switch (status) {
      case SocketStatus.conectado:
        return const Color(0xFF00E676);
      case SocketStatus.conectando:
        return const Color(0xFFFFD700);
      case SocketStatus.desconectado:
        return const Color(0xFFD62828);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = nickname.isEmpty ? '?' : nickname[0].toUpperCase();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            alignment: Alignment.center,
            child: Text(
              '[$initial]',
              style: GoogleFonts.pressStart2p(
                fontSize: 12,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              nickname.isEmpty ? 'ANÓNIMO' : nickname,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.pressStart2p(
                fontSize: 10,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _statusText,
            style: GoogleFonts.pressStart2p(
              fontSize: 8,
              color: _statusColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Contador de pixeles + timer de recarga + barra segmentada.
class _CooldownBar extends StatelessWidget {
  const _CooldownBar({
    required this.pixelsRemaining,
    required this.pixelsPerCycle,
    required this.timeLeft,
  });

  final int pixelsRemaining;
  final int pixelsPerCycle;
  final Duration timeLeft;

  String get _timerText {
    if (pixelsRemaining > 0) return 'LISTO';
    return _formatMmss(timeLeft);
  }

  @override
  Widget build(BuildContext context) {
    final blocked = pixelsRemaining <= 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: Colors.white, width: 3),
        ),
        child: Column(
          children: [
            Row(
              children: [
                PixelBatteryIcon(
                  value: pixelsRemaining,
                  max: pixelsPerCycle,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'PIXELES: $pixelsRemaining / $pixelsPerCycle',
                    style: GoogleFonts.pressStart2p(
                      fontSize: 9,
                      color: const Color(0xFFFFF3D6),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                RetroCounter(
                  text: 'PRÓXIMA RECARGA\n$_timerText',
                  fontSize: 8,
                  color: blocked
                      ? const Color(0xFFD62828)
                      : const Color(0xFF00E676),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (int i = 0; i < pixelsPerCycle; i++)
                  Expanded(
                    child: Container(
                      height: 8,
                      margin: EdgeInsets.only(right: i < pixelsPerCycle - 1 ? 4 : 0),
                      decoration: BoxDecoration(
                        color: i < pixelsRemaining
                            ? const Color(0xFFFF8C42)
                            : Colors.transparent,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

/// URL del backend. Se puede sobreescribir sin editar código:
///   flutter run --dart-define=WS_URL=ws://10.0.2.2:3000
const String kWsUrl = String.fromEnvironment(
  'WS_URL',
  defaultValue: 'ws://localhost:3000',
);

enum SocketStatus { conectando, conectado, desconectado }

/// Contraste mínimo para inyectar fakes en los tests.
abstract class SocketClient {
  Stream<Map<String, dynamic>> get messages;
  Stream<SocketStatus> get status;

  void connect(String nickname, {String? token});
  void sendHello(String nickname, {String? token});
  void sendChat(String text);
  void sendPaint({
    required int x,
    required int y,
    required String color,
    required String nickname,
  });
  void dispose();
}

/// Conexión WebSocket con el backend: reconexión automática con backoff,
/// re-identificación (hello) tras cada reconexión y streams de mensajes/estado.
///
/// Identidad: el nickname es el nombre único registrado en el backend y el
/// token la credencial secreta que prueba que somos su dueño.
class WebsocketService implements SocketClient {
  WebsocketService({
    this.url = kWsUrl,
    this.maxBackoff = const Duration(seconds: 8),
  });

  final String url;
  final Duration maxBackoff;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  final StreamController<Map<String, dynamic>> _messages =
      StreamController.broadcast();
  final StreamController<SocketStatus> _status =
      StreamController<SocketStatus>.broadcast();

  String? _nickname;
  String? _token;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _disposed = false;

  /// Mensajes del servidor ya parseados como mapas.
  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  /// Cambios de estado de la conexión (para el indicador de la UI).
  @override
  Stream<SocketStatus> get status => _status.stream;

  /// Conecta e identifica al usuario; reintenta solo ante cortes.
  @override
  void connect(String nickname, {String? token}) {
    _nickname = nickname;
    _token = token;
    _open();
  }

  void _open() {
    if (_disposed || _nickname == null) return;
    _setStatus(SocketStatus.conectando);

    final channel = WebSocketChannel.connect(Uri.parse(url));
    _channel = channel;

    channel.ready.then((_) {
      if (_disposed) return;
      _attempt = 0;
      _setStatus(SocketStatus.conectado);
      sendHello(_nickname!, token: _token);
    }).catchError((Object _) {
      _handleDisconnect();
    });

    _channelSub = channel.stream.listen(
      (data) {
        if (data is String) {
          try {
            _messages.add(jsonDecode(data) as Map<String, dynamic>);
          } on FormatException {
            // Mensaje corrupto: se ignora.
          }
        }
      },
      onError: (Object _) => _handleDisconnect(),
      onDone: _handleDisconnect,
    );
  }

  void _handleDisconnect() {
    if (_disposed) return;
    _setStatus(SocketStatus.desconectado);
    _reconnectTimer ??= Timer(_nextBackoff(), () {
      _reconnectTimer = null;
      _open();
    });
  }

  Duration _nextBackoff() {
    final ms = 500 * pow(2, min(_attempt, 4)).toInt();
    _attempt++;
    return Duration(milliseconds: min(ms, maxBackoff.inMilliseconds));
  }

  void _setStatus(SocketStatus value) {
    if (!_status.isClosed) _status.add(value);
  }

  /// Identifica al usuario ante el servidor. Con un nombre nuevo responde
  /// `canvas_snapshot` (con token de credencial); si el nombre ya está
  /// registrado y el token no coincide, responde `nickname_taken`.
  @override
  void sendHello(String nickname, {String? token}) {
    _channel?.sink.add(
      jsonEncode({'type': 'hello', 'nickname': nickname, 'token': ?token}),
    );
  }

  /// Envía un mensaje al chat; el server lo valida, persiste y broadcastea
  /// como `chat_update` a todos los clientes.
  @override
  void sendChat(String text) {
    _channel?.sink.add(jsonEncode({'type': 'chat', 'text': text}));
  }

  @override
  void sendPaint({
    required int x,
    required int y,
    required String color,
    required String nickname,
  }) {
    _channel?.sink.add(
      jsonEncode({
        'type': 'paint',
        'x': x,
        'y': y,
        'color': color,
        'userId': nickname,
      }),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _channelSub?.cancel();
    _channel?.sink.close();
    _messages.close();
    _status.close();
  }
}
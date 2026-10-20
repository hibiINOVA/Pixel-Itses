import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

const String kWsUrl = String.fromEnvironment(
  'WS_URL',
  defaultValue: 'ws://localhost:3000',
);

enum SocketStatus { conectando, conectado, desconectado }

abstract class SocketClient {
  Stream<Map<String, dynamic>> get messages;
  Stream<SocketStatus> get status;

  void connect(String nickname, {String? token});
  void sendHello(String nickname);
  void sendChat(String text);
  void sendPaint({required int x, required int y, required String color, required String nickname});
  void sendFinishTurn();
  void sendNextGame();
  void sendStartMatchmaking();
  void dispose();
}

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

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  @override
  Stream<SocketStatus> get status => _status.stream;

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
      sendHello(_nickname!);
    }).catchError((Object _) {
      _handleDisconnect();
    });

    _channelSub = channel.stream.listen(
      (data) {
        if (data is String) {
          try {
            final message = jsonDecode(data) as Map<String, dynamic>;
            // Adoptar el token más reciente del servidor para que la
            // próxima reconexión pueda reclamar el mismo nickname.
            if (message['type'] == 'auth_ok' &&
                message['token'] is String) {
              _token = message['token'] as String;
            }
            _messages.add(message);
          } on FormatException {
            // Mensaje no es JSON válido, ignorar
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

  @override
  void sendHello(String nickname) {
    _channel?.sink.add(jsonEncode({
      'type': 'hello',
      'nickname': nickname,
      if (_token != null) 'token': _token,
    }));
  }

  @override
  void sendChat(String text) {
    _channel?.sink.add(jsonEncode({'type': 'chat', 'text': text}));
  }

  @override
  void sendPaint({required int x, required int y, required String color, required String nickname}) {
    _channel?.sink.add(jsonEncode({'type': 'paint', 'x': x, 'y': y, 'color': color, 'userId': nickname}));
  }

  @override
  void sendFinishTurn() {
    _channel?.sink.add(jsonEncode({'type': 'finish_turn'}));
  }

  @override
  void sendNextGame() {
    _channel?.sink.add(jsonEncode({'type': 'next_game'}));
  }

  @override
  void sendStartMatchmaking() {
    _channel?.sink.add(jsonEncode({'type': 'start_matchmaking'}));
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

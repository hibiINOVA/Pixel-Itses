import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/websocket_service.dart';
import 'retro_text_field.dart';

class ChatMessage {
  const ChatMessage({
    required this.nickname,
    required this.text,
    required this.createdAt,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
        nickname: map['nickname'] as String,
        text: map['text'] as String,
        createdAt: (map['createdAt'] as num).toInt(),
      );

  final String nickname;
  final String text;
  final int createdAt;
}

/// Panel de chat por sala. Solo muestra mensajes de la sala actual.
class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key, required this.socket, this.roomId});

  final SocketClient socket;
  final String? roomId;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.socket.messages.listen(_handleMessage);
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (message['type'] == 'chat_update') {
      setState(() {
        _messages.add(ChatMessage.fromMap(message));
        if (_messages.length > 50) {
          _messages.removeRange(0, _messages.length - 50);
        }
      });
    }
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.socket.sendChat(text);
    _controller.clear();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: const Color(0xFFD62828),
            child: Text(
              'CHAT',
              textAlign: TextAlign.center,
              style: GoogleFonts.pressStart2p(
                fontSize: 11,
                color: const Color(0xFFFFF3D6),
              ),
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'ESCRIBÍ ALGO...',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.pressStart2p(
                        fontSize: 8,
                        height: 1.8,
                        color: Colors.white24,
                      ),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(10),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message =
                          _messages[_messages.length - 1 - index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '[${message.nickname}] ',
                                style: const TextStyle(
                                    color: Color(0xFFFF8C42)),
                              ),
                              TextSpan(text: message.text),
                            ],
                          ),
                          style: GoogleFonts.pressStart2p(
                            fontSize: 8,
                            height: 1.6,
                            color: const Color(0xFFFFF3D6),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white, width: 2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: RetroTextField(
                    hint: 'MENSAJE...',
                    controller: _controller,
                    maxLength: 200,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF8C42),
                      border: Border.fromBorderSide(
                        BorderSide(color: Colors.black, width: 3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black,
                          offset: Offset(3, 3),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: Text(
                      'ENVIAR',
                      style: GoogleFonts.pressStart2p(
                        fontSize: 9,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

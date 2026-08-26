import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/login_screen.dart';
import 'services/websocket_service.dart';

void main() {
  runApp(const PixelBoardApp());
}

class PixelBoardApp extends StatelessWidget {
  const PixelBoardApp({super.key, this.socket});

  /// Socket inyectable para tests; en producción es null y cada pantalla
  /// crea su WebsocketService real.
  final SocketClient? socket;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pixel Board',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: GoogleFonts.pressStart2p().fontFamily,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: LoginScreen(socket: socket),
    );
  }
}
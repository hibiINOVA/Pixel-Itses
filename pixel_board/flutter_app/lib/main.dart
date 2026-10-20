import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/login_screen.dart';
import 'screens/matchmaking_screen.dart';
import 'services/user_store.dart';
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
      home: _StartRouter(socket: socket),
    );
  }
}

/// Decide entre LoginScreen y MatchmakingScreen según si hay sesión guardada.
class _StartRouter extends StatefulWidget {
  const _StartRouter({this.socket});

  final SocketClient? socket;

  @override
  State<_StartRouter> createState() => _StartRouterState();
}

class _StartRouterState extends State<_StartRouter> {
  final UserStore _userStore = UserStore();

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final nickname = await _userStore.getNickname();
    if (!mounted) return;

    if (nickname != null && nickname.isNotEmpty) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MatchmakingScreen(socket: widget.socket),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LoginScreen(socket: widget.socket),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Splash minimalista mientras se revisa la sesión
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            color: Color(0xFFFF6B35),
            strokeWidth: 4,
          ),
        ),
      ),
    );
  }
}

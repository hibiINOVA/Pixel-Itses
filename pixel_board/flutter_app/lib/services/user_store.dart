import 'package:shared_preferences/shared_preferences.dart';

/// Guarda la sesión local (shared_preferences): el nickname registrado
/// y el token secreto que el backend entregó al registrarlo. El token
/// permite volver a entrar con el mismo nombre sin que lo rechacen.
class UserStore {
  static const _keyNickname = 'nickname';
  static const _keyToken = 'token';

  Future<void> saveNickname(String nickname) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNickname, nickname);
  }

  Future<String?> getNickname() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyNickname);
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }
}
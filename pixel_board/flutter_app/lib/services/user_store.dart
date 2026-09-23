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

  Future<void> saveStats({
    required int wins,
    required int losses,
    required int draws,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('wins', wins);
    await prefs.setInt('losses', losses);
    await prefs.setInt('draws', draws);
  }

  Future<Map<String, int>> getStats() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'wins': prefs.getInt('wins') ?? 0,
      'losses': prefs.getInt('losses') ?? 0,
      'draws': prefs.getInt('draws') ?? 0,
    };
  }

  /// Borra todos los datos de sesión (cerrar sesión).
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyNickname);
    await prefs.remove(_keyToken);
    await prefs.remove('wins');
    await prefs.remove('losses');
    await prefs.remove('draws');
  }
}
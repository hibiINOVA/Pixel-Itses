# Pixel Itses — Frontend Flutter

Cliente Flutter para el juego de dibujar de memoria y comparar. Dos jugadores memorizan una imagen, cada uno dibuja la suya en un lienzo 32×32, y al finalizar se comparan los resultados con la referencia.

## Getting Started

```bash
flutter pub get       # instalar dependencias
flutter analyze       # verificar lint (0 warnings)
flutter test          # ejecutar 25 tests
flutter run -d chrome # correr en Chrome
```

## Build Web

```bash
flutter build web --dart-define=WS_URL=ws://tudominio:3000
```

El build toma ~2.5 minutos. Los archivos se generan en `build/web/`.

## Arquitectura

- **Screens:** `LoginScreen`, `RegisterScreen`, `MatchmakingScreen`, `GameScreen`
- **Widgets reutilizables:** `RetroButton`, `RetroTextField`, `RetroPasswordField`, `RetroCounter`, `ColorPalette`, `PixelCanvas`, `ChatPanel`, `ScorpyMascot`
- **Servicios:** `SocketClient` (abstract) / `WebsocketService`, `UserStore` (SharedPreferences)
- **Modelo:** `PixelState` (ChangeNotifier para el canvas)

La URL del backend se define en compile-time con `--dart-define=WS_URL=ws://host:3000` (default `ws://localhost:3000`). Ver `kWsUrl` en `websocket_service.dart`.

## Mascota: Scorpy

Scorpy es un escorpión virtual pixel art dibujado programáticamente con `ScorpyPainter` (CustomPainter). No usa imágenes externas — cada píxel se dibuja como un `Canvas.drawRect` perfecto para mantener la nitidez del pixel art en cualquier pantalla.

**Estados:** `idle`, `tipOn` (bombilla encendida + glow pulsante), `celebrating` (tenazas elevadas).

**Mensajes contextuales:** Scorpy muestra pistas dinámicas según el estado de la UI (foco de campos, errores de login, fortaleza de contraseña, fase del juego, resultados).

## Testing

```bash
flutter test       # 25 tests de widget + modelo
flutter analyze    # 0 issues
```

Los tests usan `FakeSocket` (implementación de `SocketClient`) para inyectar mensajes sin conexión real. `SharedPreferences.setMockInitialValues({})` en `setUp` para aislamiento.

## Dependencies

- `shared_preferences` — persistencia de sesión (nickname, token, stats)
- `google_fonts` — fuente Press Start 2P (necesita red en runtime)
- `web_socket_channel` — conexión WebSocket al backend
- `url_launcher` — apertura de URLs externas

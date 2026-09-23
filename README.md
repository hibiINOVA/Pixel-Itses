# Pixel Itses

Juego dos jugadores de **dibujar de memoria y comparar**: cada ronda muestra una imagen de referencia que ambos memorizan, luego cada jugador dibuja la suya en un lienzo pixel de 32×32. Al finalizar ambos turnos, se comparan los dibujos con la referencia y se calcula un puntaje de similitud.

## Problemática

Jugar solo es divertido, pero jugar **con alguien más** crea conexión real. Pixel Itses combina la nostalgia del pixel art retro con la tensión de dibujar de memoria: ¿qué tan bien recordás esa imagen? ¿Mejor que tu oponente?

No hay likes, no hay algoritmos: solo dos personas creando arte pixel a pixel bajo presión, comparando resultados y riéndose de los intentos. Un espacio simple para construir algo juntos en tiempo real.

## Stack

| Capa | Tecnologías |
|---|---|
| **Backend** | Node.js · WebSocket (`ws`) · SQLite (`node:sqlite`) · `crypto` (scrypt passwords/tokens) · ESM |
| **Frontend** | Flutter (Dart ^3.12) · `web_socket_channel` · `shared_preferences` · `google_fonts` (Press Start 2P) · `url_launcher` |
| **Arquitectura** | `CustomPainter` (grid 32×32) · `ScorpyPainter` (mascota pixel art) · `SocketClient` (abstracción inyectable para tests) · Streams |
| **Testing** | `flutter test` (25 tests) · `npm run smoke` (tests de integración autónomos) · `flutter analyze` (0 warnings) |

## Estructura

```
pixel_board/
├── backend/                  # Node.js + WebSocket + SQLite
│   ├── server.js             # servidor WebSocket + HTTP
│   ├── canvas.js             # lógica del grid (matriz de colores)
│   ├── room.js               # salas de juego y fases
│   ├── matcher.js            # matchmaking automático
│   ├── scoring.js            # comparación de imágenes y puntajes
│   ├── images.js             # generación de imágenes de referencia
│   ├── users.js              # usuarios, cooldowns, stats
│   ├── db.js                 # persistencia SQLite (migración aditiva v1→v2→v3)
│   ├── test/smoke.js         # test de integración autónomo
│   └── package.json
│
└── flutter_app/              # Cliente Flutter (web/Chrome)
    ├── lib/
    │   ├── main.dart         # routing + splash screen
    │   ├── screens/
    │   │   ├── login_screen.dart         # login con nickname + password
    │   │   ├── register_screen.dart      # registro con validación de contraseña
    │   │   ├── matchmaking_screen.dart   # espera de oponente + stats
    │   │   └── game_screen.dart          # juego completo (preview/draw/results)
    │   ├── widgets/
    │   │   ├── scorpy_painter.dart       # mascota Scorpy pixel art (CustomPainter)
    │   │   ├── scorpy_mascot.dart        # widget wrapper de Scorpy + bocadillo
    │   │   ├── pixel_canvas.dart         # CustomPainter del grid 32×32
    │   │   ├── color_palette.dart        # selector de colores
    │   │   ├── retro_button.dart         # botón estilo retro
    │   │   ├── retro_text_field.dart     # input estilo retro
    │   │   ├── retro_password_field.dart # input password con toggle visibilidad
    │   │   ├── retro_counter.dart        # texto pixel con borde
    │   │   └── chat_panel.dart           # chat in-game
    │   ├── services/
    │   │   ├── websocket_service.dart    # conexión, streams, SocketClient
    │   │   └── user_store.dart           # SharedPreferences (nickname, token, stats)
    │   └── models/
    │       └── pixel_state.dart          # estado del canvas + ChangeNotifier
    ├── test/
    │   ├── widget_test.dart              # tests de UI (25 tests)
    │   └── pixel_state_test.dart         # tests del modelo
    └── pubspec.yaml
```

## Cómo correr

### 1. Backend

```bash
cd pixel_board/backend
npm install        # solo la primera vez
npm start          # servidor en ws://localhost:3000
npm run smoke      # test de integración autónomo (levanta su propio servidor)
```

Variables de entorno opcionales: `PORT` (3000), `DB_PATH` (`pixel_board.sqlite`), `PREVIEW_SECONDS` (15), `DRAW_SECONDS` (60).

El canvas, matchmaking, scoring y stats se persisten en SQLite y sobreviven reinicios. La DB migra automáticamente al esquema v3.

### 2. Frontend

```bash
cd pixel_board/flutter_app
flutter pub get    # solo la primera vez
flutter analyze    # lint (0 warnings)
flutter test       # 25 tests
flutter run -d chrome
```

Para apuntar a otro backend:

```bash
flutter run --dart-define=WS_URL=ws://10.0.2.2:3000
```

Build web (toma ~2.5 min):

```bash
flutter build web --dart-define=WS_URL=ws://tudominio:3000
```

## Flujo del juego

1. **Login/Registro** — el nickname es tu identidad única. Login envía `hello {nickname, password}`. Registro envía `register {nickname, password}` con contraseña fuerte (8+ chars, mayús, minús, número, especial).
2. **Matchmaking** — al autenticarse, el jugador entra en cola automáticamente. Al encontrar oponente, se crea una sala.
3. **`game_start`** — ambos reciben la imagen de referencia + countdown de preview.
4. **Fase de preview** — memorizá la imagen (15s por defecto).
5. **Turno del jugador 1** — dibujá tu versión en el lienzo 32×32 (60s por defecto).
6. **Turno del jugador 2** — mismo proceso. Chat disponible durante la espera.
7. **`game_results`** — se muestran los tres lienzos (referencia, tuyo, oponente) con puntajes de similitud. Botón "SIGUIENTE PARTIDA" re-encola.

## Mascota: Scorpy

**Scorpy** es un escorpión virtual pixel art que guía al usuario con bocadillos de texto contextuales. Dibujado programáticamente con `CustomPainter` (sin imágenes externas) para mantener los bordes del pixel art completamente nítidos (Nearest-Neighbor implícito).

- **Estados:** `idle` (bombilla apagada), `tipOn` (bombilla encendida con glow pulsante), `celebrating` (tenazas elevadas).
- **Paleta:** cuerpo `#B86F2C`, sombras `#6F411C`, luces `#FFD8A8`, bombilla `#F9BB30`, contorno `#100D09`.
- **Posición:** esquina inferior derecha en todas las pantallas (48px en login/register/matchmaking, 40px en juego).
- **Mensajes:** dinámicos según contexto (foco de campos, errores, resultados del juego).

## Identidad del usuario

- El **nickname** es la identidad única en el servidor (PK).
- Auth usa **contraseñas** (hash scrypt) — el token es credencial de reanudación de sesión.
- Login envía `hello {nickname, password}`, registro envía `register {nickname, password}`.
- Nombre duplicado → `nickname_taken`; password incorrecto → `auth_error {error: 'wrong_password'}`; cuenta inexistente → `auth_error {error: 'not_found'}`.

## Estilo visual

Retro pixel art como requisito duro:
- Fuente: Press Start 2P (monospace pixel)
- Bordes: sólidos negros/blancos, 2-4px, **sin** `borderRadius`
- Sombras: `BoxShadow` con `blurRadius: 0` (sombra sólida offset)
- Paleta: crema `#FFF3D6`, naranjas `#FF6B35`/`#FF8C42`, rojo `#D62828`, negro puro

## Estado del proyecto

- ✅ Backend WebSocket con juego completo (matchmaking, fases, scoring, stats)
- ✅ Persistencia SQLite (usuarios, mensajes, historial de partidas)
- ✅ Login + registro con validación de contraseña fuerte
- ✅ Matchmaking automático
- ✅ Juego completo: preview → turno jugador 1 → turno jugador 2 → resultados
- ✅ Chat in-game
- ✅ Mascota Scorpy pixel art interactiva (CustomPainter)
- ✅ Frontend Flutter con 25 tests pasando
- ✅ Build web funcional

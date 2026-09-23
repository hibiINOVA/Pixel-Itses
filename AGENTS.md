# AGENTS.md

## Project state

Two-player memory-draw-and-compare game. Structure: `pixel_board/{backend, flutter_app}`. Root `README.md` has run instructions for humans.

## Stack

- Backend: Node.js + WebSocket (`ws`), SQLite (`node:sqlite`) for persistence, `crypto` for passwords/tokens. ESM (`"type": "module"` in package.json). Entry: `server.js`. Source: `canvas.js`, `room.js`, `matcher.js`, `scoring.js`, `images.js`, `users.js`, `db.js`.
- Frontend: Flutter (Dart ^3.12) with `shared_preferences`, `google_fonts` (Press Start 2P), `web_socket_channel`, `url_launcher`. Single `CustomPainter` grid (never per-pixel widgets). `SocketClient` abstract class (`websocket_service.dart`) lets widget tests inject fakes — screens take an optional socket, null means real `WebsocketService`.
- Mascot: `ScorpyPainter` (`scorpy_painter.dart`) draws a scorpion pixel-by-pixel via `CustomPainter`. `ScorpyMascot` (`scorpy_mascot.dart`) wraps it with a speech bubble and animation. States: `idle`, `tipOn`, `celebrating`.

## Commands

In `pixel_board/backend/`: `npm install`, `npm start` (node server.js, port 3000), `npm run smoke` (test/smoke.js — self-hosted: spawns its own server on a random port with PREVIEW_SECONDS=1, DRAW_SECONDS=2, tests full game flow including matchmaking/draw/results/stats persistence; no running server needed).

Backend env vars: `PORT` (3000), `DB_PATH`, `PREVIEW_SECONDS` (15), `DRAW_SECONDS` (60).

In `pixel_board/flutter_app/`: `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run -d chrome`, `flutter build web`. Deps: `shared_preferences`, `google_fonts` (`Press Start 2P` — needs network at runtime), `web_socket_channel`, `url_launcher`. No image assets (Scorpy is rendered programmatically). Backend URL is a compile-time define: `--dart-define=WS_URL=ws://host:3000` (default `ws://localhost:3000`, see `kWsUrl`). Login/register texts are in Spanish.

Verification order: `flutter analyze` (lint) → `flutter test` → `npm run smoke`.

- `flutter build web` takes ~2.5 min and can look hung; give bash tool calls ≥300s timeout.

## Conventions to follow

- All doc, UI copy, and code comments in Spanish.
- Message protocol: client → server `hello {nickname, token?, password?}`, `register {nickname, password}`, `paint {x,y,color,userId}`, `finish_turn`, `chat {text}` (máx. 200 chars), `next_game`; server → client `auth_ok {token, wins, losses, draws}`, `canvas_snapshot`, `game_start {roomId, player1, player2, opponent, referenceImage, previewSeconds, drawSeconds}`, `draw_start {drawSeconds}`, `pixel_update`, `player_finished {nickname}`, `game_results {winner, player1Score, player2Score, player1Canvas, player2Canvas, reference, forfeit}`, `chat_update`, `nickname_taken`, `auth_error {error}`, `matchmaking_status {status}`, `stats_update {wins, losses, draws}`.
- Identity: the nickname IS the unique identity (users PK). Auth uses passwords (scrypt hash) — token is a session resume credential. Login sends `hello {nickname, password}`, register sends `register {nickname, password}`. Duplicate name → `nickname_taken`; wrong password → `auth_error {error: 'wrong_password'}`; unknown name → `auth_error {error: 'not_found'}`.
- Game flow: login → auto-matchmaking → `game_start` with reference image → preview phase (memorize) → both players draw simultaneously → `game_results` with similarity scores → "SIGUIENTE PARTIDA" button re-queues.
- Backend is the single source of truth for all game state. Paint coordinates validated with strict types (`Number.isInteger`). Nicknames normalized server-side: trimmed, 1–16 chars, regex `[a-zA-Z0-9_\- ]`.
- SQLite schema: users keyed by nickname with `token NOT NULL`, `password_hash`, `wins`, `losses`, `draws`; messages table scoped to room; `games` table for match history.
- Retro pixel style is a hard requirement: pixel/monospace font (Press Start 2P), thick solid black/white borders, **no** `borderRadius`, solid offset shadows via `BoxShadow` with blur of 0. Palette is cream `#FFF3D6`, oranges `#FF6B35`/`#FF8C42`, red `#D62828`, pure black borders.
- Scorpy mascot: drawn programmatically with `ScorpyPainter` (CustomPainter, no image assets). Color palette: body `#B86F2C`, shadows `#6F411C`, lights `#FFD8A8`, bulb `#F9BB30`/`#E69E58`, outline `#100D09`. States: `idle`, `tipOn` (bulb lit + glow), `celebrating` (claws raised). Positioned bottom-right in all screens.

## Gotchas

- Port 8080 is occupied by a docker-proxy — use the default 3000.
- Starting `server.js` in the background from a bash tool call can wedge the shell; run it detached (`setsid node server.js </dev/null >log 2>&1 &`) and kill via `pkill -f "node server.js"` (the pkill call itself may hang the tool shell — it still works; verify port with `ss -tlnp | grep 3000`).
- The smoke test no longer needs a live server or clean state — it manages its own lifecycle. Don't reintroduce dependence on a manually started server.
- The smoke test must close earlier connections (`a2.ws.close()` etc.) before starting the matchmaking section, otherwise stale connections remain in the matcher queue and corrupt pairing.
- `draw_start` is sent to **both** players simultaneously — both draw at the same time.
- Chat is always visible as a sidebar on the right during preview and drawing phases.
- Flutter widget tests: `SharedPreferences.setMockInitialValues({})` in `setUp`; after navigating to a screen use explicit `pump(duration)` steps, never `pumpAndSettle` (reconnect timers never settle). Messages emitted via FakeSocket must be done AFTER the target screen's message listener is set up (add pump delays).
- `_StartRouter._checkSession()` is async — tests need extra pumps (3 total) after `pumpWidget` for the navigation to complete. The `_enterBoard` method in both login and register screens has a `Future.delayed(800ms)` for Scorpy's celebration animation — tests need to pump through that delay.
- `GameScreen._myNickname` is derived from `gameStart`: if `player1 == opponent` then the user is `player2`, else `player1`.
- `PixelCanvas.onTapPixel` takes `void Function(int x, int y)`, not single-arg.

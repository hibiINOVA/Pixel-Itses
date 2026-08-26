# AGENTS.md

## Project state

Spec + backend + login + pizarra + cooldown + persistencia: **todas las 5 fases implementadas**. The authoritative design document is `pixel-board-spec.md` (written in Spanish). Backend Phases 1/4/5 done (WebSocket, cooldown 5/2min, SQLite), Flutter Phases 2/3 done (login, board funcional). Follow spec §2 structure.

Structure: `pixel_board/{backend, flutter_app}` per spec §2. Root `README.md` has run instructions for humans.

## Stack (per spec, not yet implemented)

- Backend: Node.js + WebSocket (state held in memory), SQLite (`db.js`) for persistence only.
- Frontend: Flutter with `shared_preferences` for the local `{nickname, token}` session; real-time rendering via a single `CustomPainter` grid (never per-pixel widgets). `SocketClient` interface (`websocket_service.dart`) lets widget tests inject fakes — screens take an optional socket, null means real `WebsocketService`.

## Conventions to follow

- All doc, UI copy, and code comments in Spanish (matches the spec). Keep the identifier names exactly as the spec defines them: `pixelsRemaining`, `cooldownEndsAt`, `pixel_update`, `canvas_snapshot`, `cooldown_update`, `paint`.
- Message protocol: client → server `hello {nickname, token?}` (token = credencial secreta; omitido al registrarse por primera vez) and `paint {x,y,color,userId}` (userId carries the nickname) and `chat {text}` (máx. 200 chars, requiere sesión identificada, throttle 500ms/conexión); server → client `canvas_snapshot {canvas, pixelsRemaining, cooldownEndsAt, token}` (token only when the hello is accepted), `chat_history {messages: [{nickname, text, createdAt}]}` (últimos 50 al entrar), `chat_update {nickname, text, createdAt}` (broadcast), `pixel_update {x,y,color}`, `cooldown_update {pixelsRemaining,cooldownEndsAt}`, `nickname_taken {nickname}` (name registered and token missing/wrong — no snapshot follows).
- Identity: the nickname IS the unique identity (users PK). On first registration the backend issues a random token (`crypto.randomBytes`); the Flutter app stores `{nickname, token}` in shared_preferences and re-sends both on every connect/reconnect so the owner resumes silently. Duplicate name without a matching token → `nickname_taken`; login does a pre-check with an ephemeral WS connection BEFORE navigating (error "NOMBRE YA USADO · PROBÁ OTRO" inline under the button; 3s timeout → "SIN CONEXIÓN AL SERVIDOR"). Board handles `nickname_taken` defensively by returning to login.
- Backend is the single source of truth for the cooldown (5 pixels / 2 min) — the client's counter check is UX only; never accept a paint from server-side logic without validating `pixelsRemaining` and `cooldownEndsAt`. Paint coordinates are validated with strict types (`Number.isInteger`) before touching the grid — no JS coercion. Nicknames are normalized server-side: trimmed, 1–16 chars, regex `[a-zA-Z0-9_\- ]`.
- SQLite `pixels` uses composite PK `(x, y)` — paint means `UPDATE`, never `INSERT`. No history table (no undo). `cooldownEndsAt` is `null` until the user hits 0. `pixels.updatedBy` references the nickname that painted. Schema v2 (2026-08): users keyed by nickname with `token NOT NULL`; the old UUID-based DB was deleted during migration.
- Retro pixel style is a hard requirement: pixel/monospace font (e.g. `Press Start 2P`), thick solid black/white borders, **no** `borderRadius`, solid offset shadows via `BoxShadow` with blur of 0 (no soft Material shadows). Palette is cream `#FFF3D6`, oranges `#FF6B35`/`#FF8C42`, red `#D62828`, pure black borders.

## Commands

In `pixel_board/backend/`: `npm install`, `npm start` (node server.js, port 3000), `npm run smoke` (test/smoke.js — self-hosted: spawns its own server on a random port with COOLDOWN_MS=600, tests nickname uniqueness/token resume/cooldown expiry AND SQLite persistence across a restart; no running server needed).

Backend env vars: `PORT` (3000), `DB_PATH`, `COOLDOWN_MS`, `PIXELS_PER_CYCLE`.

In `pixel_board/flutter_app/`: `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run -d chrome`, `flutter build web`. Deps: `shared_preferences`, `google_fonts` (`Press Start 2P` — needs network at runtime), `web_socket_channel`. Backend URL is a compile-time define: `--dart-define=WS_URL=ws://host:3000` (default `ws://localhost:3000`, see `kWsUrl`). Login texts are in Spanish (user choice, not the English mockups).
- `flutter build web` takes ~2.5 min here and can look hung; use `--no-wasm-dry-run` (skips the slow wasm dry-run pass) and give bash tool calls ≥300s timeout.

Gotchas:
- Port 8080 is occupied by a docker-proxy — use the default 3000.
- Starting `server.js` in the background from a bash tool call can wedge the shell; run it detached (`setsid node server.js </dev/null >log 2>&1 &`) and kill via `pkill -f "node server.js"` (the pkill call itself may hang the tool shell — it still works; verify port with `ss -tlnp | grep 3000`).
- The smoke test no longer needs a live server or clean state — it manages its own lifecycle. Don't reintroduce dependence on a manually started server.
- Flutter widget tests: `SharedPreferences.setMockInitialValues({})` in `setUp`; after navigating to the board use explicit `pump(duration)` steps, never `pumpAndSettle` (reconnect timers never settle).
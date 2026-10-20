# AGENTS.md

## Project state

Two-player memory-draw-and-compare game. `pixel_board/{backend, flutter_app}`. Root `README.md` has human run instructions.

**Working tree is mid-refactor and uncommitted.** Passwords and the whole `register` flow were just deleted (see "Auth model"). Trust the code, not the docs:

- `README.md` is STALE — documents register/passwords, lists `register_screen.dart` (deleted), claims 25 tests (actual: 19), and claims a v1→v3 DB migration that `db.js` no longer performs (it's only `CREATE TABLE IF NOT EXISTS`). Don't "restore" the password flow from it.
- `pixel-board-spec.md` is older still: it specs a *different* game (r/place-style shared canvas, 5-pixel/2-min cooldowns, `canvas_snapshot`). Ignore its architecture entirely.
- The local dev `pixel_board.sqlite` (gitignored) was created by the old schema, so it still has a leftover nullable `password_hash` column and ~13 pre-existing users. Harmless (new INSERTs omit the column), but it's what makes the lockout bug below trigger immediately.

## Stack

- Backend: Node ESM (`"type": "module"`), `ws`, `node:sqlite`, `crypto.randomBytes`. Entry `server.js`; modules `canvas.js`, `room.js`, `matcher.js`, `scoring.js`, `images.js`, `users.js`, `db.js`.
- Frontend: Flutter (Dart ^3.12). Deps: `shared_preferences`, `google_fonts` (Press Start 2P — fetches at runtime, needs network), `web_socket_channel`, `url_launcher`. No image assets; Scorpy is drawn programmatically.
- 32×32 grid is ONE `CustomPainter` (`pixel_canvas.dart`) — never per-pixel widgets.
- `SocketClient` abstract class in `websocket_service.dart` is the test seam: every screen takes an optional `SocketClient socket`; null ⇒ real `WebsocketService`. `test/widget_test.dart`'s `FakeSocket implements SocketClient` records sends and can `emit()` server messages.
- Backend URL is compile-time only: `kWsUrl` via `--dart-define=WS_URL=...` (default `ws://localhost:3000`). Rebuild to change it.

## Commands

Backend (`pixel_board/backend/`): `npm install`, `npm start` (port 3000), `npm run smoke`. Only those two scripts exist — there is no `npm test` or lint script.
Env vars: `PORT` (3000), `DB_PATH` (`pixel_board.sqlite`), `PREVIEW_SECONDS` (15), `DRAW_SECONDS` (60) — the last two are read in `room.js`.

Frontend (`pixel_board/flutter_app/`): `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run -d chrome`, `flutter build web`.

Verify in this order: `flutter analyze` → `flutter test` → `npm run smoke` (the two suites are independent; don't need both to pass to iterate on one). There is no CI or pre-commit config — these three commands are the entire verification surface.
`flutter build web` takes ~2.5 min and looks hung — give it ≥300s.

## Auth model (changed recently — read this before touching auth)

There is **no password and no register**. `users.js` has no `register`/`login`; the `password_hash` column was dropped from `db.js`; the server has no `register` handler. `hello` is the only entry:

- unknown nickname → `getOrCreate` (fresh random token) → `auth_ok`
- existing nickname + matching `token` → `auth_ok` (reconnect)
- existing nickname + no/invalid token → `nickname_taken`

The server never sends `auth_error` — only `auth_ok` and `nickname_taken`. Client still handles `auth_error` in `login_screen.dart` and `matchmaking_screen.dart`; that branch is dead.

### Known live bug: returning players are locked out

`UserStore` no longer persists the token (`saveToken`/`getToken` deleted) and `sendHello` never sends one, but the server requires it to reclaim an existing nickname. Since users persist in SQLite, a returning player gets `nickname_taken` for their own name on:
- `WebsocketService._handleDisconnect` auto-reconnect (sends `hello` with no token, server keeps the record)
- the `_StartRouter` fast-path in `main.dart` (nickname saved ⇒ skip login ⇒ connect ⇒ `nickname_taken`)

Worse, `matchmaking_screen.dart` handles `auth_error` but **not** `nickname_taken`, so that path strands the player on the matchmaking screen until the matchmaking timeout. If you touch auth, the fix is to persist the token again and send it on reconnect — don't paper over it by deleting the duplicate-name check, which is what makes names unique.

Dead code left behind: `lib/widgets/retro_password_field.dart` has zero references.

## Protocol

Client → server: `hello {nickname, token?}`, `start_matchmaking`, `paint {x,y,color,userId}`, `finish_turn`, `chat {text}`, `next_game` (server ignores `paint.userId` — it uses the authenticated nickname).
Server → client: `auth_ok {token, wins, losses, draws}`, `matchmaking_status {status}`, `game_start {roomId, player1, player2, opponent, referenceImage, previewSeconds, drawSeconds}`, `draw_start {drawSeconds}`, `pixel_update`, `player_finished {nickname}`, `game_results {roomId, winner, player1, player2, opponent, player1Score, player2Score, player1Canvas, player2Canvas, reference, forfeit}`, `chat_update {nickname, text, createdAt}`, `stats_update {wins, losses, draws}`, `nickname_taken {nickname}`. That list is complete — the server sends nothing else (older docs mention `canvas_snapshot`, which is never sent).

- `start_matchmaking` is required to enter the queue — matchmaking is NOT automatic on `auth_ok`. `matchmaking_screen.dart` sends it from inside its `auth_ok` handler, so the listener must exist before the first server message arrives.
- `draw_start` goes to **both** players: they draw simultaneously, not in turns.
- Chat only works inside a room (`getRoomForWs(ws)` returns null otherwise), max 200 chars, 500 ms rate limit.
- Everything except `hello` requires prior auth (`wsToNickname`).
- Don't confuse protocol message types with `GameScreen._phase`, a local UI state string (`'image_preview' | 'drawing' | 'waiting_results' | 'results'`) assigned in handlers. Grepping for `case '...'` in `game_screen.dart` hits both.

## Conventions

- All docs, UI copy, and code comments in **Spanish**.
- Backend is the single source of truth for game state. `paint` validates strictly: `Number.isInteger(x/y)`, `color` must be a 7-char string.
- Nicknames normalized server-side in `normalizeNickname`: trimmed, ≤16 chars, regex `[a-zA-Z0-9_\- ]`. Invalid → connection silently ignored (no error reply).
- SQLite: `users` keyed by nickname (`token NOT NULL`, `wins`, `losses`, `draws`); `messages` scoped to room; `games` for match history. `getStats` always returns all three stat keys, so `...stats` spreads safely into `auth_ok`.
- Retro pixel style is a hard requirement: Press Start 2P, thick solid black borders, **no** `borderRadius`, offset shadows with `blurRadius: 0`. Palette: cream `#FFF3D6`, `#FF6B35`/`#FF8C42`, red `#D62828`, black.
- Scorpy (`scorpy_painter.dart` + `scorpy_mascot.dart`): `CustomPainter`, states `idle` / `tipOn` / `celebrating`, bottom-right in every screen.

## Gotchas

- Port 8080 is a docker proxy — use 3000.
- Backgrounding the server from a bash call can wedge the shell: `setsid node server.js </dev/null >log 2>&1 &`, kill with `pkill -f "node server.js"`, verify with `ss -tlnp | grep 3000`.
- `npm run smoke` is hermetic — random port and a per-PID temp SQLite in `tmpdir()`, cleaned up itself. Safe to re-run; needs no server running and no clean state. Don't reintroduce a dependency on a manually started server.
- Smoke test must `ws.close()` earlier connections (e.g. `a.ws.close()`, `dup.ws.close()`) before the matchmaking section, or stale sockets sit in the matcher queue and corrupt pairing. It also reuses fixed nicknames (`player1`, `alice`, `bob`) that only work because the DB is fresh each run — a new check added there must either use a fresh nickname or tolerate `nickname_taken`.
- `WebsocketService` retries with exponential backoff capped at 8 s and never settles → widget tests must use explicit `pump(duration)` steps, **never** `pumpAndSettle`.
- Widget tests: `SharedPreferences.setMockInitialValues({})` in `setUp`; emit via `FakeSocket` only after the screen's listener is attached (add pump delays); `_StartRouter._checkSession()` is async (needs 3 pumps after `pumpWidget`); `LoginScreen._enterBoard` has `Future.delayed(800ms)` for Scorpy's celebration (pump ~900 ms).
- `GameScreen._myNickname` is inferred, not sent: if `player1 == opponent` the user is `player2`, else `player1`. Result mapping in `game_results` depends on it.
- `PixelCanvas.onTapPixel` is `void Function(int x, int y)`, not single-arg.

import { spawn } from 'node:child_process';
import { randomInt } from 'node:crypto';
import { existsSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import { WebSocket } from 'ws';

const PORT = process.env.SMOKE_PORT || String(30000 + randomInt(20000));
const DB_PATH = join(tmpdir(), `pixel-board-smoke-${process.pid}.sqlite`);
const PREVIEW_SECONDS = '1';
const DRAW_SECONDS = '2';

let failures = 0;

function check(cond, label) {
  if (!cond) { console.error(`FALLO: ${label}`); failures++; }
  else { console.log(`OK: ${label}`); }
}

function startServer() {
  const child = spawn(process.env.NODE_BIN || 'node', ['server.js'], {
    cwd: fileURLToPath(new URL('..', import.meta.url)),
    env: { ...process.env, PORT, DB_PATH, PREVIEW_SECONDS, DRAW_SECONDS },
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('el servidor no arrancó')), 5000);
    child.stdout.on('data', (chunk) => {
      if (chunk.toString().includes('escuchando')) { clearTimeout(timer); resolve(child); }
    });
    child.once('exit', (code) => reject(new Error(`servidor terminó (code=${code})`)));
  });
}

function stopServer(child) {
  return new Promise((resolve) => { child.once('exit', resolve); child.kill('SIGTERM'); });
}

function connect() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://localhost:${PORT}`);
    const queue = [];
    ws.on('message', (raw, isBinary) => {
      if (isBinary) return;
      queue.push(JSON.parse(raw.toString()));
    });
    ws.once('open', () =>
      resolve({
        ws, queue,
        waitFor(type, timeoutMs = 3000, predicate) {
          const idx = () => queue.findIndex((m) => m.type === type && (!predicate || predicate(m)));
          if (idx() !== -1) return Promise.resolve(queue.splice(idx(), 1)[0]);
          return new Promise((res, rej) => {
            const start = Date.now();
            const poll = setInterval(() => {
              if (idx() !== -1) { clearInterval(poll); res(queue.splice(idx(), 1)[0]); }
              else if (Date.now() - start > timeoutMs) { clearInterval(poll); rej(new Error(`timeout esperando ${type}`)); }
            }, 10);
          });
        },
        hello(nickname, token, password) {
          this.ws.send(JSON.stringify({ type: 'hello', nickname, ...(token ? { token } : {}), ...(password ? { password } : {}) }));
        },
        register(nickname, password) {
          this.ws.send(JSON.stringify({ type: 'register', nickname, password }));
        },
        paint(x, y, color) {
          this.ws.send(JSON.stringify({ type: 'paint', x, y, color }));
        },
        finishTurn() {
          this.ws.send(JSON.stringify({ type: 'finish_turn' }));
        },
        chat(text) {
          this.ws.send(JSON.stringify({ type: 'chat', text }));
        },
        nextGame() {
          this.ws.send(JSON.stringify({ type: 'next_game' }));
        },
        startMatchmaking() {
          this.ws.send(JSON.stringify({ type: 'start_matchmaking' }));
        },
      })
    );
    ws.once('error', reject);
  });
}

let server;

try {
  if (existsSync(DB_PATH)) rmSync(DB_PATH);

  server = await startServer();

  // ─── Registro + login ────────────────────────────────────────────
  const a = await connect();
  a.register('player1', 'Passw0rd!');
  const regA = await a.waitFor('auth_ok');
  check(typeof regA.token === 'string' && regA.token.length > 0, 'registro devuelve token');
  check(regA.wins === 0 && regA.losses === 0, 'stats iniciales en 0');

  // Login con password
  const a2 = await connect();
  a2.hello('player1', null, 'Passw0rd!');
  const loginA = await a2.waitFor('auth_ok');
  check(loginA.token === regA.token, 'login con password devuelve mismo token');

  // Login con password incorrecto
  const bad = await connect();
  bad.hello('player1', null, 'Wrong0ne!');
  const authErr = await bad.waitFor('auth_error');
  check(authErr.error === 'wrong_password', 'password incorrecto → auth_error');

  // Nombre duplicado sin password
  const dup = await connect();
  dup.hello('player1');
  const taken = await dup.waitFor('nickname_taken');
  check(taken.nickname === 'player1', 'nombre duplicado sin password → nickname_taken');

  // Cleanup conexiones anteriores que podrían estar en la cola de matchmaking
  a.ws.close();
  a2.ws.close();
  bad.ws.close();
  dup.ws.close();
  await new Promise(r => setTimeout(r, 200));

  // ─── Matchmaking: dos jugadores emparejan ────────────────────────
  const p1 = await connect();
  p1.register('alice', 'Passw0rd!');
  await p1.waitFor('auth_ok');
  p1.startMatchmaking();
  const matchP1 = await p1.waitFor('matchmaking_status');
  check(matchP1.status === 'waiting', 'alice en cola de matchmaking');

  const p2 = await connect();
  p2.register('bob', 'Passw0rd!');
  await p2.waitFor('auth_ok');
  p2.startMatchmaking();

  // Ambos reciben game_start cuando se emparejan
  const start1 = await p1.waitFor('game_start');
  check(start1.referenceImage.length === 32, 'game_start incluye imagen de 32x32');
  check(start1.previewSeconds === Number(PREVIEW_SECONDS), 'previewSeconds configurable');
  check(start1.drawSeconds === Number(DRAW_SECONDS), 'drawSeconds configurable');
  check(start1.opponent === 'bob', 'alice ve a bob como oponente');

  const start2 = await p2.waitFor('game_start');
  check(start2.referenceImage.length === 32, 'bob también recibe imagen 32x32');
  check(start2.opponent === 'alice', 'bob ve a alice como oponente');

  // ─── Fase de dibujo: ambos dibujan al mismo tiempo ──────────────
  const drawStart = await p1.waitFor('draw_start');
  check(typeof drawStart.drawSeconds === 'number', 'draw_start incluye drawSeconds');
  // Ambos reciben draw_start — bob también recibe el primero
  await p2.waitFor('draw_start');

  // Alice pinta un pixel
  p1.paint(5, 5, '#FF6B35');
  const pixelUpdate = await p2.waitFor('pixel_update', 2000, (m) => m.x === 5 && m.y === 5);
  check(pixelUpdate.color === '#FF6B35', 'bob recibe pixel_update de alice');

  // Bob también pinta (simultáneamente)
  p2.paint(10, 10, '#D62828');
  const pixelUpdate2 = await p1.waitFor('pixel_update', 2000, (m) => m.x === 10 && m.y === 10);
  check(pixelUpdate2.color === '#D62828', 'alice recibe pixel_update de bob');

  // ─── Chat dentro de la sala ──────────────────────────────────────
  p1.chat('hola bob');
  const chatMsg = await p2.waitFor('chat_update', 2000, (m) => m.text === 'hola bob');
  check(chatMsg.nickname === 'alice', 'chat_update llega con nickname del autor');

  // ─── Alice termina su turno primero ──────────────────────────────
  p1.finishTurn();
  const bobFinished = await p2.waitFor('player_finished', 2000);
  check(bobFinished.nickname === 'alice', 'bob recibe player_finished de alice');

  // ─── Bob termina su turno → ambos terminaron → resultados ────────
  p2.finishTurn();
  const results1 = await p1.waitFor('game_results');
  check(typeof results1.player1Score === 'number', 'alice recibe player1Score');
  check(typeof results1.player2Score === 'number', 'alice recibe player2Score');
  check(['alice', 'bob', 'tie'].includes(results1.winner), 'winner es válido');

  const results2 = await p2.waitFor('game_results');
  check(results2.player1Score === results1.player1Score, 'scores consistentes entre jugadores');

  // ─── Stats actualizadas ──────────────────────────────────────────
  const stats1 = await p1.waitFor('stats_update');
  check(typeof stats1.wins === 'number', 'alice recibe stats_update');

  const stats2 = await p2.waitFor('stats_update');
  check(typeof stats2.wins === 'number', 'bob recibe stats_update');

  // ─── Persistencia: resultado guardado en SQLite ──────────────────
  const rawDb = new DatabaseSync(DB_PATH);
  const gameRow = rawDb.prepare('SELECT * FROM games ORDER BY id DESC LIMIT 1').get();
  check(gameRow !== undefined, 'partida guardada en SQLite');
  check(gameRow.player1 === 'alice' && gameRow.player2 === 'bob', 'jugadores correctos en DB');
  check(typeof gameRow.winner === 'string', 'winner guardado en DB');

  // Stats en DB
  const statsRow = rawDb.prepare('SELECT wins, losses, draws FROM users WHERE nickname = ?').get('alice');
  check(statsRow !== undefined, 'stats de alice en SQLite');
  rawDb.close();

  // ─── Siguiente partida: re-encolar ───────────────────────────────
  p1.nextGame();
  p2.nextGame();
  const nextMatch1 = await p1.waitFor('matchmaking_status');
  check(nextMatch1.status === 'waiting', 'alice re-encolada para siguiente partida');

  const nextStart1 = await p1.waitFor('game_start');
  check(nextStart1.referenceImage.length === 32, 'segunda partida inicia con nueva imagen');

  const nextStart2 = await p2.waitFor('game_start');
  check(nextStart2.referenceImage.length === 32, 'bob también recibe segunda partida');

  // ─── Desconexión durante matchmaking ─────────────────────────────
  const p3 = await connect();
  p3.register('charlie', 'Passw0rd!');
  await p3.waitFor('auth_ok');
  p3.startMatchmaking();
  await p3.waitFor('matchmaking_status');
  p3.ws.close();
  await new Promise((r) => setTimeout(r, 200));

  // Cleanup final
  p1.ws.close();
  p2.ws.close();

} catch (err) {
  console.error('FALLO:', err.message);
  failures++;
} finally {
  if (server) await stopServer(server).catch(() => {});
  if (existsSync(DB_PATH)) rmSync(DB_PATH);
  process.exit(failures === 0 ? 0 : 1);
}

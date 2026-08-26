import { spawn } from 'node:child_process';
import { randomInt } from 'node:crypto';
import { existsSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import { WebSocket } from 'ws';

// El smoke levanta su propio servidor: estado siempre limpio y sin depender
// de que haya un `npm start` corriendo.
const PORT = process.env.SMOKE_PORT || String(30000 + randomInt(20000));
const DB_PATH = join(tmpdir(), `pixel-board-smoke-${process.pid}.sqlite`);
const COOLDOWN_MS = '600';
const CHAT_MIN_INTERVAL_MS = 500;

let failures = 0;

function check(cond, label) {
  if (!cond) {
    console.error(`FALLO: ${label}`);
    failures++;
  } else {
    console.log(`OK: ${label}`);
  }
}

function startServer() {
  const child = spawn(process.env.NODE_BIN || 'node', ['server.js'], {
    cwd: fileURLToPath(new URL('..', import.meta.url)),
    env: { ...process.env, PORT, DB_PATH, COOLDOWN_MS },
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('el servidor no arrancó')), 5000);
    child.stdout.on('data', (chunk) => {
      if (chunk.toString().includes('escuchando')) {
        clearTimeout(timer);
        resolve(child);
      }
    });
    child.once('exit', (code) => reject(new Error(`servidor terminó (code=${code})`)));
  });
}

function stopServer(child) {
  return new Promise((resolve) => {
    child.once('exit', resolve);
    child.kill('SIGTERM');
  });
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
        ws,
        queue,
        waitFor(type, timeoutMs = 2000, predicate) {
          const index = () =>
            queue.findIndex((m) => m.type === type && (!predicate || predicate(m)));
          if (index() !== -1) return Promise.resolve(queue.splice(index(), 1)[0]);
          return new Promise((res, rej) => {
            const start = Date.now();
            const poll = setInterval(() => {
              if (index() !== -1) {
                clearInterval(poll);
                res(queue.splice(index(), 1)[0]);
              } else if (Date.now() - start > timeoutMs) {
                clearInterval(poll);
                rej(new Error(`timeout esperando ${type}`));
              }
            }, 10);
          });
        },
        hello(nickname, token) {
          this.ws.send(JSON.stringify({ type: 'hello', nickname, ...(token ? { token } : {}) }));
        },
        paint(x, y, color, nickname) {
          this.ws.send(JSON.stringify({ type: 'paint', x, y, color, userId: nickname }));
        },
        chat(text) {
          this.ws.send(JSON.stringify({ type: 'chat', text }));
        },
      })
    );
    ws.once('error', reject);
  });
}

let server;

try {
  if (existsSync(DB_PATH)) rmSync(DB_PATH);

  // ─── Servidor 1: registro, unicidad de nombre y cooldown ─────────
  server = await startServer();

  const a = await connect();
  a.hello('u1');
  const snapA = await a.waitFor('canvas_snapshot');
  const tokenU1 = snapA.token;

  check(snapA.canvas.length === 32, 'snapshot tiene 32 filas');
  check(snapA.canvas.every((row) => row.length === 32), 'cada fila tiene 32 columnas');
  check(snapA.canvas[3][2] === '#FFFFFF', 'canvas nuevo arranca en blanco');
  check(snapA.pixelsRemaining === 5, 'snapshot incluye pixelsRemaining=5');
  check(snapA.cooldownEndsAt === null, 'snapshot incluye cooldownEndsAt=null');
  check(typeof tokenU1 === 'string' && tokenU1.length > 0, 'registro devuelve token secreto');

  // El dueño vuelve con su token: resume sin error.
  const owner = await connect();
  owner.hello('u1', tokenU1);
  const snapOwner = await owner.waitFor('canvas_snapshot');
  check(snapOwner.pixelsRemaining === 5, 'dueño con token resume su cuenta');

  // Otro cliente con el mismo nombre y SIN token: rechazado.
  const dup = await connect();
  dup.hello('u1');
  const taken = await dup.waitFor('nickname_taken');
  check(taken.nickname === 'u1', 'nombre duplicado sin token → nickname_taken');

  // Con token incorrecto también: rechazado.
  const impostor = await connect();
  impostor.hello('u1', 'token-falso');
  const taken2 = await impostor.waitFor('nickname_taken');
  check(taken2.nickname === 'u1', 'nombre duplicado con token inválido → nickname_taken');
  check(dup.queue.every((m) => m.type !== 'canvas_snapshot'), 'rechazado NO recibe snapshot');
  check(
    impostor.queue.every((m) => m.type !== 'canvas_snapshot'),
    'impostor NO recibe snapshot'
  );

  // Nombres inválidos se ignoran (sin snapshot ni registro).
  const anon = await connect();
  anon.hello('');
  anon.hello('x'.repeat(20));
  anon.hello('mal$$nombre');

  // B registra su propio nombre sin problema.
  const b = await connect();
  b.hello('u2');
  await b.waitFor('canvas_snapshot');

  let bBroadcastCount = 0;
  b.ws.on('message', (raw, isBinary) => {
    if (isBinary) return;
    if (JSON.parse(raw.toString()).type === 'pixel_update') bBroadcastCount++;
  });

  // A pinta 5 veces: descuenta 4,3,2,1,0. El pixel queda a nombre de 'u1'.
  for (let i = 0; i < 5; i++) {
    a.paint(i, i, '#FF6B35', 'u1');
    const update = await a.waitFor('pixel_update', 2000, (m) => m.x === i && m.y === i);
    const cooldown = await a.waitFor('cooldown_update');
    check(update.x === i && update.y === i, `pixel_update correcto en el intento ${i + 1}`);
    check(cooldown.pixelsRemaining === 4 - i, `cooldown descuenta a ${4 - i} tras intento ${i + 1}`);
  }

  // La 6ª pintada se rechaza por cooldown: sin broadcast nuevo.
  const beforeRejected = bBroadcastCount;
  a.paint(10, 10, '#FF6B35', 'u1');
  const rejected = await a.waitFor('cooldown_update', 2000, (m) => m.pixelsRemaining === 0);
  check(rejected.cooldownEndsAt > Date.now(), '6ª pintada: cooldownEndsAt futuro');
  await new Promise((r) => setTimeout(r, 300));
  check(bBroadcastCount === beforeRejected, '6ª pintada NO genera broadcast (cooldown)');

  // B tiene presupuesto propio.
  b.paint(3, 4, '#D62828', 'u2');
  const updateB = await b.waitFor('pixel_update', 2000, (m) => m.x === 3 && m.y === 4);
  check(updateB.x === 3 && updateB.y === 4, 'B pinta su primer pixel');

  // Paint inválido (fuera de rango / tipo incorrecto / paleta ajena): sin broadcast.
  const before = bBroadcastCount;
  a.paint(40, 40, '#FF6B35', 'u1');
  a.paint('2', 2, '#FF6B35', 'u1');
  a.paint(1, 1, '#BADBAD', 'u1');
  await new Promise((r) => setTimeout(r, 300));
  check(bBroadcastCount === before, 'paints inválidos NO generan broadcast');

  // Expiración del cooldown (COOLDOWN_MS=600): recarga automática a 5→4.
  await new Promise((r) => setTimeout(r, 900));
  a.paint(20, 20, '#FFD700', 'u1');
  const recharged = await a.waitFor('cooldown_update', 2000, (m) =>
    m.cooldownEndsAt === null && m.pixelsRemaining === 4
  );
  check(recharged.pixelsRemaining === 4, 'tras expirar el cooldown recarga (queda 4)');
  check(recharged.cooldownEndsAt === null, 'cooldownEndsAt vuelve a null tras recarga');

  // ─── Chat en vivo ────────────────────────────────────────────────
  let aChats = 0;
  a.ws.on('message', (raw, isBinary) => {
    if (isBinary) return;
    if (JSON.parse(raw.toString()).type === 'chat_update') aChats++;
  });

  b.chat('hola desde u2');
  const chatMsg = await a.waitFor('chat_update', 2000, (m) => m.text === 'hola desde u2');
  check(chatMsg.nickname === 'u2', 'chat_update llega con el nickname del autor');
  check(typeof chatMsg.createdAt === 'number', 'chat_update incluye createdAt');

  // Mensajes inválidos: sin broadcast ni persistencia.
  const chatsBeforeInvalid = aChats;
  b.chat('');
  b.chat('   ');
  b.chat('x'.repeat(201));
  b.chat(42);
  b.chat({ text: 'objeto' });
  await new Promise((r) => setTimeout(r, 300));
  check(aChats === chatsBeforeInvalid, 'chats inválidos NO se difunden');

  // Throttle: dos mensajes seguidos, el segundo se descarta.
  // (Primero dejar vencer el intervalo desde el último mensaje válido.)
  await new Promise((r) => setTimeout(r, CHAT_MIN_INTERVAL_MS));
  b.chat('rápido 1');
  await a.waitFor('chat_update', 2000, (m) => m.text === 'rápido 1');
  b.chat('rápido 2'); // dentro de los 500ms mínimos
  await new Promise((r) => setTimeout(r, 300));
  check(aChats === chatsBeforeInvalid + 1, 'segundo mensaje inmediato bloqueado por throttle');

  // Sin sesión identificada no se puede chatear.
  anon.chat('soy anónimo');
  await new Promise((r) => setTimeout(r, 300));
  check(aChats === chatsBeforeInvalid + 1, 'conexión sin hello no puede chatear');

  a.ws.close();
  b.ws.close();
  owner.ws.close();
  dup.ws.close();
  impostor.ws.close();
  anon.ws.close();

  // ─── Persistencia: reinicio con la misma DB ──────────────────────
  await stopServer(server);

  // Lectura directa de la SQLite mientras el servidor está parado:
  // cada pixel sabe qué usuario (nickname) lo pintó.
  const rawDb = new DatabaseSync(DB_PATH);
  const pixelRow = rawDb.prepare('SELECT color, updatedBy FROM pixels WHERE x = 2 AND y = 2').get();
  check(pixelRow.color === '#FF6B35', 'pixel pintado quedó en SQLite');
  check(pixelRow.updatedBy === 'u1', 'updatedBy referencia al nickname que pintó');
  const userRow = rawDb.prepare('SELECT token FROM users WHERE nickname = ?').get('u1');
  check(userRow.token === tokenU1, 'token del dueño persistido en users');
  const msgRow = rawDb
    .prepare('SELECT nickname, text FROM messages ORDER BY id DESC LIMIT 1')
    .get();
  check(
    msgRow.nickname === 'u2' && msgRow.text === 'rápido 1',
    'mensaje del chat persistido en messages con su autor'
  );
  rawDb.close();

  server = await startServer();

  const c = await connect();
  c.hello('u1', tokenU1);
  const snapC = await c.waitFor('canvas_snapshot');

  check(snapC.canvas[3][2] === '#FFFFFF', 'pixel nunca tocado sigue blanco tras reinicio');
  check(snapC.canvas[2][2] === '#FF6B35', 'pixel pintado sobrevive el reinicio');
  check(snapC.canvas[20][20] === '#FFD700', 'segundo pixel pintado sobrevive el reinicio');
  check(snapC.pixelsRemaining === 4, 'estado de cooldown de u1 sobrevive el reinicio');
  check(snapC.token === tokenU1, 'token del dueño sobrevive el reinicio');

  // Historial del chat tras el snapshot: los mensajes sobreviven el reinicio.
  const history = await c.waitFor('chat_history');
  check(history.messages.length === 2, 'historial incluye todos los mensajes válidos');
  check(history.messages[0].text === 'hola desde u2', 'historial en orden ascendente');
  check(history.messages[1].nickname === 'u2', 'historial trae el nickname de cada autor');

  c.ws.close();
} catch (err) {
  console.error('FALLO:', err.message);
  failures++;
} finally {
  if (server) await stopServer(server).catch(() => {});
  if (existsSync(DB_PATH)) rmSync(DB_PATH);
  process.exit(failures === 0 ? 0 : 1);
}

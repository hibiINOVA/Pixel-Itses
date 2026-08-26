import { DatabaseSync } from 'node:sqlite';

/**
 * Persistencia SQLite (fase 5): el canvas y los usuarios sobreviven
 * reinicios del backend. La memoria sigue siendo la fuente de velocidad;
 * SQLite es solo respaldo.
 *
 * Identidad: el nickname es la clave única del usuario y pixels.updatedBy
 * apunta directo al nickname (cada pixel sabe quién lo pintó).
 */
class Db {
  constructor(path = process.env.DB_PATH || 'pixel_board.sqlite') {
    this.db = new DatabaseSync(path);
    this.path = path;

    this.db.exec(`
      CREATE TABLE IF NOT EXISTS users (
        nickname        TEXT PRIMARY KEY,
        token           TEXT NOT NULL,
        pixelsRemaining INTEGER NOT NULL DEFAULT 5,
        cooldownEndsAt  INTEGER,
        createdAt       INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS pixels (
        x         INTEGER NOT NULL,
        y         INTEGER NOT NULL,
        color     TEXT NOT NULL DEFAULT '#FFFFFF',
        updatedBy TEXT,
        updatedAt INTEGER,
        PRIMARY KEY (x, y),
        FOREIGN KEY (updatedBy) REFERENCES users(nickname)
      );

      CREATE TABLE IF NOT EXISTS messages (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        nickname  TEXT NOT NULL REFERENCES users(nickname),
        text      TEXT NOT NULL,
        createdAt INTEGER NOT NULL
      );
    `);

    this._savePixelStmt = this.db.prepare(
      'UPDATE pixels SET color = ?, updatedBy = ?, updatedAt = ? WHERE x = ? AND y = ?'
    );
    this._upsertUserStmt = this.db.prepare(`
      INSERT INTO users (nickname, token, pixelsRemaining, cooldownEndsAt, createdAt)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(nickname) DO UPDATE SET
        token = excluded.token,
        pixelsRemaining = excluded.pixelsRemaining,
        cooldownEndsAt = excluded.cooldownEndsAt
    `);
    this._insertMessageStmt = this.db.prepare(
      'INSERT INTO messages (nickname, text, createdAt) VALUES (?, ?, ?)'
    );
  }

  /** Pre-pobla el grid en blanco la primera vez (PK compuesta: una fila por coordenada). */
  seedPixels(size) {
    const count = this.db.prepare('SELECT COUNT(*) AS n FROM pixels').get().n;
    if (count > 0) return;
    const insert = this.db.prepare(
      "INSERT INTO pixels (x, y, color) VALUES (?, ?, '#FFFFFF')"
    );
    this.db.exec('BEGIN');
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        insert.run(x, y);
      }
    }
    this.db.exec('COMMIT');
  }

  loadPixels(size) {
    const rows = this.db.prepare('SELECT x, y, color FROM pixels').all();
    if (rows.length === 0) return null;
    const grid = Array.from({ length: size }, () =>
      new Array(size).fill('#FFFFFF')
    );
    for (const row of rows) {
      if (row.x >= 0 && row.x < size && row.y >= 0 && row.y < size) {
        grid[row.y][row.x] = row.color;
      }
    }
    return grid;
  }

  savePixel(x, y, color, updatedBy) {
    // Paint significa UPDATE: cada coordenada existe una sola vez (sin historial).
    this._savePixelStmt.run(color, updatedBy, Date.now(), x, y);
  }

  loadUsers() {
    return this.db
      .prepare('SELECT * FROM users')
      .all()
      .map((row) => ({
        nickname: row.nickname,
        token: row.token,
        pixelsRemaining: row.pixelsRemaining,
        cooldownEndsAt: row.cooldownEndsAt,
      }));
  }

  saveUser(user) {
    this._upsertUserStmt.run(
      user.nickname,
      user.token,
      user.pixelsRemaining,
      user.cooldownEndsAt,
      Date.now()
    );
  }

  saveMessage(nickname, text, createdAt) {
    this._insertMessageStmt.run(nickname, text, createdAt);
  }

  /** Últimos `limit` mensajes en orden ascendente (para el historial del chat). */
  loadMessages(limit = 50) {
    const rows = this.db
      .prepare('SELECT nickname, text, createdAt FROM messages ORDER BY id DESC LIMIT ?')
      .all(limit);
    return rows.reverse();
  }

  close() {
    this.db.close();
  }
}

export { Db };
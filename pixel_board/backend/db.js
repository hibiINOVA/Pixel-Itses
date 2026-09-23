import { DatabaseSync } from 'node:sqlite';

/**
 * Persistencia SQLite: usuarios, mensajes de chat (por sala),
 * resultados de partidas y estadísticas.
 */
class Db {
  constructor(path = process.env.DB_PATH || 'pixel_board.sqlite') {
    this.db = new DatabaseSync(path);
    this.path = path;

    this.db.exec(`
      CREATE TABLE IF NOT EXISTS users (
        nickname        TEXT PRIMARY KEY,
        token           TEXT NOT NULL,
        password_hash   TEXT,
        wins            INTEGER NOT NULL DEFAULT 0,
        losses          INTEGER NOT NULL DEFAULT 0,
        draws           INTEGER NOT NULL DEFAULT 0,
        createdAt       INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS messages (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        roomId    TEXT NOT NULL,
        nickname  TEXT NOT NULL,
        text      TEXT NOT NULL,
        createdAt INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS games (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        roomId          TEXT NOT NULL,
        player1         TEXT NOT NULL,
        player2         TEXT NOT NULL,
        referenceImage  TEXT NOT NULL,
        player1Canvas   TEXT NOT NULL,
        player2Canvas   TEXT NOT NULL,
        player1Score    INTEGER NOT NULL,
        player2Score    INTEGER NOT NULL,
        winner          TEXT NOT NULL,
        createdAt       INTEGER NOT NULL
      );
    `);

    // Migración: si la tabla users tiene columnas viejas (tier, cooldownEndsAt, etc.)
    // las ignoramos silenciosamente — SQLite permite columnas extra.

    this._upsertUserStmt = this.db.prepare(`
      INSERT INTO users (nickname, token, password_hash, wins, losses, draws, createdAt)
      VALUES (?, ?, ?, 0, 0, 0, ?)
      ON CONFLICT(nickname) DO UPDATE SET
        token = excluded.token,
        password_hash = COALESCE(excluded.password_hash, users.password_hash),
        wins = COALESCE(users.wins, 0),
        losses = COALESCE(users.losses, 0),
        draws = COALESCE(users.draws, 0)
    `);
    this._insertMessageStmt = this.db.prepare(
      'INSERT INTO messages (roomId, nickname, text, createdAt) VALUES (?, ?, ?, ?)'
    );
    this._insertGameStmt = this.db.prepare(`
      INSERT INTO games (roomId, player1, player2, referenceImage, player1Canvas, player2Canvas, player1Score, player2Score, winner, createdAt)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    this._updateStatsStmt = this.db.prepare(`
      UPDATE users SET wins = wins + ?, losses = losses + ?, draws = draws + ? WHERE nickname = ?
    `);
  }

  saveUser(user) {
    this._upsertUserStmt.run(
      user.nickname,
      user.token,
      user.passwordHash || null,
      Date.now()
    );
  }

  loadUsers() {
    return this.db
      .prepare('SELECT * FROM users')
      .all()
      .map((row) => ({
        nickname: row.nickname,
        token: row.token,
        passwordHash: row.password_hash || null,
        wins: row.wins || 0,
        losses: row.losses || 0,
        draws: row.draws || 0,
      }));
  }

  getStats(nickname) {
    const row = this.db
      .prepare('SELECT wins, losses, draws FROM users WHERE nickname = ?')
      .get(nickname);
    if (!row) return { wins: 0, losses: 0, draws: 0 };
    return { wins: row.wins || 0, losses: row.losses || 0, draws: row.draws || 0 };
  }

  updateStats(winner, loser) {
    if (winner === 'tie') {
      this._updateStatsStmt.run(0, 0, 1, loser);
      return;
    }
    this._updateStatsStmt.run(1, 0, 0, winner);
    this._updateStatsStmt.run(0, 1, 0, loser);
  }

  saveMessage(roomId, nickname, text, createdAt) {
    this._insertMessageStmt.run(roomId, nickname, text, createdAt);
  }

  loadMessages(roomId, limit = 50) {
    return this.db
      .prepare('SELECT nickname, text, createdAt FROM messages WHERE roomId = ? ORDER BY id DESC LIMIT ?')
      .all(roomId, limit)
      .reverse();
  }

  saveGame(game) {
    this._insertGameStmt.run(
      game.roomId,
      game.player1,
      game.player2,
      JSON.stringify(game.referenceImage),
      JSON.stringify(game.player1Canvas),
      JSON.stringify(game.player2Canvas),
      game.player1Score,
      game.player2Score,
      game.winner,
      Date.now()
    );
  }

  close() {
    this.db.close();
  }
}

export { Db };

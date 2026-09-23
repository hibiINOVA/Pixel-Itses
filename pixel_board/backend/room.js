/**
 * Estado de una sala de juego entre dos jugadores.
 *
 * Flujo: image_preview → drawing (ambos dibujan al mismo tiempo) → results
 */

import { generateRandomImage } from './images.js';
import { compareCanvases } from './scoring.js';

const PREVIEW_SECONDS = Number.parseInt(process.env.PREVIEW_SECONDS || '15', 10);
const DRAW_SECONDS = Number.parseInt(process.env.DRAW_SECONDS || '60', 10);
const SIZE = 32;

const Phase = {
  WAITING: 'waiting',
  IMAGE_PREVIEW: 'image_preview',
  DRAWING: 'drawing',
  RESULTS: 'results',
};

class Room {
  constructor(id, player1, player2) {
    this.id = id;
    this.phase = Phase.WAITING;
    this.players = [player1, player2];
    this.reference = null;
    this.player1Canvas = this._emptyCanvas();
    this.player2Canvas = this._emptyCanvas();
    this.player1Score = 0;
    this.player2Score = 0;
    this.winner = null;
    this.turnTimer = null;
    this.turnEndsAt = null;
    this.finishedPlayers = new Set();
  }

  _emptyCanvas() {
    return Array.from({ length: SIZE }, () => new Array(SIZE).fill('#FFFFFF'));
  }

  startGame() {
    this.reference = generateRandomImage();
    this.phase = Phase.IMAGE_PREVIEW;
    this.turnEndsAt = Date.now() + PREVIEW_SECONDS * 1000;
    return {
      type: 'game_start',
      roomId: this.id,
      opponent: this.players[1],
      referenceImage: this.reference.grid,
      previewSeconds: PREVIEW_SECONDS,
      drawSeconds: DRAW_SECONDS,
      player1: this.players[0],
      player2: this.players[1],
    };
  }

  advanceFromPreview() {
    this.phase = Phase.DRAWING;
    this.turnEndsAt = Date.now() + DRAW_SECONDS * 1000;
    return {
      type: 'draw_start',
      drawSeconds: DRAW_SECONDS,
    };
  }

  finishGame() {
    this.phase = Phase.RESULTS;
    if (this.turnTimer) {
      clearTimeout(this.turnTimer);
      this.turnTimer = null;
    }

    const result1 = compareCanvases(this.reference.grid, this.player1Canvas);
    const result2 = compareCanvases(this.reference.grid, this.player2Canvas);

    this.player1Score = result1.accuracy;
    this.player2Score = result2.accuracy;

    if (this.player1Score > this.player2Score) {
      this.winner = this.players[0];
    } else if (this.player2Score > this.player1Score) {
      this.winner = this.players[1];
    } else {
      this.winner = 'tie';
    }

    return {
      type: 'game_results',
      roomId: this.id,
      reference: this.reference.grid,
      player1Canvas: this.player1Canvas,
      player2Canvas: this.player2Canvas,
      player1: this.players[0],
      player2: this.players[1],
      player1Score: this.player1Score,
      player2Score: this.player2Score,
      winner: this.winner,
    };
  }

  finishPlayer(nickname) {
    if (this.phase !== Phase.DRAWING) return 'wrong_phase';
    if (!this.players.includes(nickname)) return 'not_in_room';
    this.finishedPlayers.add(nickname);
    if (this.finishedPlayers.size >= this.players.length) return 'both';
    return 'ok';
  }

  paintPixel(nickname, x, y, color) {
    if (this.phase !== Phase.DRAWING) return false;
    if (this.finishedPlayers.has(nickname)) return false;

    if (nickname === this.players[0]) {
      if (x >= 0 && x < SIZE && y >= 0 && y < SIZE) {
        this.player1Canvas[y][x] = color;
        return true;
      }
    } else if (nickname === this.players[1]) {
      if (x >= 0 && x < SIZE && y >= 0 && y < SIZE) {
        this.player2Canvas[y][x] = color;
        return true;
      }
    }
    return false;
  }

  isActivePlayer(nickname) {
    return this.phase === Phase.DRAWING && this.players.includes(nickname) && !this.finishedPlayers.has(nickname);
  }

  includes(nickname) {
    return this.players.includes(nickname);
  }

  removePlayer(nickname) {
    const idx = this.players.indexOf(nickname);
    if (idx === -1) return null;
    this.players.splice(idx, 1);
    if (this.players.length === 0) return 'empty';
    // El otro jugador gana por forfeit
    return 'forfeit';
  }

  toJSON() {
    return {
      id: this.id,
      phase: this.phase,
      players: this.players,
      player1Score: this.player1Score,
      player2Score: this.player2Score,
      winner: this.winner,
      turnEndsAt: this.turnEndsAt,
    };
  }
}

export { Room, Phase, PREVIEW_SECONDS, DRAW_SECONDS };

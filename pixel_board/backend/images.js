/**
 * Generación procedural de imágenes pixel-art de 32x32 para el juego de
 * memorización. Cada template es un array 2D de índices de color;
 * generateRandomImage() elige uno al azar, aplica variación de color y
 * devuelve la grilla como string[][] de hex colors.
 */

const SIZE = 32;
const BG = '#FFFFFF';

// ── Paleta base para templates (índice 0 = fondo) ────────────────────
const TEMPLATES_PALETTE = [
  BG,
  '#000000', // 1: outline / negro
  '#FF6B35', // 2: naranja
  '#D62828', // 3: rojo
  '#FFD700', // 4: amarillo
  '#4A4A4A', // 5: gris oscuro
  '#8B4513', // 6: marrón
  '#228B22', // 7: verde
  '#87CEEB', // 8: celeste
  '#FF8C42', // 9: naranja claro
  '#FFB3BA', // 10: rosa pastel
  '#E8BAFF', // 11: lila
  '#FF4136', // 12: rojo brillante
];

// ── Helpers ──────────────────────────────────────────────────────────

function empty() {
  return Array.from({ length: SIZE }, () => new Array(SIZE).fill(0));
}

function set(grid, x, y, v) {
  if (y >= 0 && y < SIZE && x >= 0 && x < SIZE) grid[y][x] = v;
}

function rect(grid, x1, y1, x2, y2, v) {
  for (let y = y1; y <= y2; y++) {
    for (let x = x1; x <= x2; x++) {
      set(grid, x, y, v);
    }
  }
}

function hline(grid, x1, x2, y, v) {
  for (let x = x1; x <= x2; x++) set(grid, x, y, v);
}

function vline(grid, x, y1, y2, v) {
  for (let y = y1; y <= y2; y++) set(grid, x, y, v);
}

// ── Templates de animales y emojis ───────────────────────────────────

function cat() {
  const g = empty();
  // orejas
  set(g, 8, 4, 2); set(g, 9, 4, 2); set(g, 7, 5, 2); set(g, 10, 5, 2);
  set(g, 22, 4, 2); set(g, 23, 4, 2); set(g, 21, 5, 2); set(g, 24, 5, 2);
  // cabeza
  rect(g, 9, 6, 22, 14, 9);
  rect(g, 10, 7, 21, 13, 2);
  // ojos
  set(g, 13, 9, 4); set(g, 14, 9, 4);
  set(g, 17, 9, 4); set(g, 18, 9, 4);
  // nariz
  set(g, 15, 11, 3); set(g, 16, 11, 3);
  // bigotes
  hline(g, 11, 14, 12, 1); hline(g, 17, 20, 12, 1);
  // cuerpo
  rect(g, 11, 15, 20, 24, 2);
  rect(g, 12, 16, 19, 23, 9);
  // patas
  rect(g, 11, 25, 13, 27, 2);
  rect(g, 18, 25, 20, 27, 2);
  // cola
  vline(g, 21, 16, 22, 2); set(g, 22, 22, 2); set(g, 23, 23, 2);
  return g;
}

function dog() {
  const g = empty();
  // orejas caídas
  rect(g, 6, 6, 9, 14, 6);
  rect(g, 23, 6, 26, 14, 6);
  // cabeza
  rect(g, 10, 6, 22, 16, 6);
  rect(g, 11, 7, 21, 15, 9);
  // ojos
  set(g, 13, 9, 1); set(g, 18, 9, 1);
  // nariz
  rect(g, 14, 12, 17, 13, 1);
  // lengua
  set(g, 15, 14, 3); set(g, 16, 14, 3);
  // cuerpo
  rect(g, 10, 17, 22, 25, 6);
  rect(g, 11, 18, 21, 24, 9);
  // patas
  rect(g, 10, 26, 12, 28, 6);
  rect(g, 20, 26, 22, 28, 6);
  // cola
  set(g, 23, 18, 6); set(g, 24, 17, 6); set(g, 25, 16, 6);
  return g;
}

function bird() {
  const g = empty();
  // cabeza
  rect(g, 13, 4, 19, 9, 3);
  rect(g, 14, 5, 18, 8, 9);
  // ojo
  set(g, 16, 6, 1);
  // pico
  set(g, 20, 7, 4); set(g, 21, 7, 4); set(g, 20, 8, 4);
  // cuerpo
  rect(g, 10, 10, 22, 20, 3);
  rect(g, 11, 11, 21, 19, 9);
  // ala izq
  rect(g, 5, 10, 9, 17, 3);
  rect(g, 6, 11, 8, 16, 12);
  // ala der
  rect(g, 23, 10, 27, 17, 3);
  rect(g, 24, 11, 26, 16, 12);
  // patas
  vline(g, 13, 21, 26, 4); vline(g, 19, 21, 26, 4);
  set(g, 12, 26, 4); set(g, 14, 26, 4);
  set(g, 18, 26, 4); set(g, 20, 26, 4);
  return g;
}

function fish() {
  const g = empty();
  // cuerpo
  rect(g, 8, 10, 24, 22, 8);
  rect(g, 9, 11, 23, 21, 2);
  // cola
  set(g, 6, 10, 2); set(g, 5, 9, 2); set(g, 4, 8, 2);
  set(g, 6, 22, 2); set(g, 5, 23, 2); set(g, 4, 24, 2);
  set(g, 7, 11, 2); set(g, 7, 21, 2);
  // aleta sup
  set(g, 15, 8, 2); set(g, 16, 7, 2); set(g, 14, 9, 2);
  // ojo
  set(g, 20, 14, 1); set(g, 21, 14, 1);
  // boca
  set(g, 24, 16, 3);
  // rayas
  hline(g, 12, 12, 13, 8); hline(g, 12, 12, 19, 8);
  hline(g, 16, 16, 13, 8); hline(g, 16, 16, 19, 8);
  return g;
}

function frog() {
  const g = empty();
  // ojos (sobre la cabeza)
  set(g, 9, 5, 7); set(g, 10, 5, 7); set(g, 11, 5, 7);
  set(g, 20, 5, 7); set(g, 21, 5, 7); set(g, 22, 5, 7);
  set(g, 10, 4, 7); set(g, 21, 4, 7);
  // pupilas
  set(g, 10, 5, 1); set(g, 21, 5, 1);
  // cabeza
  rect(g, 8, 7, 23, 14, 7);
  rect(g, 9, 8, 22, 13, 7);
  // boca
  hline(g, 11, 20, 13, 1);
  // cuerpo
  rect(g, 9, 15, 22, 22, 7);
  rect(g, 10, 16, 21, 21, 7);
  // patas delanteras
  rect(g, 6, 20, 8, 22, 7);
  rect(g, 23, 20, 25, 22, 7);
  // patas traseras
  rect(g, 7, 23, 10, 26, 7);
  rect(g, 21, 23, 24, 26, 7);
  return g;
}

function heart() {
  const g = empty();
  const pts = [
    [10,6],[11,5],[12,5],[13,5],[14,6],[15,7],[16,8],[17,9],[18,10],
    [19,11],[20,12],[21,13],
    [21,14],[20,15],[19,16],[18,17],[17,18],[16,19],[15,20],[14,21],
    [13,22],[12,23],[11,24],[10,25],[9,24],[8,23],[7,22],[6,21],
    [5,20],[5,19],[5,18],[5,17],[5,16],[6,15],[7,14],[8,13],
    [9,12],[10,11],[11,10],[12,9],[13,8],[14,7],
    [22,6],[21,5],[20,5],[19,5],[18,6],
  ];
  for (const [x, y] of pts) set(g, x, y, 3);
  // relleno
  for (let y = 6; y <= 25; y++) {
    for (let x = 4; x <= 23; x++) {
      if (g[y][x] === 0) {
        // fill interior: check if surrounded
        let inside = true;
        for (let dx = -1; dx <= 1 && inside; dx++) {
          for (let dy = -1; dy <= 1 && inside; dy++) {
            if (y+dy >= 0 && y+dy < SIZE && x+dx >= 0 && x+dx < SIZE) {
              // ok
            } else {
              inside = false;
            }
          }
        }
        if (inside) set(g, x, y, 3);
      }
    }
  }
  // relleno simple por fill horizontal
  for (let y = 6; y <= 25; y++) {
    let first = -1, last = -1;
    for (let x = 0; x < SIZE; x++) {
      if (g[y][x] === 3) {
        if (first === -1) first = x;
        last = x;
      }
    }
    if (first !== -1 && last !== -1) {
      for (let x = first; x <= last; x++) set(g, x, y, 3);
    }
  }
  return g;
}

function star() {
  const g = empty();
  // punta superior
  set(g, 15, 3, 4); set(g, 16, 3, 4);
  set(g, 14, 4, 4); set(g, 15, 4, 4); set(g, 16, 4, 4); set(g, 17, 4, 4);
  set(g, 13, 5, 4); set(g, 14, 5, 4); set(g, 15, 5, 4);
  set(g, 16, 5, 4); set(g, 17, 5, 4); set(g, 18, 5, 4);
  // brazos
  for (let i = 0; i < 6; i++) {
    set(g, 12 - i, 6 + i, 4);
    set(g, 19 + i, 6 + i, 4);
    set(g, 13 - i, 7 + i, 4);
    set(g, 18 + i, 7 + i, 4);
  }
  // centro
  rect(g, 11, 8, 20, 18, 4);
  // piernas
  set(g, 11, 19, 4); set(g, 12, 20, 4); set(g, 13, 21, 4);
  set(g, 20, 19, 4); set(g, 19, 20, 4); set(g, 18, 21, 4);
  // borde negro
  const dirs = [[-1,0],[1,0],[0,-1],[0,1]];
  const copy = g.map(r => [...r]);
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      if (copy[y][x] === 4) {
        for (const [dx, dy] of dirs) {
          const nx = x + dx, ny = y + dy;
          if (ny >= 0 && ny < SIZE && nx >= 0 && nx < SIZE && copy[ny][nx] === 0) {
            set(g, nx, ny, 1);
          }
        }
      }
    }
  }
  return g;
}

function house() {
  const g = empty();
  // techo
  for (let i = 0; i < 10; i++) {
    hline(g, 6 + i, 25 - i, 10 - i, 3);
  }
  // paredes
  rect(g, 7, 11, 24, 26, 9);
  rect(g, 8, 12, 23, 25, 4);
  // puerta
  rect(g, 14, 20, 17, 26, 6);
  set(g, 16, 23, 4);
  // ventana izq
  rect(g, 9, 14, 12, 17, 8);
  hline(g, 9, 12, 15, 1); vline(g, 10, 14, 17, 1);
  // ventana der
  rect(g, 19, 14, 22, 17, 8);
  hline(g, 19, 22, 15, 1); vline(g, 20, 14, 17, 1);
  // chimenea
  rect(g, 20, 3, 22, 9, 5);
  return g;
}

function tree() {
  const g = empty();
  // copa
  for (let i = 0; i < 5; i++) {
    rect(g, 10 - i, 4 + i * 2, 21 + i, 7 + i * 2, 7);
  }
  rect(g, 8, 14, 23, 18, 7);
  // tronco
  rect(g, 14, 19, 17, 27, 6);
  // manzanas / frutas
  set(g, 11, 8, 3); set(g, 20, 10, 3); set(g, 14, 14, 3);
  return g;
}

function flower() {
  const g = empty();
  // tallo
  vline(g, 15, 16, 27, 7);
  // hojas
  set(g, 13, 20, 7); set(g, 12, 19, 7);
  set(g, 17, 22, 7); set(g, 18, 21, 7);
  // pétalos
  const petalPositions = [
    [15, 5], [13, 7], [17, 7], [11, 9], [19, 9],
    [12, 11], [18, 11], [14, 12], [16, 12],
  ];
  for (const [x, y] of petalPositions) {
    rect(g, x - 1, y - 1, x + 1, y + 1, 3);
  }
  // centro
  rect(g, 14, 9, 17, 12, 4);
  return g;
}

function smiley() {
  const g = empty();
  // cara
  rect(g, 8, 4, 23, 27, 4);
  rect(g, 9, 5, 22, 26, 4);
  // ojos
  set(g, 12, 10, 1); set(g, 13, 10, 1);
  set(g, 18, 10, 1); set(g, 19, 10, 1);
  // sonrisa
  hline(g, 11, 20, 18, 1);
  set(g, 10, 17, 1); set(g, 21, 17, 1);
  set(g, 10, 19, 1); set(g, 21, 19, 1);
  return g;
}

function skull() {
  const g = empty();
  // cráneo
  rect(g, 9, 4, 22, 18, 0);
  rect(g, 8, 6, 23, 16, 0);
  rect(g, 10, 5, 21, 17, 0);
  // ojos
  rect(g, 11, 9, 14, 12, 1);
  rect(g, 17, 9, 20, 12, 1);
  // nariz
  set(g, 15, 14, 1); set(g, 16, 14, 1);
  // mandíbula
  rect(g, 11, 19, 20, 24, 0);
  rect(g, 12, 20, 19, 23, 0);
  // dientes
  hline(g, 12, 19, 19, 1);
  vline(g, 14, 19, 22, 1); vline(g, 16, 19, 22, 1); vline(g, 18, 19, 22, 1);
  return g;
}

function rocket() {
  const g = empty();
  // punta
  set(g, 15, 2, 5); set(g, 16, 2, 5);
  set(g, 14, 3, 5); set(g, 15, 3, 5); set(g, 16, 3, 5); set(g, 17, 3, 5);
  // cuerpo
  rect(g, 13, 4, 18, 22, 5);
  rect(g, 14, 5, 17, 21, 8);
  // ventanilla
  rect(g, 14, 10, 17, 13, 1);
  rect(g, 15, 11, 16, 12, 8);
  // aletas
  set(g, 12, 18, 3); set(g, 11, 19, 3); set(g, 10, 20, 3);
  set(g, 19, 18, 3); set(g, 20, 19, 3); set(g, 21, 20, 3);
  // llama
  rect(g, 13, 23, 18, 27, 2);
  rect(g, 14, 24, 17, 28, 4);
  set(g, 15, 25, 3); set(g, 16, 25, 3);
  return g;
}

function mushroom() {
  const g = empty();
  // sombrero
  rect(g, 7, 6, 24, 15, 3);
  rect(g, 8, 5, 23, 14, 3);
  rect(g, 10, 4, 21, 13, 3);
  // puntos blancos
  set(g, 12, 7, 4); set(g, 17, 6, 4); set(g, 20, 9, 4);
  set(g, 10, 11, 4); set(g, 15, 10, 4);
  // borde inferior sombrero
  hline(g, 7, 24, 15, 1);
  // tallo
  rect(g, 13, 16, 18, 27, 0);
  rect(g, 12, 17, 19, 26, 0);
  // ojos en el tallo
  set(g, 14, 20, 1); set(g, 17, 20, 1);
  return g;
}

function ghost() {
  const g = empty();
  // cabeza
  rect(g, 10, 3, 21, 10, 0);
  rect(g, 9, 5, 22, 8, 0);
  // cuerpo
  rect(g, 9, 11, 22, 22, 0);
  // ondulación inferior
  set(g, 9, 23, 0); set(g, 11, 24, 0); set(g, 13, 23, 0);
  set(g, 15, 24, 0); set(g, 17, 23, 0); set(g, 19, 24, 0); set(g, 21, 23, 0);
  set(g, 10, 24, 0); set(g, 12, 25, 0); set(g, 14, 24, 0);
  set(g, 16, 25, 0); set(g, 18, 24, 0); set(g, 20, 25, 0); set(g, 22, 24, 0);
  // ojos
  set(g, 12, 9, 1); set(g, 13, 9, 1); set(g, 12, 10, 1); set(g, 13, 10, 1);
  set(g, 18, 9, 1); set(g, 19, 9, 1); set(g, 18, 10, 1); set(g, 19, 10, 1);
  // boca
  set(g, 15, 13, 1); set(g, 16, 13, 1);
  return g;
}

// ── Registro de templates ────────────────────────────────────────────

const TEMPLATES = [
  { name: 'cat', generate: cat },
  { name: 'dog', generate: dog },
  { name: 'bird', generate: bird },
  { name: 'fish', generate: fish },
  { name: 'frog', generate: frog },
  { name: 'heart', generate: heart },
  { name: 'star', generate: star },
  { name: 'house', generate: house },
  { name: 'tree', generate: tree },
  { name: 'flower', generate: flower },
  { name: 'smiley', generate: smiley },
  { name: 'skull', generate: skull },
  { name: 'rocket', generate: rocket },
  { name: 'mushroom', generate: mushroom },
  { name: 'ghost', generate: ghost },
];

// ── Variación de color ───────────────────────────────────────────────

function varyColor(hex, amount) {
  const r = Math.max(0, Math.min(255, parseInt(hex.slice(1, 3), 16) + (Math.random() * amount * 2 - amount)));
  const g = Math.max(0, Math.min(255, parseInt(hex.slice(3, 5), 16) + (Math.random() * amount * 2 - amount)));
  const b = Math.max(0, Math.min(255, parseInt(hex.slice(5, 7), 16) + (Math.random() * amount * 2 - amount)));
  return `#${Math.round(r).toString(16).padStart(2, '0')}${Math.round(g).toString(16).padStart(2, '0')}${Math.round(b).toString(16).padStart(2, '0')}`.toUpperCase();
}

// ── API pública ──────────────────────────────────────────────────────

let lastGeneratedIndex = -1;

function generateRandomImage() {
  let index;
  do {
    index = Math.floor(Math.random() * TEMPLATES.length);
  } while (index === lastGeneratedIndex && TEMPLATES.length > 1);
  lastGeneratedIndex = index;
  
  const template = TEMPLATES[index];
  const grid = template.generate();

  // Mapear índices a hex colors con variación
  const colorMap = new Map();
  const result = [];
  for (let y = 0; y < SIZE; y++) {
    const row = [];
    for (let x = 0; x < SIZE; x++) {
      const idx = grid[y][x];
      if (idx === 0) {
        row.push(BG);
        continue;
      }
      if (!colorMap.has(idx)) {
        const base = TEMPLATES_PALETTE[idx] || '#888888';
        colorMap.set(idx, varyColor(base, 15));
      }
      row.push(colorMap.get(idx));
    }
    result.push(row);
  }

  return { name: template.name, grid: result };
}

function getValidColors() {
  return TEMPLATES_PALETTE.slice(1); // sin el fondo blanco
}

export { generateRandomImage, getValidColors, SIZE };

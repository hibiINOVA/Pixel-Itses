const CANVAS_SIZE = 32;

const PALETTE = [
  '#D3D3D3', // gris claro
  '#4A4A4A', // gris oscuro
  '#FFD700', // amarillo
  '#FF8C42', // naranja claro
  '#FF6B35', // naranja oscuro
  '#FF4136', // rojo
  '#D62828', // rojo oscuro
  '#800000', // granate
];

function createCanvas(size = CANVAS_SIZE) {
  const grid = [];
  for (let y = 0; y < size; y++) {
    grid.push(new Array(size).fill('#FFFFFF'));
  }
  return grid;
}

function inBounds(grid, x, y) {
  return y >= 0 && y < grid.length && x >= 0 && x < grid[0].length;
}

function isValidColor(color) {
  return typeof color === 'string' && PALETTE.includes(color);
}

class Canvas {
  constructor(size = CANVAS_SIZE, initialGrid = null) {
    this.size = size;
    // Grid inicial desde SQLite (fase 5) o blanco por defecto.
    this.grid =
      initialGrid && initialGrid.length === size
        ? initialGrid
        : createCanvas(size);
  }

  getSnapshot() {
    return this.grid;
  }

  isValid(x, y, color) {
    return inBounds(this.grid, x, y) && isValidColor(color);
  }

  paintPixel(x, y, color) {
    if (!this.isValid(x, y, color)) return false;
    this.grid[y][x] = color;
    return true;
  }
}

export { Canvas, CANVAS_SIZE, PALETTE };
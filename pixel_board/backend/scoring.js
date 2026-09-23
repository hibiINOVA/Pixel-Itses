/**
 * Comparación de similitud entre dos grillas de pixeles.
 * Cada grilla es string[][] de hex colors (#RRGGBB).
 * Devuelve un porcentaje de precisión (0-100).
 */

const COLOR_THRESHOLD = 80;

function hexToRgb(hex) {
  const n = parseInt(hex.replace('#', ''), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function colorDistance(hex1, hex2) {
  const [r1, g1, b1] = hexToRgb(hex1);
  const [r2, g2, b2] = hexToRgb(hex2);
  return Math.sqrt((r1 - r2) ** 2 + (g1 - g2) ** 2 + (b1 - b2) ** 2);
}

function compareCanvases(reference, drawing) {
  const size = reference.length;
  let intersection = 0;
  let union = 0;

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const refColor = reference[y][x].toUpperCase();
      const drawColor = drawing[y][x].toUpperCase();
      
      const dist = colorDistance(refColor, drawColor);
      const isMatch = dist <= COLOR_THRESHOLD;
      
      const isRefBg = refColor === '#FFFFFF';
      const isDrawBg = drawColor === '#FFFFFF';
      
      if (!isRefBg || !isDrawBg) {
        union++;
        if (isMatch) {
          intersection++;
        }
      }
    }
  }

  const accuracy = union === 0 ? 100 : Math.round((intersection / union) * 100);
  return { accuracy, matchingPixels: intersection, totalPixels: union };
}

export { compareCanvases };

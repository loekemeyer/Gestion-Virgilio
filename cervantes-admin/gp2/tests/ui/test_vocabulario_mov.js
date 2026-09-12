/* Guardia del VOCABULARIO de movimiento (2026-09-11).
 *
 * Existe porque las pantallas suman columnas de stock filtrando por `tipo_mov`, y esos tokens
 * estaban escritos a mano en tres lugares de JS. Se desfasaron sin que nadie se enterara:
 * gp2-stock-sector.js filtraba por "produccion", "envio_prov", "envio_tall", "recepcion_prov" y
 * "recepcion_tall" -- cinco palabras que la base NUNCA escribe -- asi que esas columnas daban
 * cero para siempre y el operario veia stock que entraba y salia "de la nada". Y a los tres les
 * faltaba "traslado".
 *
 * La fuente de verdad es GP2.tipo_movimiento (db/vocabulario_GP2.sql). Este test falla si una
 * pantalla nombra una palabra que no esta en el catalogo. Si falla porque el catalogo cambio,
 * se actualiza db/vocabulario_GP2.sql (y la base), no el test. Sin navegador: lee archivos.
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
let fallas = 0;
const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) { fallas++; process.exitCode = 1; } };
const leer = (p) => fs.readFileSync(p, 'utf8');

// ── el catalogo, segun db/vocabulario_GP2.sql ───────────────────────────
const vocab = new Set();
for (const m of leer(path.join(ROOT, 'db', 'vocabulario_GP2.sql'))
       .matchAll(/^\s*\('([a-z_]+)',\s*'/gm)) vocab.add(m[1]);
ok(vocab.size >= 15, 'db/vocabulario_GP2.sql se pudo leer (' + vocab.size + ' tipos)');
ok(vocab.has('traslado') && vocab.has('compra'), 'el catalogo trae los tipos conocidos');

// ── 1) gp2-stock-sector.js: los `tipos:[...]` de cada columna ───────────
const secSrc = leer(path.join(ROOT, 'gp2-stock-sector.js'));
const tokensSector = new Set();
for (const m of secSrc.matchAll(/tipos:\s*\[([^\]]*)\]/g))
  for (const t of m[1].matchAll(/"([a-z_]+)"|'([a-z_]+)'/g)) tokensSector.add(t[1] || t[2]);
const malosSector = [...tokensSector].filter((t) => !vocab.has(t));
ok(tokensSector.size > 5 && malosSector.length === 0,
   'gp2-stock-sector.js: ' + tokensSector.size + ' tipos, todos del catalogo' +
   (malosSector.length ? ' — INVENTADOS: ' + malosSector.join(', ') : ''));

// ── 2) los mapas TIPOS de pantalla (etiquetas) ──────────────────────────
const mapas = [
  ['gp2-composicion.js', /var TIPOS = \{([\s\S]*?)\n  \};/],
  ['Stocks General/StockGeneral_GP2.html', /var TIPOS=\{([\s\S]*?)\n\};/],
];
for (const [rel, re] of mapas) {
  const m = re.exec(leer(path.join(ROOT, rel)));
  if (!m) { ok(false, rel + ': no se encontro el mapa TIPOS'); continue; }
  // las claves van de a varias por linea: `compra: "Compra", consumo: "..."` / `compra:{lbl:...}`
  const claves = [...m[1].matchAll(/(?:^\s*|[{,]\s*)([a-z_]+)\s*:\s*["'{]/gm)].map((x) => x[1])
    .filter((k) => k !== 'lbl' && k !== 'cls');
  const malas = claves.filter((k) => !vocab.has(k));
  const faltan = [...vocab].filter((k) => !claves.includes(k));
  ok(malas.length === 0, rel + ': ' + claves.length + ' etiquetas, ninguna inventada' +
     (malas.length ? ' — INVENTADAS: ' + malas.join(', ') : ''));
  ok(faltan.length === 0, rel + ': ninguna clave del catalogo sin etiqueta' +
     (faltan.length ? ' — FALTAN: ' + faltan.join(', ') : ''));
}

// ── 3) Control Envios: los tipos de cada vista ──────────────────────────
const ctrl = leer(path.join(ROOT, 'Control Envios y Entregas', 'ControlEnvios_GP2.html'));
const vistas = /var VISTAS = \{([\s\S]*?)\n\};/.exec(ctrl);
if (!vistas) ok(false, 'ControlEnvios_GP2.html: no se encontro el mapa VISTAS');
else {
  const tks = new Set();
  for (const m of vistas[1].matchAll(/\[([^\]]*)\]/g))
    for (const t of m[1].matchAll(/'([a-z_]+)'/g)) tks.add(t[1]);
  const malos = [...tks].filter((t) => !vocab.has(t));
  ok(tks.size > 3 && malos.length === 0,
     'ControlEnvios_GP2.html: ' + tks.size + ' tipos, todos del catalogo' +
     (malos.length ? ' — INVENTADOS: ' + malos.join(', ') : ''));
}

console.log(fallas ? '\nTOTAL: ' + fallas + ' fallas' : '\nTODO OK');

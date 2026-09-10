/* Guardia del CONTRATO pantalla <-> base (2026-09-05).
 *
 * Existe porque en la auditoria de arquitectura se borraron y renombraron funciones y
 * tablas (control_cajas_bundle + control_kg_bundle -> control_recepcion_bundle,
 * cargar_compra_altrak -> cargar_compra_mp, movimientos_componente, v_valor_stock...) y la
 * unica red era grepear a mano. Este test lee el respaldo del schema en db/ y chequea que:
 *   1. toda RPC que nombra una pantalla GP2 (rpc('x')) exista en db/funciones_GP2.sql;
 *   2. toda tabla/vista que lee una pantalla (from('x')) exista en db/tablas_GP2.sql o
 *      db/vistas_GP2.sql;
 *   3. cada clave p_* que viaja en el objeto literal de una llamada rpc('x', {...}) sea un
 *      parametro real de esa funcion (una clave con un typo llega a PostgREST como
 *      "function not found" recien en produccion);
 *   4. esa llamada mande todos los parametros SIN DEFAULT de la funcion (el mismo error, al
 *      reves: falta uno obligatorio y PostgREST no encuentra la firma);
 *   5. cada columna que una pantalla pide con from(tabla).select('a,b,...') exista en la tabla
 *      (una columna borrada o renombrada en la base es un 400 silencioso en la pantalla).
 * Si falla porque db/ esta viejo, la respuesta es regenerar db/ (db/regenerar.sql), no
 * tocar el test. Sin navegador: lee archivos.
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
let fallas = 0;
const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) { fallas++; process.exitCode = 1; } };
const leer = (p) => fs.readFileSync(p, 'utf8');

// ── el schema, segun db/ ────────────────────────────────────────────────
const funciones = {};
// la firma termina en el ")" que precede a RETURNS (los DEFAULT now() traen parentesis adentro)
for (const m of leer(path.join(ROOT, 'db', 'funciones_GP2.sql'))
       .matchAll(/CREATE OR REPLACE FUNCTION "GP2"\.(\w+)\(([\s\S]*?)\)\s*\n\s*RETURNS/g)) {
  const params = new Set(), requeridos = new Set();
  // los DEFAULT pueden traer comas adentro ('{}'::jsonb no, pero ARRAY[...] o now() si parentesis):
  // se parte por coma solo a profundidad 0 de parentesis/corchetes
  const partes = []; let depth = 0, cur = '';
  for (const ch of m[2]) {
    if (ch === '(' || ch === '[') depth++;
    if (ch === ')' || ch === ']') depth--;
    if (ch === ',' && depth === 0) { partes.push(cur); cur = ''; } else cur += ch;
  }
  partes.push(cur);
  for (const parte of partes) {
    const nombre = parte.trim().split(/\s+/)[0];
    if (!nombre) continue;
    const n = nombre.replace(/^"|"$/g, '');
    params.add(n);
    if (!/\sDEFAULT\s/i.test(parte)) requeridos.add(n);
  }
  funciones[m[1]] = { params, requeridos };
}
const relaciones = new Set();
const columnas = {};   // tabla -> Set de columnas (solo tablas: las vistas no declaran la lista)
for (const m of leer(path.join(ROOT, 'db', 'tablas_GP2.sql')).matchAll(/create table "GP2"\.(\w+) \(\n([\s\S]*?)\n\);/g)) {
  relaciones.add(m[1]);
  columnas[m[1]] = new Set(m[2].split('\n').map(l => l.trim()).filter(l => l && !l.startsWith('constraint')).map(l => l.split(/\s+/)[0]));
}
for (const m of leer(path.join(ROOT, 'db', 'vistas_GP2.sql')).matchAll(/create or replace view "GP2"\.(\w+) as/g)) relaciones.add(m[1]);
ok(Object.keys(funciones).length > 100 && relaciones.size > 50,
   'db/ se pudo leer (' + Object.keys(funciones).length + ' funciones, ' + relaciones.size + ' tablas+vistas)');

// ── las pantallas GP2 y los JS que cargan ───────────────────────────────
const EXCLUIR = /(^|[\\/])(_backup|node_modules|\.git|tests)([\\/]|$)/;
// pantallas GP2 sin sufijo: las de entrada y las que test_smoke_gp2 tambien abre, mas los dos
// controles de recepcion (control-cajas / control-remaches), que son GP2 aunque no lleven _GP2
const SIN_SUFIJO = new Set(['GP2_MODULOS.html', 'login.html', 'envios-only.html', 'Programa.html',
  'Validacion_Stock.html', 'OrdenProduccion.html', 'control-cajas.html', 'control-remaches.html']);
const archivos = [];
(function walk(dir) {
  for (const f of fs.readdirSync(dir)) {
    const p = path.join(dir, f);
    if (EXCLUIR.test(p)) continue;
    if (fs.statSync(p).isDirectory()) walk(p);
    else if (f.endsWith('_GP2.html') || SIN_SUFIJO.has(f)) archivos.push(p);
  }
})(ROOT);
for (const p of archivos.slice()) {
  for (const m of leer(p).matchAll(/src\s*=\s*["']([^"'>]+\.js)(?:\?[^"'>]*)?["']/g)) {
    const abs = path.resolve(path.dirname(p), m[1]);
    if (fs.existsSync(abs) && !archivos.includes(abs)) archivos.push(abs);
  }
}
const rel = (p) => path.relative(ROOT, p).replace(/\\/g, '/');

// ── 1) rpc('x') existe ───────────────────────────────────────────────────
const rpcInexistentes = [];
const fromInexistentes = [];
const clavesMalas = [];
const faltanRequeridos = [];
const columnasMalas = [];
let nRpc = 0, nFrom = 0, nLlamadasConObjeto = 0;

// objeto literal que sigue a rpc('x', { ... }): claves de PRIMER nivel
function clavesTopLevel(txt, desde) {
  // una clave es un identificador seguido de ":" cuyo ultimo caracter significativo anterior
  // (a profundidad 1) es "{" o "," — asi un ternario "a ? b : null" no cuenta como clave
  let i = desde, depth = 0, claves = [], inStr = null, prev = '';
  for (; i < txt.length; i++) {
    const ch = txt[i];
    if (inStr) { if (ch === inStr && txt[i - 1] !== '\\') inStr = null; continue; }
    if (ch === '"' || ch === "'" || ch === '`') { inStr = ch; prev = ch; continue; }
    if (ch === '{' || ch === '[' || ch === '(') { depth++; prev = ch; continue; }
    if (ch === '}' || ch === ']' || ch === ')') { depth--; prev = ch; if (depth === 0) break; continue; }
    if (depth === 1) {
      const m = /^([A-Za-z_$][\w$]*)\s*:/.exec(txt.slice(i, i + 60));
      if (m && (prev === '{' || prev === ',')) { claves.push(m[1]); i += m[0].length - 1; prev = ':'; continue; }
    }
    if (!/\s/.test(ch)) prev = ch;
  }
  return claves;
}

for (const p of archivos) {
  const txt = leer(p);
  for (const m of txt.matchAll(/\.rpc\(\s*["'](\w+)["']\s*(,\s*)?/g)) {
    nRpc++;
    const fn = m[1];
    if (!funciones[fn]) { rpcInexistentes.push(rel(p) + ':' + txt.slice(0, m.index).split('\n').length + '  ' + fn); continue; }
    const after = m.index + m[0].length;
    if (m[2] && txt[after] === '{') {
      nLlamadasConObjeto++;
      const claves = clavesTopLevel(txt, after);
      const linea = txt.slice(0, m.index).split('\n').length;
      for (const k of claves) {
        if (!funciones[fn].params.has(k)) clavesMalas.push(rel(p) + ':' + linea + '  ' + fn + '(' + k + ')');
      }
      for (const k of funciones[fn].requeridos) {
        if (!claves.includes(k)) faltanRequeridos.push(rel(p) + ':' + linea + '  ' + fn + ' sin ' + k);
      }
    }
  }
  for (const m of txt.matchAll(/\.from\(\s*["'](\w+)["']\s*\)(?:\s*\.select\(\s*["']([^"']*)["']\s*\))?/g)) {
    nFrom++;
    const linea = txt.slice(0, m.index).split('\n').length;
    if (!relaciones.has(m[1])) { fromInexistentes.push(rel(p) + ':' + linea + '  ' + m[1]); continue; }
    // columnas del select literal, solo para TABLAS (las vistas no declaran columnas en db/):
    // "a, b, alias:col, rel:fk_col(sub, cols)" -> a, b, col, fk_col
    if (m[2] && columnas[m[1]] && m[2].trim() !== '*') {
      let depth = 0, item = '', items = [];
      for (const ch of m[2]) {
        if (ch === '(') depth++;
        if (ch === ')') depth--;
        if (ch === ',' && depth === 0) { items.push(item); item = ''; } else item += ch;
      }
      items.push(item);
      for (let it of items) {
        it = it.trim(); if (!it) continue;
        const sinEmbebido = it.split('(')[0];
        const col = sinEmbebido.includes(':') ? sinEmbebido.split(':').pop().trim() : sinEmbebido.trim();
        if (col && col !== '*' && !columnas[m[1]].has(col)) columnasMalas.push(rel(p) + ':' + linea + '  ' + m[1] + '.' + col);
      }
    }
  }
}
rpcInexistentes.forEach(i => console.log('     ' + i));
ok(rpcInexistentes.length === 0, 'toda RPC que nombra una pantalla existe en la base (' + nRpc + ' llamadas en ' + archivos.length + ' archivos)');
fromInexistentes.forEach(i => console.log('     ' + i));
ok(fromInexistentes.length === 0, 'toda tabla/vista que lee una pantalla existe (' + nFrom + ' from())');
// una columna borrada o renombrada en la base rompe la pantalla en silencio (PostgREST 400)
columnasMalas.forEach(i => console.log('     ' + i));
ok(columnasMalas.length === 0, 'cada columna que una pantalla pide en from(tabla).select(...) existe en la tabla');
clavesMalas.forEach(i => console.log('     ' + i));
ok(clavesMalas.length === 0, 'cada clave del objeto de una llamada rpc es un parametro real de la funcion (' + nLlamadasConObjeto + ' llamadas con objeto literal)');
// un parametro sin DEFAULT que no viaja: PostgREST no encuentra la firma y la pantalla ve "function not found"
faltanRequeridos.forEach(i => console.log('     ' + i));
ok(faltanRequeridos.length === 0, 'cada llamada con objeto literal manda todos los parametros sin DEFAULT de la funcion');

console.log(fallas ? 'HAY FALLOS' : 'TODO OK');

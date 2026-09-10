/* Regla del usuario (2026-08-30): "Siempre quiero letras bien grandes y legibles
   para que alguien que ve mal pueda escribir y no equivocarse. Donde van numeros,
   solo teclado numerico."
   Este test la vigila en frio (sin browser):
   1. Ningun <input type="number"> sin inputmode (numeric/decimal) en todo el repo.
   2. gp2-modulo.css mantiene el piso de 18px para input/select/textarea.
   3. NINGUNA regla CSS de una pantalla GP2 baja un campo de 18px.
   4. Ningun <input type="text"> que pide un numero se queda sin inputmode.
   Es estatico a proposito: corre rapido y agarra el HTML generado por JS tambien.

   Los chequeos 3 y 4 se agregaron el 2026-09-03 porque el 2 solo miraba
   gp2-modulo.css: gp2-claro.css lo pisaba con 17px !important en 13 pantallas,
   el cluster de Produccion tenia los campos en 13px y nadie se entero. Solo
   miran pantallas GP2 (*_GP2.html + los CSS que esas paginas cargan): las
   pantallas viejas del programa anterior quedan afuera a proposito. */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
let fallas = 0;
const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) { fallas++; process.exitCode = 1; } };

const EXCLUIR = /(^|[\\/])(_backup|node_modules|\.git|tests)([\\/]|$)/;
const archivos = [];
(function walk(dir) {
  for (const f of fs.readdirSync(dir)) {
    const p = path.join(dir, f);
    if (EXCLUIR.test(p)) continue;
    const st = fs.statSync(p);
    if (st.isDirectory()) walk(p);
    else if (/\.(html|js)$/.test(f)) archivos.push(p);
  }
})(ROOT);

const TAG = /<input\b[^>]*?>/gs;
const malos = [];
for (const p of archivos) {
  const s = fs.readFileSync(p, 'utf8');
  if (!s.includes('type="number"') && !s.includes("type='number'")) continue;
  for (const m of s.matchAll(TAG)) {
    const t = m[0];
    if (!/type=["']number["']/.test(t)) continue;
    if (/inputmode=/.test(t)) continue;
    const linea = s.slice(0, m.index).split('\n').length;
    malos.push(path.relative(ROOT, p) + ':' + linea);
  }
}
ok(malos.length === 0, 'todo type="number" lleva inputmode (' + archivos.length + ' archivos)' +
   (malos.length ? ' — faltan: ' + malos.slice(0, 8).join(', ') : ''));

const css = fs.readFileSync(path.join(ROOT, 'gp2-modulo.css'), 'utf8');
const piso = css.match(/input,\s*select,\s*textarea\s*\{\s*font-size:\s*(\d+)px/);
ok(!!piso && Number(piso[1]) >= 18, 'gp2-modulo.css mantiene el piso de letra grande (18px) en los campos');


// ── 3) ninguna regla CSS de una pantalla GP2 baja un campo de 18px ────────
// Se juntan los <style> de cada *_GP2.html mas los .css que esas paginas
// cargan (y los helpers compartidos que se inyectan por JS, que no aparecen
// como <link> en ningun lado).
const HELPERS = ['gp2-modulo.css', 'gp2-claro.css', 'tandas-popup.css', 'cajones-popup.css'];
const fuentes = new Map();                       // etiqueta -> css
for (const h of HELPERS) {
  const abs = path.join(ROOT, h);
  if (fs.existsSync(abs)) fuentes.set(h, fs.readFileSync(abs, 'utf8'));
}
for (const p of archivos.filter(f => f.endsWith('_GP2.html'))) {
  const s = fs.readFileSync(p, 'utf8');
  const rel = path.relative(ROOT, p);
  for (const m of s.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/gi)) fuentes.set(rel, (fuentes.get(rel) || '') + m[1]);
  for (const m of s.matchAll(/href\s*=\s*["']([^"'>]+\.css)(?:\?[^"'>]*)?["']/gi)) {
    const abs = path.resolve(path.dirname(p), m[1]);
    if (!fs.existsSync(abs)) continue;
    const r = path.relative(ROOT, abs);
    if (!fuentes.has(r)) fuentes.set(r, fs.readFileSync(abs, 'utf8'));
  }
}
// El selector tiene que tocar un campo de verdad. Se sacan los comentarios
// primero: si no, un /* ... input ... */ arriba de una regla de botones la
// hacia pasar por regla de campo.
const TOCA_CAMPO = /(^|[\s,>+~(])(input|select|textarea)([\s.:#[,{]|$)/i;
const chicos = [];
for (const [etiqueta, cssTxt] of fuentes) {
  const limpio = cssTxt.replace(/\/\*[\s\S]*?\*\//g, '');
  for (const m of limpio.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    const sel = m[1].trim();
    if (!TOCA_CAMPO.test(sel)) continue;
    const fz = m[2].match(/font-size:\s*([\d.]+)px/);
    if (fz && parseFloat(fz[1]) < 18) chicos.push(etiqueta + '  ->  ' + sel.replace(/\s+/g, ' ').slice(0, 60) + ' = ' + fz[1] + 'px');
  }
}
if (chicos.length) chicos.slice(0, 12).forEach(c => console.log('     ' + c));
ok(chicos.length === 0, 'ninguna regla CSS de una pantalla GP2 baja un campo de 18px (' + fuentes.size + ' hojas)');

// ── 4) type="text" que pide un numero, sin inputmode ─────────────────────
// El chequeo 1 solo mira type="number"; el legajo del operario, el N° de
// matriz y el codigo de articulo son type="text" y abrian teclado de letras.
const PIDE_NUMERO = /(legajo|matriz|codigo|cod_|cantidad|kilos|\bkg\b|golpes|cajones|telefono|dni|cuit|precio|numero|n°)/i;
// Un buscador es texto A PROPOSITO (se tipea "31" o "cuchilla"), y el remito
// del proveedor viene alfanumerico. Esos no piden teclado numerico.
const NO_ES_NUMERO = /(busc|search|nombre|remito|opcional|descrip)/i;
const textoSinModo = [];
for (const p of archivos.filter(f => f.endsWith('_GP2.html'))) {
  const s = fs.readFileSync(p, 'utf8');
  for (const m of s.matchAll(TAG)) {
    const t = m[0];
    if (!/type=["']text["']/.test(t)) continue;
    if (/inputmode=/.test(t)) continue;
    const pistas = (t.match(/(?:id|name|placeholder)=["']([^"']*)["']/g) || []).join(' ');
    if (!PIDE_NUMERO.test(pistas) || NO_ES_NUMERO.test(pistas)) continue;
    const linea = s.slice(0, m.index).split('\n').length;
    textoSinModo.push(path.relative(ROOT, p) + ':' + linea + ' ' + pistas.slice(0, 50));
  }
}
if (textoSinModo.length) textoSinModo.slice(0, 10).forEach(c => console.log('     ' + c));
ok(textoSinModo.length === 0, 'los type="text" que piden un numero llevan inputmode');

console.log(fallas ? 'HAY FALLOS' : 'TODO OK');

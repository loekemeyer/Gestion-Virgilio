/* Guardia de los helpers de PANTALLA de la casa (gp2-ui.js, 2026-09-04).
 *
 * Existe porque la auditoria A3 encontro 40 esc() con tres implementaciones,
 * 33 $(), 12 "hoy" con tres semanticas (UTC, hora del aparato y Argentina: las
 * dos primeras corren el dia despues de las 21:00) y 3 exportar-a-CSV, uno
 * distinto por pantalla. Ahora la copia es UNA (window.GP2UI). Este test:
 *   1. corre gp2-ui.js en node y chequea que cada helper haga lo que promete;
 *   2. lee el repo: toda pagina que carga un JS compartido que depende de
 *      GP2UI / GP2N (gp2-envios-common, gp2-composicion, gp2-stock-sector,
 *      consumo-detalle) tiene que cargar gp2-ui.js y gp2-numero.js ANTES,
 *      porque esos JS los toman al cargar y si faltan revientan;
 *   3. una pagina que ya carga gp2-ui.js no puede tener su propia copia
 *      (function esc / function $ / fecha con getTimezoneOffset / CSV a mano):
 *      si vuelve a aparecer una, es la regla escrita dos veces y falla.
 * Sin navegador: lee archivos.
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
let fallas = 0;
const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) { fallas++; process.exitCode = 1; } };

// ── 1) los helpers hacen lo que prometen ────────────────────────────────
const g = { document: { getElementById(id) { return { id }; } } };
new Function('window', 'document', fs.readFileSync(path.join(ROOT, 'gp2-ui.js'), 'utf8'))(g, g.document);
const UI = g.GP2UI;

ok(UI.esc('<a href="x">&</a>') === '&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;' && UI.esc(null) === '' && UI.esc(0) === '0',
   'esc(): & < > " escapados; null vacio; 0 se ve');
ok(UI.$('abc').id === 'abc', '$(id) es getElementById');
ok(UI.cls(5) === 'pos' && UI.cls(-0.5) === 'neg' && UI.cls(0) === 'cero' && UI.cls(null) === 'cero' && UI.cls('12') === 'pos',
   'cls(): pos / neg / cero segun el signo (acepta texto numerico)');
ok(/^\d{4}-\d{2}-\d{2}$/.test(UI.hoyAR()), 'hoyAR() es YYYY-MM-DD');
ok(UI.hoyAR(-1) < UI.hoyAR() && UI.hoyAR(1) > UI.hoyAR(), 'hoyAR(n) corre n dias');
// 2026-09-04 23:30 UTC ya es 2026-09-04 20:30 en Argentina (no el dia 5, que es lo que daba toISOString)
ok(UI.hoyAR(new Date('2026-09-04T23:30:00Z')) === '2026-09-04', 'hoyAR(Date): la fecha se decide en Argentina, no en UTC');
// 2026-09-05 02:30 UTC todavia es el 4 en Argentina
ok(UI.hoyAR(new Date('2026-09-05T02:30:00Z')) === '2026-09-04', 'hoyAR(Date): a las 23:30 AR sigue siendo hoy');
ok(UI.fechaAR('2026-09-04') === '04/09/2026' && UI.fechaAR('2026-09-04T12:00:00') === '04/09/2026'
   && UI.fechaAR('') === '' && UI.fechaAR(null) === '' && UI.fechaAR('ayer') === 'ayer',
   'fechaAR(): ISO -> dd/mm/aaaa; vacio -> vacio; lo que no es ISO vuelve igual');
ok(typeof UI.exportarCSV === 'function', 'exportarCSV existe');

// ── 2) orden de carga y 3) copias en las paginas ────────────────────────
const EXCLUIR = /(^|[\\/])(_backup|node_modules|\.git|tests)([\\/]|$)/;
const html = [];
(function walk(dir) {
  for (const f of fs.readdirSync(dir)) {
    const p = path.join(dir, f);
    if (EXCLUIR.test(p)) continue;
    if (fs.statSync(p).isDirectory()) walk(p);
    else if (f.endsWith('.html')) html.push(p);
  }
})(ROOT);

const DEPENDIENTES = ['gp2-envios-common.js', 'gp2-composicion.js', 'gp2-stock-sector.js', 'consumo-detalle.js'];
const pos = (txt, js) => { const m = new RegExp('<script[^>]+src="[^"]*' + js.replace('.', '\\.') + '(\\?[^"]*)?"').exec(txt); return m ? m.index : -1; };

const malOrden = [], conCopia = [], conUI = [];
for (const p of html) {
  const txt = fs.readFileSync(p, 'utf8');
  const rel = path.relative(ROOT, p);
  const pUI = pos(txt, 'gp2-ui.js'), pN = pos(txt, 'gp2-numero.js');
  for (const js of DEPENDIENTES) {
    const pd = pos(txt, js);
    if (pd < 0) continue;
    if (pUI < 0 || pUI > pd) malOrden.push(rel + ': ' + js + ' sin gp2-ui.js antes');
    if (pN < 0 || pN > pd) malOrden.push(rel + ': ' + js + ' sin gp2-numero.js antes');
  }
  if (pUI < 0) continue;
  conUI.push(rel);
  // el script inline que usa GP2UI al cargar tiene que venir despues del <script src=gp2-ui>
  const primerUso = txt.search(/GP2UI\./);
  if (primerUso >= 0 && primerUso < pUI) malOrden.push(rel + ': usa GP2UI antes de cargar gp2-ui.js');
  const COPIAS = [
    [/function\s+esc\s*\(/, 'function esc() propia'],
    [/function\s+\$\s*\(/, 'function $() propia'],
    [/getTimezoneOffset\(\)/, 'fecha "hoy" con getTimezoneOffset (usar GP2UI.hoyAR)'],
    [/sep=;/, 'CSV armado a mano (usar GP2UI.exportarCSV)'],
    [/toISOString\(\)\.slice\(0,\s*10\)/, 'fecha "hoy" en UTC con toISOString (usar GP2UI.hoyAR)'],
    // 2026-09-05: cuatro pantallas conservaban un hoyAR() byte a byte igual al de la casa
    [/function\s+hoyAR\s*\(/, 'function hoyAR() propia (usar var hoyAR = GP2UI.hoyAR)'],
  ];
  for (const [re, que] of COPIAS) {
    const m = re.exec(txt);
    if (m) conCopia.push(rel + ':' + txt.slice(0, m.index).split('\n').length + '  ' + que);
  }
}
malOrden.forEach(x => console.log('     ' + x));
ok(malOrden.length === 0, 'gp2-ui.js y gp2-numero.js se cargan antes que los JS que dependen de ellos (' + html.length + ' paginas)');
conCopia.forEach(x => console.log('     ' + x));
ok(conCopia.length === 0, 'ninguna pagina que carga gp2-ui.js tiene su propia copia de un helper (' + conUI.length + ' paginas)');
ok(conUI.length >= 11, 'gp2-ui.js esta en las pantallas que lo necesitan (' + conUI.length + ')');

// ── 4) el cliente Supabase se crea en UN lugar (GP2_SB en supabase-config.js) ──────
// 2026-09-05: habia 40 createClient inline en cinco formas distintas. Las pantallas GP2 y los
// JS que cargan llaman GP2_SB(); un createClient propio es una copia nueva y falla.
const PERMITIDO_CLIENTE = new Set([
  'supabase-config.js',                          // la fabrica misma
  'login.html',                                  // cliente de auth (schema public), no de datos
  'Produccion/RegistroApp/operarios_gp2.js',     // opciones de auth propias (storageKey de operarios)
]);
const ES_GP2 = p => /_GP2\.html$/.test(p) || /(^|[\\/])(Programa|Validacion_Stock|OrdenProduccion|GP2_MODULOS|envios-only)\.html$/.test(p);
const conCliente = [];
const vistos = new Set();
for (const p of html.filter(ES_GP2)) {
  const archivos = [p];
  const txt = fs.readFileSync(p, 'utf8');
  for (const m of txt.matchAll(/src\s*=\s*["']([^"'>]+\.js)(?:\?[^"'>]*)?["']/g)) {
    const abs = path.resolve(path.dirname(p), m[1]);
    if (fs.existsSync(abs)) archivos.push(abs);
  }
  for (const a of archivos) {
    const rel = path.relative(ROOT, a).replace(/\\/g, '/');
    if (vistos.has(rel) || PERMITIDO_CLIENTE.has(rel)) continue;
    vistos.add(rel);
    const t = fs.readFileSync(a, 'utf8');
    const m = /\bcreateClient\s*\(/.exec(t);
    if (m) conCliente.push(rel + ':' + t.slice(0, m.index).split('\n').length);
  }
}
conCliente.forEach(x => console.log('     ' + x));
ok(conCliente.length === 0, 'ninguna pantalla GP2 crea su propio cliente Supabase: usan GP2_SB() (' + vistos.size + ' archivos)');

// ── 5) ninguna pantalla GP2 escribe una tabla directo ─────────────────────
// Desde el 2026-08-31 anon no tiene INSERT/UPDATE/DELETE en ninguna tabla GP2: toda escritura
// va por RPC SECURITY DEFINER. Un .from('x').update(...) en una pantalla falla con
// "permission denied" (asi estuvo roto "Desmarcar" en control-cajas/remaches 5 dias).
const escriben = [];
for (const rel of vistos) {
  if (PERMITIDO_CLIENTE.has(rel) && rel !== 'Produccion/RegistroApp/operarios_gp2.js') continue;
  const t = fs.readFileSync(path.join(ROOT, rel), 'utf8');
  for (const m of t.matchAll(/\.from\(\s*['"][A-Za-z_]+['"]\s*\)[^;\n]*\.(insert|update|delete|upsert)\s*\(/g)) {
    escriben.push(rel + ':' + t.slice(0, m.index).split('\n').length + '  .' + m[1] + '(');
  }
}
escriben.forEach(x => console.log('     ' + x));
ok(escriben.length === 0, 'ninguna pantalla GP2 escribe una tabla directo (todo por RPC) (' + vistos.size + ' archivos)');

console.log(fallas ? 'HAY FALLOS' : 'TODO OK');

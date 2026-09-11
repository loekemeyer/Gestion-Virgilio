/* Guardia de la REGLA DE NUMERO de la casa [usuario 2026-09-03]: "si hay un
 * punto, el punto para el separador de mil; la coma para los decimales" y "en
 * cada lugar que ponga cuatro digitos, que se ponga automatico un separador de
 * miles".
 *
 * Existe porque la regla habia quedado escrita SEIS veces y ninguna igual
 * (idea 7217), asi que cada pantalla contestaba distinto que era "1.234". Este
 * test chequea dos cosas:
 *   1. gp2-numero.js cumple la regla (tabla de casos, ida y vuelta).
 *   2. Ninguna pantalla GP2 se escribe SU PROPIO parser: si aparece un
 *      replace(/\D/g) sobre el .value de un input, o un parseFloat con
 *      replace(',','.') a mano, es una copia nueva de la regla y falla.
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
let fallas = 0;
const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) { fallas++; process.exitCode = 1; } };

// ── 1) la regla ──────────────────────────────────────────────────────────
const g = { document: { addEventListener() {} } };
new Function('window', 'document', fs.readFileSync(path.join(ROOT, 'gp2-numero.js'), 'utf8'))(g, g.document);
const { num, entero, conMiles } = g.GP2N;

const CASOS_NUM = [
  ['1.234', 1234],        // el punto es MILES, no decimal
  ['1.234,5', 1234.5],
  ['1.234.567,89', 1234567.89],
  ['12,5', 12.5],
  ['12.5', 125],          // "12.5" son ciento veinticinco
  ['250,75', 250.75],
  ['999', 999],
  ['0,5', 0.5],
  ['-1.500,25', -1500.25],
  ['12,5,7', 12.57],      // una sola coma: las demas se ignoran
  ['', 0], [null, 0], ['abc', 0],
];
let malos = CASOS_NUM.filter(([e, s]) => num(e) !== s);
malos.forEach(([e, s]) => console.log('     num(' + JSON.stringify(e) + ') = ' + num(e) + ', esperaba ' + s));
ok(malos.length === 0, 'el punto es separador de miles y la coma decimal (' + CASOS_NUM.length + ' casos)');

const CASOS_MILES = [
  ['999', '999'],         // tres digitos: SIN separador
  ['1000', '1.000'],      // cuatro: aparece
  ['12345', '12.345'],
  ['1234567', '1.234.567'],
  ['1234,5', '1.234,5'],
  ['12,50', '12,50'],
  ['-12345', '-12.345'],
  ['', ''],
];
malos = CASOS_MILES.filter(([e, s]) => conMiles(e) !== s);
malos.forEach(([e, s]) => console.log('     conMiles(' + JSON.stringify(e) + ') = ' + JSON.stringify(conMiles(e)) + ', esperaba ' + JSON.stringify(s)));
ok(malos.length === 0, 'el separador de miles aparece recien con cuatro digitos (' + CASOS_MILES.length + ' casos)');

// lo que el operario VE tiene que volver a leerse como el mismo numero
const IDA_VUELTA = [999, 1000, 12345, 1234.5, 250.75, 1234567.89];
malos = IDA_VUELTA.filter(n => Math.abs(num(conMiles(String(n).replace('.', ','))) - n) > 1e-9);
ok(malos.length === 0, 'ida y vuelta: lo que se ve en pantalla se lee igual (' + IDA_VUELTA.length + ' numeros)');

ok(entero('1.234,9') === 1234, 'entero() corta los decimales sin redondear');

// ── 2) nadie se escribe su propio parser ─────────────────────────────────
// Las pantallas viejas del programa anterior quedan afuera: se van a morir.
const EXCLUIR = /(^|[\\/])(_backup|node_modules|\.git|tests)([\\/]|$)/;
const archivos = [];
(function walk(dir) {
  for (const f of fs.readdirSync(dir)) {
    const p = path.join(dir, f);
    if (EXCLUIR.test(p)) continue;
    if (fs.statSync(p).isDirectory()) walk(p);
    else if (f.endsWith('_GP2.html')) archivos.push(p);
  }
})(ROOT);
// y los .js que esas pantallas cargan: ahi tambien se puede colar una copia
for (const p of archivos.slice()) {
  const txt = fs.readFileSync(p, 'utf8');
  for (const m of txt.matchAll(/src\s*=\s*["']([^"'>]+\.js)(?:\?[^"'>]*)?["']/g)) {
    const abs = path.resolve(path.dirname(p), m[1]);
    if (fs.existsSync(abs) && !archivos.includes(abs)) archivos.push(abs);
  }
}

// Un saneador propio se reconoce por pisar el .value de un campo con \D, o por
// armar el numero a mano con replace(',','.') antes de parseFloat/Number.
const PROPIOS = [
  { re: /\.value\s*=\s*[^;\n]*replace\(\/\\D\/g/, que: 'sanea el input con replace(/\\D/g) en vez de GP2N.autoMiles' },
  { re: /(?:parseFloat|Number)\((?:[^()]|\([^()]*\))*replace\(\s*["'],["']\s*,\s*["']\.["']/, que: "arma el numero con replace(',','.') en vez de GP2N.num" },
];
// Recepcion Insumos trae parseNum + sanitizadores propios (usuario 2026-09-01) que contradicen
// la regla del 2026-09-03 ("12.5" es 12,5 ahi y 125 en la casa). Es la pantalla de carga mas
// usada: se migra con el operario al lado (IDEAS 7259), no a ciegas. Hasta entonces, permitida.
const PERMITIDO_PARSER = new Set(['StockFlejes/RecepcionInsumos_GP2.html']);
const infractores = [];
for (const p of archivos) {
  if (PERMITIDO_PARSER.has(path.relative(ROOT, p).replace(/\\/g, '/'))) continue;
  const txt = fs.readFileSync(p, 'utf8');
  for (const { re, que } of PROPIOS) {
    const m = txt.match(re);
    if (m) infractores.push(path.relative(ROOT, p) + ':' + txt.slice(0, m.index).split('\n').length + '  ' + que);
  }
}
infractores.forEach(i => console.log('     ' + i));
ok(infractores.length === 0,
   'ninguna pantalla GP2 se escribe su propio parser de numero (' + archivos.length + ' pantallas)');

// ── 3) donde esta cargada la regla, los campos se leen con ella ──────────
// gp2-numero.js formatea lo tipeado con separador de miles ("1.500"), asi que
// un Number()/parseFloat()/parseInt() crudo sobre el .value de un campo lee 1,5
// (o 1). Encontrado en Control PS y en el popup de tandas (2026-09-04).
const conRegla = new Set();
for (const p of archivos) {
  if (!p.endsWith('.html')) continue;
  const txt = fs.readFileSync(p, 'utf8');
  if (!/<script[^>]+src="[^"]*gp2-numero\.js/.test(txt)) continue;
  conRegla.add(p);
  for (const m of txt.matchAll(/src\s*=\s*["']([^"'>]+\.js)(?:\?[^"'>]*)?["']/g)) {
    const abs = path.resolve(path.dirname(p), m[1]);
    if (fs.existsSync(abs)) conRegla.add(abs);
  }
}
const CRUDO = /(?:\bNumber|\bparseFloat|\bparseInt)\(\s*(?:String\()?\s*\(?\s*(?:\$R?\(['"][^'"]*['"]\)|document\.getElementById\(['"][^'"]*['"]\)|[\w.]+)\.value\b/g;
const crudos = [];
for (const p of conRegla) {
  const txt = fs.readFileSync(p, 'utf8');
  for (const m of txt.matchAll(CRUDO)) {
    crudos.push(path.relative(ROOT, p) + ':' + txt.slice(0, m.index).split('\n').length + '  ' + m[0].trim());
  }
}
crudos.forEach(i => console.log('     ' + i));
ok(crudos.length === 0,
   'donde esta cargado gp2-numero.js los campos se leen con GP2N.num/entero, no con Number/parseInt crudo (' + conRegla.size + ' archivos)');

// ── 4) donde esta la regla, tampoco hay un formateador propio ────────────
// toLocaleString('es-AR') escrito en la pantalla es GP2N.fmt copiado (con otro default de
// decimales o de "sin valor": para eso GP2N.fmt tiene los parametros).
// Se mira el formateo de NUMEROS (con FractionDigits o sobre Number(...)); las fechas
// (new Date().toLocaleString('es-AR')) no son esta regla. tandas-popup.js queda afuera
// mientras lo carguen las pantallas viejas sin gp2-numero.js (pregunta 2 de PREGUNTAS).
const PERMITIDO_FMT = new Set(['tandas-popup.js']);
const copiasFmt = [];
for (const p of conRegla) {
  if (path.basename(p) === 'gp2-numero.js' || PERMITIDO_FMT.has(path.basename(p))) continue;
  const txt = fs.readFileSync(p, 'utf8');
  for (const m of txt.matchAll(/(?:Number\([^)]*\)\.toLocaleString\(\s*["']es-AR["']|toLocaleString\(\s*["']es-AR["']\s*,\s*\{[^}]*FractionDigits)/g)) {
    copiasFmt.push(path.relative(ROOT, p) + ':' + txt.slice(0, m.index).split('\n').length);
  }
}
copiasFmt.forEach(i => console.log('     ' + i));
ok(copiasFmt.length === 0,
   'donde esta cargado gp2-numero.js no hay toLocaleString(es-AR) propio: se usa GP2N.fmt (' + conRegla.size + ' archivos)');

console.log(fallas ? 'HAY FALLOS' : 'TODO OK');

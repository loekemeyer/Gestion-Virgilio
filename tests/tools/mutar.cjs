#!/usr/bin/env node
/* PRUEBA DE MUTACIÓN — v21.79 (Luis, 23/09: "revisá otros tests").

   Un test verde no dice que el test sirva: dice que hoy no se rompió. La única forma de
   saber si MUERDE es romper el código a propósito y ver si se entera. Eso es esto.

   Cada entrada del catálogo rompe UNA regla del front y nombra los tests que TIENEN que
   ponerse rojos. Si alguno sigue verde, ese test no está cubriendo lo que su nombre dice.

   ⚠ NO va en tests/run.sh: muta index.html y tarda. Se corre a mano cuando se agrega una
   regla cara, o cuando se duda de un test.

     node tests/tools/mutar.cjs              # todo el catálogo
     node tests/tools/mutar.cjs excedente    # sólo las que matcheen ese texto

   ⚠ index.html se restaura SIEMPRE (finally), también con Ctrl-C. Si algo sale mal igual,
   el original queda en tests/tools/.index.html.bak y se restaura copiándolo encima.

   ⚠ Y una mutación que NO rompe a nadie no siempre es un test flojo: puede ser INOCUA.
   Pasó el 23/09 con `items.concat(excSteps)` — el orden lo da el sector y la concatenación
   sólo decide el desempate a igual orden, así que el test tenía razón en no moverse. Antes
   de acusar a un test, mirar si la mutación cambia algo de verdad. (Ese caso terminó bien:
   el desempate no se probaba corriendo, y se le agregó el chequeo D a pk-excedente-orden.) */
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const RAIZ = path.join(__dirname, "..", "..");
const IDX = path.join(RAIZ, "index.html");
const BAK = path.join(__dirname, ".index.html.bak");

// nombre · qué se rompe · por qué reemplazo · qué tests tienen que enterarse
const CATALOGO = [
  { n: "busqueda-prefijo", de: "function codEmpiezaCon(cod, term) {",
    a: "function codEmpiezaCon(cod, term) { return true; /*MUT*/",
    rompe: ["stk-busqueda-prefijo", "mg-buscar-prefijo", "stk-buscar-cero-adelante"] },
  { n: "regla-L", de: "function pkStripL(cod)",
    a: "function pkStripL(cod) { return cod; } function _pkStripLMut(cod)",
    rompe: ["fcs-codigo-l"] },
  { n: "armado-anulado", de: "function _entregaAnulada(",
    a: "function _entregaAnulada(r){return false;} function _entregaAnuladaMut(",
    rompe: ["comp-armado-anulado"] },
  { n: "gondola-4-filas", de: "function pmapAlto(",
    a: "function pmapAlto(g){return 5;} function _pmapAltoMut(",
    rompe: ["pmap-gondolas"] },
  { n: "supervisor-legajo", de: "function gvLegajoSupervisor(",
    a: "function gvLegajoSupervisor(){return '0';} function _gvLegMut(",
    rompe: ["rr-supervisor-legajo"] },
  { n: "cuarentena-lote", de: "function cuarMarcarPedidos(",
    a: "function cuarMarcarPedidos(){return;} function _cuarMut(",
    rompe: ["apr-cuar-chef-tarde"] },
  { n: "excedente-empate", de: "items.concat(excSteps)", a: "excSteps.concat(items)",
    rompe: ["pk-excedente-orden"] },
  { n: "codigo-inexistente", de: "r.visible_en_stock === false &&",
    a: "false && r.visible_en_stock === false &&", rompe: ["stk-codigo-inexistente"] },
  // v21.80: el comentario del pedido, que hasta esa version se veia SOLO con el mouse encima.
  { n: "obs-en-la-np", de: "function _pgaObsHtml(",
    a: "function _pgaObsHtml(){return '';} function _pgaObsHtmlMut(",
    rompe: ["ppp-obs-boton"] },
  // v21.84: la L es de Cencosud y de Tierra del Fuego, de nadie mas (regla v21.09).
  // Esta NO vive en index.html: el espejo del panel de LK se sirve igual por Pages.
  { n: "regla-L-super", archivo: "admin/admin-supercot.js",
    de: "isChefSuper(state.superKey) && !usesChefProducts(state.superKey);",
    a: "isChefSuper(state.superKey);",
    rompe: ["regla-L-super"] },
  { n: "obs-badge-grupo", de: "function _pgaObsGrupoBadge(",
    a: "function _pgaObsGrupoBadge(){return '';} function _pgaObsGrupoBadgeMut(",
    rompe: ["ppp-obs-boton"] },
];

const filtro = process.argv[2] || "";
const lista = CATALOGO.filter((m) => !filtro || m.n.indexOf(filtro) >= 0);
if (!lista.length) { console.error("nada matchea '" + filtro + "'"); process.exit(2); }

const orig = fs.readFileSync(IDX);
fs.writeFileSync(BAK, orig);
// v21.84 — una mutacion puede vivir en otro archivo (el espejo del panel de LK).
// Se guarda el original de cada uno y se restauran TODOS en el finally.
const ORIGINALES = new Map([[IDX, orig]]);
function destinoDe(m) {
  const f = m.archivo ? path.join(RAIZ, m.archivo) : IDX;
  if (!ORIGINALES.has(f)) ORIGINALES.set(f, fs.readFileSync(f));
  return f;
}
const env = Object.assign({}, process.env,
  { PLAYWRIGHT_BROWSERS_PATH: process.env.PLAYWRIGHT_BROWSERS_PATH || "/opt/pw-browsers" });
const fallas = [];

function restaurar() { for (const [f, b] of ORIGINALES) fs.writeFileSync(f, b); }
process.on("SIGINT", () => { restaurar(); process.exit(130); });

try {
  for (const m of lista) {
    const dest = destinoDe(m);
    const txt = ORIGINALES.get(dest).toString("latin1");  // ⚠ latin1 = byte a byte, no rompe el NUL
    const n = txt.split(m.de).length - 1;
    if (n !== 1) { console.log("SALTEADA (" + n + " coincidencias): " + m.n); fallas.push(m.n + ": el patrón ya no existe"); continue; }
    fs.writeFileSync(dest, Buffer.from(txt.replace(m.de, m.a), "latin1"));
    console.log("== " + m.n);
    for (const t of m.rompe) {
      const f = path.join(RAIZ, "tests", t + ".cjs");
      if (!fs.existsSync(f)) { console.log("   (no existe " + t + ")"); fallas.push(m.n + ": falta " + t); continue; }
      let verde = true;
      try { execFileSync("node", [f], { env, stdio: "ignore", timeout: 180000 }); }
      catch (_e) { verde = false; }
      console.log("   " + t.padEnd(28) + (verde ? "⚠ SIGUE VERDE" : "se entera"));
      if (verde) fallas.push(m.n + " → " + t + " no se entera");
    }
    restaurar();
  }
} finally { restaurar(); }

let _rest = [];
for (const [f, b] of ORIGINALES) if (!fs.readFileSync(f).equals(b)) _rest.push(f);
if (!_rest.length) console.log("\narchivos restaurados ✓ (" + ORIGINALES.size + ")");
else { console.error("\n⚠⚠ NO quedaron iguales: " + _rest.join(", ") + " — index.html se restaura desde " + BAK); process.exit(1); }

if (fallas.length) { console.error("\nFALLAN " + fallas.length + ":\n· " + fallas.join("\n· ")); process.exit(1); }
console.log("mutar: las " + lista.length + " mutaciones las caza su test ✓");

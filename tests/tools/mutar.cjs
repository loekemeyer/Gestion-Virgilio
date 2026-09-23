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
];

const filtro = process.argv[2] || "";
const lista = CATALOGO.filter((m) => !filtro || m.n.indexOf(filtro) >= 0);
if (!lista.length) { console.error("nada matchea '" + filtro + "'"); process.exit(2); }

const orig = fs.readFileSync(IDX);
fs.writeFileSync(BAK, orig);
const env = Object.assign({}, process.env,
  { PLAYWRIGHT_BROWSERS_PATH: process.env.PLAYWRIGHT_BROWSERS_PATH || "/opt/pw-browsers" });
const fallas = [];

function restaurar() { fs.writeFileSync(IDX, orig); }
process.on("SIGINT", () => { restaurar(); process.exit(130); });

try {
  for (const m of lista) {
    const txt = orig.toString("latin1");          // ⚠ latin1 = byte a byte, no rompe el NUL
    const n = txt.split(m.de).length - 1;
    if (n !== 1) { console.log("SALTEADA (" + n + " coincidencias): " + m.n); fallas.push(m.n + ": el patrón ya no existe"); continue; }
    fs.writeFileSync(IDX, Buffer.from(txt.replace(m.de, m.a), "latin1"));
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

if (fs.readFileSync(IDX).equals(orig)) console.log("\nindex.html restaurado ✓");
else { console.error("\n⚠⚠ index.html NO quedó igual: restaurar desde " + BAK); process.exit(1); }

if (fallas.length) { console.error("\nFALLAN " + fallas.length + ":\n· " + fallas.join("\n· ")); process.exit(1); }
console.log("mutar: las " + lista.length + " mutaciones las caza su test ✓");

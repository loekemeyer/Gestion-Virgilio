/* v18.08 (Luis, 2026-09-15) — RECEPCIÓN, pop-up "Cajas entregadas": el aviso de exceso y la ×.

   Pedido: *"el botón X para cerrar se ve feo ahí, ponelo más lindo"* y *"no pone cartel cuando el
   código no tiene OC de que se está recibiendo más mercadería de la habilitada"*.

   El problema 217: el aviso en vivo sólo salía si el código TENÍA OC vigente y además le quedaban
   cajas por recibir (`if (!oc || !(oc.pend > 0)) return;`), y sin OC la caja se escondía entera.
   Quedaban DOS casos mudos que el gate de WhatsApp del resumen SÍ cuenta como exceso
   (`opExcesoItems` usa `ocRef(oc)`): (a) código sin OC, (b) OC ya recibida entera. O sea que el
   operario cargaba sin ningún aviso y recién al final se enteraba de que tenía que avisar.

   Lo que fija este test:
     · sin OC → la caja se ve igual, y al tipear una cantidad avisa en rojo;
     · OC recibida entera (pend = 0) → el límite es lo pedido, y pasarse avisa;
     · OC con saldo → sigue avisando como antes, y NO avisa si entra justo;
     · el aviso en vivo y el gate del resumen coinciden código por código — que es lo que el
       comentario de la v17.27 ya afirmaba y no era cierto;
     · si las OCs no se pudieron leer (ocOk = false) no se afirma nada, igual que el gate;
     · la × está centrada de verdad (flex), se distingue del fondo y es tocable.
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado (ver tests/smoke.cjs)."); process.exit(2); }
}

const root = path.join(__dirname, "..");
const src = fs.readFileSync(path.join(root, "recepcion.js"), "utf8");

const FAKE_CLIENT = `
const __fake = { rows: [] };
window.__fakeRows = function (rows) { __fake.rows = rows; };
function __q() {
  const o = {};
  ["select","gte","lte","eq","neq","in","not","or","ilike","order","limit","single","update","delete","insert"]
    .forEach(function (m) { o[m] = function () { return o; }; });
  o.then = function (res, rej) { return Promise.resolve({ data: [], error: null }).then(res, rej); };
  return o;
}
window.supabase = { createClient: function () {
  return {
    from: __q,
    rpc: function (fn) {
      // ⚠ el nombre real es \`oc_vigentes_por_proveedor\`. Con el nombre equivocado el stub devolvía
      // [] y TODOS los códigos caían en "sin OC": el chequeo de que el aviso en vivo y el gate
      // coinciden pasaba trivialmente, midiendo el mismo caso tres veces.
      if (fn === "oc_vigentes_por_proveedor") return Promise.resolve({ data: __fake.rows, error: null });
      return Promise.resolve({ data: [], error: null });
    },
    auth: {
      getSession: function () { return Promise.resolve({ data: { session: { fake: true } } }); },
      signInAnonymously: function () { return Promise.resolve({ data: { session: { fake: true } }, error: null }); }
    }
  };
} };
`;

const patched = src + `
window.__rcp = { opState: opState, cargarOCVigentes: cargarOCVigentes, openCajas: openCajas,
  opExcesoItems: opExcesoItems, ocRef: ocRef, ocDeCod: ocDeCod,
  el: { cajasInput: opCajasInput, cajasOc: opCajasOc, cajasClose: opCajasClose,
        cajasModal: opCajasModal } };
`;

if (!/window\.supabase/.test(src)) { console.error("rcp-cajas-aviso: recepcion.js ya no toma createClient de window.supabase — actualizá el stub."); process.exit(1); }
if (!/oc_vigentes_por_proveedor/.test(src)) { console.error("rcp-cajas-aviso: recepcion.js ya no llama oc_vigentes_por_proveedor — el stub devolvería [] y TODO pasaría como 'sin OC'."); process.exit(1); }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.setContent('<!doctype html><meta charset="utf-8"><body><script>' + FAKE_CLIENT + '<\/script><script type="module">' + patched + "<\/script></body>");
  await p.waitForFunction(() => !!window.__rcp, null, { timeout: 10000 });

  const r = await p.evaluate(async () => {
    const R = window.__rcp, S = R.opState, out = {};
    // tipea `n` en el pop-up del código `cod` y devuelve lo que quedó en la caja del aviso
    const cargar = function (cod, n) {
      R.openCajas(cod);
      R.el.cajasInput.value = String(n);
      R.el.cajasInput.oninput();
      const box = R.el.cajasOc;
      return { txt: box.textContent, rojo: getComputedStyle(box).backgroundColor,
               visible: getComputedStyle(box).display !== "none" };
    };
    const ROJO = "rgb(254, 242, 242)";      // #fef2f2, el fondo del aviso

    /* ⚠ La RPC devuelve el código pasado por `norm_cod`, que saca los ceros de adelante — es la
       MISMA regla que `_ocgNorm` en el front, así que el 034 de la pantalla entra como "34". El
       fixture tiene que respetarlo: con "034" acá el lookup fallaba y el caso se medía como
       "sin OC" sin que nada se quejara. Se abre el pop-up con "034", como lo ve el operario. */
    window.__fakeRows([
      { cod: "34",  fecha: "2026-09-09", ped: 64, rec: 0,  pend: 64 },   // con saldo
      { cod: "586", fecha: "2026-07-29", ped: 100, rec: 100, pend: 0 }   // ya recibida entera
    ]);
    S.tipo = "tallerista"; S.tallNombre = "Lucho"; S.linea = "LK"; S.fecha = "2026-09-15";
    S.remito = "12345"; S.cargas = {}; S.ocPorCod = null;
    await R.cargarOCVigentes();
    out.ocOk = S.ocOk === true;

    // ── (a) el código SIN OC — lo que pidió Luis ───────────────────────────
    const sinOcAbierto = (R.openCajas("031"), {
      txt: R.el.cajasOc.textContent, visible: getComputedStyle(R.el.cajasOc).display !== "none" });
    out.sinOcSeVe = sinOcAbierto.visible;
    out.sinOcDiceQueNoHay = /no tiene OC vigente/i.test(sinOcAbierto.txt);
    const sinOc50 = cargar("031", 50);
    out.sinOcAvisa = /más mercadería que la que tenés habilitada/i.test(sinOc50.txt);
    out.sinOcRojo = sinOc50.rojo === ROJO;
    out.sinOcDiceSinOc = /no tiene ninguna OC/i.test(sinOc50.txt);
    // con 0 tipeado no hay exceso todavía: informa, pero no grita
    const sinOc0 = cargar("031", 0);
    out.sinOcCeroNoGrita = !/más mercadería/i.test(sinOc0.txt) && sinOc0.rojo !== ROJO;

    // ── (b) OC ya recibida entera (pend = 0): el límite es lo PEDIDO ───────
    const rec101 = cargar("586", 101);
    out.recibidaAvisa = /más mercadería/i.test(rec101.txt) && rec101.rojo === ROJO;
    out.recibidaDice100 = /faltan 100/.test(rec101.txt);
    const rec100 = cargar("586", 100);
    out.recibidaJustoNoAvisa = !/más mercadería/i.test(rec100.txt);

    // ── (c) OC con saldo: como antes ───────────────────────────────────────
    const c70 = cargar("034", 70);
    out.conOcAvisa = /más mercadería/i.test(c70.txt) && /faltan 64/.test(c70.txt) && c70.rojo === ROJO;
    const c64 = cargar("034", 64);
    out.conOcJustoNoAvisa = !/más mercadería/i.test(c64.txt) && c64.rojo !== ROJO;
    out.conOcMuestraLaOc = /64.*caja\(s\) pedidas/.test(c64.txt);
    out.sinBoton = !R.el.cajasOc.querySelector("button");   // no interrumpe la carga

    // ── (d) el aviso en vivo y el gate del resumen dicen LO MISMO ──────────
    S.cargas = { "031": 50, "586": 101, "034": 70, "777": 3, "018": 0 };
    const gate = {};
    R.opExcesoItems().forEach(function (i) { gate[i.cod] = true; });
    const vivo = {};
    ["031", "586", "034", "777", "018"].forEach(function (cod) {
      const n = S.cargas[cod];
      const t = cargar(cod, n).txt;
      if (/más mercadería/i.test(t)) vivo[cod] = true;
    });
    out.gate = Object.keys(gate).sort().join(",");
    out.vivo = Object.keys(vivo).sort().join(",");
    out.coinciden = out.gate === out.vivo;
    /* ⚠ Control de que la comparación no es trivial: tiene que haber los tres casos DISTINTOS
       (con OC y saldo, OC ya recibida, y sin OC). Si el fixture se rompe y todo cae en "sin OC",
       `coinciden` da verde midiendo el mismo caso tres veces — pasó al escribir este test. */
    out.casosDistintos = !!R.ocDeCod("034") && R.ocDeCod("034").pend === 64 &&
                         !!R.ocDeCod("586") && R.ocDeCod("586").pend === 0 &&
                         R.ocDeCod("031") === null;

    // ── (e) si las OCs no se leyeron, no se afirma nada ────────────────────
    S.ocOk = false;
    const caido = cargar("031", 50);
    out.sinOcOkNoAfirma = !/más mercadería/i.test(caido.txt);
    S.ocOk = true;

    // ── (f) la × ──────────────────────────────────────────────────────────
    R.el.cajasModal.classList.add("open");
    const x = R.el.cajasClose, cs = getComputedStyle(x), rc = x.getBoundingClientRect();
    out.x = { display: cs.display, align: cs.alignItems, justify: cs.justifyContent,
              bg: cs.backgroundColor, border: cs.borderTopWidth, font: cs.fontSize,
              w: Math.round(rc.width), h: Math.round(rc.height) };
    out.xCentrada = cs.display === "flex" && cs.alignItems === "center" && cs.justifyContent === "center";
    out.xSeDistingue = cs.backgroundColor !== "rgb(255, 255, 255)" &&
                       cs.backgroundColor !== "rgba(0, 0, 0, 0)";
    out.xLegible = parseFloat(cs.fontSize) >= 18;
    out.xTocable = rc.width >= 32 && rc.height >= 32 && Math.abs(rc.width - rc.height) < 2;
    out.xSinBordeFeo = parseFloat(cs.borderTopWidth) === 0;
    return out;
  });

  await b.close();
  const ok = [];
  const chk = (c, d) => ok.push([!!c, d]);
  chk(r.ocOk, "las OCs se leyeron (ocOk)");
  chk(r.sinOcSeVe, "un código SIN OC ya no esconde la caja del aviso");
  chk(r.sinOcDiceQueNoHay, "y dice que no tiene OC vigente antes de tipear nada");
  chk(r.sinOcAvisa, "al cargar cajas sin OC AVISA que se recibe más de lo habilitado ← el pedido");
  chk(r.sinOcRojo, "y lo pinta en rojo, igual que el caso con OC");
  chk(r.sinOcDiceSinOc, "el texto no inventa un 'faltan N': dice que no hay ninguna OC");
  chk(r.sinOcCeroNoGrita, "con 0 tipeado informa pero no grita");
  chk(r.recibidaAvisa, "una OC ya recibida entera (pend=0) también avisa al pasarse");
  chk(r.recibidaDice100, "y el límite que muestra es lo PEDIDO (100), no 0");
  chk(r.recibidaJustoNoAvisa, "y con la cantidad justa no avisa");
  chk(r.conOcAvisa, "con OC y saldo sigue avisando como antes (70 > 64)");
  chk(r.conOcJustoNoAvisa, "y con 64 justas no avisa");
  chk(r.conOcMuestraLaOc, "la caja sigue mostrando la OC vigente");
  chk(r.sinBoton, "el aviso no trae botón: no interrumpe la carga (v17.17/v17.27)");
  chk(r.casosDistintos, "el fixture tiene los tres casos distintos (con saldo / ya recibida / sin OC)");
  chk(r.coinciden, "el aviso en vivo y el gate del resumen coinciden código por código — gate: " +
      JSON.stringify(r.gate) + " · vivo: " + JSON.stringify(r.vivo));
  chk(r.sinOcOkNoAfirma, "si las OCs no se pudieron leer no se afirma nada (ocOk=false)");
  chk(r.xCentrada, "la × se centra con flex, no con el padding del user-agent: " +
      JSON.stringify([r.x.display, r.x.align, r.x.justify]));
  chk(r.xSeDistingue, "y se distingue del fondo blanco de la tarjeta: " + r.x.bg);
  chk(r.xLegible, "con la × legible (≥18px): " + r.x.font);
  chk(r.xTocable, "y redonda y tocable: " + r.x.w + "×" + r.x.h);
  chk(r.xSinBordeFeo, "sin el borde gris apenas visible de antes");
  chk(errs.length === 0, "sin errores de JS: " + JSON.stringify(errs));

  let malas = 0;
  for (const [bien, d] of ok) { console.log((bien ? "  ok   " : "  FALLA") + " " + d); if (!bien) malas++; }
  console.log(malas ? "\n✗ " + malas + " de " + ok.length + " fallaron" : "\n✓ " + ok.length + " chequeos ok");
  process.exit(malas ? 1 : 0);
})();

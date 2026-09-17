/* Test de regresión (v19.57) — RECEPCIÓN: un proveedor entrega un código que NO está en SU
   orden de compra, pero sí en la de OTRO. Ése es un aviso DISTINTO del de exceso.

   Pedido de Thomas (2026-09-17): *"si pasa que un proveedor entrega mercadería que no le
   corresponde, tiene que avisarme de otra manera... el aviso tiene que llegarme de 'está
   entregando un proveedor algo que no está en su orden de compra', por fuera de que él tiene
   la orden de compra"*.

   El caso testigo es el 550: lo entrega Garcia y la OC está a nombre de Poly, con 155 cajas
   pendientes. Hasta la v19.52 el WhatsApp decía "SIN OC generada (OC = 0)", que es FALSO — la
   OC existe, sólo que no es de Garcia.

   Verifica:
   - `cargarOCAjenas` llena opState.ocAjena SÓLO con los códigos que tienen OC de otro
     (`otros` null = no lo pidió nadie → eso lo sigue cubriendo el aviso de "SIN OC"),
   - el pop-up de cajas dice de quién es la OC, y lo dice TAMBIÉN cuando hay exceso
     (el cartel de exceso no se come la nota),
   - `opExcesoItems` marca el item con `ajena`,
   - el WhatsApp usa el texto nuevo y NO el "SIN OC generada" en ese caso,
   - un código que sí está en la OC del proveedor no queda marcado como ajeno,
   - guard: recepcion.js sigue llamando a la RPC `gv_oc_entrega_ajena` (si alguien la saca,
     el aviso se apaga en silencio y el test tiene que gritar).
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

/* Guards de contrato: si se cae la llamada a la RPC, el aviso deja de existir sin ruido. */
if (!/gv_oc_entrega_ajena/.test(src)) {
  console.error("rcp-oc-ajena: recepcion.js ya no llama a gv_oc_entrega_ajena — el aviso de entrega ajena quedó apagado.");
  process.exit(1);
}
if (!/window\.supabase/.test(src)) {
  console.error("rcp-oc-ajena: recepcion.js ya no toma createClient de window.supabase — actualizá el stub.");
  process.exit(1);
}

const FAKE_CLIENT = `
const __fake = { ocs: [], ajenas: [] };
window.__fakeOcs = function (rows) { __fake.ocs = rows; };
window.__fakeAjenas = function (rows) { __fake.ajenas = rows; };
window.__rpcCalls = [];
function __q(table) {
  const o = {};
  ["select","gte","lte","eq","neq","in","not","or","ilike","order","limit","single","update","delete","insert"]
    .forEach(function (m) { o[m] = function () { return o; }; });
  o.then = function (res, rej) { return Promise.resolve({ data: [], error: null }).then(res, rej); };
  return o;
}
window.supabase = { createClient: function () {
  return {
    from: __q,
    rpc: function (fn, args) {
      window.__rpcCalls.push({ fn: fn, args: args });
      if (fn === "oc_vigentes_por_proveedor") return Promise.resolve({ data: __fake.ocs, error: null });
      if (fn === "gv_oc_entrega_ajena") return Promise.resolve({ data: __fake.ajenas, error: null });
      return Promise.resolve({ data: null, error: null });
    },
    auth: {
      getSession: function () { return Promise.resolve({ data: { session: { fake: true } } }); },
      signInAnonymously: function () { return Promise.resolve({ data: { session: { fake: true } }, error: null }); }
    }
  };
} };
`;

const patched = src + `
window.__rcp = { opState: opState,
  cargarOCVigentes: cargarOCVigentes, cargarOCAjenas: cargarOCAjenas, ocAjenaDe: ocAjenaDe,
  openCajas: openCajas, renderResumen: renderResumen, opExcesoItems: opExcesoItems,
  el: { body: opBody, cajasInput: opCajasInput, cajasOc: opCajasOc } };
`;

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.setContent('<!doctype html><meta charset="utf-8"><body><script>' + FAKE_CLIENT + '<\/script><script type="module">' + patched + "<\/script></body>");
  await p.waitForFunction(() => !!window.__rcp, null, { timeout: 10000 });

  const r = await p.evaluate(async () => {
    const R = window.__rcp, S = R.opState, out = {};
    window.__wa = [];
    window.open = function (url) { window.__wa.push(url); return { closed: false }; };

    // Garcia entrega: tiene OC propia del 437E, y entrega 550 (de Poly) y 999 (de nadie).
    window.__fakeOcs([{ cod: "437E", fecha: "2026-09-10", ped: 30, rec: 0, pend: 30 }]);
    window.__fakeAjenas([
      { cod: "550", otros: "Poly", pend_otros: 155, fecha_otra: "2026-09-16", prov_config: "Poly" },
      { cod: "999", otros: null,   pend_otros: 0,   fecha_otra: null,         prov_config: null }
    ]);
    S.tipo = "tallerista"; S.tallNombre = "Garcia"; S.linea = "LK"; S.fecha = "2026-09-17";
    S.remito = "37842"; S.cargas = {}; S.ocPorCod = null; S.ocAjena = null;
    S.excesoAvisado = null; S.fotoFile = null;
    await R.cargarOCVigentes();
    await R.cargarOCAjenas(["437E", "550", "999"]);

    // ---- 1) sólo entra la que tiene OC de OTRO ----
    out.ajenaCargada = !!R.ocAjenaDe("550") && R.ocAjenaDe("550").otros === "Poly"
      && R.ocAjenaDe("550").pend === 155;
    out.sinOcDeNadieNoEsAjena = R.ocAjenaDe("999") === null;   // `otros` null → no es ajena
    out.propiaNoEsAjena = R.ocAjenaDe("437E") === null;
    // y el código normalizado también resuelve (0550 → 550)
    out.normaliza = !!R.ocAjenaDe("0550");

    // ---- 2) el pop-up dice de quién es la OC ----
    R.openCajas("550");
    const t1 = R.el.cajasOc.textContent;
    out.popupDiceDeQuienEs = t1.indexOf("no está en la OC de") >= 0 && t1.indexOf("Poly") >= 0;
    // con exceso encima, la nota de ajena NO se pierde
    R.el.cajasInput.value = "11";
    R.el.cajasInput.oninput();
    const t2 = R.el.cajasOc.textContent;
    out.conExcesoSigueLaNota = t2.indexOf("Poly") >= 0 && t2.indexOf("más mercadería") >= 0;
    // un código con OC propia no muestra la nota
    R.openCajas("437E");
    out.propiaSinNota = R.el.cajasOc.textContent.indexOf("no está en la OC de") < 0;

    // ---- 3) el item queda marcado como ajeno ----
    S.cargas = { "550": 11, "999": 25 };
    const items = R.opExcesoItems();
    const i550 = items.filter(function (x) { return x.cod === "550"; })[0];
    const i999 = items.filter(function (x) { return x.cod === "999"; })[0];
    out.itemMarcado = !!i550 && !!i550.ajena && i550.ajena.otros === "Poly";
    out.itemSinOcNoAjeno = !!i999 && !i999.ajena && i999.sinOc === true;

    // ---- 4) el WhatsApp lo dice bien, y no miente con "SIN OC generada" ----
    S.fotoFile = { fake: true };
    R.renderResumen();
    document.getElementById("opExcWa").click();
    const url = decodeURIComponent(window.__wa[0] || "");
    out.waTitulo = url.indexOf("no está en su orden de compra") > 0;
    out.waLinea550 = url.indexOf("550: recibo 11, NO está en la OC de Garcia") > 0
      && url.indexOf("la OC es de Poly (155 pendientes)") > 0;
    // el 550 ya NO sale como "SIN OC generada"; el 999, que de verdad no tiene OC, sí
    const antes = url.indexOf("• 550"), corte = url.indexOf("• 999");
    out.no550SinOc = url.slice(antes, corte).indexOf("SIN OC generada") < 0;
    out.si999SinOc = url.slice(corte).indexOf("SIN OC generada (OC = 0)") >= 0;

    // ---- 5) la RPC se llamó con el proveedor y los códigos ----
    const c = window.__rpcCalls.filter(function (x) { return x.fn === "gv_oc_entrega_ajena"; })[0];
    out.rpcLlamada = !!c && c.args.p_nombre === "Garcia" && c.args.p_cods.indexOf("550") >= 0;

    // ---- 6) si la RPC falla, no se afirma nada (queda {} y el resto funciona) ----
    S.ocAjena = null;
    window.__fakeAjenas(null);
    await R.cargarOCAjenas(["550"]);
    out.rpcCaidaNoAfirma = R.ocAjenaDe("550") === null && R.opExcesoItems().length === 2;

    return out;
  });

  await b.close();
  const fail = [];
  Object.keys(r).forEach(function (k) { if (r[k] !== true) fail.push(k + "=" + JSON.stringify(r[k])); });
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  if (fail.length) { console.error("rcp-oc-ajena: FALLÓ →", fail.join(", ")); process.exit(1); }
  console.log("rcp-oc-ajena: OK — el aviso distingue \"no está en SU OC\" de \"no hay OC de nadie\"");
  process.exit(0);
})();

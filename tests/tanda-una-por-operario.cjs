/* Regresión v18.73 — UNA tanda abierta por operario y fase. Pedido de Luis, 16/09:
   "ningún operario puede arrancar a pickear una tanda si ya tiene una abierta (y lo mismo
   con armado)".

   Lo que había: la v18.65 cerró "dos operarios en LA MISMA tanda" (el lock es por
   (tanda, fase) y gana el primero). El caso inverso —UN operario con DOS tandas— vivía sólo
   en el front y era un `confirm()` con "Aceptar = arrancar igual", o sea que dejar la tanda
   vieja colgada estaba a un toque. De ahí salieron E11B (leg 237: AP 11:15, arrancó E01C
   13:44), el picking de E25A y el armado de E23A. Y como el guard mira `getLegajoState`
   (localStorage), un celular que perdió el estado no avisaba nada.

   Chequea:
     1) que el front NO ofrezca más "arrancar igual" — ni confirm ni rama que siga de largo;
     2) en vivo, que con otra tanda abierta el EP/AP se CORTE, diga cuál es y cómo soltarla,
        y que reabra la vieja en vez de dejar al operario en la nada;
     3) que el motivo del backend ('otra_tanda_abierta') esté contemplado — es el que llega
        cuando el celular perdió el estado local, que es justo el caso que el front no ve;
     4) que la MISMA tanda siga reabriéndose (no es un bloqueo, es continuar);
     5) que siga fallando ABIERTO: sin red no bloquea a nadie.

   El invariante de verdad lo garantiza `gv_tanda_reservar` en el backend
   (sql/gv_tanda_reservar_una_por_operario_v1873.sql), probado contra la base; esto cuida
   que el front no lo contradiga. Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");

const fallas = [];

// ---- 1 y 3) estático ----
if (!src.includes("otra_tanda_abierta")) {
  fallas.push("el front no contempla el motivo 'otra_tanda_abierta' del backend");
}
/* El confirm que dejaba arrancar igual. Se busca la LLAMADA, no el texto suelto: buscar
   «Aceptar = arrancar» a secas matchea el comentario que explica por qué ya no está. */
const reConfirmViejo = /confirm\(\s*"[^"]{0,60}Ten[eé]s el (picking|armado) de la tanda/;
if (reConfirmViejo.test(src)) {
  fallas.push("sigue el confirm «Tenés el picking/armado … Aceptar = arrancar igual»: dejar " +
    "la tanda vieja colgada vuelve a estar a un toque");
}
if (fallas.length) {
  console.log("tanda-una-por-operario: ✗ FAIL\n  - " + fallas.join("\n  - "));
  process.exit(1);
}

let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log("tanda-una-por-operario: estático ✓ OK (sin Playwright para la parte en vivo)"); process.exit(0); }
}

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    const avisos = [];
    let reabrio = null;
    let respuesta = { ok: true, motivo: "propia", legajo: "77" };

    const realAlert = window.alert, realConfirm = window.confirm, realFetch = window.fetch;
    window.alert   = (m) => avisos.push(String(m));
    window.confirm = () => { avisos.push("__CONFIRM__"); return true; };
    window.fetch = function (url, opts) {
      const u = String(url);
      if (/\/rpc\/gv_tanda_/.test(u)) {
        return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(respuesta) });
      }
      return Promise.resolve({ ok: true, status: 200,
        headers: { get: () => "0-0/0" }, json: () => Promise.resolve([]) });
    };
    // espiamos a dónde nos manda después de cortar
    const realPick = window.showPickingList, realWiz = window.showCompletarWizard;
    window.showPickingList     = (t) => { reabrio = "picking:" + t; };
    window.showCompletarWizard = (l, t) => { reabrio = "armado:" + t; };

    /* deja al legajo 77 con UNA tanda abierta en la fase pedida y toca OTRA */
    const conAbierta = async (fase, abierta, nueva) => {
      const st = getLegajoState("77");
      st.picking = { active: false, value: "", ts_inicio: null };
      st.armado  = { active: false, value: "", ts_inicio: null };
      st[fase === "EP" ? "picking" : "armado"] =
        { active: true, value: abierta, ts_inicio: new Date(Date.now() - 2 * 3600 * 1000).toISOString() };
      setLegajoState("77", st);
      legajoInput.value = "77"; textInput.value = nueva; selected = fase;
      avisos.length = 0; reabrio = null;
      await send();
    };

    // ---- 2) picking: corta, no pregunta ----
    await conAbierta("EP", "E25A", "E30A");
    out.pickCorta        = avisos.length === 1 && /⛔/.test(avisos[0]);
    out.pickNoPregunta   = !avisos.includes("__CONFIRM__");
    out.pickDiceCual     = /E25A/.test(avisos[0] || "");
    out.pickDiceComo     = /Anular picking/i.test(avisos[0] || "");
    out.pickReabreVieja  = reabrio === "picking:E25A";

    // ---- 2b) armado: igual, con su propio botón ----
    await conAbierta("AP", "E11C", "E30A");
    out.armCorta         = avisos.length === 1 && /⛔/.test(avisos[0]);
    out.armNoPregunta    = !avisos.includes("__CONFIRM__");
    out.armDiceCual      = /E11C/.test(avisos[0] || "");
    out.armDiceComo      = /No la armo yo/i.test(avisos[0] || "");
    out.armReabreVieja   = reabrio === "armado:E11C";

    // ---- 4) la MISMA tanda se reabre (continuar no es bloquear) ----
    await conAbierta("EP", "E25A", "E25A");
    out.mismaSeReabre    = reabrio === "picking:E25A" && !/⛔/.test(avisos[0] || "");

    // ---- 3) el motivo del backend, con el estado local LIMPIO (celular que lo perdió) ----
    const limpio = async (fase, nueva) => {
      const st = getLegajoState("77");
      st.picking = { active: false, value: "", ts_inicio: null };
      st.armado  = { active: false, value: "", ts_inicio: null };
      setLegajoState("77", st);
      legajoInput.value = "77"; textInput.value = nueva; selected = fase;
      avisos.length = 0; reabrio = null;
      await send();
    };
    respuesta = { ok: false, motivo: "otra_tanda_abierta", tanda_abierta: "E11D", legajo: "77" };
    await limpio("EP", "E30A");
    out.backendCorta     = avisos.length === 1 && /⛔/.test(avisos[0]);
    out.backendDiceCual  = /E11D/.test(avisos[0] || "");
    out.backendDiceComo  = /Anular picking/i.test(avisos[0] || "");

    // ---- 5) sin red no bloquea ----
    window.fetch = function () { return Promise.reject(new Error("sin red")); };
    await limpio("EP", "E31A");
    out.sinRedNoBloquea  = !avisos.some((m) => /⛔/.test(m));

    window.alert = realAlert; window.confirm = realConfirm; window.fetch = realFetch;
    window.showPickingList = realPick; window.showCompletarWizard = realWiz;
    return out;
  });
  const malas = Object.keys(r).filter((k) => !r[k]);
  const pass = malas.length === 0 && errs.length === 0;
  console.log("tanda-una-por-operario:", JSON.stringify(r),
    malas.length ? "· fallan: " + malas.join(", ") : "",
    "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();

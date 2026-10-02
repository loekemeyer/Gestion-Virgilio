/* v26.04 (02/10) — «Deuda a cobrar / Cobranzas» y «Cobranzas (nuevo)» son UNA pantalla.
   Pedido: "integrá los dos submódulos en «Cobranzas»; las pestañas de Cobranzas son lo principal,
   agregale las del otro pero ponelas después".
   Corre la pantalla de verdad (RPC interceptadas, sin red) y mide:
     (a) el panel supervisor tiene UN botón «Cobranzas» (openCobranzas) y ninguno que abra openCobros();
     (b) la botonera: Clientes y Conciliación primero, las 7 viejas DESPUÉS, con su rayita separadora;
     (c) tocar una pestaña vieja (🕵 Agente) la dibuja adentro de la pantalla nueva y pide su RPC;
     (d) un cbzRender posterior (lo llama cbzCargarClientes al terminar de leer) NO rehace la pestaña
         vieja: el filtro que tipeó el supervisor sigue ahí;
     (e) openCobros('cruce') — el botón «🔍 Cruce con ISIS» de Facturación — abre la pantalla nueva en
         esa pestaña, y cobrosSetTab('banco') cambia de pestaña en ella (no abre otra pantalla);
     (f) volver a Clientes y otra vez a una vieja anda;
     (g) si cobranzas.js no estuviera, openCobros cae a la pantalla vieja de siempre.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 800 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {}; const calls = [];
    const sleep = (ms) => new Promise((res) => setTimeout(res, ms));
    window.alert = function () {}; window.confirm = function () { return true; };
    window.__isSupervisor = true; window.requireSupervisor = function () { return true; };
    window.fetch = async (url, opt) => {
      const u = String(url); const m = /\/rpc\/([a-z_]+)/.exec(u);
      const ok = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => null } });
      if (m) { calls.push(m[1]); return ok([]); }
      return ok([]);
    };

    // (a) un solo botón
    const sup = Array.from(document.querySelectorAll(".sup-action-btn"));
    out.btnNuevo = sup.filter((x) => /openCobranzas\(\)/.test(x.getAttribute("onclick") || "")).map((x) => x.textContent.trim());
    out.btnViejo = sup.filter((x) => /openCobros\(\)/.test(x.getAttribute("onclick") || "")).length;

    // (b) botonera
    await openCobranzas();
    await sleep(300);
    out.tabs = Array.from(document.querySelectorAll("#cbzTabs .cbz-tab")).map((x) => x.getAttribute("data-tab"));
    const sep = document.querySelector("#cbzTabs .cbz-tsep");
    out.sepAntesDeCC = !!sep && sep.nextElementSibling && sep.nextElementSibling.getAttribute("data-tab") === "cc";

    // (c) pestaña vieja adentro de la nueva
    calls.length = 0;
    document.querySelector('#cbzTabs .cbz-tab[data-tab="agente"]').click();
    await sleep(200);
    const wrap = document.getElementById("cbzWrap");
    out.agEnWrap = !!(wrap && wrap.querySelector("#cobrosBody #agTabla"));
    out.pidioAgente = calls.indexOf("gv_cobranza_agente_resumen") >= 0;
    out.activa = (document.querySelector("#cbzTabs .cbz-tab.on") || {}).getAttribute ? document.querySelector("#cbzTabs .cbz-tab.on").getAttribute("data-tab") : null;
    out.viejoAbierto = !!document.getElementById("cobrosOverlay");

    // (d) un cbzRender posterior no rehace la pestaña (no pierde el filtro)
    const inp = document.getElementById("agQ"); if (inp) inp.value = "torres";
    calls.length = 0;
    cbzRender();
    await sleep(100);
    out.filtroQueda = (document.getElementById("agQ") || {}).value === "torres";
    out.mismoInput = document.getElementById("agQ") === inp;
    out.noRepidio = calls.indexOf("gv_cobranza_agente_resumen") < 0;

    // (e) la puerta vieja abre la nueva en la pestaña pedida
    cbzClose();
    await openCobros("cruce");
    await sleep(200);
    out.cruceActiva = (document.querySelector("#cbzTabs .cbz-tab.on") || { getAttribute: () => null }).getAttribute("data-tab");
    out.cruceTabla = !!document.querySelector("#cbzWrap #cruceTabla");
    cobrosSetTab("banco");
    await sleep(200);
    out.bancoActiva = (document.querySelector("#cbzTabs .cbz-tab.on") || { getAttribute: () => null }).getAttribute("data-tab");
    out.bancoTabla = !!document.querySelector("#cbzWrap #bkTabla");
    out.viejoAbierto2 = !!document.getElementById("cobrosOverlay");

    // (f) ida y vuelta
    cbzSetTab("clientes");
    await sleep(100);
    out.clientesSinViejo = !document.getElementById("cobrosBody") && !!document.getElementById("cbzQ");
    cbzSetTab("deuda");
    await sleep(200);
    out.deudaTabla = !!document.querySelector("#cbzWrap #deudaTabla");

    // (g) sin cobranzas.js → la pantalla vieja
    // sin cobranzas.js tampoco existiría su pantalla: se saca, o su #cobrosBody escondido se lleva el dibujo
    const cbzOv = document.getElementById("cbzOv"); if (cbzOv) cbzOv.remove();
    const guard = window.cbzSetTab; window.cbzSetTab = undefined;
    await openCobros("agente");
    await sleep(200);
    const ov = document.getElementById("cobrosOverlay");
    out.fallback = !!ov && ov.style.display === "flex" && !!document.querySelector("#cobrosOverlay #agTabla");
    window.cbzSetTab = guard;
    return out;
  });
  await b.close();

  const f = [];
  const q = (c, m) => { if (!c) f.push(m); };
  q(r.btnNuevo.length === 1 && /^💳\s*Cobranzas$/.test(r.btnNuevo[0]), "(a) tiene que haber UN botón «Cobranzas»: " + JSON.stringify(r.btnNuevo));
  q(r.btnViejo === 0, "(a) sigue el botón viejo «Deuda a cobrar / Cobranzas»");
  q(JSON.stringify(r.tabs) === JSON.stringify(["clientes", "conc", "escalones", "cc", "deuda", "cob", "cruce", "anticipado", "agente", "banco"]),
    "(b) orden de pestañas: " + JSON.stringify(r.tabs));
  q(r.sepAntesDeCC, "(b) falta la rayita que separa las propias de las viejas");
  q(r.agEnWrap, "(c) Agente no se dibujó adentro de la pantalla nueva");
  q(r.pidioAgente, "(c) Agente no pidió gv_cobranza_agente_resumen");
  q(r.activa === "agente", "(c) la pestaña activa no es Agente: " + r.activa);
  q(!r.viejoAbierto && !r.viejoAbierto2, "(c/e) se abrió la pantalla vieja aparte");
  q(r.filtroQueda && r.mismoInput, "(d) un cbzRender rehízo la pestaña vieja y borró el filtro");
  q(r.noRepidio, "(d) un cbzRender volvió a pedir el Agente a la base");
  q(r.cruceActiva === "cruce" && r.cruceTabla, "(e) openCobros('cruce') no abrió la pantalla nueva en cruce: " + r.cruceActiva);
  q(r.bancoActiva === "banco" && r.bancoTabla, "(e) cobrosSetTab('banco') no cambió de pestaña en la nueva: " + r.bancoActiva);
  q(r.clientesSinViejo, "(f) volver a Clientes no limpió la pestaña vieja");
  q(r.deudaTabla, "(f) volver a una vieja (Facturas ISIS) no la dibujó");
  q(r.fallback, "(g) sin cobranzas.js, openCobros no cayó a la pantalla vieja");
  if (errs.length) f.push("errores JS: " + errs.join(" | "));
  if (f.length) { console.error("FALLA cbz-integra-cobros:\n  " + f.join("\n  ")); process.exit(1); }
  console.log("OK cbz-integra-cobros: un solo botón Cobranzas; Clientes y Conciliación primero y las 7 viejas después; la vieja se dibuja adentro, no pierde el filtro, Facturación sigue abriendo cruce y sin cobranzas.js cae a la pantalla vieja.");
})();

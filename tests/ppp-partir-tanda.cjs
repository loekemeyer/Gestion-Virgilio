/* v25.77 (Luis, 2026-10-01) — «✂ PARTIR TANDA» desde «🔧 Modificar tanda».
   El botón de la fila de la tanda abre «Modificar tanda»; «Partir tanda» muestra las NP con
   checkbox y, al tildar algunas y elegir día, las saca a una tanda NUEVA (gv_ppp_web_tanda_codigo_nuevo
   + gv_ppp_nps_mover_a) dejando el resto en la tanda original. Se chequea:
     (a) el submenu tiene «Partir tanda» y abre la lista de NP con checkboxes;
     (b) tildando algunas + día → llama gv_ppp_web_tanda_codigo_nuevo y gv_ppp_nps_mover_a con
         SÓLO las NP tildadas, p_tanda = el código nuevo, p_fecha = el día elegido;
     (c) NO deja sacar TODAS las NP (quedaría la tanda vacía).
   Estado inyectado; no pega contra la red. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
const _d = (n) => { const d = new Date(); d.setHours(12,0,0,0); d.setDate(d.getDate() + n);
  return d.getFullYear() + "-" + String(d.getMonth()+1).padStart(2,"0") + "-" + String(d.getDate()).padStart(2,"0"); };
const F = { hoy: _d(0), d1: _d(1), d2: _d(2) };
F.hoyC = F.hoy.replace(/-/g, ""); F.d1C = F.d1.replace(/-/g, "");
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 1000 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async (F) => {
    const out = {}, rpc = [], confirms = [], alerts = [];
    Object.defineProperty(window, "__isSupervisor", { get: () => true, set: () => {}, configurable: true });
    window.confirm = function (t) { confirms.push(String(t || "")); return true; };
    window.alert = function (t) { alerts.push(String(t || "")); };
    window.getTodayKey = () => F.hoy;
    window.pppSetStatus = function () {};
    window.pppLoadProgFromSupabase = async function () {};
    window._faltMiLegajo = () => "52";
    window.pgaNeed = function () {}; window.patrNeed = function () {};
    window.pgaRecargar = function () {};
    window._pppPlanAgrupar = function () { return { venc: [], byDay: new Map() }; };
    window.pppPaintTabs = function () {};
    _pppParsed = { prog: [{ np: "98630", tanda: "D99Z", fecha_entrega: F.d2, m3: 1.8, cod: "1", razon_social: "Otra", zona: "Zona 2", programmed: true }] };
    window.aprRpc = async function (fn, args) {
      rpc.push({ fn: fn, args: args });
      if (fn === "gv_ppp_web_tanda_codigo_nuevo") return "E99Z";
      if (fn === "gv_ppp_nps_mover_a") return 2;
      return [];
    };
    const mk = (fecha, tanda, np, m3) => ({ fecha: fecha, tanda: tanda, np: np, np_num: 58,
      cod: "2118", razon_social: "Ricci Gabriel", localidad: "CABA", zona: "Zona 2", zona_corta: "Zona 2",
      empresa: "LK", origen: "web", m3: m3, estado: "pendiente", estado_orden: 3, barrio: "Villa Crespo", fecha_pedido: "2026-09-11" });
    _pgaRows = [mk(F.d1, "E01A", "LK 0058", 0.3), mk(F.d1, "E01A", "LK 0059", 0.3), mk(F.d1, "E01A", "LK 0060", 0.3)];
    _pgaTs = Date.now(); _patrRows = []; _patrTs = Date.now();
    const esperar = async function (fn, ms) { const t0 = Date.now();
      while (Date.now() - t0 < (ms || 12000)) { if (fn()) return true; await new Promise((res) => setTimeout(res, 40)); } return false; };
    const filaTanda = function (txt) { const pv = document.getElementById("pppPreview"); if (!pv) return null;
      return [...pv.querySelectorAll("tr.pga-t")].find((x) => x.textContent.indexOf(txt) >= 0) || null; };

    _pppTab = "plan"; _pppPlanTabla = true; _pppPlanDay = null;
    document.getElementById("pppOverlay").classList.add("show");
    pppRenderProg();
    await esperar(() => !!document.querySelector("#pppPreview table.pga"));
    pgaAbrirDia(F.d1C);
    await esperar(() => !!filaTanda("E01A"));
    const bt = filaTanda("E01A") && filaTanda("E01A").querySelector(".pga-acc-b.dia");
    if (!bt) { out.sinBoton = true; return out; }
    bt.click();
    await esperar(() => !!document.querySelector("#pppMovBody .mv-esp-b.nueva"));

    // (a) elegir «Partir tanda»
    const bp = [...document.querySelectorAll("#pppMovBody .mv-esp-b")].find((x) => /Partir tanda/.test(x.textContent));
    out.hayPartir = !!bp;
    if (bp) bp.click();
    out.hayChecks = await esperar(() => document.querySelectorAll("#pppMovBody input[type=checkbox]").length === 3);
    out.hayInputDia = !!document.getElementById("pgaPartirDia");

    // (c) primero: tildar TODAS no deja (quedaría vacía)
    let chks = [...document.querySelectorAll("#pppMovBody input[type=checkbox]")];
    chks.forEach((c) => { if (!c.checked) c.click(); });
    rpc.length = 0; alerts.length = 0;
    let bpc = [...document.querySelectorAll("#pppMovBody .mv-esp-b.nueva")].find((x) => /Partir a tanda nueva/.test(x.textContent));
    if (bpc) bpc.click();
    await esperar(() => alerts.length > 0, 3000);
    out.frenaTodas = rpc.every((x) => x.fn !== "gv_ppp_nps_mover_a") && alerts.some((a) => /TODAS/.test(a));

    // (b) destildar una → tildadas 2 → parte
    chks = [...document.querySelectorAll("#pppMovBody input[type=checkbox]")];
    chks[2].click();   // deja 2 tildadas (LK 0058, LK 0059)
    rpc.length = 0; confirms.length = 0;
    bpc = [...document.querySelectorAll("#pppMovBody .mv-esp-b.nueva")].find((x) => /Partir a tanda nueva/.test(x.textContent));
    if (bpc) bpc.click();
    await esperar(() => rpc.some((x) => x.fn === "gv_ppp_nps_mover_a"), 6000);
    out.pidioCodigoNuevo = rpc.some((x) => x.fn === "gv_ppp_web_tanda_codigo_nuevo");
    const mv = rpc.find((x) => x.fn === "gv_ppp_nps_mover_a");
    out.argMover = mv ? JSON.stringify({ nps: mv.args.p_nps, t: mv.args.p_tanda, f: mv.args.p_fecha }) : "";
    out.movioDosASuNueva = !!mv && Array.isArray(mv.args.p_nps) && mv.args.p_nps.length === 2 &&
      mv.args.p_nps.indexOf("LK 0058") >= 0 && mv.args.p_nps.indexOf("LK 0059") >= 0 &&
      mv.args.p_tanda === "E99Z" && mv.args.p_fecha === F.d1;
    return out;
  }, F);

  const fallas = [];
  const ok = (c, txt, extra) => { console.log((c ? "ok  " : "FALLA") + " " + txt + (extra ? " — " + extra : "")); if (!c) fallas.push(txt); };
  ok(!r.sinBoton, "la fila de la tanda trae el botón Modificar");
  ok(r.hayPartir, "(a) el submenu ofrece «Partir tanda»");
  ok(r.hayChecks, "(a) muestra las 3 NP con checkbox");
  ok(r.hayInputDia, "(a) y un selector de día para la tanda nueva");
  ok(r.frenaTodas, "(c) no deja sacar TODAS las NP (quedaría vacía)");
  ok(r.pidioCodigoNuevo, "(b) pide un código de tanda nuevo (gv_ppp_web_tanda_codigo_nuevo)");
  ok(r.movioDosASuNueva, "(b) mueve SÓLO las 2 tildadas a la tanda nueva, en el día elegido", r.argMover);
  ok(errs.length === 0, "sin errores de página", errs.join(" | "));

  await b.close();
  if (fallas.length) { console.error("\nppp-partir-tanda: " + fallas.length + " falla(s)."); process.exit(1); }
  console.log("\nppp-partir-tanda OK");
})();

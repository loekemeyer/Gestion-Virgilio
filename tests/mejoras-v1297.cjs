/* Regresión v12.97 — tres mejoras chicas del backlog de agentes:
   (4210) rcConfirm con doble tap pasaba las cajas DOS veces (doble stock, doble lío):
          ahora un flag en _rc frena el segundo toque → stockMove se llama UNA vez.
   (8818) fetchMonitorDayStats sumaba las horas de CADA TP/TAP aunque el m³ de la tanda
          se contara una vez: dos TP de la misma tanda daban el doble de horas y la mitad
          de m³/h en Premios → ahora el tiempo se acredita una vez por tanda.
   (2359) populateTandasList resalta el grupo de HOY con un badge. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const J = (data) => Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(data), text: () => Promise.resolve(JSON.stringify(data)),
      headers: { get: () => null } });

    // ── (4210) doble tap en rcConfirm ────────────────────────────────────────
    let stockCalls = 0, rpcCalls = 0;
    window.fetch = (url, opts) => { if (String(url).indexOf("reasignar_cajas") >= 0) rpcCalls++; return J([]); };
    window.stockMove = async () => { stockCalls++; await new Promise((res) => setTimeout(res, 30)); };
    window.rcAddToLio = async () => {}; window.rcRemoveFromLio = async () => {};
    window.rcEmitEvent = () => {}; window.updatePendingIndicator = () => {}; window.opDraftClear = () => {};
    window.cpLoadFaltantes = async () => []; window.rcRender = () => {};
    _rc = { legajo: "55", sel: { id: 1, np: "98001", cod_art: "027", tanda: "D01A" }, donors: [{ type: "pickeado", id: 2, np: "98002", tanda: "D02A" }], donorSel: 0, qty: 1 };
    await Promise.all([rcConfirm(), rcConfirm()]);
    out.rcStock = stockCalls; out.rcRpc = rpcCalls; out.rcBusyLiberado = _rc && _rc._busy === false;

    // ── (8818) horas una vez por tanda ────────────────────────────────────────
    const day = "2026-06-16";
    const T0 = new Date(day + "T08:00:00-03:00").getTime();
    const iso = (ms) => new Date(ms).toISOString();
    const evs = [
      { legajo: "55", opcion: "TP",  texto: "A1", ts_inicio: iso(T0),               ts_cliente: iso(T0 + 3600000) },
      { legajo: "55", opcion: "TP",  texto: "A1", ts_inicio: iso(T0 + 2 * 3600000), ts_cliente: iso(T0 + 3 * 3600000) },   // la misma tanda cerrada dos veces
      { legajo: "55", opcion: "TAP", texto: "A2", ts_inicio: iso(T0 + 4 * 3600000), ts_cliente: iso(T0 + 5 * 3600000) }
    ];
    window.fetch = (url) => {
      const u = String(url);
      if (u.indexOf("opcion=eq.FJ") >= 0) return J([]);
      if (u.indexOf(SUPABASE_FICHADAS_ENDPOINT) >= 0) return J([]);
      if (u.indexOf(SUPABASE_TABLE_ENDPOINT) >= 0) return J(evs);
      return J([]);
    };
    window.getEmpleadosNombres = async () => new Map();
    window.getHistoricMap = async () => new Map();
    try {
      const st = await fetchMonitorDayStats(day, new Map());
      const ops = (st && (st.perOperario || st.operarios)) || [];
      const o = ops.find((x) => String(x.legajo) === "55") || {};
      out.pickH = o.pickH; out.armH = o.armH; out.pickDetalles = (o.pickedDetail || []).length;
    } catch (e) { out.statsErr = String(e && e.message || e); }

    // ── (2359) badge HOY ──────────────────────────────────────────────────────
    const hoy = getTodayKey();
    const otro = "2031-01-15";
    window.getPppTandasForOperator = async () => [
      { tanda: "H01A", opIsSi: true, fechaRaw: hoy,  fechaDisplay: "hoy dd/mm", prioridad: 0, agregados: [] },
      { tanda: "H02A", opIsSi: true, fechaRaw: otro, fechaDisplay: "15/01/2031", prioridad: 0, agregados: [] }
    ];
    let box = document.getElementById("tandasList");
    if (!box) { box = document.createElement("div"); box.id = "tandasList"; document.body.appendChild(box); }
    await populateTandasList("all");
    const html = box.innerHTML;
    const win = (s) => { const i = html.indexOf(s); return i < 0 ? "" : html.slice(Math.max(0, i - 200), i + 60); };
    const gHoy  = win("hoy dd/mm");
    const gOtro = win("15/01/2031");
    out.hoyBadge  = html.indexOf("hoy dd/mm") >= 0 && gHoy.indexOf('tandas-day-group hoy') >= 0 && html.indexOf("tandas-hoy-badge") >= 0;
    out.otroSin   = html.indexOf("15/01/2031") >= 0 && gOtro.indexOf('tandas-day-group hoy') < 0;
    out.chips     = html.indexOf('data-code="H01A"') >= 0 && html.indexOf('data-code="H02A"') >= 0;
    return out;
  });

  const checks = [
    ["4210: doble tap → stockMove UNA vez",                     r.rcStock === 1],
    ["4210: y la RPC reasignar_cajas UNA vez",                  r.rcRpc === 1],
    ["4210: el candado se libera al terminar",                  r.rcBusyLiberado === true],
    ["8818: dos TP de la misma tanda → 1 h de picking, no 2",   Math.abs((r.pickH || 0) - 1) < 0.01],
    ["8818: el TAP se acredita normal (1 h)",                   Math.abs((r.armH || 0) - 1) < 0.01],
    ["8818: el popup sigue listando los dos cierres",           r.pickDetalles === 2],
    ["2359: el grupo de HOY lleva la clase y el badge",         r.hoyBadge === true],
    ["2359: el otro día no",                                    r.otroSin === true],
    ["2359: los chips se siguen dibujando",                     r.chips === true],
    ["sin errores de página",                                   errs.length === 0]
  ];
  let bad = 0;
  for (const [name, ok] of checks) { console.log((ok ? "  ok   " : "  FALLA") + " · " + name); if (!ok) bad++; }
  if (bad) console.log("  detalle:", JSON.stringify(r));
  if (errs.length) console.log("  pageerror: " + errs.join(" | "));
  console.log(bad ? "mejoras-v1297: " + bad + " FALLA(S)" : "mejoras-v1297: OK (" + checks.length + " chequeos)");
  await b.close();
  process.exit(bad ? 1 : 0);
})();

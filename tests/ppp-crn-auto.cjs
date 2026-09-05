/* Regresión (v12.95): CONTROL DE REMITO = PEDIDO ENTREGADO, SOLO.

   Regla del dueño (2026-09-05): "cuando ya el pedido se controla el remito, ya tiene que
   pasar directamente a Pedidos Entregados, sin que nadie toque nada. Hoy en Producción
   requiere corregir el Excel para que se corrija el espejo (la PPP). En Gestión tiene que
   ser automático."

   Fuente durable: la vista gv_ppp_entregados (toda NP con CRN, sql/gv_ppp_entregados.sql).
   Verifica que, con la NP 98001 en la vista y la 98002 no, y SIN nada en localStorage ni
   en la vista de facturados:
   (a) Programación esconde la 98001 y muestra la 98002,
   (b) Pedidos Entregados muestra la 98001 aunque no esté facturada ni cerrada,
   (c) la 98001 no cae en "En Salida" (está confirmada por el CRN),
   (d) el panel de errores no marca "🚮 SACAR" (en Gestión no hay Excel que corregir). */
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
    try { localStorage.clear(); } catch (_e) {}
    const J = (data) => {
      const n = Array.isArray(data) ? data.length : 0;
      return Promise.resolve({ ok: true, status: 200,
        headers: { get: (h) => String(h).toLowerCase() === "content-range" ? ("0-" + Math.max(0, n - 1) + "/" + n) : null },
        json: () => Promise.resolve(data), text: () => Promise.resolve(JSON.stringify(data)) });
    };
    window.fetch = (url) => {
      const u = String(url);
      if (u.indexOf("gv_ppp_programacion_diaria") >= 0) return J([
        { np: "98001", tanda: "D01A", tipo: "", fecha_recep: "2026-09-01", cod: "1111", razon_social: "Uno SA", m3: 0.4, direccion: "Calle 1", barrio: "Mataderos", fecha_entrega: "2026-09-04", zona: "Zona 1" },
        { np: "98002", tanda: "D01A", tipo: "", fecha_recep: "2026-09-01", cod: "2222", razon_social: "Dos SA", m3: 0.3, direccion: "Calle 2", barrio: "Mataderos", fecha_entrega: "2026-09-04", zona: "Zona 1" }
      ]);
      if (u.indexOf("ppp_entregados_meta") >= 0) return J([]);
      if (u.indexOf("gv_ppp_entregados") >= 0) return J([
        { np: "98001", empresa: "lk", es_web: false, tanda: "D01A", cod_cliente: "1111", razon_social: "Uno SA", m3: 0.4, fecha_entrega: "2026-09-04", fecha_carga: "2026-09-04", controlado_at: "2026-09-04T15:00:00Z", n_crn: 1, cajas_entregadas: 3, cajas_falto: 0, facturada: false }
      ]);
      return J([]);   // vista_ppp_pedidos_entregados vacía, PPP_Web_Programacion vacía, eventos vacíos
    };
    window._pppEmitError = function () {};
    await pppLoadProgFromSupabase();
    await pppRefreshControlado();
    await pppRefreshMetaEntSet();
    await pppRefreshDelivered();
    _pppPlanClasica = true; _pppTab = "plan"; pppRenderProg();
    let html = document.body.innerHTML;
    out.plan98001 = html.indexOf('id="ppprow_98001"') >= 0;
    out.plan98002 = html.indexOf('id="ppprow_98002"') >= 0;
    out.sacar = html.indexOf('class="ppp-err-sacar"') >= 0;   // la fila con badge 🚮 SACAR
    _pppTab = "ent"; pppRenderProg();
    html = document.body.innerHTML;
    const ent = _pppSplitDelivered();
    out.entregados = ent.entregados.map((x) => x.np).join(",");
    out.enViaje    = ent.enViaje.map((x) => x.np).join(",");
    out.ent98001   = html.indexOf("98001") >= 0;
    out.controlado = _pppControladoCR && _pppControladoCR.has("98001");
    out.conf       = _pppConfirmadas().has("98001");
    return out;
  });

  const checks = [
    ["Programación esconde la NP controlada (98001)",              r.plan98001 === false],
    ["y sigue mostrando la no controlada (98002)",                 r.plan98002 === true],
    ["sin badge SACAR (no hay Excel que corregir)",                r.sacar === false],
    ["el CRN se lee de la vista (sin ventana de 60 días)",         r.controlado === true],
    ["y cuenta como confirmada",                                   r.conf === true],
    ["Pedidos Entregados la lista aunque no esté facturada",       r.entregados === "98001"],
    ["y no cae en En Salida",                                      r.enViaje === ""],
    ["se ve en la solapa Entregados",                              r.ent98001 === true],
    ["sin errores de página",                                      errs.length === 0]
  ];
  let bad = 0;
  for (const [name, ok] of checks) { console.log((ok ? "  ok   " : "  FALLA") + " · " + name); if (!ok) bad++; }
  if (bad) console.log("  detalle:", JSON.stringify(r));
  if (errs.length) console.log("  pageerror: " + errs.join(" | "));
  console.log(bad ? "ppp-crn-auto: " + bad + " FALLA(S)" : "ppp-crn-auto: OK (" + checks.length + " chequeos)");
  await b.close();
  process.exit(bad ? 1 : 0);
})();

/* Regresión (v13.02, idea 4459): CARGADO AL CAMIÓN = EN SALIDA.
   Regla del dueño: "si hay pedidos que ya se cargaron a un camión, tienen que salir de la
   Programación y pasar a En Salida, y no verse más en Programación".
   Fuente: gv_ppp_en_salida (NP con CCN, sin CRN, sin FSS posterior).
   Fixture: 98001 controlada (CRN), 98002 cargada sin CRN, 98003 sin nada.
   (a) Programación muestra sólo la 98003, (b) En Salida lista la 98002 (y no la 98001 ni la
   98003), (c) Pedidos Entregados lista la 98001, (d) la cargada vencida lleva SIN CONTROLAR
   en En Salida, (e) con la vista vacía En Salida queda vacía (no vuelven los facturados sin cargar). */
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
    const mk = (np, rs) => ({ np, tanda: "D01A", tipo: "", fecha_recep: "2026-09-01", cod: "1" + np.slice(-3), razon_social: rs, m3: 0.3, direccion: "Calle " + np, barrio: "Mataderos", fecha_entrega: "2026-09-04", zona: "Zona 1" });
    let salida = [{ np: "98002", empresa: "lk", es_web: false, tanda: "D01A", cod_cliente: "1002", razon_social: "Dos SA", m3: 0.3, fecha_entrega: "2026-09-04", zona: "Zona 1", barrio: "Mataderos", fecha_carga: "2026-09-04", cargado_at: "2026-09-04T12:00:00Z", facturada: true }];
    window.fetch = (url) => {
      const u = String(url);
      if (u.indexOf("gv_ppp_programacion_diaria") >= 0) return J([mk("98001", "Uno SA"), mk("98002", "Dos SA"), mk("98003", "Tres SA")]);
      if (u.indexOf("ppp_entregados_meta") >= 0) return J([]);
      if (u.indexOf("gv_ppp_en_salida") >= 0) return J(salida);
      if (u.indexOf("gv_ppp_entregados") >= 0) return J([
        { np: "98001", empresa: "lk", es_web: false, tanda: "D01A", cod_cliente: "1001", razon_social: "Uno SA", m3: 0.3, fecha_entrega: "2026-09-04", fecha_carga: "2026-09-04", controlado_at: "2026-09-04T15:00:00Z", n_crn: 1, cajas_entregadas: 3, cajas_falto: 0, facturada: false }
      ]);
      return J([]);
    };
    window._pppEmitError = function () {};
    await pppLoadProgFromSupabase();
    await pppRefreshControlado();
    await pppRefreshMetaEntSet();
    await pppRefreshDelivered();
    await pppRefreshEnSalida();
    // cargada hace 48 h, sin FSS → vencida
    _pppEntregadoCC = new Set(["98002"]); _pppLoadMs = new Map([["98002", Date.now() - 48 * 3600000]]);
    window.crVencido = (ms) => ms > 0 && (Date.now() - ms) > 30 * 3600000;

    _pppTab = "plan"; pppRenderProg();
    let html = document.body.innerHTML;
    out.plan98001 = html.indexOf('id="ppprow_98001"') >= 0;
    out.plan98002 = html.indexOf('id="ppprow_98002"') >= 0;
    out.plan98003 = html.indexOf('id="ppprow_98003"') >= 0;
    out.tabSalida = /En Salida \(1\)/.test(html);
    const sp = _pppSplitDelivered();
    out.enViaje = sp.enViaje.map((x) => x.np).join(",");
    out.entregados = sp.entregados.map((x) => x.np).join(",");
    _pppTab = "enviaje"; pppRenderProg();
    html = document.body.innerHTML;
    out.salidaMuestra98002 = html.indexOf("98002") >= 0 && html.indexOf("Dos SA") >= 0;
    out.salidaBadge = html.indexOf("ppp-cargvenc-badge") >= 0;
    out.salidaNota = html.indexOf("cargaron al camión") >= 0;
    _pppTab = "ent"; pppRenderProg();
    html = document.body.innerHTML;
    out.entMuestra98001 = html.indexOf("98001") >= 0;
    // vista vacía → En Salida vacía, aunque haya facturados sin confirmar
    salida = []; await pppRefreshEnSalida();
    out.vaciaSinCargados = _pppSplitDelivered().enViaje.length === 0;
    _pppTab = "plan"; pppRenderProg();
    out.vuelve98002 = document.body.innerHTML.indexOf('id="ppprow_98002"') >= 0;
    return out;
  });

  const checks = [
    ["Programación esconde la cargada (98002)",                  r.plan98002 === false],
    ["y la controlada (98001)",                                  r.plan98001 === false],
    ["y sigue mostrando la que no salió (98003)",                r.plan98003 === true],
    ["la solapa En Salida cuenta 1",                             r.tabSalida === true],
    ["En Salida = la cargada sin CRN",                           r.enViaje === "98002"],
    ["Entregados = la controlada",                               r.entregados === "98001"],
    ["En Salida la muestra con cliente",                         r.salidaMuestra98002 === true],
    ["y con la pastilla SIN CONTROLAR (vencida)",                r.salidaBadge === true],
    ["y la nota habla de cargado al camión",                     r.salidaNota === true],
    ["Pedidos Entregados muestra la 98001",                      r.entMuestra98001 === true],
    ["sin cargados, En Salida queda vacía",                      r.vaciaSinCargados === true],
    ["y la 98002 vuelve a Programación si la vista no la trae",  r.vuelve98002 === true],
    ["sin errores de página",                                    errs.length === 0]
  ];
  let bad = 0;
  for (const [name, ok] of checks) { console.log((ok ? "  ok   " : "  FALLA") + " · " + name); if (!ok) bad++; }
  if (bad) console.log("  detalle:", JSON.stringify(r));
  if (errs.length) console.log("  pageerror: " + errs.join(" | "));
  console.log(bad ? "ppp-en-salida: " + bad + " FALLA(S)" : "ppp-en-salida: OK (" + checks.length + " chequeos)");
  await b.close();
  process.exit(bad ? 1 : 0);
})();

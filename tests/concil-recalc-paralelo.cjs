/* v22.28 (Luis, 24/09) — «tarda mucho en cargar las facturas en conciliación… sale timeout».
   La lista NO espera el recálculo del cruce NP↔FC (2,5 s, y con la base cargada se iba al corte):
   (a) la lista sale aunque el recálculo tarde (acá: 1,5 s);
   (b) si el recálculo cambió facturas (devuelve > 0), la lista se vuelve a pedir sola;
   (c) si devuelve 0 / -1 / -2, no se vuelve a pedir;
   (d) dos entradas seguidas no disparan dos recálculos a la vez.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const correr = (devuelve) => p.evaluate(async (devuelve) => {
    window.alert = function () {}; window.__isSupervisor = true; window.requireSupervisor = function () { return true; };
    const ev = []; const t0 = Date.now();
    const fila = { np: "98619", empresa: "lk", tanda: "D68A", cod_cliente: "1651", razon_social: "SALVETTI", fecha_salida: "2026-09-08", cajas_ent: 585, neto_gestion: 100, items_sin_precio: 0, registrado_at: "2026-09-08T12:01:00-03:00", factura_neto: 100, factura_cajas: 585, comprobante_id: "X", doc_fecha: "2026-09-08", storage_path: "a.pdf", es_super: false, diff: 0, diff_pct: 0, estado: "ok", neto_actual: 100, corregido: false, total_count: 1 };
    window.fetch = async (url) => {
      const m = /\/rpc\/([a-z_]+)/.exec(String(url));
      const ok = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => null } });
      if (m) {
        ev.push({ fn: m[1], t: Date.now() - t0 });
        if (m[1] === "gv_cruce_fc_asig_refrescar_si_viejo") { await new Promise((r) => setTimeout(r, 1500)); ev.push({ fn: "recalc_fin", t: Date.now() - t0 }); return ok(devuelve); }
        if (m[1] === "gv_conciliacion_lista") return ok([fila]);
        if (m[1] === "gv_conciliacion_totales") return ok([{ estado: "ok", n: 1, suma_diff: 0 }]);
      }
      return ok([]);
    };
    _concil.rows = []; _concil.recalcEnCurso = false;
    facSetTab("concil");
    concilRefresh();            // segunda entrada inmediata (d)
    await new Promise((r) => setTimeout(r, 400));
    const filasAntes = document.querySelectorAll("#concilTabla tbody tr").length;
    await new Promise((r) => setTimeout(r, 2200));
    return { ev, filasAntes };
  }, devuelve);

  const r1 = await correr(3);
  const lista1 = r1.ev.filter((e) => e.fn === "gv_conciliacion_lista");
  const fin1 = r1.ev.find((e) => e.fn === "recalc_fin");
  if (!(r1.filasAntes > 0)) fail("(a) la lista no se dibujó mientras el recálculo seguía corriendo");
  if (!lista1.length || !fin1 || lista1[0].t >= fin1.t) fail("(a) la lista esperó al recálculo: " + JSON.stringify(r1.ev));
  if (!lista1.some((e) => e.t >= fin1.t)) fail("(b) el recálculo cambió facturas y la lista no se volvió a pedir: " + JSON.stringify(r1.ev));
  const recalcs = r1.ev.filter((e) => e.fn === "gv_cruce_fc_asig_refrescar_si_viejo" && e.t < fin1.t).length;
  if (recalcs !== 1) fail("(d) se dispararon " + recalcs + " recálculos a la vez");

  for (const v of [0, -1, -2]) {
    const r = await correr(v);
    const fin = r.ev.find((e) => e.fn === "recalc_fin");
    if (fin && r.ev.some((e) => e.fn === "gv_conciliacion_lista" && e.t >= fin.t)) fail("(c) con " + v + " la lista se volvió a pedir igual");
  }
  if (errs.length) fail("errores de página: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("concil-recalc-paralelo: OK — lista en " + lista1[0].t + " ms, recálculo terminó en " + fin1.t + " ms, recarga sólo si cambió algo");
})();

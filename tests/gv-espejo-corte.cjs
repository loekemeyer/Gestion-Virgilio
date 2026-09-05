/* Regresión (v12.90): LA CANILLA DEL ESPEJO DE ISIS ESTÁ CERRADA PARA GESTIÓN.

   Regla del dueño (2026-09-05): "una vez que ya esté todo en Gestión Virgilio, cerrá la
   canilla para que no lleguen más desde el espejo del Excel". Producción sigue leyendo las
   tablas compartidas (PPP_Programacion_Diaria, PPP_Base_Pedidos, PPP_Entregados_Meta) y el
   Apps Script las sigue pisando; Gestión NO las lee más directo: lee las vistas gv_ppp_*
   (sql/gv_espejo_corte.sql), que sólo devuelven NP <= espejo_np_corte_lk / _chef.

   Verifica que:
   (a) en index.html no quede NI UNA lectura directa por REST de las tres tablas (la única
       referencia que puede quedar es PPP_TABLE, el import manual de Excel, que escribe),
   (b) los tres endpoints constantes apunten a las vistas,
   (c) al abrir la PPP (pppLoadProgFromSupabase), la base de picking (fetchPickingBaseFromSupabase) y el set
       de entregados (pppRefreshMetaEntSet), lo que sale por fetch va a gv_ppp_* y nunca a
       las tablas crudas. */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
const crudas = html.match(/\/rest\/v1\/PPP_(Programacion_Diaria|Base_Pedidos|Entregados_Meta)\b/g) || [];
const vistas = html.match(/\/rest\/v1\/gv_ppp_(programacion_diaria|base_pedidos|entregados_meta)\b/g) || [];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = { urls: [] };
    out.endpoints = [SUPABASE_PPP_PROG_ENDPOINT, SUPABASE_PPP_BASE_ENDPOINT, SUPABASE_PPP_ENTREGADOS_ENDPOINT];
    const json = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o),
                           headers: { get: () => "0-0/1" } });
    window.fetch = async (url) => {
      const u = String(url); out.urls.push(u);
      if (u.indexOf("gv_ppp_programacion_diaria") >= 0) return json([{ np: "98694", tanda: "D52B", cod: "4109", razon_social: "Di Leo", m3: 0.5, fecha_entrega: "2026-09-08 00:00:00", zona: "Zona 1" }]);
      if (u.indexOf("gv_ppp_base_pedidos") >= 0) return json([{ pedido: "98694", articulo: "035E", cajas: 2 }]);
      if (u.indexOf("gv_ppp_entregados_meta") >= 0) return json([{ np: "98000" }]);
      return json([]);
    };
    try { await pppLoadProgFromSupabase(); } catch (e) { out.errProg = String(e && e.message || e); }
    try { const m = await fetchPickingBaseFromSupabase(); out.baseNp = m && m.keys ? [...m.keys()][0] : null; } catch (e) { out.errBase = String(e && e.message || e); }
    try { await pppRefreshMetaEntSet(); out.metaTiene98000 = !!(_pppMetaEntSet && _pppMetaEntSet.has("98000")); } catch (e) { out.errMeta = String(e && e.message || e); }
    out.progNp = (_pppParsed.prog || []).map((x) => String(x.np));
    return out;
  });

  const aTabla = r.urls.filter((u) => /\/rest\/v1\/PPP_(Programacion_Diaria|Base_Pedidos|Entregados_Meta)\b/.test(u));
  const aVista = r.urls.filter((u) => /\/rest\/v1\/gv_ppp_(programacion_diaria|base_pedidos|entregados_meta)\b/.test(u));
  const checks = [
    ["index.html no lee más las tres tablas crudas por REST",          crudas.length === 0],
    ["y sí lee las vistas gv_ppp_* (>= 20 lugares)",                    vistas.length >= 20],
    ["los tres endpoints constantes apuntan a las vistas",              r.endpoints.every((e) => /\/gv_ppp_(programacion_diaria|base_pedidos|entregados_meta)$/.test(e))],
    ["la PPP carga desde gv_ppp_programacion_diaria",                    r.progNp.indexOf("98694") >= 0],
    ["la base de picking carga desde gv_ppp_base_pedidos",              r.baseNp === "98694"],
    ["los entregados cargan desde gv_ppp_entregados_meta",              r.metaTiene98000 === true],
    ["ningún fetch fue a una tabla cruda",                              aTabla.length === 0 && aVista.length >= 3],
    ["sin errores de página",                                           errs.length === 0]
  ];
  let bad = 0;
  for (const [name, ok] of checks) { console.log((ok ? "  ok   " : "  FALLA") + " · " + name); if (!ok) bad++; }
  if (bad) console.log("  detalle:", JSON.stringify({ crudas, nVistas: vistas.length, r: { ...r, urls: r.urls.slice(0, 12) } }));
  if (errs.length) console.log("  pageerror: " + errs.join(" | "));
  console.log(bad ? "gv-espejo-corte: " + bad + " FALLA(S)" : "gv-espejo-corte: OK (" + checks.length + " chequeos)");
  await b.close();
  process.exit(bad ? 1 : 0);
})();

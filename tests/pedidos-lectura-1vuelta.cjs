/* Regresión (v20.78): LA TOMA DE DATOS DE PEDIDOS VA EN UNA VUELTA, NO EN DIEZ.

   Luis, 21/09, con la captura del "canceling statement due to statement timeout" en
   A Programar: "banda de timeouts, fijate de optimizar la toma de datos de pedidos".

   Medido en pg_stat_statements (ventana de 22.553 s): las dos lecturas de
   gv_ppp_base_pedidos sumaban 1.670 s de base -el 7,4 % de la ventana- para leer DOS
   VECES la misma vista entera, 9.618 filas, o sea 10 páginas de PostgREST cada una, y
   cada página recalculaba la vista completa.

   Lo que verifica, que es lo que se pierde si alguien revierte:
   (a) supaFetchAll NO manda `Prefer: count=exact`. Nadie usa ese total y obligaba a
       PostgREST a contar la vista entera en CADA página.
   (b) Sin ese header el Content-Range viene `0-999/*` → el total no se puede parsear, y
       el corte tiene que ser la PÁGINA CORTA. Si el `else` vuelve a colgar del `/` en vez
       del NaN, el total queda en Infinity y se pide una página vacía de más: acá eso se
       ve como una request extra.
   (c) La base de picking sale de gv_ppp_base_pedidos_items (816 filas, UNA página) y el
       mapa que arma es el mismo de siempre.
   (d) El panel de Despiece pide gv_ppp_base_articulos (321 códigos), no la vista entera. */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = { reqs: [], prefer: [] };
    const hdr = (cr) => ({ get: (k) => (String(k).toLowerCase() === "content-range" ? cr : null) });
    const json = (o, cr) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: hdr(cr) });

    // (a)+(b) — paginación sin count exacto: 1.000 + 5 tiene que cortar en DOS requests.
    window.fetch = async (url, opt) => {
      const u = String(url);
      out.reqs.push(u);
      out.prefer.push((opt && opt.headers && opt.headers.Prefer) || null);
      const rango = (opt && opt.headers && opt.headers.Range) || "";
      const desde = parseInt(String(rango).split("-")[0], 10) || 0;
      if (desde === 0) return json(Array.from({ length: 1000 }, (_, i) => ({ n: i })), "0-999/*");
      if (desde === 1000) return json(Array.from({ length: 5 }, (_, i) => ({ n: 1000 + i })), "1000-1004/*");
      return json([], "*/*");
    };
    const filas = await supaFetchAll("https://x/rest/v1/loquesea", "select=n");
    out.nFilas = filas.length;
    out.nReqs = out.reqs.length;

    // (c) — la base de picking, desde la vista agregada
    out.reqs = [];
    window.fetch = async (url) => {
      const u = String(url);
      out.reqs.push(u);
      if (u.indexOf("gv_ppp_base_pedidos_items") >= 0)
        return json([{ pedido: "98694", items: [{ a: "035E", c: 2 }, { a: "550", c: 7 }] }], "0-0/*");
      return json([], "0--1/*");
    };
    const m = await fetchPickingBaseFromSupabase();
    out.baseNp = m && m.keys ? [...m.keys()][0] : null;
    out.baseItems = m && m.get ? (m.get("98694") || []) : [];
    out.baseUrls = out.reqs.slice();
    return out;
  });

  const enSupaFetchAll = html.slice(html.indexOf("async function _supaFetchAllRaw"), html.indexOf("async function supaFetchAllSafe"));
  const checks = [
    // el literal del header, con comillas: el comentario que explica por que se saco no cuenta
    ["supaFetchAll no manda Prefer: count=exact",                enSupaFetchAll.indexOf('"count=exact"') < 0],
    ["ni una sola request salio con ese Prefer",                 r.prefer.every((x) => !x)],
    ["1.000 + 5 filas llegan enteras",                           r.nFilas === 1005],
    ["y cortan en DOS requests (la pagina corta es el final)",   r.nReqs === 2],
    ["el endpoint de items existe",                              html.indexOf("SUPABASE_PPP_BASE_ITEMS_ENDPOINT") > 0],
    ["el endpoint de articulos existe",                          html.indexOf("SUPABASE_PPP_BASE_ARTS_ENDPOINT") > 0],
    ["el picking pide gv_ppp_base_pedidos_items",                r.baseUrls.some((u) => u.indexOf("gv_ppp_base_pedidos_items") >= 0)],
    ["y ninguna request pide la vista cruda entera",             !r.baseUrls.some((u) => /gv_ppp_base_pedidos\?/.test(u))],
    ["el mapa sale igual: la NP",                                r.baseNp === "98694"],
    ["el mapa sale igual: los items, en orden",                  JSON.stringify(r.baseItems) === JSON.stringify([{ art: "035E", cajas: 2 }, { art: "550", cajas: 7 }])],
    ["el panel de Despiece pide gv_ppp_base_articulos",          html.indexOf("SUPABASE_PPP_BASE_ARTS_ENDPOINT, \"select=articulo\"") > 0],
    ["sin errores de pagina",                                    errs.length === 0]
  ];
  let bad = 0;
  for (const [t, ok] of checks) { if (!ok) bad++; console.log("  " + (ok ? "ok   " : "FALLA") + " · " + t); }
  if (bad) console.log("  detalle:", JSON.stringify(r));
  console.log("pedidos-lectura-1vuelta: " + (bad ? bad + " FALLA(S)" : "OK (" + checks.length + " chequeos)"));
  await b.close();
  process.exit(bad ? 1 : 0);
})();

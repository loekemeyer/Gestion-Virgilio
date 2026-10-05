/* v26.69 (Luis, 05/10/2026) — «en pedidos entregados quiero que figure la fecha de cuando nos
   llegaron los pedidos de los clientes, no necesariamente de cuando se programaron. De todos los que
   tengas datos, y forward-facing».

   A) con la tabla GV_NP_Fecha_Pedido: la fila de un entregado muestra «📥 dd/mm» y el title trae la
      fecha entera, la hora y los días corridos hasta la salida
   B) una NP web que la captura todavía no tomó sale igual, en vivo (PPP_Web_Programacion + la hora de
      lk_pedidos_match, pedida SÓLO por esos order_id)
   C) SIN la tabla (todavía no se aplicó el SQL o la lectura cae): web en vivo + ISIS desde la PPP y la
      base de pedidos; y una NP sin dato en ningún lado NO lleva chip (no se inventa)
   D) pppTab("ent") pide las fechas, el buscador las encuentra y el Excel de la PPP trae la columna
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    let conTabla = true; const urls = [];
    function J(data, ok) {
      const n = Array.isArray(data) ? data.length : 0;
      return Promise.resolve({
        ok: ok !== false, status: ok === false ? 404 : 200,
        headers: { get: function (h) { return String(h).toLowerCase() === "content-range" ? ("0-" + Math.max(0, n - 1) + "/" + n) : null; } },
        json: function () { return Promise.resolve(data); },
        text: function () { return Promise.resolve(JSON.stringify(data)); }
      });
    }
    window.fetch = function (url) {
      url = String(url); urls.push(url);
      if (url.indexOf("GV_NP_Fecha_Pedido") >= 0) {
        if (!conTabla) return J({ message: "relation does not exist" }, false);
        return J(url.indexOf("offset=0") >= 0 ? [
          { np: "98574", fecha_pedido: "2026-08-28", hora_pedido: null },
          { np: "LK 0101", fecha_pedido: "2026-09-12", hora_pedido: "14:46:03" }
        ] : []);
      }
      if (url.indexOf("PPP_Web_Programacion") >= 0) return J(url.indexOf("offset=0") >= 0 ? [
        { empresa: "lk", order_id: 1500, np: 101, fecha_recep: "2026-09-12" },
        { empresa: "chef", order_id: 220, np: 30, fecha_recep: "2026-09-20" }
      ] : []);
      if (url.indexOf("lk_pedidos_match") >= 0) {
        const all = [{ empresa: "lk", order_id: 1500, fecha_pedido: "2026-09-12", hora_pedido: "14:46:03" },
                     { empresa: "chef", order_id: 220, fecha_pedido: "2026-09-20", hora_pedido: "09:05:00" }];
        const m = /order_id=in\.\(([^)]*)\)/.exec(url); const ids = m ? m[1].split(",") : [];
        return J(all.filter(function (x) { return ids.indexOf(String(x.order_id)) >= 0; }));
      }
      if (url.indexOf("GV_PPP_Programacion_Diaria") >= 0) return J([{ np: "98704", fecha_recep: "2026-09-04 00:00:00" }]);
      if (url.indexOf("GV_PPP_Base_Pedidos") >= 0) return J(url.indexOf("offset=0") >= 0 ? [
        { pedido: "98574", fecha: "2026-08-28 00:00:00" }, { pedido: "98704", fecha: "2026-08-20 00:00:00" }] : []);
      return J([]);
    };
    const filas = [
      { np: "98574",   tanda: "C03B", cod: "2533", rs: "Osa", m3: 0.5, cajE: 5, cajF: 0, frep: "2026-09-10", fkey: "20260910" },
      { np: "LK 0101", tanda: "E29C", cod: "4188", rs: "Orfali", m3: 1.1, cajE: 9, cajF: 0, frep: "2026-09-19", fkey: "20260919" },
      { np: "CH 0030", tanda: "D47B", cod: "2686", rs: "Dorinka", m3: 0.9, cajE: 4, cajF: 0, frep: "2026-09-25", fkey: "20260925" },
      { np: "97001",   tanda: "B10A", cod: "100", rs: "Viejo", m3: 0.2, cajE: 1, cajF: 0, frep: "2026-06-01", fkey: "20260601" }
    ];
    const chip = function (html, np) {
      const i = html.indexOf("<b>" + np + "</b>"); if (i < 0) return null;
      const fin = html.indexOf("</div>", i); const row = html.slice(i, fin);
      const m = row.match(/<span class="ppp-ent-fped" title="([^"]*)">📥 ([^<]*)<\/span>/);
      return m ? { tit: m[1], txt: m[2] } : "";
    };
    // A + B (con tabla)
    await pppRefreshFechaPedido(true);
    let h = _pppEntGroupedHtml(filas, true, 0).html;
    const a1 = chip(h, "LK 0101"), a2 = chip(h, "98574"), b1 = chip(h, "CH 0030");
    out.a_txt = a1 && a1.txt;
    out.a_tit = a1 && a1.tit;
    out.a_isis = a2 && a2.txt;
    out.b_txt = b1 && b1.txt;
    out.b_hora = b1 && b1.tit.indexOf("09:05") >= 0;
    // sólo pidió la hora de lo que faltaba (el 220 de Chef), no la del 1500 que ya estaba en la tabla
    const lpm = urls.filter(function (u) { return u.indexOf("lk_pedidos_match") >= 0; });
    out.b_soloFalta = lpm.length === 1 && /order_id=in\.\(220\)/.test(lpm[0]);
    out.a_sinBaseIsis = !urls.some(function (u) { return u.indexOf("GV_PPP_Base_Pedidos") >= 0; });
    // C (sin tabla)
    conTabla = false; urls.length = 0;
    await pppRefreshFechaPedido(true);
    h = _pppEntGroupedHtml(filas, true, 0).html;
    const c1 = chip(h, "LK 0101"), c2 = chip(h, "98574");
    out.c_web = c1 && c1.txt; out.c_webHora = c1 && c1.tit.indexOf("14:46") >= 0;
    out.c_isis = c2 && c2.txt;
    out.c_ppp98704 = (_pppFechaPedOf("98704") || {}).f;   // la PPP gana sobre la base (04/09, no 20/08)
    out.c_sinDato = chip(h, "97001");                         // "" = sin chip
    // D
    out.d_tab = /if \(t === "ent"\) \{ pppRefreshFechaPedido\(\)/.test(String(pppTab));
    _pppSearch = "2026-09-12";
    out.d_busca = _pppEntFilter(filas).map(function (x) { return x.np; }).join(",");
    _pppSearch = "";
    const hoja = PPP_XLS_HOJAS.filter(function (x) { return x.hoja === "Pedidos Entregados"; })[0];
    out.d_xlsCol = !!hoja && hoja.cols.some(function (c) { return c[0] === "_fped"; });
    out.d_xlsSel = /charAt\(0\) !== "_"/.test(String(pppExportExcel));
    return out;
  });
  const pass = r.a_txt === "12/09" && /12\/09\/2026 14:46 hs · salió 7 días corridos después/.test(r.a_tit || "") &&
    r.a_isis === "28/08" && r.b_txt === "20/09" && r.b_hora && r.b_soloFalta && r.a_sinBaseIsis &&
    r.c_web === "12/09" && r.c_webHora && r.c_isis === "28/08" && r.c_ppp98704 === "2026-09-04" && r.c_sinDato === "" &&
    r.d_tab && r.d_busca === "LK 0101" && r.d_xlsCol && r.d_xlsSel && errs.length === 0;
  console.log("ppp-ent-fecha-pedido:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();

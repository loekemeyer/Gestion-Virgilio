/* Regla GV-UI «Ancho según contenido» (Luis, 16/10/2026 — docs/GV-UI.md §5).
   "Tablas optimizadas horizontalmente (no debería haber tanto espacio entre columna y columna...).
   Headers centrados, minimo gasto de espacio horizontal, font y visual lo mas grande y clara posible."

   Caso: pop-up «Cajas pedidas» (stkOpenCajasPedidasArt). Antes la tabla iba a width:100% con
   table-layout:fixed en la tarjeta de 760 px: 730 px de tabla, NP 266 px, encabezado 10 px gris
   en mayúscula, dato 12 px, números a la derecha. Mide, a 1280 y a 430 px:
   (a) la tabla NO se estira: mide menos que la tarjeta menos 120 px (a 1280)
   (b) a 430 px entra sin scroll horizontal en su wrapper
   (c) encabezados centrados, >= 13 px, color oscuro (contraste >= 7:1 sobre #f1f5f9)
   (d) dato >= 14 px; la columna Cajas centrada y con cifras tabulares
   (e) .stk-tbl / .oc-tbl / .abast-tbl no vuelven a width:100% (candado estático)
   Sale 1 si falla. */
const path = require("path"), fs = require("fs");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const lum = (rgb) => { const v = rgb.match(/\d+/g).slice(0, 3).map((x) => { x = x / 255; return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4); }); return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]; };
const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
(async () => {
  const b = await chromium.launch();
  const out = {};
  for (const W of [1280, 430]) {
    const p = await b.newPage({ viewport: { width: W, height: 900 } });
    const errs = []; p.on("pageerror", (e) => errs.push(e.message));
    await p.route("**/rest/v1/**", (r) => r.abort());
    await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
    const m = await p.evaluate(async () => {
      const J = (d) => Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(d) });
      _stk = { movs: [], viewRows: [] }; window.alert = () => {};
      window.getEmpleadosNombres = async () => new Map();
      window.fetch = function (url) { url = String(url);
        if (url.includes("gv_demanda_pedidos")) return J([
          { pedido: "44600", cajas: 16, articulo: "936E", origen: "isis" },
          { pedido: "44601", cajas: 4, articulo: "936E", origen: "isis" },
          { pedido: "LK 0053", cajas: 80, articulo: "936E", origen: "web" }]);
        if (url.includes("gv_np_prog_info")) return J([
          { np: "44600", tanda: "D58A", razon_social: "Dorinka S.R.L", fecha_entrega: "2026-10-03" },
          { np: "44601", tanda: "D58B", razon_social: "Cencosud S.A. Suc 123 Jumbo Unicenter Martinez", fecha_entrega: "2026-10-04" },
          { np: "LK 0053", tanda: "E17B", razon_social: "Orfali Alfredo", fecha_entrega: "2026-10-22" }]);
        return J([]); };
      await stkOpenCajasPedidasArt(encodeURIComponent("936E"));
      const t = document.querySelector(".cp-tbl"), card = document.querySelector(".stkpop-card"), wrap = t.closest(".mva-tblwrap");
      const ths = [...t.querySelectorAll("thead th")].map((x) => { const c = getComputedStyle(x); return { fs: parseFloat(c.fontSize), color: c.color, bg: c.backgroundColor, al: c.textAlign }; });
      const td = getComputedStyle(t.querySelector("tbody td:nth-child(2)")), num = getComputedStyle(t.querySelector("tbody td:nth-child(3)"));
      return { tbl: t.getBoundingClientRect().width, card: card.getBoundingClientRect().width, wrapScroll: wrap.scrollWidth - wrap.clientWidth,
        ths, tdFs: parseFloat(td.fontSize), numAl: num.textAlign, numTab: num.fontVariantNumeric };
    });
    out[W] = m; if (errs.length) out["err" + W] = errs.join("|");
    await p.close();
  }
  await b.close();
  const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
  const c = {
    a_noEstira: out[1280].tbl < out[1280].card - 120,
    b_entra430: out[430].wrapScroll <= 1,
    c_thCentrado: [1280, 430].every((W) => out[W].ths.every((h) => h.al === "center")),
    c_th13: out[1280].ths.every((h) => h.fs >= 13),
    c_thOscuro: out[1280].ths.every((h) => ratio(h.color, h.bg === "rgba(0, 0, 0, 0)" ? "rgb(255,255,255)" : h.bg) >= 7),
    d_dato14: out[1280].tdFs >= 14,
    d_numCentrado: out[1280].numAl === "center" && /tabular-nums/.test(out[1280].numTab),
    e_mvaAuto: html.indexOf('".mva-tbl{border-collapse:collapse;width:auto;') > 0,
    e_stkOcAbast: /\.stk-tbl\{width:auto;/.test(html) && /\.oc-tbl\{width:auto;/.test(html) && /\.abast-tbl\{width:auto;/.test(html),
    sinErrores: !out.err1280 && !out.err430
  };
  const pass = Object.values(c).every(Boolean);
  console.log("stk-tabla-ancho-contenido:", JSON.stringify(c), "· tabla", Math.round(out[1280].tbl), "/ tarjeta", Math.round(out[1280].card), "·", pass ? "✓ OK" : "✗ FAIL");
  if (!pass) console.log(JSON.stringify(out));
  process.exit(pass ? 0 : 1);
})();

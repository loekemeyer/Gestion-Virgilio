/* v24.32 (Luis, 29/09) — "mirá la cantidad de espacio muerto entre «descripción» y «proy u/mes».
   Arreglalo ya. OPTIMIZACIÓN DE ESPACIO".

   `.mva-tbl.wide` iba a width:100% dentro de una tarjeta de 1760px y el <colgroup> le daba ancho
   a 10 de las 11 columnas: TODO el sobrante (~700px en un monitor ancho) caía en Descripción,
   que es la única sin width. Ahora todas tienen width, la tabla mide lo que suman y la TARJETA
   se achica a eso.

   Se mide el ancho REAL de la celda con la pantalla corriendo, no el CSS: verificado que falla
   poniendo Descripción en 700px. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };

const CFG_PROV = [{ proveedor: "Fujian", importador: "Chef", usa_ntl: false, ntl_pct: 0.05, derechos_pct: 0.35,
  meses_objetivo: 10, min_usd: 25000, valor_m3: 110, moq: 1000, moq_meses_max: 12, activo: true, orden: 1,
  ntl_pct_propio: null, derechos_pct_propio: 0.35, meses_objetivo_propio: null, min_usd_propio: null,
  valor_m3_propio: 110, moq_propio: null, moq_meses_max_propio: null, codigos: 2 }];
const CFG_NAC = [{ meses_objetivo: 10, derechos_pct: 0.18, ntl_pct: 0.05, iva_pct: 0.21, iva_adic_pct: 0.20,
  gcias_pct: 0.06, iibb_pct: 0.0017, estad_pct: 0.03, estad_fob_desde: 6000, estad_fob_hasta: 10000,
  estad_fijo: 180, valor_m3: 110, flete_full: 2000, min_usd: 25000, moq: 1000, moq_meses_max: 12 }];

const it = (cod, o) => Object.assign({
  cod, prov: "Fujian", key: cod, desc: cod, proyUni: 100, objetivoUni: 1000, stockUni: 0, enCurso: 0,
  meses: 10, aPedirUni: 100, aPedirCajas: 100, uniMaster: 1, uxc: 1, fobUni: 1, m3Master: 0.1,
  det: [{ id: 1, curso: 0, marca: "" }]
}, o || {});
const ITEMS = [it("AAA", { fobUni: 90 }), it("BBB", { fobUni: 9 })];

(async () => {
  const b = await chromium.launch();
  // pantalla ANCHA a propósito: es donde el sobrante se veía
  const p = await b.newPage({ viewport: { width: 1920, height: 1000 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", async (r) => {
    const u = r.request().url();
    let body = "[]";
    if (/gv_imp_proveedor_cfg/.test(u)) body = JSON.stringify(CFG_PROV);
    else if (/gv_imp_nac_config/.test(u)) body = JSON.stringify(CFG_NAC);
    await r.fulfill({ status: 200, contentType: "application/json", body });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  await p.evaluate(() => _impCfgCargar());
  await p.evaluate((its) => {
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items: its, meses: 10, minUsd: 25000, nac: { modo: "consolidada", valorM3: 110, tn: 0 } }, soloPedir: false, mcOverride: {} };
    _pedImpRender();
  }, ITEMS);

  const m = await p.evaluate(() => {
    const t = document.querySelector(".mva-tbl.wide"), c = document.querySelector(".stkpop-card");
    const tr = [...document.querySelectorAll(".mva-tbl.wide tbody tr")].find((x) => /^(AAA|BBB)$/.test(x.cells[0].textContent.trim()));
    const cols = [...t.querySelectorAll("colgroup col")].map((co) => co.style.width || "");
    return {
      cols: t.rows[0].cells.length,
      sinWidth: cols.filter((w) => !w).length,
      tabla: Math.round(t.getBoundingClientRect().width),
      card: Math.round(c.getBoundingClientRect().width),
      desc: Math.round(tr.cells[1].getBoundingClientRect().width),
      // el hueco: lo que hay entre donde termina el texto de Descripción y donde arranca Proy
      proyX: Math.round(tr.cells[2].getBoundingClientRect().left),
      descX: Math.round(tr.cells[1].getBoundingClientRect().left)
    };
  });

  if (m.cols !== 13) fail("esperaba 13 columnas (v24.73: En camino y A pedir separadas) y hay " + m.cols);
  if (m.sinWidth) fail("quedan " + m.sinWidth + " columna(s) sin width en el <colgroup>: se comen el sobrante de la tarjeta");
  if (m.desc > 280) fail("Descripción se está comiendo el sobrante: " + m.desc + "px (el hueco muerto que reclamó Luis)");
  if (m.card - m.tabla > 60) fail("la tarjeta (" + m.card + "px) es mucho más ancha que la tabla (" + m.tabla + "px): queda espacio muerto a la derecha");
  if (m.tabla < 1100) fail("la tabla quedó demasiado angosta: " + m.tabla + "px");
  if (errs.length) fail("errores de página: " + errs.join(" · "));

  await b.close();
  if (!process.exitCode) console.log("pedimp-ancho-tabla · ✓ OK (tabla " + m.tabla + "px en tarjeta de " + m.card + "px · Descripción " + m.desc + "px · 0 columnas sin width)");
})();

/* v24.31 (Luis, 29/09) — dos cosas del módulo 📦 Pedidos Importación, corriendo la pantalla:

   (A) ESPACIO. Hasta la v24.01 «Descripción» era la ÚNICA columna sin width en el <colgroup>
       y la tabla iba a width:100% dentro de una tarjeta de 1760px: todo el sobrante caía ahí
       y quedaba un hueco muerto entre Descripción y Proy u/mes. Ahora todas las columnas
       tienen width y la TARJETA se achica al ancho de la tabla.
   (B) NACIONALIZACIÓN POR ARTÍCULO ("apretás sobre el proveedor y debería expandirse las
       unidades"): el encabezado del proveedor abre dos columnas — lo que le toca a cada
       artículo del costo del embarque y el puesto en Argentina por unidad — con los tres
       criterios de reparto y el u$s/m³ editable, que guarda SÓLO su clave.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };
const num = (t) => Number(String(t || "").replace(/\./g, "").replace(",", ".").replace(/[^0-9.\-]/g, "")) || 0;

const CFG_PROV = [{ proveedor: "Fujian", importador: "Chef", usa_ntl: false, ntl_pct: 0.05, derechos_pct: 0.35,
  meses_objetivo: 10, min_usd: 25000, valor_m3: 110, moq: 1000, moq_meses_max: 12, activo: true, orden: 1,
  ntl_pct_propio: null, derechos_pct_propio: 0.35, meses_objetivo_propio: null, min_usd_propio: null,
  valor_m3_propio: 110, moq_propio: null, moq_meses_max_propio: null, codigos: 2 }];
const CFG_NAC = [{ meses_objetivo: 10, derechos_pct: 0.18, ntl_pct: 0.05, iva_pct: 0.21, iva_adic_pct: 0.20,
  gcias_pct: 0.06, iibb_pct: 0.0017, estad_pct: 0.03, estad_fob_desde: 6000, estad_fob_hasta: 10000,
  estad_fijo: 180, valor_m3: 110, flete_full: 2000, min_usd: 25000, moq: 1000, moq_meses_max: 12 }];

/* MISMO m³ (10 cada uno) y FOB muy distinto (u$s 9.000 vs u$s 900): así se ve de qué base
   reparte cada criterio. Por m³ → mitad y mitad; por FOB → 10 a 1. */
const it = (cod, o) => Object.assign({
  cod, prov: "Fujian", key: cod, desc: cod, proyUni: 100, objetivoUni: 1000, stockUni: 0, enCurso: 0,
  meses: 10, aPedirUni: 100, aPedirCajas: 100, uniMaster: 1, uxc: 1, fobUni: 1, m3Master: 0.1,
  det: [{ id: 1, curso: 0, marca: "" }]
}, o || {});
const ITEMS = [
  it("AAA", { aPedirUni: 100, aPedirCajas: 100, uniMaster: 1, fobUni: 90, m3Master: 0.1 }),   // 9.000 u$s · 10 m³
  it("BBB", { aPedirUni: 100, aPedirCajas: 100, uniMaster: 1, fobUni: 9, m3Master: 0.1 })     //   900 u$s · 10 m³
];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1920, height: 1000 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  const rpc = [];
  await p.route("**/rest/v1/**", async (r) => {
    const u = r.request().url();
    let body = "[]";
    if (/gv_imp_proveedor_cfg/.test(u)) body = JSON.stringify(CFG_PROV);
    else if (/gv_imp_nac_config/.test(u)) body = JSON.stringify(CFG_NAC);
    else if (/\/rpc\//.test(u)) { try { rpc.push({ url: u, body: JSON.parse(r.request().postData() || "{}") }); } catch (_e) {} }
    await r.fulfill({ status: 200, contentType: "application/json", body });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  // el u$s/m³ escribe con el JWT del supervisor (_scfgAuth): sin sesión de Google corta antes
  // de llamar a la RPC. Lo que se mide acá es QUÉ manda, no el login.
  await p.evaluate(() => { window.facAuthWriteHeaders = async () => ({ apikey: "k", Authorization: "Bearer t" }); });
  await p.evaluate(() => _impCfgCargar());
  await p.evaluate((its) => {
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items: its, meses: 10, minUsd: 25000, nac: { modo: "consolidada", valorM3: 110, tn: 0 } }, soloPedir: false, mcOverride: {} };
    _pedImpRender();
  }, ITEMS);

  const medir = () => p.evaluate(() => {
    const t = document.querySelector(".mva-tbl.wide"), c = document.querySelector(".stkpop-card");
    const filas = [...document.querySelectorAll(".mva-tbl.wide tbody tr")];
    const dato = filas.filter((tr) => /^(AAA|BBB)$/.test(tr.cells[0].textContent.trim()));
    return {
      cols: t.rows[0].cells.length,
      head: t.rows[0].innerHTML,
      tabla: Math.round(t.getBoundingClientRect().width),
      card: Math.round(c.getBoundingClientRect().width),
      desc: Math.round(dato[0].cells[1].getBoundingClientRect().width),
      celdas: dato.map((tr) => [...tr.cells].map((td) => td.textContent.trim())),
      ultima: (filas[filas.length - 1] || {}).textContent || ""
    };
  });

  // ── (A) sin hueco muerto y la tarjeta pegada a la tabla ───────────────────────────────
  const A = await medir();
  if (A.cols !== 11) fail("(A) esperaba 11 columnas cerrado y hay " + A.cols);
  if (A.desc > 280) fail("(A) Descripción se está comiendo el sobrante: " + A.desc + "px (el hueco muerto que reclamó Luis)");
  if (A.card - A.tabla > 60) fail("(A) la tarjeta (" + A.card + "px) es mucho más ancha que la tabla (" + A.tabla + "px): queda espacio muerto");
  if (A.tabla < 1100) fail("(A) la tabla quedó demasiado angosta: " + A.tabla + "px");

  // ── (B) el proveedor abre la nacionalización por artículo ─────────────────────────────
  const tog = await p.evaluate(() => {
    const d = document.querySelector(".pedimp-provtog");
    return d ? (d.getAttribute("onclick") || "") : "(sin encabezado clickeable)";
  });
  if (!/pedImpNacToggle\(/.test(tog)) fail("(B) el encabezado del proveedor no abre la nacionalización: " + tog);

  await p.evaluate(() => pedImpNacToggle(encodeURIComponent("Fujian")));
  const B = await medir();
  if (B.cols !== 13) fail("(B) abierto esperaba 13 columnas y hay " + B.cols);
  if (!/🛃 Nac\. u\$s/.test(B.head)) fail("(B) falta la columna «🛃 Nac. u$s»");
  if (!/Puesto<small[^>]*>u\$s\/u<\/small>/.test(B.head)) fail("(B) falta la columna «Puesto u$s/u»");
  if (!/TOTAL nacionalización repartida/.test(B.ultima)) fail("(B) falta la fila TOTAL: " + B.ultima.slice(0, 80));

  // el total repartido es EXACTAMENTE el no recuperable del embarque
  const noRecup = await p.evaluate(() => {
    const der = _derechosPedido([], "Fujian");
    return _pedImpNacionalizar(9900, 20, { modo: "consolidada", valorM3: 110, tn: 0, ntl: false, derechos: der }).noRecup;
  });
  const totRep = num(B.ultima.replace("TOTAL nacionalización repartida", ""));
  if (Math.abs(totRep - Math.round(noRecup)) > 2) fail("(B) el total repartido (" + totRep + ") no es el no recuperable del embarque (" + Math.round(noRecup) + ")");

  // ── criterios: por m³ (mismo m³ → mismo costo) vs por FOB (10 a 1) ────────────────────
  const nacDe = (m) => ({ aaa: num(m.celdas[0][9]), bbb: num(m.celdas[1][9]) });
  await p.evaluate(() => pedImpNacCrit(encodeURIComponent("Fujian"), "m3"));
  const m3 = nacDe(await medir());
  if (Math.abs(m3.aaa - m3.bbb) > 2) fail("(B) por m³, con el MISMO m³, los dos tienen que pagar igual: " + JSON.stringify(m3));
  await p.evaluate(() => pedImpNacCrit(encodeURIComponent("Fujian"), "fob"));
  const fob = nacDe(await medir());
  if (!(fob.aaa > fob.bbb * 8)) fail("(B) por FOB, con 10× de FOB, AAA tiene que pagar ~10×: " + JSON.stringify(fob));
  await p.evaluate(() => pedImpNacCrit(encodeURIComponent("Fujian"), "mixto"));
  const mix = nacDe(await medir());
  if (!(mix.aaa > m3.aaa && mix.aaa < fob.aaa)) fail("(B) mixto tiene que quedar entre m³ y FOB: " + JSON.stringify({ m3, mix, fob }));

  // el total NO cambia con el criterio
  if (Math.abs((mix.aaa + mix.bbb) - (m3.aaa + m3.bbb)) > 3) fail("(B) el criterio cambió el TOTAL: " + JSON.stringify({ m3, mix }));

  // ── el u$s/m³ guarda SÓLO su clave (la RPC deja intacta toda clave ausente) ───────────
  rpc.length = 0;
  await p.evaluate(() => pedImpSetNacM3(encodeURIComponent("Fujian"), 140));
  await p.waitForTimeout(250);
  const g = rpc.filter((r) => /gv_imp_proveedor_guardar/.test(r.url)).pop();
  if (!g) fail("(B) el u$s/m³ no llamó a gv_imp_proveedor_guardar");
  else {
    const pay = (g.body && g.body.p) || {};
    if (Object.keys(pay).length !== 2 || pay.proveedor !== "Fujian" || Number(pay.valor_m3) !== 140)
      fail("(B) el u$s/m³ tiene que mandar SÓLO {proveedor, valor_m3} y mandó: " + JSON.stringify(pay));
  }

  // y cerrar vuelve a 11 columnas
  await p.evaluate(() => pedImpNacToggle(encodeURIComponent("Fujian")));
  const C = await medir();
  if (C.cols !== 11) fail("(B) al cerrar tenía que volver a 11 columnas y hay " + C.cols);

  if (errs.length) fail("errores de página: " + errs.join(" · "));
  await b.close();
  if (!process.exitCode) console.log("pedimp-nac-articulo · ✓ OK (tabla " + A.tabla + "px en tarjeta de " + A.card + "px · Descripción " + A.desc + "px)");
})();

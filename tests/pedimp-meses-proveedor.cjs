/* v23.95 (Luis, 29/09) — los MESES OBJETIVO se eligen al lado del nombre del proveedor:
   un desplegable de 1 a 24 (más «gral», que es heredar el general) que guarda en
   GV_Imp_Proveedor.meses_objetivo, o sea que vale para TODOS los códigos de ese proveedor.
   Corre la pantalla: mira el select, lo cambia y verifica el cuerpo REAL de la RPC.
   ⚠ Se manda SÓLO {proveedor, meses_objetivo}: la función deja intacta toda clave ausente,
   así que mandar el resto pisaría lo que otro editó en el ⚙. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };

const CFG_PROV = [
  { proveedor: "Frontier", importador: "Chef", usa_ntl: true, ntl_pct: 0.05, derechos_pct: 0.18,
    meses_objetivo: 10, meses_objetivo_propio: null, min_usd: 25000, valor_m3: 110, moq: 1000, moq_meses_max: 12, codigos: 1, orden: 1 },
  { proveedor: "Kangli", importador: "Chef", usa_ntl: false, ntl_pct: 0.05, derechos_pct: 0.18,
    meses_objetivo: 6, meses_objetivo_propio: 6, min_usd: 25000, valor_m3: 110, moq: 2000, moq_meses_max: 12, codigos: 1, orden: 2 }
];
const CFG_NAC = [{ meses_objetivo: 10, derechos_pct: 0.18, ntl_pct: 0.05, iva_pct: 0.21, iva_adic_pct: 0.20,
  gcias_pct: 0.06, iibb_pct: 0.0017, estad_pct: 0.03, estad_fob_desde: 6000, estad_fob_hasta: 10000,
  estad_fijo: 180, valor_m3: 110, flete_full: 2000, min_usd: 25000, moq: 1000, moq_meses_max: 12 }];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 950 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  let guardado = null;
  await p.route("**/rest/v1/**", async (r) => {
    const u = r.request().url();
    let body = "[]";
    if (/gv_imp_proveedor_guardar/.test(u)) { try { guardado = JSON.parse(r.request().postData() || "{}"); } catch (_e) {} body = "{}"; }
    else if (/gv_imp_proveedor_cfg/.test(u)) body = JSON.stringify(CFG_PROV);
    else if (/gv_imp_nac_config/.test(u)) body = JSON.stringify(CFG_NAC);
    else if (/\/rpc\//.test(u)) body = "[]";
    await r.fulfill({ status: 200, contentType: "application/json", body });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  // sin sesión de Google no hay headers: el guardado es de supervisor. Se mockea la identidad,
  // no la RPC — lo que el test mide es QUÉ se manda.
  await p.evaluate(() => { window._scfgAuth = async () => ({ apikey: "x", Authorization: "Bearer x" }); });
  await p.evaluate(() => _impCfgCargar());

  const it = (cod, prov) => ({ cod, prov, key: cod, desc: cod, proyUni: 100, objetivoUni: 1000, stockUni: 0,
    enCurso: 0, meses: 10, aPedirUni: 500, aPedirCajas: 5, uniMaster: 100, uxc: 10, fobUni: 1, m3Master: 0.05,
    det: [{ id: 1, curso: 0, marca: "" }] });
  await p.evaluate((its) => {
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items: its, meses: 10, minUsd: 25000, nac: { modo: "consolidada", valorM3: 110, tn: 0 } }, soloPedir: false, mcOverride: {} };
    _pedImpRender();
  }, [it("111", "Frontier"), it("222", "Kangli")]);

  // (A) hay un select por proveedor, con 1..24 + «gral», y marca lo que tiene cada uno
  const sels = await p.evaluate(() => [...document.querySelectorAll(".pedimp-mesessel select")].map((s) => ({
    n: s.options.length,
    primera: s.options[0].value,
    max: Math.max.apply(null, [...s.options].map((o) => Number(o.value) || 0)),
    elegida: s.value
  })));
  if (sels.length !== 2) fail("(A) esperaba un selector de meses por proveedor y hay " + sels.length);
  if (sels[0] && (sels[0].n !== 25 || sels[0].max !== 24 || sels[0].primera !== ""))
    fail("(A) el desplegable tiene que ir de 1 a 24 más «gral»: " + JSON.stringify(sels[0]));
  if (sels[0] && sels[0].elegida !== "") fail("(A) Frontier no tiene meses propios: tenía que quedar en «gral», y quedó en " + sels[0].elegida);
  if (sels[1] && sels[1].elegida !== "6") fail("(A) Kangli tiene 6 meses propios y el select dice " + (sels[1] || {}).elegida);

  // (B) cambiarlo guarda SÓLO ese campo, para ese proveedor
  await p.evaluate(() => {
    const s = document.querySelectorAll(".pedimp-mesessel select")[0];
    s.value = "14"; s.dispatchEvent(new Event("change"));
  });
  await p.waitForTimeout(400);
  if (!guardado || !guardado.p) fail("(B) no se llamó a gv_imp_proveedor_guardar: " + JSON.stringify(guardado));
  else {
    if (guardado.p.proveedor !== "Frontier") fail("(B) guardó el proveedor equivocado: " + guardado.p.proveedor);
    if (Number(guardado.p.meses_objetivo) !== 14) fail("(B) no guardó los meses elegidos: " + JSON.stringify(guardado.p));
    const extra = Object.keys(guardado.p).filter((k) => k !== "proveedor" && k !== "meses_objetivo");
    if (extra.length) fail("(B) mandó campos de más (pisaría lo que editó otro en el ⚙): " + extra.join(", "));
  }

  // (C) volver a «gral» manda null (= heredar), no 0 ni ""
  guardado = null;
  await p.evaluate(() => {
    const s = document.querySelectorAll(".pedimp-mesessel select")[0];
    s.value = ""; s.dispatchEvent(new Event("change"));
  });
  await p.waitForTimeout(400);
  if (!guardado || !guardado.p || guardado.p.meses_objetivo !== null)
    fail("(C) «gral» tiene que guardar null (heredar el general) y mandó: " + JSON.stringify(guardado && guardado.p));

  if (errs.length) fail("errores de página: " + errs.join(" | "));
  if (!process.exitCode) console.log("pedimp-meses-proveedor: OK — select 1..24 por proveedor, guarda sólo meses_objetivo, «gral» = null");
  await b.close();
})();

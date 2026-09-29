/* v23.89 (Luis, 29/09) — «⚙ Configurar parámetros» al lado de cada proveedor de importación.
   La regla que sostiene: LOS DATOS NO VIVEN EN EL FRONT. Lo que estaba escrito en index.html
   (_IMPORTADOR_DE, _NTL_PROVEEDORES, _DERECHOS_PROV, las tasas y el mínimo) es sólo el
   FALLBACK; la fuente es GV_Imp_Proveedor / Importados_Config, y el pop-up las escribe por RPC.

   Se corre la pantalla de verdad (no es un candado de texto) y se mira:
   (a) el botón ⚙ sale en el encabezado de CADA proveedor;
   (b) _impCfgCargar() hidrata los cachés desde la vista: un proveedor nuevo que sólo existe
       en la tabla aparece, y uno que la tabla NO marca NTL deja de llevar la comisión;
   (c) las tasas de nacionalización salen de gv_imp_nac_config (cambiar el % de derechos en
       la "base" cambia la cuenta de la pantalla);
   (d) los meses objetivo y el mínimo se leen POR PROVEEDOR;
   (e) el pop-up guarda por RPC (gv_imp_proveedor_guardar) mandando los % en tanto por uno,
       y una casilla vacía viaja como null = "heredado del general";
   (f) sacar un código llama a gv_imp_codigo_proveedor con proveedor null (no lo borra).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };

// lo que "la base" contesta en este test: Frontier deja de ser NTL y Kangli pasa a 30% de
// derechos y 6 meses; y aparece un proveedor que el front no conoce.
const CFG_PROV = [
  { proveedor: "Frontier", importador: "Chef", usa_ntl: false, ntl_pct: 0.05, derechos_pct: 0.18,
    meses_objetivo: 10, min_usd: 25000, valor_m3: 110, activo: true, orden: 1,
    ntl_pct_propio: null, derechos_pct_propio: null, meses_objetivo_propio: null, min_usd_propio: null, valor_m3_propio: null, codigos: 2 },
  { proveedor: "Kangli", importador: "Chef", usa_ntl: true, ntl_pct: 0.05, derechos_pct: 0.30,
    meses_objetivo: 6, min_usd: 40000, valor_m3: 110, activo: true, orden: 2,
    ntl_pct_propio: null, derechos_pct_propio: 0.30, meses_objetivo_propio: 6, min_usd_propio: 40000, valor_m3_propio: null, codigos: 3 },
  { proveedor: "Nueva Fabrica", importador: "Tierra Nativa", usa_ntl: false, ntl_pct: 0.05, derechos_pct: 0.18,
    meses_objetivo: 10, min_usd: 25000, valor_m3: 110, activo: true, orden: 3,
    ntl_pct_propio: null, derechos_pct_propio: null, meses_objetivo_propio: null, min_usd_propio: null, valor_m3_propio: null, codigos: 0 }
];
const CFG_NAC = [{ meses_objetivo: 10, derechos_pct: 0.25, ntl_pct: 0.05, iva_pct: 0.21, iva_adic_pct: 0.20,
  gcias_pct: 0.06, iibb_pct: 0.0017, estad_pct: 0.03, estad_fob_desde: 6000, estad_fob_hasta: 10000,
  estad_fijo: 180, valor_m3: 110, flete_full: 2000, min_usd: 25000 }];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 950 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  const rpc = [];   // lo que el pop-up le manda al backend
  await p.route("**/rest/v1/**", async (r) => {
    const u = r.request().url();
    let body = "[]";
    if (/gv_imp_proveedor_cfg/.test(u)) body = JSON.stringify(CFG_PROV);
    else if (/gv_imp_nac_config/.test(u)) body = JSON.stringify(CFG_NAC);
    else if (/vista_prov_importacion/.test(u)) body = JSON.stringify([
      { cod: "587C", descripcion: "cuchilla pelapapas laser", marca: "LK", proveedor: "Frontier" },
      { cod: "505C", descripcion: "cuchilla pelador", marca: "LK", proveedor: "Frontier" },
      { cod: "231", descripcion: "palo de amasar", marca: "LK", proveedor: "Kangli" }
    ]);
    else if (/\/rpc\//.test(u)) {
      let js = null; try { js = JSON.parse(r.request().postData() || "null"); } catch (_e) {}
      rpc.push({ fn: u.split("/rpc/")[1].split("?")[0], body: js });
      body = "{}";
    }
    await r.fulfill({ status: 200, contentType: "application/json", body });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  // el pop-up escribe con el JWT del supervisor (_scfgAuth): sin sesión de Google corta antes
  // de llamar a la RPC, así que acá se le da una. Lo que se mide es QUÉ manda, no el login
  // (eso ya lo sostiene tests/imp-escritura-login.cjs).
  await p.evaluate(() => { window.facAuthWriteHeaders = async () => ({ apikey: "k", Authorization: "Bearer t" }); });

  // ── (b) y (c): la config de la BASE pisa lo que dice el front ───────────────────────
  const hidr = await p.evaluate(async () => {
    const antes = { ntlFrontier: _esProvNtl("Frontier"), derKangli: _derechosProv("Kangli"), derOtro: _derechosProv("Ownland") };
    await _impCfgCargar();
    return { antes, ntlFrontier: _esProvNtl("Frontier"), derKangli: _derechosProv("Kangli"),
             derOtro: _derechosProv("Ownland"), lista: _PROV_IMP_LISTA.slice(),
             impNueva: _IMPORTADOR_DE["Nueva Fabrica"] || "",
             mesesKangli: _impProvNum("Kangli", "meses_objetivo", 10),
             mesesFrontier: _impProvNum("Frontier", "meses_objetivo", 10),
             minKangli: _impProvNum("Kangli", "min_usd", 25000) };
  });
  if (hidr.antes.ntlFrontier !== true) fail("(b) el fallback del front ya no marcaba Frontier como NTL");
  if (hidr.ntlFrontier !== false) fail("(b) la tabla dice que Frontier NO factura por NTL y el front lo sigue cobrando");
  if (Math.abs(hidr.derKangli - 0.30) > 1e-9) fail("(b) derechos de Kangli: esperaba 0,30 de la tabla y dio " + hidr.derKangli);
  if (Math.abs(hidr.derOtro - 0.25) > 1e-9) fail("(c) el default de derechos tiene que salir de gv_imp_nac_config (0,25) y dio " + hidr.derOtro);
  if (hidr.lista.indexOf("Nueva Fabrica") < 0) fail("(b) un proveedor que sólo está en la tabla no apareció en _PROV_IMP_LISTA");
  if (hidr.impNueva !== "Tierra Nativa") fail("(b) el importador tiene que salir de la tabla y dio: " + hidr.impNueva);
  if (hidr.mesesKangli !== 6) fail("(d) meses objetivo de Kangli: esperaba 6 y dio " + hidr.mesesKangli);
  if (hidr.mesesFrontier !== 10) fail("(d) Frontier hereda el general (10) y dio " + hidr.mesesFrontier);
  if (hidr.minKangli !== 40000) fail("(d) el mínimo de Kangli sale de su fila (40.000) y dio " + hidr.minKangli);

  // ── (a) el botón está en el encabezado de cada proveedor ───────────────────────────
  const it = (cod, prov) => ({ cod, prov, desc: cod, proyUni: 10, objetivoUni: 100, stockUni: 0, enCurso: 0,
    aPedirUni: 100, aPedirCajas: 1, uniMaster: 100, fobUni: 0.2, m3Master: 0.05, det: [{ id: 1, curso: 0, marca: "" }] });
  const botones = await p.evaluate((items) => {
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items: items, meses: 10, minUsd: 25000, nac: { modo: "consolidada", valorM3: 110, tn: 0 } }, soloPedir: true, mcOverride: {} };
    _pedImpRender();
    return [...document.querySelectorAll('#stkPopBody button')].filter(x => /Configurar/.test(x.textContent))
      .map(x => (x.getAttribute("onclick") || ""));
  }, [it("587C", "Frontier"), it("231", "Kangli")]);
  if (botones.length !== 2) fail("(a) esperaba un ⚙ por proveedor (2) y salieron " + botones.length);
  if (!botones.every(o => /pedImpCfgAbrir\(/.test(o))) fail("(a) el ⚙ no llama a pedImpCfgAbrir: " + botones.join(" | "));

  // ── (e) el pop-up guarda por RPC, con los % en tanto por uno y el vacío como null ──
  await p.evaluate(() => pedImpCfgAbrir(encodeURIComponent("Kangli")));
  await p.waitForFunction(() => !!document.getElementById("impCfgDer"));
  const pintado = await p.evaluate(() => ({
    der: document.getElementById("impCfgDer").value,
    meses: document.getElementById("impCfgMeses").value,
    m3: document.getElementById("impCfgM3").value,
    m3ph: document.getElementById("impCfgM3").getAttribute("placeholder")
  }));
  if (pintado.der !== "30") fail("(e) el % propio se muestra en PORCENTAJE; dio: " + pintado.der);
  if (pintado.meses !== "6") fail("(e) los meses propios no se pintaron: " + pintado.meses);
  if (pintado.m3 !== "") fail("(e) un valor heredado tiene que verse VACÍO y dio: " + pintado.m3);
  if (pintado.m3ph !== "110") fail("(e) el heredado va de placeholder y dio: " + pintado.m3ph);

  await p.evaluate(() => { document.getElementById("impCfgDer").value = "22"; document.getElementById("impCfgMeses").value = ""; });
  await p.evaluate(() => pedImpCfgGuardar());
  await p.waitForFunction(() => !document.querySelector("#impCfgOv button[disabled]"));
  const g = rpc.filter(x => x.fn === "gv_imp_proveedor_guardar").pop();
  if (!g) fail("(e) no se llamó a gv_imp_proveedor_guardar");
  else {
    if (Math.abs(g.body.p.derechos_pct - 0.22) > 1e-9) fail("(e) el % tiene que viajar en tanto por uno y viajó " + g.body.p.derechos_pct);
    if (g.body.p.meses_objetivo !== null) fail("(e) el campo vacío tiene que viajar null (= heredado) y viajó " + g.body.p.meses_objetivo);
    if (g.body.p.proveedor !== "Kangli") fail("(e) guardó otro proveedor: " + g.body.p.proveedor);
  }

  // ── (f) sacar un código NO lo borra: lo deja sin proveedor ─────────────────────────
  await p.evaluate(() => pedImpCfgTab("cods"));
  await p.waitForFunction(() => !!document.querySelector("#impCfgOv"));
  await p.evaluate(() => pedImpCfgCodigo(encodeURIComponent("231"), ""));
  await p.waitForFunction(() => true);
  const c = rpc.filter(x => x.fn === "gv_imp_codigo_proveedor").pop();
  if (!c) fail("(f) no se llamó a gv_imp_codigo_proveedor");
  else if (c.body.p_cod !== "231" || c.body.p_proveedor !== null) fail("(f) sacar un código mandó: " + JSON.stringify(c.body));

  if (errs.length) fail("errores de página: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("pedimp-config-proveedor: OK — ⚙ por proveedor · la config sale de la base · % en tanto por uno · vacío = heredado · sacar código no borra");
})();

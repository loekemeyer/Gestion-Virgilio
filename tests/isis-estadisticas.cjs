/* v26.16 · v26.20 · Estadísticas ISIS por artículo (Luis, 02/10/2026) — candado del layout CONFIGURADO.
   Arma los dos .xls con estadisticas.js + SheetJS de verdad, los vuelve a leer y compara celda por celda
   contra lo que dejan los manuales después de configurar el export de ISIS:
     · manual 29: sin F, D y C ni «Total General» → A2:D = código · descripción · bonificación · cantidad;
     · manual 31: sin I, J y K → B:H igual que ISIS (BUSCARV col 7 = unidades, col 4 = cajas), hoja «LK Sep-26»;
   y el código todo dígitos ya convertido a número. Los PEDIDOS DISRUPTIVOS van en ROJO y NEGRITA con el detalle
   en la columna I: se verifica leyendo el BIFF (FONT rojo + negrita y los XF de esas celdas), porque SheetJS
   community no escribe estilos y el color se pega a mano en eiXlsBytes. */
const path = require("path");
const fs = require("fs");
const X = require(path.join(__dirname, "..", "vendor", "xlsx.full.min.js"));
const ei = require(path.join(__dirname, "..", "estadisticas.js"));

let fallas = 0;
function ok(cond, msg) { if (!cond) { fallas++; console.log("  ✗ " + msg); } }
function celda(ws, a) { return ws[a] ? ws[a].v : undefined; }
function fmt(ws, a) { return ws[a] ? ws[a].z : undefined; }

/* lee el stream Workbook: fuentes, XF y el XF de cada celda (r,c) de la primera hoja */
function biff(bytes) {
  const cfb = X.CFB.read(bytes, { type: "array" });
  const ent = cfb.FileIndex.find(f => f && f.name === "Workbook");
  if (!ent) return null;
  const c = Uint8Array.from(ent.content), u16 = (p) => c[p] | (c[p + 1] << 8);
  const fonts = [], xfs = [], celdas = {}, hojas = [];
  let p = 0, enGlobals = true;
  while (p + 4 <= c.length) {
    const t = u16(p), len = u16(p + 2), d = p + 4;
    if (enGlobals && t === 0x31) fonts.push({ alto: u16(d), grbit: u16(d + 2), icv: u16(d + 4), bls: u16(d + 6) });
    if (enGlobals && t === 0xE0) xfs.push({ ifnt: u16(d), ifmt: u16(d + 2) });
    if (enGlobals && t === 0x85) hojas.push((c[d] | (c[d + 1] << 8) | (c[d + 2] << 16) | (c[d + 3] << 24)) >>> 0);
    if (enGlobals && t === 0x0A) enGlobals = false;
    else if (!enGlobals && [0x203, 0x204, 0xFD, 0x27E, 0x201].includes(t)) celdas[u16(d) + "," + u16(d + 2)] = u16(d + 4);
    p += 4 + len;
  }
  /* índice de FONT → registro (el 4 no existe en BIFF) */
  const fontDe = (i) => fonts[i >= 4 ? i - 1 : i];
  const rojaNegrita = (r, col) => {
    const ix = celdas[r + "," + col]; if (ix == null) return null;
    const f = fontDe(xfs[ix].ifnt); return !!f && f.icv === 0x0A && f.bls >= 700 && (f.grbit & 1) === 1;
  };
  const bofEn = hojas.map(pos => u16(pos) === 0x809);
  return { fonts, rojaNegrita, bofEn };
}

/* ---------- A) VENTAS configurada (manual 29) ---------- */
const filasV = [
  { cod: "026L", descripcion: "COLADOR Nº8", cantidad: 36, precio_max: 1122.1, promedio: 1122.1, precio_min: 1122.1, total: 40395.6, particip: 0.02 },
  { cod: "1546903", descripcion: "parte corta queso P/Loeke x 48", cantidad: 42768, precio_max: 1151.25, promedio: 1151.25, precio_min: 1151.25, total: 49236660, particip: 20.02 },
  { cod: "055", descripcion: "x", cantidad: 0, precio_max: 3777.31, promedio: 0, precio_min: 3348.07, total: 0, particip: 0 }
];
const bytesV = ei.eiXlsBytes(X, ei.eiHojaVentas(filasV), ei.eiNombreHoja("lk", "2026-09-01", "2026-09-30"));
const wbV = X.read(bytesV, { type: "array", cellNF: true });
const wsV = wbV.Sheets[wbV.SheetNames[0]];
ok(wbV.SheetNames[0] === "LK Sep-26", "ventas: la hoja se llama «LK Sep-26» (vino " + wbV.SheetNames[0] + ")");
const encV = { A1: "Artículo", B1: "Descripción", C1: "Bonificación", D1: "Cantidad", E1: "Máximo", F1: "Promedio", G1: "Mínimo", H1: "Total", I1: "% Particip." };
Object.keys(encV).forEach(a => ok(celda(wsV, a) === encV[a], "ventas encabezado " + a + " = " + encV[a] + " (vino " + celda(wsV, a) + ")"));
/* A2:D = lo que se pega en Costos (paso 22): código · descripción · bonificación · cantidad */
ok(celda(wsV, "A2") === "026L" && typeof celda(wsV, "A2") === "string", "ventas A2: código con letra queda TEXTO (026L)");
ok(celda(wsV, "A3") === 1546903 && typeof celda(wsV, "A3") === "number", "ventas A3: código todo dígitos va como NÚMERO (paso 25 «Convertir en número»)");
ok(celda(wsV, "A4") === 55, "ventas A4: 055 → 55, igual que lo convierte Excel");
ok(celda(wsV, "B2") === "COLADOR Nº8", "ventas B2 descripción");
ok(celda(wsV, "C2") === 0 && fmt(wsV, "C2") === "#,##0.000", "ventas C2 bonificación 0 #,##0.000");
ok(celda(wsV, "D2") === 36 && fmt(wsV, "D2") === "#,##0.000", "ventas D2 cantidad 36 #,##0.000");
ok(celda(wsV, "E2") === 1122.1 && fmt(wsV, "E2") === "#,##0.00", "ventas E2 máximo");
ok(celda(wsV, "F2") === 1122.1 && celda(wsV, "G2") === 1122.1, "ventas F2/G2 promedio y mínimo");
ok(celda(wsV, "H2") === 40395.6 && fmt(wsV, "H2") === "#,##0.00", "ventas H2 total");
ok(celda(wsV, "I2") === 0.02, "ventas I2 % particip.");
ok(wsV["!ref"] === "A1:I4", "ventas rango A1:I4: sin «Total General» ni pie, sin columnas vacías (vino " + wsV["!ref"] + ")");
ok(!Object.keys(wsV).some(k => k[0] !== "!" && String(wsV[k].v) === "Total General"), "ventas: no hay fila «Total General»");

/* ---------- B) PEDIDOS configurada (manual 31) + disruptivos ---------- */
const filasP = [
  { cod: "026", descripcion: " Ø 8 Env.", cajas: 121, unidades: 4356, importe: 112618.53 },
  { cod: "55219", descripcion: "Prensa Matambre", cajas: 1002, unidades: 1002, importe: 5495970 },
  { cod: "838", descripcion: "", cajas: 32, unidades: null, importe: null },
  { cod: "437E", descripcion: "Colador", cajas: 40, unidades: 480, importe: 1 }
];
const disrup = [
  { cod: "55219", cliente: "4263", razon_social: "Matiz SA", order_id: 1533, fecha: "2026-09-23", cajas: 1000, unidades: 1000,
    prom_cajas: 167, prom_unidades: 167, pedidos_hist: 3, hist_fc: 2, hist_desde: "2025-10-02", desvio: 4.988, tipo: "alza" },
  { cod: "437e", cliente: "801", razon_social: "Coto", order_id: 9, fecha: "2026-09-10", cajas: 20, unidades: 240,
    prom_cajas: null, prom_unidades: null, pedidos_hist: 0, hist_fc: 0, hist_desde: null, desvio: null, tipo: "incorporacion" },
  { cod: "437E", cliente: "771", razon_social: "La Anónima", order_id: 10, fecha: "2026-09-12", cajas: 4, unidades: 48,
    prom_cajas: 12, prom_unidades: 144, pedidos_hist: 2, hist_fc: 0, hist_desde: "2026-05-01", desvio: -0.6667, tipo: "baja" }
];
const bytesP = ei.eiXlsBytes(X, ei.eiHojaPedidos(filasP, { emp: "lk", disrup: ei.eiDisrupMapa(disrup) }), ei.eiNombreHoja("lk", "2026-09-01", "2026-09-30"));
const wbP = X.read(bytesP, { type: "array", cellNF: true });
const wsP = wbP.Sheets[wbP.SheetNames[0]];
ok(wbP.SheetNames[0] === "LK Sep-26", "pedidos: hoja «LK Sep-26» (la «LK MES-AÑO» del manual 31)");
const encP = { B1: "Artículo", D1: "Med.", E1: "Cantidad", F1: "Bonificac.", G1: "Med.", H1: "Cantidad" };
Object.keys(encP).forEach(a => ok(celda(wsP, a) === encP[a], "pedidos encabezado " + a + " = " + encP[a] + " (vino " + celda(wsP, a) + ")"));
ok(/disruptivo/i.test(String(celda(wsP, "I1"))), "pedidos I1: encabezado del detalle de disruptivos");
const filaP = { A2: "Div", B2: 26, C2: " Ø 8 Env.", D2: "caja", E2: 121, F2: 0, G2: "unidad", H2: 4356 };
Object.keys(filaP).forEach(a => ok(celda(wsP, a) === filaP[a], "pedidos " + a + " = " + filaP[a] + " (vino " + celda(wsP, a) + ")"));
ok(fmt(wsP, "E2") === "#,##0.00" && fmt(wsP, "H2") === "#,##0.00", "pedidos números #,##0.00");
ok(celda(wsP, "I2") === undefined, "pedidos I2 vacío (026 no es disruptivo)");
/* BUSCARV(cod; B:H; 7) = unidades y (…;4) = cajas: la columna 7 contando desde B es H, la 4 es E */
ok(celda(wsP, "B3") === 55219 && celda(wsP, "H3") === 1002 && celda(wsP, "E3") === 1002, "pedidos: BUSCARV B:H col 7 (unidades) y col 4 (cajas), código número");
ok(celda(wsP, "B4") === 838 && celda(wsP, "E4") === 32 && celda(wsP, "H4") === undefined, "pedidos sin UxB: unidades VACÍAS, no las cajas");
ok(celda(wsP, "B5") === "437E", "pedidos: 437E queda texto");
ok(!Object.keys(wsP).some(k => k[0] !== "!" && ["Total General", "$", "Impreso por:"].includes(String(wsP[k].v))), "pedidos: sin I, J, K (importe, $), sin total ni pie");
ok(wsP["!ref"] === "A1:I5", "pedidos rango A1:I5 (vino " + wsP["!ref"] + ")");
const d3 = String(celda(wsP, "I3")), d5 = String(celda(wsP, "I5"));
ok(/^▲ \+499%: Matiz SA \(LK 4263\) pidió 1\.000 u \(1\.000 cj\) el 23\/09 · prom\. 167 u \(167 cj\) en 3 ped\. \(2 por factura ISIS\) desde 02\/10\/25$/.test(d3),
   "pedidos I3: detalle del alza con cliente, cuánto, cuándo y contra qué promedio (vino " + d3 + ")");
ok(d5.indexOf("★ Incorporación: Coto (LK 801) pidió 240 u (20 cj) el 10/09") === 0, "pedidos I5: la incorporación va PRIMERO, con cliente y unidades (manual 31) (vino " + d5 + ")");
ok(/ \| ▼ -67%: La Anónima \(LK 771\) pidió 48 u \(4 cj\)/.test(d5), "pedidos I5: la baja también se detalla (±50 %) (vino " + d5 + ")");
/* el ROJO y la NEGRITA, leídos del BIFF */
const bP = biff(bytesP);
ok(!!bP, "pedidos: es un .xls BIFF8 (stream Workbook)");
if (bP) {
  ok(bP.fonts.every(f => f.alto === 200), "pedidos: toda la letra en 10 pt (vino " + JSON.stringify(bP.fonts.map(f => f.alto)) + ")");
  ok(bP.fonts.some(f => f.icv === 0x0A && f.bls === 700), "pedidos: existe la fuente roja y negrita");
  ok(bP.bofEn.length === 1 && bP.bofEn[0], "pedidos: el puntero de la hoja (BOUNDSHEET) quedó bien después de insertar la fuente");
  ok([0, 1, 2, 3, 4, 5, 6, 7, 8].every(c => bP.rojaNegrita(2, c) === true), "pedidos: la fila 3 (55219, disruptivo) entera en rojo y negrita, I incluida");
  ok([0, 1, 2, 3, 4, 5, 6, 7].every(c => bP.rojaNegrita(4, c) === true), "pedidos: la fila 5 (437E, incorporación) en rojo y negrita");
  ok([0, 1, 2, 3, 4, 5, 6, 7].every(c => bP.rojaNegrita(1, c) === false), "pedidos: la fila 2 (026) NO va en rojo");
  ok([1, 3, 4, 5, 7].every(c => bP.rojaNegrita(0, c) === false), "pedidos: el encabezado NO va en rojo");
}
/* sin disruptivos: ni columna I ni fuente roja */
const bytesP0 = ei.eiXlsBytes(X, ei.eiHojaPedidos(filasP, { emp: "lk", disrup: {} }), "LK Sep-26");
const wsP0 = X.read(bytesP0, { type: "array" }).Sheets["LK Sep-26"];
ok(wsP0 && wsP0["!ref"] === "A1:H5" && celda(wsP0, "I1") === undefined, "pedidos sin disruptivos: termina en H, sin columna I vacía");
const bP0 = biff(bytesP0);
ok(bP0 && !bP0.fonts.some(f => f.icv === 0x0A), "pedidos sin disruptivos: no se agrega la fuente roja");
/* un pedido grande: el stream pasa de 4 KB y CFB lo devuelve como Array (v26.20: así se perdía el parche) */
const muchas = []; for (let i = 0; i < 400; i++) muchas.push({ cod: String(1000 + i), descripcion: "art " + i, cajas: i, unidades: i * 12 });
muchas.push({ cod: "55219", descripcion: "Prensa", cajas: 1, unidades: 1 });
const bytesG = ei.eiXlsBytes(X, ei.eiHojaPedidos(muchas, { emp: "lk", disrup: ei.eiDisrupMapa(disrup) }), "LK Sep-26");
const bG = biff(bytesG);
ok(bG && bG.fonts.every(f => f.alto === 200) && bG.rojaNegrita(401, 1) === true && bG.rojaNegrita(400, 1) === false,
   "pedidos de 400 artículos: también Arial 10 y la fila disruptiva en rojo");
ok(X.read(bytesG, { type: "array" }).Sheets["LK Sep-26"]["!ref"] === "A1:I402", "pedidos de 400 artículos: SheetJS lo vuelve a leer entero");

/* ---------- C) ventas: .xls Excel 97 (BIFF8) con letra Arial 10 y sin rojo ---------- */
const bV = biff(bytesV);
ok(!!bV, "ventas: es un .xls BIFF8 (stream Workbook)");
if (bV) {
  ok(bV.fonts.length > 0 && bV.fonts.every(f => f.alto === 200), "ventas: letra de 10 puntos (200 twips) — vino " + JSON.stringify(bV.fonts.map(f => f.alto)));
  ok(!bV.fonts.some(f => f.icv === 0x0A), "ventas: sin fuente roja");
}

/* ---------- D) nombres de archivo ---------- */
ok(ei.eiNombre("ventas", "lk", "2026-09-01", "2026-09-30") === "esta_vtaarticutot1corte_vtas_sept_lk.xls", "nombre ventas LK sept");
ok(ei.eiNombre("ventas", "ch", "2026-09-01", "2026-09-30") === "esta_vtaarticutot1corte_vtas_sept_ch.xls", "nombre ventas CH sept");
ok(ei.eiNombre("pedidos", "lk", "2026-09-01", "2026-09-30") === "vta_pedidoporarticulotot_pedidos_lk_sep_26.xls", "nombre pedidos LK sep_26");
ok(ei.eiNombre("pedidos", "ch", "2026-02-01", "2026-02-28") === "vta_pedidoporarticulotot_pedidos_ch_feb_26.xls", "nombre pedidos CH feb (mes de 28)");
ok(ei.eiNombre("ventas", "lk", "2026-09-10", "2026-09-20").indexOf("1009-2009") > 0, "rango suelto lleva las fechas en el nombre");
ok(ei.eiNombreHoja("ch", "2026-02-01", "2026-02-28") === "CH Feb-26", "hoja CH Feb-26 (mes de 28)");
ok(ei.eiNombreHoja("lk", "2026-09-10", "2026-09-20") === "LK 10.09-20.09-26", "hoja de un rango suelto lleva las fechas (sin «/», que Excel no acepta)");

/* ---------- E) candados de puerta y de la regla de vacío ---------- */
const src = fs.readFileSync(path.join(__dirname, "..", "estadisticas.js"), "utf8");
const idx = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
ok(/onclick="openEstadisticasIsis\(\)"/.test(idx), "index: botón del panel supervisor abre openEstadisticasIsis()");
ok(/<script src="estadisticas\.js\?v=/.test(idx), "index: carga estadisticas.js con ?v=");
ok(/if \(!rows\.length\)[^\n]*No se bajó nada/.test(src), "una RPC vacía NO baja un Excel vacío");
ok(/if \(q\.error\)[^\n]*No se bajó nada/.test(src), "una RPC con error NO baja nada");
const sqlE = fs.readFileSync(path.join(__dirname, "..", "sql", "gv_isis_estadisticas_v2616.sql"), "utf8");
const sqlPed = sqlE.slice(sqlE.indexOf("function public.gv_isis_estad_pedidos"));
ok(/clave = 'gestion_desde'/.test(sqlPed) && /x\.fecha_pedido >= par\.gdesde/.test(sqlPed), "pedidos: sólo el pipeline (desde gestion_desde)");
ok(/"GV_Web_Cancelados"/.test(sqlPed) && /"GV_Pedidos_Anulados"/.test(sqlPed), "pedidos: sin cancelados ni anulados");

/* ---------- F) la pantalla de verdad: baja los .xls configurados, marca disruptivos y un vacío o un error no baja nada ---------- */
(async () => {
  let chromium;
  try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
  catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { chromium = null; } }
  if (!chromium) { console.log("  (sin Playwright: se saltea la parte de pantalla)"); return fin(); }
  const b = await chromium.launch();
  try {
    const ctx = await b.newContext({ viewport: { width: 1400, height: 900 }, serviceWorkers: "block", acceptDownloads: true });
    const p = await ctx.newPage();
    const errs = []; p.on("pageerror", (e) => errs.push(e.message));
    await p.route("**/rest/v1/**", (r) => r.abort());
    await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
    await p.evaluate(async (FILAS) => {
      const espera = (ms) => new Promise((res) => setTimeout(res, ms));
      for (let i = 0; i < 50 && typeof window.openEstadisticasIsis !== "function"; i++) await espera(100);
      window.requireSupervisor = () => true;
      window.__eiRpcLlamadas = [];
      window.__eiDisErr = false;
      window.sb = { rpc: async (name, args) => {
        window.__eiRpcLlamadas.push({ name, args });
        if (name === "gv_isis_estad_pedidos_disruptivos")
          return window.__eiDisErr ? { data: null, error: { message: "canceling statement due to statement timeout" } } : { data: FILAS.d, error: null };
        if (args.p_empresa === "ch" && name === "gv_isis_estad_pedidos") return { data: [], error: null };   /* vacío */
        if (name === "gv_isis_estad_ventas") return { data: FILAS.v, error: null };
        return { data: FILAS.p, error: null };
      } };
    }, { v: filasV, p: filasP, d: disrup });
    const btn = await p.$('.sup-actions.sup-secondary .sup-action-btn[onclick="openEstadisticasIsis()"]');
    ok(!!btn, "pantalla: el botón está en los secundarios del panel supervisor");
    await p.evaluate(() => window.openEstadisticasIsis());
    await p.waitForSelector("#eiB_vlk", { timeout: 5000 });
    await p.evaluate(() => { document.getElementById("eiMes").value = "2026-09"; window.eiMes(); });
    const anchoBtn = await p.$eval("#eiB_vlk", (e) => e.getBoundingClientRect().width);
    ok(anchoBtn < 200, "pantalla: el botón no hereda el button{width:100%} global (mide " + Math.round(anchoBtn) + " px)");
    /* ventas LK: el .xls ya configurado (manual 29) */
    const [dl] = await Promise.all([p.waitForEvent("download", { timeout: 15000 }), p.click("#eiB_vlk")]);
    ok(dl.suggestedFilename() === "esta_vtaarticutot1corte_vtas_sept_lk.xls", "pantalla: nombre del archivo (" + dl.suggestedFilename() + ")");
    const wb = X.read(fs.readFileSync(await dl.path()), { type: "buffer" });
    const ws = wb.Sheets[wb.SheetNames[0]];
    ok(wb.SheetNames[0] === "LK Sep-26" && celda(ws, "A2") === "026L" && celda(ws, "D2") === 36 && celda(ws, "A3") === 1546903 && ws["!ref"] === "A1:I4",
       "pantalla: ventas bajada ya configurada (sin C/D/F de ISIS ni «Total General», código número)");
    let llam = await p.evaluate(() => window.__eiRpcLlamadas);
    ok(llam.length === 1 && llam[0].name === "gv_isis_estad_ventas" && llam[0].args.p_empresa === "lk" && llam[0].args.p_desde === "2026-09-01" && llam[0].args.p_hasta === "2026-09-30",
       "pantalla: ventas llama UNA RPC con LK y el mes entero, sin disruptivos (" + JSON.stringify(llam) + ")");
    /* pedidos LK: pide también los disruptivos y los marca */
    const [dlP] = await Promise.all([p.waitForEvent("download", { timeout: 15000 }), p.click("#eiB_plk")]);
    ok(dlP.suggestedFilename() === "vta_pedidoporarticulotot_pedidos_lk_sep_26.xls", "pantalla: nombre de pedidos (" + dlP.suggestedFilename() + ")");
    const bytesDl = fs.readFileSync(await dlP.path());
    const wbD = X.read(bytesDl, { type: "buffer" });
    const wsD = wbD.Sheets[wbD.SheetNames[0]];
    ok(wbD.SheetNames[0] === "LK Sep-26" && celda(wsD, "B3") === 55219 && /^▲ \+499%: Matiz SA/.test(String(celda(wsD, "I3"))),
       "pantalla: pedidos bajado con hoja «LK Sep-26» y el detalle del disruptivo en I");
    const bD = biff(new Uint8Array(bytesDl));
    ok(bD && bD.rojaNegrita(2, 1) === true && bD.rojaNegrita(1, 1) === false, "pantalla: el .xls bajado trae la fila disruptiva en rojo y negrita");
    llam = (await p.evaluate(() => window.__eiRpcLlamadas)).slice(1);
    ok(llam.length === 2 && llam.some(x => x.name === "gv_isis_estad_pedidos") && llam.some(x => x.name === "gv_isis_estad_pedidos_disruptivos" && x.args.p_empresa === "lk"),
       "pantalla: pedidos llama a la RPC de pedidos y a la de disruptivos (" + JSON.stringify(llam.map(x => x.name)) + ")");
    const filaPlk = await p.$eval("#eiB_plk", (e) => e.closest("tr").textContent);
    ok(/2 art\.\s*3 pedidos/.test(filaPlk), "pantalla: la tabla dice cuántos artículos van en rojo y de cuántos pedidos (" + filaPlk + ")");
    /* los disruptivos no se pueden leer → NO se baja el archivo sin marcar */
    let bajoDeMas = false; p.on("download", () => { bajoDeMas = true; });
    await p.evaluate(() => { window.__eiDisErr = true; });
    await p.click("#eiB_plk");
    await p.waitForFunction(() => /disruptivos/.test((document.getElementById("eiT") || {}).textContent || "") && /No se bajó nada/.test(document.getElementById("eiT").textContent), null, { timeout: 5000 }).catch(() => {});
    await new Promise((res) => setTimeout(res, 600));
    let txt = await p.$eval("#eiT", (e) => e.textContent);
    ok(!bajoDeMas, "pantalla: si los disruptivos no se pueden leer, NO baja el archivo sin marcar");
    ok(/No pude leer los pedidos disruptivos/.test(txt), "pantalla: el error de los disruptivos lo dice en la tabla");
    /* pedidos CH vuelve vacío: no tiene que bajar nada y tiene que decirlo */
    await p.evaluate(() => { window.__eiDisErr = false; });
    await p.click("#eiB_pch");
    await p.waitForFunction(() => /Volvió vacío/.test((document.getElementById("eiT") || {}).textContent || ""), null, { timeout: 5000 }).catch(() => {});
    await new Promise((res) => setTimeout(res, 600));
    txt = await p.$eval("#eiT", (e) => e.textContent);
    ok(!bajoDeMas, "pantalla: un reporte vacío NO baja un Excel");
    ok(/Volvió vacío[^]*No se bajó nada/.test(txt), "pantalla: el vacío lo dice en la tabla");
    ok(!errs.length, "pantalla: sin errores de JS (" + errs.join(" | ") + ")");
  } catch (e) { ok(false, "pantalla: " + (e && e.message || e)); }
  await b.close();
  fin();
})();

function fin() {
  if (fallas) { console.log("isis-estadisticas: " + fallas + " falla(s)"); process.exit(1); }
  console.log("isis-estadisticas: ok (ventas y pedidos configurados como piden los manuales 29 y 31, disruptivos en rojo con detalle, BIFF8 Arial 10; pantalla y descarga)");
}

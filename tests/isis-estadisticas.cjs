/* v26.15 · Estadísticas ISIS por artículo (Luis, 02/10/2026) — candado del layout.
   Arma los dos .xls con estadisticas.js + SheetJS de verdad, los vuelve a leer y compara
   celda por celda contra el export crudo de ISIS (valores sacados de los Excel de sept/26:
   esta_vtaarticutot1corte_vtas_sept_ch.xls y vta_pedidoporarticulotot_pedidos_lk_sep_26.xls).
   Si alguien corre una columna, el BUSCARV de la Estadística Madre (B:H, col 7 / col 4) y el
   paso 21 del manual 29 (borrar F, D, C) dejan de andar sin que nadie se entere: por eso esto. */
const path = require("path");
const fs = require("fs");
const X = require(path.join(__dirname, "..", "vendor", "xlsx.full.min.js"));
const ei = require(path.join(__dirname, "..", "estadisticas.js"));

let fallas = 0;
function ok(cond, msg) { if (!cond) { fallas++; console.log("  ✗ " + msg); } }
function celda(ws, a) { return ws[a] ? ws[a].v : undefined; }
function fmt(ws, a) { return ws[a] ? ws[a].z : undefined; }

const cuando = new Date(2026, 9, 1, 15, 39, 47);   /* 01/10/2026 15:39:47, como el de Vivi */

/* ---------- A) VENTAS (16 columnas A..P) ---------- */
const filasV = [
  { cod: "026L", descripcion: "COLADOR Nº8", cantidad: 36, precio_max: 1122.1, promedio: 1122.1, precio_min: 1122.1, total: 40395.6, particip: 0.02 },
  { cod: "1546903", descripcion: "parte corta queso P/Loeke x 48", cantidad: 42768, precio_max: 1151.25, promedio: 1151.25, precio_min: 1151.25, total: 49236660, particip: 20.02 },
  { cod: "055", descripcion: "x", cantidad: 0, precio_max: 3777.31, promedio: 0, precio_min: 3348.07, total: 0, particip: 0 }
];
const bytesV = ei.eiXlsBytes(X, ei.eiHojaVentas(filasV, { usuario: "VIVI", cuando }));
const wbV = X.read(bytesV, { type: "array", cellNF: true });
const wsV = wbV.Sheets[wbV.SheetNames[0]];
ok(wbV.SheetNames[0] === "Sheet1", "ventas: la hoja se llama Sheet1");
/* encabezado: exactamente donde lo pone ISIS */
const encV = { E1: "Bonificación", G1: "Cantidad", I1: "Máximo", K1: "Promedio", M1: "Mínimo", N1: "Total", O1: "% Particip." };
Object.keys(encV).forEach(a => ok(celda(wsV, a) === encV[a], "ventas encabezado " + a + " = " + encV[a] + " (vino " + celda(wsV, a) + ")"));
["A1", "B1", "C1", "D1", "F1", "H1", "J1", "L1", "P1"].forEach(a => ok(celda(wsV, a) === undefined, "ventas encabezado " + a + " vacío"));
/* fila de datos 026L = la de ISIS */
ok(celda(wsV, "A2") === "026L" && typeof celda(wsV, "A2") === "string", "ventas A2: código como TEXTO (026L)");
ok(celda(wsV, "B2") === "COLADOR Nº8", "ventas B2 descripción");
ok(celda(wsV, "E2") === 0 && fmt(wsV, "E2") === "#,##0.000", "ventas E2 bonificación 0 #,##0.000");
ok(celda(wsV, "G2") === 36 && fmt(wsV, "G2") === "#,##0.000", "ventas G2 cantidad 36 #,##0.000");
ok(celda(wsV, "I2") === 1122.1 && fmt(wsV, "I2") === "#,##0.00", "ventas I2 máximo");
ok(celda(wsV, "K2") === 1122.1, "ventas K2 promedio");
ok(celda(wsV, "M2") === 1122.1, "ventas M2 mínimo");
ok(celda(wsV, "N2") === 40395.6 && fmt(wsV, "N2") === "#,##0.00", "ventas N2 total");
ok(celda(wsV, "O2") === 0.02, "ventas O2 % particip.");
["C2", "D2", "F2", "H2", "J2", "L2", "P2"].forEach(a => ok(celda(wsV, a) === undefined, "ventas " + a + " vacío (el manual 29 borra F, D y C)"));
/* total corrido una columna a la izquierda, como Crystal */
ok(celda(wsV, "B5") === "Total General", "ventas B5 'Total General'");
ok(celda(wsV, "D5") === 0, "ventas D5 suma bonificación");
ok(celda(wsV, "F5") === 42804, "ventas F5 suma cantidad (36 + 42768 + 0)");
ok(celda(wsV, "M5") === 49277055.6, "ventas M5 total general");
ok(celda(wsV, "N5") === undefined, "ventas N5 vacío (el total NO va bajo la columna Total)");
/* pie */
ok(celda(wsV, "A6") === "Impreso por:" && celda(wsV, "B6") === "VIVI", "ventas pie Impreso por: VIVI");
ok(celda(wsV, "C6") === 46296 && fmt(wsV, "C6") === "m/d/yy", "ventas C6 fecha 01/10/2026 = 46296 (m/d/yy)");
ok(Math.abs(celda(wsV, "D6") - 36494.65262731481) < 1e-6, "ventas D6 hora 15:39:47 como la escribe Crystal (36494,65…)");
ok(celda(wsV, "M6") === "Hoja Nro:" && celda(wsV, "N6") === 1 && celda(wsV, "O6") === "de" && celda(wsV, "P6") === 1, "ventas pie Hoja Nro: 1 de 1");
ok(wsV["!ref"] === "A1:P6", "ventas rango A1:P6 (vino " + wsV["!ref"] + ")");

/* ---------- B) PEDIDOS (12 columnas A..L) ---------- */
const filasP = [
  { cod: "026", descripcion: " Ø 8 Env.", cajas: 121, unidades: 4356, importe: 112618.53 },
  { cod: "55219", descripcion: "Prensa Matambre", cajas: 1002, unidades: 1002, importe: 5495970 },
  { cod: "838", descripcion: "", cajas: 32, unidades: null, importe: null, uxb: null }
];
const bytesP = ei.eiXlsBytes(X, ei.eiHojaPedidos(filasP, { usuario: "VIVI", cuando }));
const wbP = X.read(bytesP, { type: "array", cellNF: true });
const wsP = wbP.Sheets[wbP.SheetNames[0]];
const encP = { B1: "Artículo", D1: "Med.", E1: "Cantidad", F1: "Bonificac.", G1: "Med.", H1: "Cantidad", I1: "Bonificac.", J1: "Mda.", K1: "Importe" };
Object.keys(encP).forEach(a => ok(celda(wsP, a) === encP[a], "pedidos encabezado " + a + " = " + encP[a] + " (vino " + celda(wsP, a) + ")"));
const filaP = { A2: "Div", B2: "026", C2: " Ø 8 Env.", D2: "caja", E2: 121, F2: 0, G2: "unidad", H2: 4356, I2: 0, J2: "$", K2: 112618.53 };
Object.keys(filaP).forEach(a => ok(celda(wsP, a) === filaP[a], "pedidos " + a + " = " + filaP[a] + " (vino " + celda(wsP, a) + ")"));
ok(fmt(wsP, "E2") === "#,##0.00" && fmt(wsP, "H2") === "#,##0.00" && fmt(wsP, "K2") === "#,##0.00", "pedidos números #,##0.00");
/* BUSCARV(cod; B:H; 7) = unidades y (…;4) = cajas: la columna 7 contando desde B es H, la 4 es E */
ok(celda(wsP, "H3") === 1002 && celda(wsP, "E3") === 1002, "pedidos: BUSCARV B:H col 7 (unidades) y col 4 (cajas)");
ok(celda(wsP, "B4") === "838" && celda(wsP, "E4") === 32 && celda(wsP, "H4") === undefined && celda(wsP, "K4") === undefined, "pedidos sin UxB: unidades e importe VACÍOS, no las cajas");
ok(celda(wsP, "H5") === "Total General" && celda(wsP, "J5") === 5608588.53, "pedidos total en H/J como ISIS");
ok(String(fmt(wsP, "J5")).indexOf("[$$-2C0A]") === 0, "pedidos total con el formato moneda de ISIS");
ok(celda(wsP, "A6") === "Impreso por:" && celda(wsP, "C6") === 46296 && fmt(wsP, "C6") === "dd/MM/yyyy", "pedidos pie con fecha dd/MM/yyyy");
ok(celda(wsP, "I6") === "Hoja Nro:" && celda(wsP, "J6") === 1 && celda(wsP, "K6") === "de" && celda(wsP, "L6") === 1, "pedidos pie Hoja Nro: 1 de 1");
ok(wsP["!ref"] === "A1:L6", "pedidos rango A1:L6 (vino " + wsP["!ref"] + ")");

/* ---------- C) es un .xls Excel 97 (BIFF8) con letra Arial 10, como ISIS ---------- */
const cfb = X.CFB.read(bytesV, { type: "array" });
const ent = cfb.FileIndex.find(f => f.name === "Workbook");
ok(!!ent, "es un .xls BIFF8 (stream Workbook)");
if (ent) {
  const c = ent.content; let p = 0; const alturas = [];
  while (p + 4 <= c.length) {
    const t = c[p] | (c[p + 1] << 8), len = c[p + 2] | (c[p + 3] << 8);
    if (t === 0x31) alturas.push(c[p + 4] | (c[p + 5] << 8));
    if (t === 0x0A) break;
    p += 4 + len;
  }
  ok(alturas.length > 0 && alturas.every(h => h === 200), "letra de 10 puntos (200 twips) — vino " + JSON.stringify(alturas));
}

/* ---------- D) nombres de archivo ---------- */
ok(ei.eiNombre("ventas", "lk", "2026-09-01", "2026-09-30") === "esta_vtaarticutot1corte_vtas_sept_lk.xls", "nombre ventas LK sept");
ok(ei.eiNombre("ventas", "ch", "2026-09-01", "2026-09-30") === "esta_vtaarticutot1corte_vtas_sept_ch.xls", "nombre ventas CH sept");
ok(ei.eiNombre("pedidos", "lk", "2026-09-01", "2026-09-30") === "vta_pedidoporarticulotot_pedidos_lk_sep_26.xls", "nombre pedidos LK sep_26");
ok(ei.eiNombre("pedidos", "ch", "2026-02-01", "2026-02-28") === "vta_pedidoporarticulotot_pedidos_ch_feb_26.xls", "nombre pedidos CH feb (mes de 28)");
ok(ei.eiNombre("ventas", "lk", "2026-09-10", "2026-09-20").indexOf("1009-2009") > 0, "rango suelto lleva las fechas en el nombre");

/* ---------- E) candados de puerta y de la regla de vacío ---------- */
const src = fs.readFileSync(path.join(__dirname, "..", "estadisticas.js"), "utf8");
const idx = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
ok(/onclick="openEstadisticasIsis\(\)"/.test(idx), "index: botón del panel supervisor abre openEstadisticasIsis()");
ok(/<script src="estadisticas\.js\?v=/.test(idx), "index: carga estadisticas.js con ?v=");
ok(/if \(!rows\.length\)[^\n]*No se bajó nada/.test(src), "una RPC vacía NO baja un Excel vacío");
ok(/if \(q\.error\)[^\n]*No se bajó nada/.test(src), "una RPC con error NO baja nada");
const sqlE = fs.readFileSync(path.join(__dirname, "..", "sql", "gv_isis_estadisticas_v2615.sql"), "utf8");
const sqlPed = sqlE.slice(sqlE.indexOf("function public.gv_isis_estad_pedidos"));
ok(/clave = 'gestion_desde'/.test(sqlPed) && /x\.fecha_pedido >= par\.gdesde/.test(sqlPed), "pedidos: sólo el pipeline (desde gestion_desde)");
ok(/"GV_Web_Cancelados"/.test(sqlPed) && /"GV_Pedidos_Anulados"/.test(sqlPed), "pedidos: sin cancelados ni anulados");

/* ---------- F) la pantalla de verdad: abre, baja el .xls y un vacío no baja nada ---------- */
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
      window.sb = { rpc: async (name, args) => {
        window.__eiRpcLlamadas.push({ name, args });
        if (args.p_empresa === "ch" && name === "gv_isis_estad_pedidos") return { data: [], error: null };   /* vacío */
        if (name === "gv_isis_estad_ventas") return { data: FILAS.v, error: null };
        return { data: FILAS.p, error: null };
      } };
    }, { v: filasV, p: filasP });
    const btn = await p.$('.sup-actions.sup-secondary .sup-action-btn[onclick="openEstadisticasIsis()"]');
    ok(!!btn, "pantalla: el botón está en los secundarios del panel supervisor");
    await p.evaluate(() => window.openEstadisticasIsis());
    await p.waitForSelector("#eiB_vlk", { timeout: 5000 });
    await p.evaluate(() => { document.getElementById("eiMes").value = "2026-09"; window.eiMes(); });
    const anchoBtn = await p.$eval("#eiB_vlk", (e) => e.getBoundingClientRect().width);
    ok(anchoBtn < 200, "pantalla: el botón no hereda el button{width:100%} global (mide " + Math.round(anchoBtn) + " px)");
    const [dl] = await Promise.all([p.waitForEvent("download", { timeout: 15000 }), p.click("#eiB_vlk")]);
    ok(dl.suggestedFilename() === "esta_vtaarticutot1corte_vtas_sept_lk.xls", "pantalla: nombre del archivo (" + dl.suggestedFilename() + ")");
    const ruta = await dl.path();
    const wb = X.read(fs.readFileSync(ruta), { type: "buffer" });
    const ws = wb.Sheets[wb.SheetNames[0]];
    ok(celda(ws, "A2") === "026L" && celda(ws, "G2") === 36 && celda(ws, "B5") === "Total General", "pantalla: el .xls bajado tiene el layout de ISIS");
    const llam = await p.evaluate(() => window.__eiRpcLlamadas);
    ok(llam.length === 1 && llam[0].args.p_empresa === "lk" && llam[0].args.p_desde === "2026-09-01" && llam[0].args.p_hasta === "2026-09-30",
       "pantalla: llama a la RPC con LK y el mes entero (" + JSON.stringify(llam) + ")");
    /* pedidos CH vuelve vacío: no tiene que bajar nada y tiene que decirlo */
    let bajoVacio = false; p.on("download", () => { bajoVacio = true; });
    await p.click("#eiB_pch");
    await p.waitForFunction(() => /No se bajó nada/.test((document.getElementById("eiT") || {}).textContent || ""), null, { timeout: 5000 }).catch(() => {});
    await new Promise((res) => setTimeout(res, 600));
    const txt = await p.$eval("#eiT", (e) => e.textContent);
    ok(!bajoVacio, "pantalla: un reporte vacío NO baja un Excel");
    ok(/No se bajó nada/.test(txt), "pantalla: el vacío lo dice en la tabla");
    ok(!errs.length, "pantalla: sin errores de JS (" + errs.join(" | ") + ")");
  } catch (e) { ok(false, "pantalla: " + (e && e.message || e)); }
  await b.close();
  fin();
})();

function fin() {
  if (fallas) { console.log("isis-estadisticas: " + fallas + " falla(s)"); process.exit(1); }
  console.log("isis-estadisticas: ok (layout ventas A..P y pedidos A..L como ISIS, Arial 10, BIFF8; pantalla y descarga)");
}

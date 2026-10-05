/* v26.69 (Luis, 05/10/2026) — «quiero que se pueda descargar un excel del stock y de los insumos
   que tenemos. botón de descargar excel en las pestañas correspondientes de Stock y Compras».

   Corre la pantalla de verdad y la librería de Excel de verdad (vendor/xlsx), y lee lo que se baja.
   A) la barra de Stocks tiene el botón «⬇ Excel» (stkXlsBtn) y la pestaña Insumos el suyo (stkInsXlsBtn)
   B) el Excel de Stock baja LO QUE SE VE: con la búsqueda puesta, sólo esas filas; y con LK/CH,
      Est. Madre y el NETO de cajas pedidas (el mismo número de la celda, regla v24.04)
   C) sin filtro, salen todas las filas visibles y en el orden de la tabla (negativos primero)
   D) el Excel de Insumos: una fila por insumo; el que tiene saldo en DOS unidades sin factor sale en
      dos filas (sumar Kg + Uni no significa nada, v8.63); el que está en 0 sale igual (es el catálogo)
   E) el Excel de Insumos respeta el filtro de «Todos los insumos»
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
    const X = await pppLoadXlsx();
    let bajado = null;
    X.writeFile = function (wb, nombre) {
      const ws = wb.Sheets[wb.SheetNames[0]];
      bajado = { nombre: nombre, hoja: wb.SheetNames[0], aoa: X.utils.sheet_to_json(ws, { header: 1, defval: "" }) };
    };
    const esperar = async function () { for (let i = 0; i < 50 && !bajado; i++) await new Promise((r) => setTimeout(r, 20)); const x = bajado; bajado = null; return x; };
    const fila = function (cod, desc, terminado, ped, linea) {
      return { cod: cod, descripcion: desc, linea: linea || "LK", terminado: terminado, excedente: 0, separar_pedidos: 0,
               a_facturar: 0, a_guardar: 0, racks: 0, racks_ch: 0, para_envasar: 0, insumos_dep: 0,
               stock_total: terminado, cajas_pedidas: ped };
    };
    const rows = [fila("501", "Pinza Asado", 10, 251), fila("505", "Cuchillo", 40, 551), fila("026", "Colador 8", -2, 0)];
    const armar = function (filtro) {
      _stk = { movs: [], viewRows: rows, cutoff: 0, dem: { "501": 251, "505": 551 }, cap: [], fcs: {}, gConf: [],
               filtro: filtro || "", openArt: null, soloNeg: false,
               pedNeto: { "501": { tot: 251, neto: 225, tp: 26, curso: 0, fam: "501", sec: false, famTp: 26, famCurso: 0, famN: 1 } } };
      return stkBodyStocks();
    };
    const out = {};
    // A
    out.btnStock = armar("").indexOf('id="stkXlsBtn"') >= 0;
    // B — con búsqueda
    armar("501");
    stkDescargarExcel();
    const x1 = await esperar();
    out.b_hoja = x1 && x1.hoja;
    out.b_nombre = x1 && /^Stock \d{4}-\d{2}-\d{2} \d{2}\.\d{2}\.xlsx$/.test(x1.nombre);
    out.b_hdr = x1 ? x1.aoa[0].slice(0, 6).join("|") : null;
    out.b_filas = x1 ? x1.aoa.slice(1).map((r) => String(r[0])).join(",") : null;
    out.b_neto = x1 && x1.aoa[1] ? x1.aoa[1][5] : null;                       // 225, no 251
    out.b_tot = x1 && x1.aoa[1] ? x1.aoa[1][8] : null;                        // 251 en «Ped. total»
    out.b_lin = x1 && x1.aoa[1] ? x1.aoa[1][1] : null;
    // C — sin filtro: todas las visibles, el negativo primero (como la tabla)
    armar("");
    stkDescargarExcel();
    const x2 = await esperar();
    out.c_filas = x2 ? x2.aoa.slice(1).map((r) => String(r[0])).join(",") : null;

    // D / E — insumos
    _stkIns = { cat: "", abierta: "", filtro: "", edit: null, nuevoEn: "", msg: "", tf: {}, hf: { cod: "", grupo: "" }, abre: {}, hist: [],
      items: [
        { cod: "9001", nombre: "Bolsa 20x30", cat: "", ubic: "", isis: "", por: "", xuni: [{ uni: "Kg", saldo: 3 }, { uni: "Uni", saldo: 500 }], ubics: [{ sector: "R01AD", cantidad: 3, estado: "ok" }] },
        { cod: "9002", nombre: "Cinta", cat: "", ubic: "X20", isis: "77", por: "", xuni: [], ubics: [] },
        { cod: "9003", nombre: "Etiqueta", cat: "", ubic: "", isis: "", por: "", xuni: [{ uni: "Uni", saldo: 1200 }], ubics: [] }
      ] };
    const hi = stkBodyInsumos();
    out.btnIns = hi.indexOf('id="stkInsXlsBtn"') >= 0 && hi.indexOf("Excel de insumos (3)") >= 0;
    stkInsDescargarExcel();
    const x3 = await esperar();
    out.d_hoja = x3 && x3.hoja;
    out.d_hdr = x3 ? x3.aoa[0].join("|") : null;
    out.d_filas = x3 ? x3.aoa.slice(1).map((r) => r[0] + ":" + r[5] + " " + r[6]).join(",") : null;
    out.d_ubic = x3 && x3.aoa[1] ? x3.aoa[1][4] : null;
    out.d_isis = x3 && x3.aoa[3] ? x3.aoa[3][1] : null;
    _stkIns.tf = { cod: "9003" };
    stkInsDescargarExcel();
    const x4 = await esperar();
    out.e_filas = x4 ? x4.aoa.slice(1).map((r) => String(r[0])).join(",") : null;
    return out;
  });
  const pass = r.btnStock && r.b_hoja === "Stock" && r.b_nombre &&
    r.b_hdr === "Código|LK/CH|Descripción|Est. Madre (caj/mes)|Total Stock|Cajas Pedidas (a cubrir)" &&
    r.b_filas === "501" && r.b_neto === 225 && r.b_tot === 251 && r.b_lin === "LK" &&
    r.c_filas === "026,501,505" &&
    r.btnIns && r.d_hoja === "Insumos" &&
    r.d_hdr === "Código|ISIS|Detalle|Categoría|Rack / sector|Cantidad|Unidad|Equivalencias / nota" &&
    r.d_filas === "9001:3 Kg,9001:500 Uni,9002:0 ,9003:1200 Uni" && r.d_ubic === "R01AD (3)" && r.d_isis === "77" &&
    r.e_filas === "9003" && errs.length === 0;
  console.log("stk-excel-stock-insumos:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();

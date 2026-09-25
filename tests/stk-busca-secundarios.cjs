/* Regresion v22.70 (Luis, 25/09/2026) — "si busco exactamente un codigo principal en la tabla
   de stock deberia aparecerme tambien el codigo secundario o los codigos secundarios".

   La familia sale de la FILA de stock (familia_principal / es_secundario, que arma el backend
   desde Equivalencias_Familia). Chequea:
   - buscar 607E trae el 565 (familia que la semilla EQUIV_FAMILIAS no conoce);
   - buscar 437E (dual) trae el 029;
   - buscar un pedazo ("60") NO trae secundarios: sólo el código entero;
   - buscar el secundario no trae nada extra;
   - el secundario sale PEGADO a su principal (orden de la tabla).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const fila = (cod, fam, sec, t) => ({ cod, descripcion: "art " + cod, linea: "LK", familia_principal: fam, es_secundario: sec,
      terminado: t, excedente: 0, separar_pedidos: 0, a_facturar: 0, a_guardar: 0, racks: 0, racks_ch: 0,
      para_envasar: 0, insumos_dep: 0, stock_total: t, cajas_pedidas: 0 });
    const rows = [fila("607E", "607E", false, 10), fila("565", "607E", true, 1), fila("600", "600", false, 5),
      fila("437E LK", "437E", false, 7), fila("29", "437E", true, 0), fila("610", "610", false, 3)];
    const armar = (filtro) => { _stk = { movs: [], viewRows: rows, cutoff: 0, dem: {}, cap: [], fcs: {}, gConf: [], filtro, openArt: null, soloNeg: false }; return stkBodyStocks(); };
    const ve = (h, c) => h.indexOf('data-stk-cod="' + c + '"') >= 0;
    const pos = (h, c) => h.indexOf('data-stk-cod="' + c + '"');
    const h607 = armar("607E"), h437 = armar("437E"), h60 = armar("60"), h565 = armar("565"), todo = armar("");
    return {
      trae565: ve(h607, "565"),
      trae029: ve(h437, "29"),
      pedazoNoTrae: !ve(h60, "565"),
      secNoTraeNada: !ve(h565, "607E"),
      pegado: pos(todo, "600") < pos(todo, "607E") && pos(todo, "607E") < pos(todo, "565") && pos(todo, "565") < pos(todo, "610")
    };
  });
  const pass = Object.values(r).every(Boolean) && errs.length === 0;
  console.log("stk-busca-secundarios:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();

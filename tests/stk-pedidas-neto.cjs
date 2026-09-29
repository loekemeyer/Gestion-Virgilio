/* Regresion v24.04 (Luis, 29/09/2026) — "si lo comprometido no es stock disponible, esta bien.
   pero se tiene que contemplar igual en OCs que en Stocks".

   Stocks decia 251 cajas pedidas del 501 y OCs decia 225. No era redondeo: son DOS columnas de
   la MISMA fila de vista_stock_procesada con dos criterios (toda la demanda viva / sin las NP
   cuya tanda ya tiene TP, regla v19.85 de Thomas) y cada pantalla leia una. El criterio de OCs
   es el bueno y NO se toca; la que contaba de mas era Stocks.

   Mide las cinco mitades, porque cada una sin las otras no sirve:
   A) la celda muestra el NETO (225), no el total (251)
   B) el tooltip trae el desglose y ESCONDE los renglones en 0 (Luis)
   C) la linea de familia aparece cuando algun miembro tiene algo pickeado
   D) SIN el dato (lectura caida o todavia en vuelo) la celda muestra el TOTAL: nunca vacia
      ni en 0 — "no pude leer" no es "no hay" (regla §"una lectura ROTA no es un CERO")
   E) el Excel usa el MISMO numero que la pantalla, o volvemos al bug movido de lugar
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
    const fila = function (cod, desc, ped) {
      return { cod: cod, descripcion: desc, linea: "LK", terminado: 10, excedente: 0, separar_pedidos: 0,
               a_facturar: 0, a_guardar: 0, racks: 0, racks_ch: 0, para_envasar: 0, insumos_dep: 0,
               stock_total: 10, cajas_pedidas: ped };
    };
    // el caso real del 501, el 505, y un secundario con familia (839 -> 838E)
    const rows = [fila("501", "Pinza Asado", 251), fila("505", "Cuchillo", 551), fila("839", "Rallador Choc", 10)];
    const neto = {
      "501": { tot: 251, neto: 225, tp: 26, curso: 0,  fam: "501",  sec: false, famTp: 26, famCurso: 0, famN: 1 },
      "505": { tot: 551, neto: 481, tp: 70, curso: 3,  fam: "505",  sec: false, famTp: 70, famCurso: 3, famN: 1 },
      "839": { tot: 10,  neto: 10,  tp: 0,  curso: 0,  fam: "838E", sec: true,  famTp: 12, famCurso: 0, famN: 2 }
    };
    const armar = function (pedNeto) {
      _stk = { movs: [], viewRows: rows, cutoff: 0, dem: { "501": 251, "505": 551, "839": 10 }, cap: [],
               fcs: {}, gConf: [], filtro: "", openArt: null, soloNeg: false, pedNeto: pedNeto };
      return stkBodyStocks();
    };
    // la celda de "Cajas Pedidas" de una fila: es la que abre stkOpenCajasPedidasArt
    const celda = function (html, cod) {
      const i = html.indexOf('data-stk-cod="' + cod + '"'); if (i < 0) return null;
      const fin = html.indexOf("</tr>", i); const tr = html.slice(i, fin < 0 ? undefined : fin);
      const j = tr.indexOf("stkOpenCajasPedidasArt"); if (j < 0) return null;
      const td0 = tr.lastIndexOf("<td", j), td1 = tr.indexOf("</td>", j);
      return tr.slice(td0, td1);
    };
    const numDe = function (td) { const m = td && td.match(/<b>([^<]*)<\/b>/); return m ? m[1].trim() : null; };
    const titDe = function (td) { const m = td && td.match(/title="([^"]*)"/); return m ? m[1] : ""; };

    const con = armar(neto);
    // E) el Excel: el helper global tiene que resolver igual desde cualquier scope.
    //    ⚠ va ACA, con el mapa puesto: armar(null) lo borra (era el motivo del null en el 1.er intento)
    const xlsMismoNum = (function () { const o = _pedNetoOf("501"); return !!o && o.neto === 225; })();
    const sin = armar(null);
    const c501 = celda(con, "501"), c505 = celda(con, "505"), c839 = celda(con, "839");
    const s501 = celda(sin, "501");
    const t501 = titDe(c501), t505 = titDe(c505), t839 = titDe(c839);

    return {
      // A
      celdaNeto501: numDe(c501),            // 225, NO 251
      celdaNeto505: numDe(c505),            // 481
      // B  (el tooltip dice lo que hay y calla lo que da 0)
      tipDiceACubrir:  t501.indexOf("225") >= 0 && t501.indexOf("a cubrir") >= 0,
      tipDicePickeadas: t501.indexOf("26") >= 0 && t501.indexOf("ya pickeadas") >= 0,
      tipDiceTotal:     t501.indexOf("251") >= 0,
      tipEsconde0:      t501.indexOf("picking EMPEZADO") < 0,        // el 501 tiene curso = 0
      tipMuestraCurso:  t505.indexOf("picking EMPEZADO") >= 0,       // el 505 tiene 3
      // C
      tipFamilia839:  t839.indexOf("familia 838E") >= 0 && t839.indexOf("SECUNDARIO") >= 0,
      tipSinFamilia501: t501.indexOf("familia") < 0,                 // famN 1 y no es secundario
      // D
      sinDatoMuestraTotal: numDe(s501),     // 251: cae al total, no a 0 ni a vacio
      sinDatoTipViejo: titDe(s501).indexOf("Todas las cajas pedidas") >= 0,
      // E
      xlsMismoNum: xlsMismoNum
    };
  });
  const pass = r.celdaNeto501 === "225" && r.celdaNeto505 === "481" && r.tipDiceACubrir &&
    r.tipDicePickeadas && r.tipDiceTotal && r.tipEsconde0 && r.tipMuestraCurso &&
    r.tipFamilia839 && r.tipSinFamilia501 && r.sinDatoMuestraTotal === "251" &&
    r.sinDatoTipViejo && r.xlsMismoNum && errs.length === 0;
  console.log("stk-pedidas-neto:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();

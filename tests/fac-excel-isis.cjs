/* Paso 0 de la idea 3717 — "⬇ Excel para ISIS (prueba de formato)" en Facturación.
   Arma el MISMO archivo que hoy sale por mail a las 12:30 (Edge Function
   procesar-pedidos-db del proyecto LK) pero con las cajas ENTREGADAS, para
   confirmar que ISIS lo importa. Lo que este test blinda:

   F1) DEDUP por (np, cod_art). Entregas_Virgilio puede tener la misma línea dos
       veces cuando la NP se re-arma (28 NP de 748 en 60 días): sin dedup el Excel
       mandaría el doble de cajas a ISIS. Se toma la última fila y se topea contra
       lo pedido.
   F2) SPLIT por empresa: 18 líneas por NP en Loekemeyer (NP 9xxxx) y 15 en CHEF
       (NP 4xxxx). Verificado contra datos reales: 253 NP de LK tienen exactamente
       18 líneas y 25 NP de Chef exactamente 15.
   F3) ORDEN por código ascendente, que es como parte ISIS (verificado con las NP
       98680/98681 y 98682/98683 del 02/09). Con otro orden coincide la cantidad de
       pedidos pero no su contenido.
   F4) FORMATO XML Spreadsheet 2003 fiel: 12 columnas en orden, "029" como String
       (empieza con cero), celda vacía <Cell/>, hoja "Resumen" con la advertencia.
   F5) El archivo se llama PRUEBA_NO_IMPORTAR_* (esas NP ya están en ISIS).

   Todo con fetch stubbeado, sin red. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    window.alert = function () {};
    window.__isSupervisor = true;

    function J(data) { return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve(data); } }); }

    // 20 líneas entregadas en una NP de Loekemeyer → tiene que partir en 2 (18 + 2).
    const entLk = [];
    for (let i = 1; i <= 20; i++) entLk.push({ id: 100 + i, np: "98001", cod_art: String(500 + i), cajas_pedidas: 2, cajas_entregadas: 2 });
    // La línea 505 va DOS veces (re-armado): 2 + 2. Sin dedup daría 4 cajas.
    entLk.push({ id: 300, np: "98001", cod_art: "505", cajas_pedidas: 2, cajas_entregadas: 2 });
    // 16 líneas en una NP de CHEF → tiene que partir en 2 (15 + 1), no en 1.
    const entCh = [];
    for (let i = 1; i <= 16; i++) entCh.push({ id: 400 + i, np: "44001", cod_art: String(600 + i), cajas_pedidas: 1, cajas_entregadas: 1 });
    // NP con un artículo de código chico y uno con letra, para el padCodArt y el orden.
    const entMix = [
      { id: 500, np: "98002", cod_art: "56E", cajas_pedidas: 3, cajas_entregadas: 3 },
      { id: 501, np: "98002", cod_art: "29",  cajas_pedidas: 5, cajas_entregadas: 1 },   // parcial
      { id: 502, np: "98002", cod_art: "438E CH", cajas_pedidas: 1, cajas_entregadas: 1 },
      { id: 503, np: "98002", cod_art: "300", cajas_pedidas: 2, cajas_entregadas: 0 }    // 0 entregadas: NO va
    ];

    window.fetch = function (url) {
      url = String(url);
      if (url.indexOf("Facturacion_NP") >= 0) return J([
        { np: "98001", tanda: "D60A", m3: 1, razon_social: "Cliente LK", cod_cliente: "111", fecha_salida: "2026-09-03", facturado_at: "2026-09-03T18:00:00-03:00" },
        { np: "98002", tanda: "D60A", m3: 1, razon_social: "Cliente Mix", cod_cliente: "222", fecha_salida: "2026-09-03", facturado_at: "2026-09-03T18:00:00-03:00" },
        { np: "44001", tanda: "D60B", m3: 1, razon_social: "Cliente CH", cod_cliente: "333", fecha_salida: "2026-09-03", facturado_at: "2026-09-03T18:00:00-03:00" }
      ]);
      if (url.indexOf("Entregas_Virgilio") >= 0) return J(entLk.concat(entCh, entMix));
      if (url.indexOf("PPP_Base_Pedidos") >= 0) return J([
        { pedido: "98001", fecha: "2026-08-25" }, { pedido: "98002", fecha: "2026-08-26" }, { pedido: "44001", fecha: "2026-08-27" }
      ]);
      if (url.indexOf("vista_uxb_articulo") >= 0) return J([{ cod: "501", uxb: 12 }, { cod: "56E", uxb: 6 }]);
      if (url.indexOf("clientes_vendedor") >= 0) return J([{ cod_cliente: "111", vend: "7" }]);
      if (url.indexOf("lk_pedidos_match") >= 0) return J([
        { cod_cliente: "111", empresa: "lk", fecha_pedido: "2026-08-25", sucursal_entrega: "Deposito Central", items_string: "501x2,502x2", ambiguo: false, orden_en_dia: 1 }
      ]);
      return J([]);
    };
    window.supaFetchAllSafe = async function (ep) {
      const r = await window.fetch(ep); return r.json();
    };

    await facXlsIsisOpen();
    for (let i = 0; i < 60 && _facXls && _facXls.cargando; i++) await new Promise(r => setTimeout(r, 50));

    out.nRows = _facXls ? _facXls.rows.length : -1;
    const byNp = {}; (_facXls ? _facXls.rows : []).forEach(function (x) { byNp[x.np] = x; });

    // F1: dedup — 505 una sola vez, 2 cajas (no 4)
    const l505 = (byNp["98001"] || { lineas: [] }).lineas.filter(function (l) { return l.art === "505"; });
    out.f1_veces505 = l505.length;
    out.f1_cajas505 = l505.length ? l505[0].cajas : null;
    out.f1_marcaReArmada = l505.length ? !!l505[0].reArmada : null;

    // F2: split por empresa
    out.f2_tramosLk = byNp["98001"] ? byNp["98001"].tramos : null;      // 21 líneas dedup → 20 → 2 tramos
    out.f2_lineasLk = byNp["98001"] ? byNp["98001"].lineas.length : null;
    out.f2_topeLk   = byNp["98001"] ? byNp["98001"].tope : null;        // 18
    out.f2_tramosCh = byNp["44001"] ? byNp["44001"].tramos : null;      // 16 líneas → 2 tramos
    out.f2_topeCh   = byNp["44001"] ? byNp["44001"].tope : null;        // 15

    // F3: orden por código y padCodArt; el de 0 entregadas no está
    out.f3_arts = byNp["98002"] ? byNp["98002"].lineas.map(function (l) { return l.art; }) : null;
    out.f3_cajasParcial = byNp["98002"] ? byNp["98002"].lineas.filter(function (l) { return l.art === "029"; }).map(function (l) { return l.cajas; })[0] : null;

    // F1b: la NP con "entregado > pedido" arranca DESTILDADA (protección: no se
    // manda a ISIS hasta que un supervisor la revise).
    out.f1b_selConExceso = _facXls ? !!_facXls.sel["98001"] : null;
    out.f1b_marcaExceso  = byNp["98001"] ? !!byNp["98001"].excede : null;

    // F4/F5: generar y leer el XML (tildando todo, para ver el split completo)
    facXlsIsisTodos(true);
    let blob = null, nombre = "";
    const origCreate = URL.createObjectURL;
    URL.createObjectURL = function (b) { blob = b; return "blob:test"; };
    const origAppend = document.body.appendChild.bind(document.body);
    document.body.appendChild = function (el) { if (el && el.tagName === "A" && el.download) { nombre = el.download; el.click = function () {}; } return origAppend(el); };
    facXlsIsisGenerar();
    URL.createObjectURL = origCreate;
    out.f5_nombre = nombre;
    out.xml = blob ? await blob.text() : "";
    return out;
  });

  const xml = r.xml || "";
  const fails = [];
  const ck = (ok, msg) => { if (!ok) fails.push(msg); };

  ck(r.nRows === 3, "esperaba 3 NP en el checklist, hubo " + r.nRows);
  // F1 dedup
  ck(r.f1_veces505 === 1, "F1 dedup: el artículo 505 aparece " + r.f1_veces505 + " veces (esperaba 1)");
  ck(r.f1_cajas505 === 2, "F1 dedup: 505 con " + r.f1_cajas505 + " cajas (esperaba 2, no la suma 4)");
  ck(r.f1_marcaReArmada === true, "F1: la línea re-armada no quedó marcada");
  ck(r.f1b_marcaExceso === true, "F1b: la NP con entregado > pedido no quedó marcada");
  ck(r.f1b_selConExceso === false, "F1b: la NP con entregado > pedido arrancó TILDADA (tiene que arrancar destildada)");
  // F2 split
  ck(r.f2_topeLk === 18, "F2: tope LK = " + r.f2_topeLk + " (esperaba 18)");
  ck(r.f2_topeCh === 15, "F2: tope Chef = " + r.f2_topeCh + " (esperaba 15)");
  ck(r.f2_lineasLk === 20, "F2: la NP de LK quedó con " + r.f2_lineasLk + " líneas (esperaba 20 tras dedup)");
  ck(r.f2_tramosLk === 2, "F2: 20 líneas en LK dieron " + r.f2_tramosLk + " pedidos (esperaba 2)");
  ck(r.f2_tramosCh === 2, "F2: 16 líneas en Chef dieron " + r.f2_tramosCh + " pedidos (esperaba 2 por el tope de 15)");
  // F3 orden y padCodArt
  ck(JSON.stringify(r.f3_arts) === JSON.stringify(["029", "056E", "438E"]),
     "F3: orden/padCodArt dio " + JSON.stringify(r.f3_arts) + " (esperaba 029,056E,438E, sin el de 0 entregadas)");
  ck(r.f3_cajasParcial === 1, "F3: el parcial 029 llevó " + r.f3_cajasParcial + " cajas (esperaba 1, lo entregado)");
  // F4 formato
  ck(xml.indexOf("<?mso-application progid=\"Excel.Sheet\"?>") >= 0, "F4: falta la cabecera mso-application");
  ck(xml.indexOf('<Data ss:Type="String">029</Data>') >= 0, "F4: el código 029 no salió como String");
  ck(xml.indexOf('ss:Name="Resumen"') >= 0, "F4: falta la hoja Resumen");
  ck(xml.indexOf("PRUEBA DE FORMATO — NO IMPORTAR") >= 0, "F4: la hoja Resumen no lleva la advertencia");
  ck(xml.indexOf("2% Descuento Web") >= 0, "F4: falta la columna pctDto");
  ck(xml.indexOf("<Cell/>") >= 0, "F4: las celdas vacías no salieron como <Cell/>");
  // 20 líneas (98001) + 3 (98002) + 16 (44001) = 39 filas de datos, más las del Resumen
  ck((xml.match(/<Row>/g) || []).length >= 39, "F4: filas insuficientes (" + (xml.match(/<Row>/g) || []).length + ", esperaba 39 de datos + Resumen)");
  // 2 pedidos por la NP de LK + 1 por la mixta + 2 por Chef = 5 números de pedido
  ck((xml.match(/<Data ss:Type="Number">5<\/Data>/g) || []).length >= 1, "F4: no se llegó al pedido nº 5 (el split no generó los 5 tramos)");
  // F5 nombre
  ck(/^PRUEBA_NO_IMPORTAR_/.test(r.f5_nombre || ""), "F5: el archivo se llama '" + r.f5_nombre + "' (esperaba PRUEBA_NO_IMPORTAR_*)");
  // sin errores de página
  ck(errs.length === 0, "errores de página: " + errs.join(" | "));

  await b.close();
  if (fails.length) { console.error("fac-excel-isis: FALLÓ\n - " + fails.join("\n - ")); process.exit(1); }
  console.log("fac-excel-isis: OK (dedup, split 18/15, orden por código, XML 2003, PRUEBA_NO_IMPORTAR)");
})();

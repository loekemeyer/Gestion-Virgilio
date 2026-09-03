/* Paso 0 de la idea 3717 — "Excel ISIS (prueba)" en Facturación.
   Se marcan NP con la casilla de cada fila de la LISTA de Facturación y el botón del
   encabezado baja el mismo archivo que hoy sale por mail a las 12:30 (Edge Function
   procesar-pedidos-db del proyecto LK), pero con las cajas ENTREGADAS. Lo que blinda:

   F1) DEDUP por (np, cod_art). Entregas_Virgilio puede tener la misma línea dos veces
       cuando la NP se re-arma (28 NP de 748 en 60 días): sin dedup el archivo mandaría
       el doble de cajas. Se toma la última fila y se topea contra lo pedido.
   F2) SPLIT por empresa: 18 líneas por NP en Loekemeyer (9xxxx) y 15 en CHEF (4xxxx).
       Verificado contra datos reales: 253 NP de LK con exactamente 18 líneas y 25 de
       Chef con exactamente 15.
   F3) ORDEN por código ascendente, que es como parte ISIS (NP 98680/98681 y
       98682/98683 del 02/09). Con otro orden coincide la cantidad de pedidos pero no
       su contenido.
   F4) FORMATO XML Spreadsheet 2003 fiel: 12 columnas en orden, "029" como String
       (empieza con cero), celda vacía <Cell/>, hoja "Resumen" con la advertencia.
   F5) El archivo se llama PRUEBA_NO_IMPORTAR_* (esas NP ya están numeradas en ISIS).
   F6) La selección vive fuera del botón: se marca en la lista y sobrevive al refresh.

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
    window.alert = function () {}; window.confirm = function () { return true; };
    window.__isSupervisor = true;

    function J(data) { return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve(data); } }); }

    // 20 líneas entregadas en una NP de Loekemeyer → parte en 2 (18 + 2).
    const ent = [];
    for (let i = 1; i <= 20; i++) ent.push({ id: 100 + i, np: "98001", cod_art: String(500 + i), cajas_pedidas: 2, cajas_entregadas: 2 });
    ent.push({ id: 300, np: "98001", cod_art: "505", cajas_pedidas: 2, cajas_entregadas: 2 });   // re-armado: 505 dos veces
    // 16 líneas en una NP de CHEF → parte en 2 (15 + 1), no en 1.
    for (let i = 1; i <= 16; i++) ent.push({ id: 400 + i, np: "44001", cod_art: String(600 + i), cajas_pedidas: 1, cajas_entregadas: 1 });
    // Mixta: código chico, con letra, parcial y una con 0 entregadas.
    ent.push({ id: 500, np: "98002", cod_art: "56E", cajas_pedidas: 3, cajas_entregadas: 3 });
    ent.push({ id: 501, np: "98002", cod_art: "29",  cajas_pedidas: 5, cajas_entregadas: 1 });
    ent.push({ id: 502, np: "98002", cod_art: "438E CH", cajas_pedidas: 1, cajas_entregadas: 1 });
    ent.push({ id: 503, np: "98002", cod_art: "300", cajas_pedidas: 2, cajas_entregadas: 0 });

    window.fetch = function (url) {
      url = String(url);
      if (url.indexOf("Entregas_Virgilio") >= 0) return J(ent);
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
    window.supaFetchAllSafe = async function (ep) { const r = await window.fetch(ep); return r.json(); };

    // La cabecera (cod cliente, razón social) sale de la lista ya cargada en pantalla.
    _facLastTandas = [{ tanda: "D60A", pedidos: [
      { np: "98001", cod: "111", razonSocial: "Cliente LK" },
      { np: "98002", cod: "222", razonSocial: "Cliente Mix" },
      { np: "44001", cod: "333", razonSocial: "Cliente CH" }
    ] }];

    // F6: marcar como lo haría la operadora desde la lista
    facXlsToggle("98001"); facXlsToggle("98002"); facXlsToggle("44001");
    out.f6_seleccionadas = _facXlsSel.size;
    facXlsToggle("98002"); facXlsToggle("98002");          // destildar y volver a tildar
    out.f6_trasToggle = _facXlsSel.size;

    // Armado (mismo camino que usa el botón)
    const filas = await _facXlsArmar(Array.from(_facXlsSel));
    const byNp = {}; filas.forEach(function (x) { byNp[x.np] = x; });

    const l505 = (byNp["98001"] || { lineas: [] }).lineas.filter(function (l) { return l.art === "505"; });
    out.f1_veces505 = l505.length;
    out.f1_cajas505 = l505.length ? l505[0].cajas : null;
    out.f1_excede   = byNp["98001"] ? !!byNp["98001"].excede : null;

    out.f2_lineasLk = byNp["98001"] ? byNp["98001"].lineas.length : null;
    out.f2_topeLk   = byNp["98001"] ? byNp["98001"].tope : null;
    out.f2_topeCh   = byNp["44001"] ? byNp["44001"].tope : null;
    out.f2_lineasCh = byNp["44001"] ? byNp["44001"].lineas.length : null;

    out.f3_arts = byNp["98002"] ? byNp["98002"].lineas.map(function (l) { return l.art; }) : null;
    out.f3_parcial = byNp["98002"] ? byNp["98002"].lineas.filter(function (l) { return l.art === "029"; }).map(function (l) { return l.cajas; })[0] : null;

    // F7: el botón abre la vista previa en pantalla (el .xls no lo abre el visor del
    // iPhone sin Excel, así que los datos se pueden chequear acá y bajar en CSV).
    _facXlsPrev = filas;
    _facXlsPreviaRender();
    const ov = document.getElementById("facXlsPrevOv");
    out.f7_previaAbre = !!ov;
    out.f7_previaFilas = ov ? ov.querySelectorAll("tbody tr").length : -1;
    out.f7_tieneCsv = !!(ov && ov.innerHTML.indexOf("facXlsDescargarCsv") >= 0);
    out.f7_tieneXls = !!(ov && ov.innerHTML.indexOf("facXlsDescargarXls") >= 0);

    // F4/F5: bajar y leer el XML
    let blob = null, nombre = "";
    const origCreate = URL.createObjectURL;
    URL.createObjectURL = function (x) { blob = x; return "blob:test"; };
    const origAppend = document.body.appendChild.bind(document.body);
    document.body.appendChild = function (el) { if (el && el.tagName === "A" && el.download) { nombre = el.download; el.click = function () {}; } return origAppend(el); };
    _facXlsDescargar(filas);
    URL.createObjectURL = origCreate;
    out.f5_nombre = nombre;
    out.xml = blob ? await blob.text() : "";

    // F9: .xlsx real (ZIP con XMLs), para que el archivo se pueda abrir en el celular.
    // El .xls XML 2003 es el único probado con ISIS; el .xlsx está para probarlo.
    blob = null; nombre = "";
    URL.createObjectURL = function (x) { blob = x; return "blob:test"; };
    facXlsDescargarXlsx();
    URL.createObjectURL = origCreate;
    out.f9_nombre = nombre;
    if (blob) {
      const u = new Uint8Array(await blob.arrayBuffer());
      out.f9_esZip = u[0] === 0x50 && u[1] === 0x4B && u[2] === 0x03 && u[3] === 0x04;   // "PK\x03\x04"
      out.f9_bytes = u.length;
      let txt = ""; for (let i = 0; i < u.length; i++) txt += String.fromCharCode(u[i]);
      out.f9_partes = ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml",
                       "xl/_rels/workbook.xml.rels", "xl/worksheets/sheet1.xml",
                       "xl/worksheets/sheet2.xml"].filter(function (n) { return txt.indexOf(n) >= 0; }).length;
      out.f9_codTexto = txt.indexOf("<t xml:space=\"preserve\">029</t>") >= 0;   // 029 va como texto, no número
    }

    // F8: el CSV alternativo (mismo contenido, para mirarlo desde el celular)
    blob = null; nombre = "";
    URL.createObjectURL = function (x) { blob = x; return "blob:test"; };
    facXlsDescargarCsv();
    URL.createObjectURL = origCreate;
    out.f8_csvNombre = nombre;
    out.csv = blob ? await blob.text() : "";
    // .text() decodifica UTF-8 y se come el BOM: hay que mirar los bytes crudos.
    out.f8_bom = blob ? (function (b) { return b[0] === 0xEF && b[1] === 0xBB && b[2] === 0xBF; })(new Uint8Array(await blob.arrayBuffer())) : false;
    facXlsPreviaClose();
    out.f7_cierra = !document.getElementById("facXlsPrevOv");
    return out;
  });

  const xml = r.xml || "";
  const fails = [];
  const ck = (ok, msg) => { if (!ok) fails.push(msg); };

  ck(r.f6_seleccionadas === 3, "F6: se marcaron " + r.f6_seleccionadas + " NP (esperaba 3)");
  ck(r.f6_trasToggle === 3, "F6: destildar y volver a tildar dejó " + r.f6_trasToggle + " (esperaba 3)");
  ck(r.f1_veces505 === 1, "F1 dedup: el artículo 505 aparece " + r.f1_veces505 + " veces (esperaba 1)");
  ck(r.f1_cajas505 === 2, "F1 dedup: 505 con " + r.f1_cajas505 + " cajas (esperaba 2, no la suma 4)");
  ck(r.f1_excede === true, "F1: la NP con entregado > pedido no quedó marcada");
  ck(r.f2_topeLk === 18, "F2: tope LK = " + r.f2_topeLk + " (esperaba 18)");
  ck(r.f2_topeCh === 15, "F2: tope Chef = " + r.f2_topeCh + " (esperaba 15)");
  ck(r.f2_lineasLk === 20, "F2: la NP de LK quedó con " + r.f2_lineasLk + " líneas (esperaba 20 tras dedup)");
  ck(r.f2_lineasCh === 16, "F2: la NP de Chef quedó con " + r.f2_lineasCh + " líneas (esperaba 16)");
  ck(JSON.stringify(r.f3_arts) === JSON.stringify(["029", "056E", "438E"]),
     "F3: orden/padCodArt dio " + JSON.stringify(r.f3_arts) + " (esperaba 029,056E,438E, sin el de 0 entregadas)");
  ck(r.f3_parcial === 1, "F3: el parcial 029 llevó " + r.f3_parcial + " cajas (esperaba 1, lo entregado)");
  ck(xml.indexOf('<?mso-application progid="Excel.Sheet"?>') >= 0, "F4: falta la cabecera mso-application");
  ck(xml.indexOf('<Data ss:Type="String">029</Data>') >= 0, "F4: el código 029 no salió como String");
  ck(xml.indexOf('ss:Name="Resumen"') >= 0, "F4: falta la hoja Resumen");
  ck(xml.indexOf("PRUEBA DE FORMATO — NO IMPORTAR") >= 0, "F4: la hoja Resumen no lleva la advertencia");
  ck(xml.indexOf("2% Descuento Web") >= 0, "F4: falta la columna pctDto");
  ck(xml.indexOf("<Cell/>") >= 0, "F4: las celdas vacías no salieron como <Cell/>");
  // 20 (98001) + 3 (98002) + 16 (44001) = 39 filas de datos
  ck((xml.match(/<Row>/g) || []).length >= 39, "F4: filas insuficientes (" + (xml.match(/<Row>/g) || []).length + ")");
  // 2 pedidos por la de LK + 1 por la mixta + 2 por Chef = 5
  ck((xml.match(/<Data ss:Type="Number">5<\/Data>/g) || []).length >= 1, "F4: no se llegó al pedido nº 5 (el split no generó los 5 tramos)");
  ck(/^PRUEBA_NO_IMPORTAR_/.test(r.f5_nombre || ""), "F5: el archivo se llama '" + r.f5_nombre + "' (esperaba PRUEBA_NO_IMPORTAR_*)");
  // F7: vista previa en pantalla
  ck(r.f7_previaAbre === true, "F7: la vista previa no se abrió");
  ck(r.f7_previaFilas === 39, "F7: la previa muestra " + r.f7_previaFilas + " filas (esperaba 39, las mismas del archivo)");
  ck(r.f7_tieneXls === true, "F7: la previa no ofrece bajar el .xls");
  ck(r.f7_tieneCsv === true, "F7: la previa no ofrece bajar el .csv");
  ck(r.f7_cierra === true, "F7: la vista previa no se cierra");
  // F8: CSV alternativo
  ck(/\.csv$/.test(r.f8_csvNombre || ""), "F8: el CSV se llama '" + r.f8_csvNombre + "'");
  ck(r.f8_bom === true, "F8: al CSV le falta el BOM (Excel/Numbers rompen los acentos)");
  ck((r.csv || "").split("\r\n").length >= 40, "F8: el CSV tiene " + (r.csv || "").split("\r\n").length + " líneas (esperaba 39 + encabezado)");
  ck((r.csv || "").indexOf(";") > 0, "F8: el CSV no usa punto y coma");
  // F9: .xlsx real
  ck(/\.xlsx$/.test(r.f9_nombre || ""), "F9: el xlsx se llama '" + r.f9_nombre + "'");
  ck(r.f9_esZip === true, "F9: el .xlsx no arranca con la firma de un ZIP");
  ck(r.f9_partes === 6, "F9: el .xlsx tiene " + r.f9_partes + " de las 6 partes obligatorias");
  ck(r.f9_codTexto === true, "F9: en el .xlsx el código 029 no quedó como texto (Excel lo mostraría como 29)");
  ck((r.f9_bytes || 0) > 1000, "F9: el .xlsx pesa " + r.f9_bytes + " bytes");
  ck(errs.length === 0, "errores de página: " + errs.join(" | "));

  await b.close();
  if (fails.length) { console.error("fac-excel-isis: FALLÓ\n - " + fails.join("\n - ")); process.exit(1); }
  console.log("fac-excel-isis: OK (selección en la lista, dedup, split 18/15, orden por código, XML 2003, previa, CSV y xlsx real)");
})();

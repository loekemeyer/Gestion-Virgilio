/* =====================================================================
 *  ppp-a-sheets.gs — Supabase (Virgilio) → Google Sheet, sentido INVERSO al
 *  sync-ppp-supabase.gs. Vuelca 2 vistas a un Sheet nuevo con 2 hojas:
 *      "Programación Diaria"  ← vista_ppp_programacion_pendiente (solo lo PENDIENTE)
 *      "Pedidos Entregados"   ← vista_ppp_pedidos_entregados (lo facturado + cerrado)
 *
 *  Las vistas derivan de las tablas que alimentan los EVENTOS de la página
 *  (Facturacion_NP / Facturacion_Cierres / Entregas_Virgilio + PPP_Programacion_Diaria).
 *  Cuando una NP se cierra (evento de la página), sale sola de "Programación Diaria" y
 *  aparece en "Pedidos Entregados" — el ajuste es automático, sin mover nada a mano.
 *
 *  INSTALACIÓN (una vez):
 *   1) Crear un Google Sheet nuevo. Copiar su ID de la URL: docs.google.com/spreadsheets/d/<ID>/edit
 *   2) En el proyecto de Apps Script, pegar este archivo.
 *   3) Configuración del proyecto → Propiedades del script, agregar:
 *         PPP_SHEET_ID = <ID del Sheet nuevo>
 *      (reusa SUPABASE_VIRGILIO_URL / SUPABASE_VIRGILIO_SERVICE_KEY que ya existen para el
 *       otro sync; si no están, agregarlas: URL del proyecto Virgilio + service_role key.)
 *   4) Disparadores → agregar uno por tiempo: función `syncPPPaSheet`, cada 10 minutos.
 *      (Para probar: correr `syncPPPaSheet` a mano una vez y autorizar los permisos.)
 *
 *  Modelo: REEMPLAZO TOTAL por hoja (clearContents + setValues), igual que el sync existente.
 * ===================================================================== */

var PPP_SHEET_VIEWS = [
  {
    view: 'vista_ppp_programacion_pendiente',
    tab:  'Programación Diaria',
    cols: ['tanda', 'np', 'tipo', 'cod_cliente', 'razon_social', 'm3', 'zona', 'barrio',
           'direccion', 'op', 'fecha_recep', 'fecha_entrega', 'fecha_fc', 'observaciones'],
    order: 'tanda.asc,np.asc'
  },
  {
    view: 'vista_ppp_pedidos_entregados',
    tab:  'Pedidos Entregados',
    cols: ['np', 'tanda', 'cod_cliente', 'razon_social', 'm3', 'fecha_salida', 'fecha_cierre',
           'fecha_reparto', 'facturado_at', 'cajas_pedidas', 'cajas_entregadas', 'cajas_falto'],
    order: 'facturado_at.desc'
  }
];

function syncPPPaSheet() {
  var creds = _pppSheetCreds_();
  var ss = SpreadsheetApp.openById(creds.sheetId);
  PPP_SHEET_VIEWS.forEach(function (v) {
    var rows = _pppSheetFetchAll_(creds, v.view, v.cols.join(','), v.order);
    _pppSheetWriteTab_(ss, v.tab, v.cols, rows);
    console.log('ppp-a-sheets ' + v.tab + ': ' + rows.length + ' filas');
  });
}

/* ---- credenciales (mismas del proyecto Virgilio que usa el otro sync) ---- */
function _pppSheetCreds_() {
  var props = PropertiesService.getScriptProperties();
  var url = (props.getProperty('SUPABASE_VIRGILIO_URL') || '').replace(/\/$/, '');
  var key = props.getProperty('SUPABASE_VIRGILIO_SERVICE_KEY') || '';
  var sheetId = props.getProperty('PPP_SHEET_ID') || '';
  if (!url || !key) throw new Error('Faltan SUPABASE_VIRGILIO_URL / SUPABASE_VIRGILIO_SERVICE_KEY en Script Properties');
  if (!sheetId) throw new Error('Falta PPP_SHEET_ID en Script Properties');
  return { url: url, key: key, sheetId: sheetId };
}

/* ---- lee una vista completa vía PostgREST, paginando por Range ---- */
function _pppSheetFetchAll_(creds, view, select, order) {
  var out = [], from = 0, page = 1000;
  var base = { apikey: creds.key, Authorization: 'Bearer ' + creds.key };
  while (true) {
    var url = creds.url + '/rest/v1/' + view + '?select=' + encodeURIComponent(select) +
              (order ? '&order=' + encodeURIComponent(order) : '');
    var resp = UrlFetchApp.fetch(url, {
      method: 'get',
      headers: Object.assign({ 'Range-Unit': 'items', Range: from + '-' + (from + page - 1) }, base),
      muteHttpExceptions: true
    });
    var code = resp.getResponseCode();
    if (code >= 300) throw new Error('Supabase GET ' + view + ' HTTP ' + code + ': ' + resp.getContentText().substring(0, 200));
    var chunk = JSON.parse(resp.getContentText() || '[]');
    out = out.concat(chunk);
    if (chunk.length < page) break;
    from += page;
  }
  return out;
}

/* ---- escribe una hoja: reemplazo total con header ---- */
function _pppSheetWriteTab_(ss, tabName, cols, rows) {
  var sh = ss.getSheetByName(tabName) || ss.insertSheet(tabName);
  sh.clearContents();
  var values = [cols];
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i], line = [];
    for (var j = 0; j < cols.length; j++) {
      var x = r[cols[j]];
      line.push((x === null || x === undefined) ? '' : x);
    }
    values.push(line);
  }
  sh.getRange(1, 1, values.length, cols.length).setValues(values);
}

/* =====================================================================
 *  ppp-a-excel.gs — Supabase (Virgilio) → archivo EXCEL (.xlsx) en Google Drive.
 *  Genera/ACTUALIZA un .xlsx con 2 hojas cada vez que corre (disparador por tiempo),
 *  a partir de las 2 vistas de Supabase. Sentido inverso al sync-ppp-supabase.gs.
 *
 *  Hojas del Excel:
 *      "Programación Diaria" ← vista_ppp_programacion_pendiente (SOLO lo pendiente)
 *      "Pedidos Entregados"  ← vista_ppp_pedidos_entregados (lo facturado + cerrado)
 *
 *  Cuando una NP se cierra (evento de la página), sale sola de "Programación Diaria" y
 *  aparece en "Pedidos Entregados" — el ajuste es automático.
 *
 *  Nota: para generar un .xlsx, Apps Script arma una planilla TEMPORAL, la exporta a xlsx
 *  y la vuelca al archivo destino; la temporal se borra al final. NO queda un Google Sheet.
 *
 *  INSTALACIÓN (una vez):
 *   1) Apps Script → pegar este archivo.
 *   2) Servicios (＋) → agregar "Drive API" (Advanced Drive Service; identificador `Drive`).
 *   3) Configuración del proyecto → Propiedades del script:
 *        PPP_XLSX_ID = <ID del .xlsx destino>   ← OPCIONAL la 1ra vez.
 *      (reusa SUPABASE_VIRGILIO_URL / SUPABASE_VIRGILIO_SERVICE_KEY que ya existen.)
 *      Si dejás PPP_XLSX_ID vacío, la 1ra corrida crea "PPP.xlsx" en tu Drive y te loguea su
 *      ID (Ejecuciones → registro): pegá ese ID en PPP_XLSX_ID para que de ahí en más ACTUALICE
 *      el mismo archivo (mismo enlace) en vez de crear uno nuevo cada vez.
 *   4) Disparadores → uno por tiempo: función `syncPPPaExcel`, cada 10 minutos.
 *      (Para probar: correr `syncPPPaExcel` a mano una vez y autorizar los permisos.)
 * ===================================================================== */

var PPP_XLSX_VIEWS = [
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

function syncPPPaExcel() {
  var creds = _pppXlsxCreds_();
  var temp = SpreadsheetApp.create('PPP_tmp_' + Date.now());   // planilla temporal (se borra al final)
  try {
    var first = true;
    PPP_XLSX_VIEWS.forEach(function (v) {
      var rows = _pppXlsxFetchAll_(creds, v.view, v.cols.join(','), v.order);
      var sh = first ? temp.getSheets()[0].setName(v.tab) : temp.insertSheet(v.tab);
      first = false;
      var values = [v.cols];
      for (var i = 0; i < rows.length; i++) {
        var r = rows[i], line = [];
        for (var j = 0; j < v.cols.length; j++) { var x = r[v.cols[j]]; line.push((x === null || x === undefined) ? '' : x); }
        values.push(line);
      }
      sh.getRange(1, 1, values.length, v.cols.length).setValues(values);
      console.log('ppp-a-excel ' + v.tab + ': ' + rows.length + ' filas');
    });
    SpreadsheetApp.flush();

    // exportar la temporal a xlsx
    var exp = UrlFetchApp.fetch('https://docs.google.com/spreadsheets/d/' + temp.getId() + '/export?format=xlsx', {
      headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() }, muteHttpExceptions: true
    });
    if (exp.getResponseCode() >= 300) throw new Error('export xlsx HTTP ' + exp.getResponseCode() + ': ' + exp.getContentText().substring(0, 200));
    var blob = exp.getBlob().setName('PPP.xlsx');

    // volcar al archivo destino (mismo ID/enlace) o crearlo la 1ra vez
    if (creds.xlsxId) {
      Drive.Files.update({}, creds.xlsxId, blob);
      console.log('PPP.xlsx actualizado (' + creds.xlsxId + ')');
    } else {
      var f = Drive.Files.insert({ title: 'PPP.xlsx' }, blob);
      console.log('⚠ Creé PPP.xlsx NUEVO. Pegá este ID en la propiedad PPP_XLSX_ID: ' + f.id);
    }
  } finally {
    try { DriveApp.getFileById(temp.getId()).setTrashed(true); } catch (e) {}
  }
}

/* ---- credenciales (mismas del proyecto Virgilio que usa el otro sync) ---- */
function _pppXlsxCreds_() {
  var props = PropertiesService.getScriptProperties();
  var url = (props.getProperty('SUPABASE_VIRGILIO_URL') || '').replace(/\/$/, '');
  var key = props.getProperty('SUPABASE_VIRGILIO_SERVICE_KEY') || '';
  var xlsxId = props.getProperty('PPP_XLSX_ID') || '';   // opcional la 1ra vez
  if (!url || !key) throw new Error('Faltan SUPABASE_VIRGILIO_URL / SUPABASE_VIRGILIO_SERVICE_KEY en Script Properties');
  return { url: url, key: key, xlsxId: xlsxId };
}

/* ---- lee una vista completa vía PostgREST, paginando por Range ---- */
function _pppXlsxFetchAll_(creds, view, select, order) {
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

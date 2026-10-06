/* =====================================================================================
   ESTADÍSTICA MADRE — UN SOLO CUADRO para la página LK y Gestión Virgilio
   Tomás Beviglia, 01/10/2026: "es un solo cuadro que se imprime en dos lados distintos.
   NUNCA puede un cuadro de est madre quedar más actualizado que otro. Si alguien quiere
   cambiar uno solo NO se puede hacer".

   ⚠ ESTE ARCHIVO ES LA ÚNICA COPIA. Vive en el repo Gestion-Virgilio (admin/est-madre.js) y
   lo publica GitHub Pages. Lo cargan, del MISMO lugar:
     · el panel de LK (loekemeyer.com/admin.html, repo pagina-LK-copia) por URL absoluta;
     · el espejo de Gestión (admin/admin.html: Panel Web LK y la pestaña EST. MADRE de
       Stock y Compras), que lo tiene al lado.
   El admin.js de cada repo sólo trae el cargador (abrirEstadisticaMadre). Ni el HTML de la
   página, ni el CSS, ni la lógica están en otro lado: cambiar este archivo cambia los dos.

   QUÉ MUESTRA
     · Las FILAS son los artículos de Stocks de Gestión: stocks_carga_rapida, las mismas filas
       que la pestaña Stocks (sin las ocultas vacías: visible_en_stock = false y sin stock ni
       pedidos). Ningún otro artículo entra.
     · EST MADRE = la columna «Est. Madre caj/mes» de Stocks (proy_cajas_mes de esa misma
       tabla): cajas enteras, el principal suma a sus secundarios y el secundario va en 0.
       Los duales (437E / 438E / 439E / 809E) son dos filas, LK y CH, como en Stocks.
     · Los MESES son cajas facturadas por mes (LK: get_estadistica_madre_mensual), con el
       criterio del motor de la Est Madre: regla L, sin ventas entre empresas, remaps y sin
       códigos administrativos. Cada fila muestra lo que vendió ESE código (y en un dual, ESA
       empresa): los totales por mes no cuentan dos veces.
   Una lectura que falla NO se reemplaza por otra fuente ni por ceros: se dice que falló.
   ===================================================================================== */
var EST_MADRE_VERSION = "v25.81";
var EM_GV_URL = "https://hrxfctzncixxqmpfhskv.supabase.co";
// Clave pública de Gestión (es la misma que usa el front de Gestión para leer Stocks).
var EM_GV_KEY = "sb_publishable_BqpAgZH6ty-9wft10_YMhw_0rcIPuWT";
var EM_PAGINA = 1000;

var _estMadreData = null;     // filas de la vista actual (con _rank / _est)
var _estMadreYms = [];        // meses de la vista actual (desc, el más reciente primero)
var _estMadreRows = null;     // todas las filas armadas (lista de Stocks + meses)
var _estMadreAllYms = null;   // todos los meses con datos (asc)
var _estMadreLoadedAt = null;
var _estMadreCargando = false;
// col: 'rank' | 'cod' | 'marca' | 'familia'. Default: mejor ranking (mayor Est Madre) primero.
var _estMadreSort = { col: "rank", dir: "asc" };
// v25.81 — switch Cajas / Unidades (Tomás Beviglia, 01/10/2026: "un switch de cajas a unidades para tener
// ambos valores"). Unidades = cajas × uxb de Gestión (vista_uxb_articulo, la misma de Stocks). Un artículo
// sin uxb NO se inventa: dice "s/uxb" y no suma al total en unidades. Se recuerda por navegador.
var _estMadreUnidad = (function () { try { return localStorage.getItem("em_unidad") === "uni" ? "uni" : "caj"; } catch (e) { return "caj"; } })();
var _estMadreUxbErr = null;   // si la lectura del uxb falló, el modo unidades queda apagado (no se muestra un 0)

var EM_CSS = `
/* v27.43 — compacto (Luis: «está horrible»): título chico, una sola fila de filtros */
#estadistica-madre .page-header { margin-bottom: 8px; }
#estadistica-madre .page-header h1 { font-size: 20px; margin: 0; }
#estadistica-madre .page-sub { font-size: 12px; margin: 2px 0 0; }
#estadistica-madre .est-madre-toolbar { display: flex; flex-wrap: wrap; align-items: center; justify-content: center;
  gap: 8px 10px; padding: 8px 12px !important; margin-bottom: 10px; width: fit-content; max-width: 100%; margin-left: auto; margin-right: auto; }
#estadistica-madre .em-sec-tit { font-size: 10.5px; font-weight: 800; letter-spacing: .6px; text-transform: uppercase; color: #64748b; }
#estadistica-madre .est-madre-toolbar .em-buscar,
#estadistica-madre .est-madre-toolbar select { width: auto; margin: 0; padding: 6px 10px; border: 1px solid #e5e7eb; border-radius: 8px;
  font-size: 13px; font-family: inherit; background: #f9fafb; }
#estadistica-madre .est-madre-toolbar .em-buscar { width: 230px; }
#estadistica-madre .est-madre-toolbar .em-unidad-sw button { padding: 6px 11px; font-size: 13px; }
#estadistica-madre .est-madre-toolbar .em-bajar { width: auto; margin: 0; padding: 6px 12px; font-size: 13px; }
#estadistica-madre .est-madre-toolbar #estMadreStatus { font-size: 11.5px; margin: 0; color: #64748b; }
/* =========================================================
   ESTADÍSTICA MADRE — tabla cajas x mes por artículo (módulo único est-madre.js)
   ========================================================= */
.est-madre-toolbar {
  display: flex;
  align-items: flex-end;
  gap: 18px;
  flex-wrap: wrap;
  margin-bottom: 16px;
}
.est-madre-search-wrap,
.est-madre-range-wrap {
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-width: 180px;
}
.est-madre-search-wrap {
  flex: 1;
  min-width: 280px;
}
.est-madre-search-wrap label,
.est-madre-range-wrap label {
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.8px;
  color: #6b7280;
}
.est-madre-search-wrap input,
.est-madre-range-wrap select {
  padding: 10px 14px;
  border: 1px solid #e5e7eb;
  border-radius: 10px;
  font-size: 14px;
  font-family: inherit;
  background: #f9fafb;
  transition: all 0.15s ease;
}
.est-madre-search-wrap input:focus,
.est-madre-range-wrap select:focus {
  outline: none;
  border-color: #111;
  background: #fff;
  box-shadow: 0 0 0 3px rgba(17, 24, 39, 0.08);
}

.est-madre-card {
  padding: 0 !important;
  overflow: hidden;
}
.est-madre-table-wrap {
  overflow-x: auto;
  overflow-y: auto;
  max-height: calc(100vh - 320px);
}
.est-madre-table {
  width: max-content;
  border-collapse: collapse;
  font-size: 12px;
}
.est-madre-table th {
  background: #19222f;
  color: #fff;
  padding: 10px 8px;
  font-size: 10.5px;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  text-align: center;
  position: sticky;
  top: 0;
  white-space: nowrap;
  z-index: 2;
}
.est-madre-table th.est-madre-th-cod {
  text-align: left;
  position: sticky;
  left: 0;
  z-index: 3;
  background: #19222f;
  min-width: 70px;
}
.est-madre-table th.est-madre-th-desc {
  text-align: left;
  position: sticky;
  left: 70px;
  z-index: 3;
  background: #19222f;
  min-width: 200px;
}
.est-madre-table th.est-madre-th-familia {
  text-align: left;
  background: #19222f;
  min-width: 140px;
}
.est-madre-table th.est-madre-th-total,
.est-madre-table th.est-madre-th-em {
  background: #1f7a3a;
}
.est-madre-table td {
  padding: 8px 8px;
  border-bottom: 1px solid #f0f1f3;
  text-align: center;
  font-variant-numeric: tabular-nums;
  color: #1f2937;
  white-space: nowrap;
}
.est-madre-table td.est-madre-td-cod {
  text-align: left;
  font-weight: 700;
  color: #c0392b;
  position: sticky;
  left: 0;
  background: #fff;
  z-index: 1;
}
.est-madre-table td.est-madre-td-desc {
  text-align: left;
  font-weight: 600;
  color: #111;
  position: sticky;
  left: 70px;
  background: #fff;
  z-index: 1;
}
.est-madre-table td.est-madre-td-total,
.est-madre-table td.est-madre-td-em {
  font-weight: 900;
  font-size: 13px;
  background: #eafaf0;
  color: #0a5d2a;
}
.est-madre-table td.est-madre-td-familia {
  text-align: left;
  font-size: 11.5px;
  color: #6b7280;
  font-weight: 500;
}

/* Fila de totales por mes (AHORA es la primera fila del thead) */
.est-madre-table tr.est-madre-totals-row th {
  background: #2c3a4e;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.3px;
  text-transform: none;
  padding: 7px 8px;
  position: sticky;
  top: 0;
  z-index: 2;
}
/* Fila de headers de mes ahora va debajo de los totales — sticky con offset */
.est-madre-table thead tr:not(.est-madre-totals-row) th {
  position: sticky;
  top: 34px;
  z-index: 1;
}
.est-madre-table thead tr:not(.est-madre-totals-row) th.est-madre-th-cod,
.est-madre-table thead tr:not(.est-madre-totals-row) th.est-madre-th-desc {
  z-index: 3;
}
.est-madre-table tr.est-madre-totals-row th.est-madre-th-desc {
  text-align: right;
  color: #d1d5db;
  font-style: italic;
}
.est-madre-table tr.est-madre-totals-row th.est-madre-th-em {
  background: #167a3a;
  color: #fff;
  font-weight: 900;
  font-size: 12.5px;
}
.est-madre-table tbody tr:nth-child(even) td {
  background: #fafbfc;
}
.est-madre-table tbody tr:nth-child(even) td.est-madre-td-cod,
.est-madre-table tbody tr:nth-child(even) td.est-madre-td-desc {
  background: #fafbfc;
}
.est-madre-table tbody tr:nth-child(even) td.est-madre-td-total,
.est-madre-table tbody tr:nth-child(even) td.est-madre-td-em {
  background: #d8f3e3;
}
.est-madre-table tbody tr:hover td {
  background: #f4f6f9 !important;
}
.est-madre-empty {
  padding: 40px 20px;
  text-align: center;
  color: #6b7280;
  font-style: italic;
}

/* Cells con valor 0 — color tenue */
.est-madre-table td.zero {
  color: #d1d5db;
}

/* Year separator — borde izquierdo dentro de la tabla */
.est-madre-table th.year-start,
.est-madre-table td.year-start {
  border-left: 2px solid #d1d5db;
}

/* Columna Ranking (#) — sticky leftmost, antes que Cod */
.est-madre-table th.est-madre-th-rank {
  text-align: center;
  position: sticky;
  left: 0;
  z-index: 3;
  min-width: 42px;
  background: #19222f;
}
.est-madre-table td.est-madre-td-rank {
  text-align: center;
  font-weight: 700;
  color: #6b7280;
  position: sticky;
  left: 0;
  background: #fff;
  z-index: 1;
  min-width: 42px;
}
.est-madre-table tbody tr:nth-child(even) td.est-madre-td-rank {
  background: #fafbfc;
}
/* Cod y Desc se corren para hacer lugar al Rank (rank ocupa los primeros 42px) */
.est-madre-table th.est-madre-th-cod {
  left: 42px;
}
.est-madre-table th.est-madre-th-desc {
  left: 112px;
}
.est-madre-table td.est-madre-td-cod {
  left: 42px;
}
.est-madre-table td.est-madre-td-desc {
  left: 112px;
}
/* Totales row: rank vacío sigue el bg de totals */
.est-madre-table tr.est-madre-totals-row th.est-madre-th-rank {
  background: #2c3a4e;
}
/* z-index para que rank quede arriba al scrollear horizontalmente (mismo trato que cod/desc) */
.est-madre-table thead tr:not(.est-madre-totals-row) th.est-madre-th-rank {
  z-index: 3;
}

/* Sortable headers — cursor pointer + hover + flecha */
.est-madre-table th.est-madre-sort-th {
  cursor: pointer;
  user-select: none;
}
.est-madre-table th.est-madre-sort-th:hover {
  background: #2a3849;
}
.est-madre-table th.est-madre-sort-th.est-madre-sorted {
  background: #1f7a3a;
}
.est-madre-table th.est-madre-sort-th .est-madre-sort-idle {
  opacity: 0.35;
  font-weight: 400;
}
.est-madre-table th.est-madre-sort-th .est-madre-sort-active {
  font-weight: 800;
}

.est-madre-table td.est-madre-clickable {
  cursor: pointer;
  transition: background 0.15s;
}
.est-madre-table td.est-madre-clickable:hover {
  background: #fff9c4 !important;
  color: #2c3e50 !important;
  font-weight: 700;
}
.em-modal {
  position: fixed; inset: 0; z-index: 9999;
  display: flex; align-items: center; justify-content: center;
}
.em-modal-overlay {
  position: absolute; inset: 0;
  background: rgba(0,0,0,0.5);
}
.em-modal-box {
  position: relative; z-index: 1;
  background: white; border-radius: 12px;
  width: 90vw; max-width: 1100px;
  max-height: 88vh; overflow: hidden;
  display: flex; flex-direction: column;
  box-shadow: 0 20px 60px rgba(0,0,0,0.3);
}
.em-modal-header {
  padding: 16px 20px; border-bottom: 1px solid #e0e0e0;
  display: flex; justify-content: space-between; align-items: center;
  background: #f8f9fa;
}
.em-modal-close {
  background: none; border: none;
  font-size: 28px; line-height: 1;
  color: #888; cursor: pointer; padding: 0 6px;
}
.em-modal-close:hover { color: #c0392b; }
.em-modal-body {
  padding: 20px; overflow-y: auto;
}
.em-detail-tbl {
  width: 100%; border-collapse: collapse;
  font-size: 12.5px;
  white-space: nowrap;
}
.em-detail-tbl th {
  background: #2c3e50; color: white;
  padding: 6px 12px; text-align: left;
  font-size: 10.5px; text-transform: uppercase;
  letter-spacing: 0.5px;
}
.em-detail-tbl td {
  padding: 4px 12px; border-bottom: 1px solid #f0f0f0;
}
.em-detail-tbl tbody tr:hover { background: #f8f9fa; }
/* Header sticky cuando la tabla está dentro de un wrapper con scroll vertical */
.em-detail-tbl-sticky thead th {
  position: sticky;
  top: 0;
  z-index: 2;
  box-shadow: 0 2px 0 rgba(0,0,0,0.1);
}
/* Card colapsable (ventas disruptivas) — usa <details>/<summary> nativo */
.em-card-collapse {
  border: 1px solid #e0e0e0;
  border-radius: 8px;
  background: #fff;
  overflow: hidden;
  transition: box-shadow 0.2s ease;
}
.em-card-collapse[open] {
  box-shadow: 0 2px 8px rgba(0,0,0,0.06);
}
.em-card-collapse.em-card-warn {
  border-color: #e74c3c;
  background: #fffaf9;
}
.em-card-collapse.em-card-ok {
  border-color: #27ae60;
  background: #f5fdf8;
}
.em-card-collapse summary {
  list-style: none;
  cursor: pointer;
  padding: 14px 18px;
  display: flex;
  align-items: center;
  gap: 14px;
  user-select: none;
  transition: background 0.15s ease;
}
.em-card-collapse summary::-webkit-details-marker {
  display: none;
}
.em-card-collapse summary:hover {
  background: rgba(0,0,0,0.025);
}
.em-card-title {
  font-weight: 700;
  font-size: 15px;
  color: #2c3e50;
  flex: 1;
}
.em-card-badge {
  font-size: 12px;
  font-weight: 700;
  padding: 4px 10px;
  border-radius: 4px;
  white-space: nowrap;
}
.em-card-badge-warn {
  background: #e74c3c;
  color: #fff;
}
.em-card-badge-ok {
  background: #27ae60;
  color: #fff;
}
.em-card-chevron {
  font-size: 14px;
  color: #888;
  transition: transform 0.2s ease;
}
.em-card-collapse[open] .em-card-chevron {
  transform: rotate(180deg);
}
.em-card-content {
  padding: 0 18px 18px;
}

/* Spinner de carga + texto dinámico — centrado en el contenedor */
.em-loader {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 14px;
  padding: 60px 0;
  width: 100%;
  text-align: center;
}
.em-spinner {
  width: 48px;
  height: 48px;
  border: 3px solid #e0e0e0;
  border-top-color: #2c3e50;
  border-radius: 50%;
  animation: emSpin 0.8s linear infinite;
}
.em-loader-text {
  font-size: 13px;
  font-weight: 600;
  color: #666;
  letter-spacing: 0.2px;
}
@keyframes emSpin {
  to { transform: rotate(360deg); }
}

/* v25.79 — Marca (LK / CH) y la fila del SECUNDARIO (su venta va a la Est Madre del principal) */
.est-madre-table th.est-madre-th-marca, .est-madre-table td.est-madre-td-marca { text-align: center; font-weight: 700; }
.est-madre-table td.est-madre-sec { color: #1e40af; font-weight: 700; font-size: 11px; white-space: nowrap; }
.est-madre-table tr.est-madre-fila-sec td.est-madre-td-cod,
.est-madre-table tr.est-madre-fila-sec td.est-madre-td-desc { color: #64748b; }
/* v25.81 — switch Cajas / Unidades */
.em-unidad-sw { display: inline-flex; border: 1px solid #e5e7eb; border-radius: 10px; overflow: hidden; }
.em-unidad-sw button { width: auto; margin: 0; padding: 10px 14px; border: 0; background: #f9fafb; color: #374151;
  font-size: 14px; font-weight: 700; font-family: inherit; cursor: pointer; }
.em-unidad-sw button + button { border-left: 1px solid #e5e7eb; }
.em-unidad-sw button.on { background: #111; color: #fff; }
.em-unidad-sw button:disabled { opacity: .45; cursor: not-allowed; }
.est-madre-table td.em-sin-uxb { color: #b45309; font-size: 11px; font-weight: 700; }
`;

var EM_HTML =
  '<div class="page-header"><div>' +
    '<h1>Estadística Madre</h1>' +
    '<p class="page-sub">Cajas (o unidades, con el switch) vendidas por mes de cada artículo de <b>Stocks</b> de Gestión Virgilio. ' +
    '<b>Est Madre</b> es la misma columna «Est. Madre caj/mes» de Stocks: el principal suma a sus secundarios. ' +
    'Es un solo cuadro: el panel de LK y Gestión muestran este mismo.</p>' +
  '</div></div>' +
  /* v27.43 (Luis, 06/10): un solo sector de filtros, compacto: buscar · meses a mostrar · cajas/unidades · Descargar E.M.
     (baja los meses que se están mostrando). Lo de importar/exportar vive en la barra de Gestión. */
  '<div class="card est-madre-toolbar">' +
    '<span class="em-sec-tit">Ver la tabla</span>' +
    '<input type="text" id="estMadreSearch" class="em-buscar" placeholder="Buscar: 505 o &quot;Abrelatas&quot;" autocomplete="off" oninput="filtrarEstadisticaMadre()" title="Buscar artículo (código o descripción)" />' +
    '<select id="estMadreMonths" onchange="aplicarRangoEstadisticaMadre()" title="Meses a mostrar">' +
      '<option value="6">Últimos 6 meses</option>' +
      '<option value="12">Últimos 12 meses</option>' +
      '<option value="24" selected>Últimos 24 meses</option>' +
      '<option value="36">Últimos 36 meses</option>' +
      '<option value="0">Todo el historial</option>' +
    '</select>' +
    '<div class="em-unidad-sw" id="estMadreUnidadSw" title="Ver en">' +
      '<button type="button" data-u="caj" onclick="setEstMadreUnidad(\'caj\')" title="Cajas, como Stocks">Cajas</button>' +
      '<button type="button" data-u="uni" onclick="setEstMadreUnidad(\'uni\')" title="Unidades = cajas × unidades por caja (uxb de Gestión)">Unidades</button>' +
    '</div>' +
    '<button class="btn-primary em-bajar" onclick="descargarEstadisticaMadreExcel()" title="Bajar en Excel la Est. Madre con los meses que se están mostrando">⬇ Descargar E.M.</button>' +
    '<div id="estMadreStatus" class="cliente-lookup-status"></div>' +
  '</div>' +
  '<div class="card est-madre-card"><div class="est-madre-table-wrap">' +
    '<table class="est-madre-table" id="estMadreTable"><thead></thead><tbody></tbody></table>' +
  '</div></div>' +
  '<div id="estMadreModal" class="em-modal" style="display:none">' +
    '<div class="em-modal-overlay" onclick="cerrarDetalleVentaMadre()"></div>' +
    '<div class="em-modal-box">' +
      '<div class="em-modal-header">' +
        '<h3 id="estMadreModalTitle" style="margin:0;font-size:18px">Detalle de ventas</h3>' +
        '<button type="button" class="em-modal-close" onclick="cerrarDetalleVentaMadre()" aria-label="Cerrar">&times;</button>' +
      '</div>' +
      '<div class="em-modal-body" id="estMadreModalBody">Cargando…</div>' +
    '</div>' +
  '</div>';

// ---- helpers de código (≡ _padCod / _ocgNorm / codBase de Gestión) ----
// "No existe 26. Solo 026": el cero adelante va siempre, también con letra (35E → 035E).
function _emPad(cod) {
  var s = String(cod == null ? "" : cod).toUpperCase().trim();
  var m = s.match(/^([0-9]+)(.*)$/);
  return m ? m[1].padStart(3, "0") + m[2] : s;
}
function _emNorm(c) { return String(c || "").toUpperCase().trim().replace(/^0+(?=.)/, ""); }
function _emSufijo(cod) {
  var m = String(cod || "").trim().toUpperCase().match(/\s+(LK|CH|LOKE)$/);
  return m ? m[1].replace("LOKE", "LK") : "";
}
function _emBase(cod) { return String(cod == null ? "" : cod).trim().toUpperCase().replace(/\s+(LK|CH|LOKE)$/, ""); }

function _emInyectarCss() {
  if (document.getElementById("estMadreCss")) return;
  var st = document.createElement("style");
  st.id = "estMadreCss";
  st.textContent = EM_CSS;
  document.head.appendChild(st);
}
function _emPintarPagina() {
  var sec = document.getElementById("estadistica-madre");
  if (!sec) return null;
  if (!document.getElementById("estMadreTable")) sec.innerHTML = EM_HTML;
  return sec;
}

// La lista de Stocks de Gestión, con la clave pública. PostgREST corta en 1000 sin avisar.
async function _emLeerStocks() {
  var out = [];
  for (var off = 0; off < 50000; off += EM_PAGINA) {
    var u = EM_GV_URL + "/rest/v1/stocks_carga_rapida" +
      "?select=cod,cod_base,descripcion,linea,familia_principal,es_secundario,proy_cajas_mes,visible_en_stock,stock_total,cajas_pedidas" +
      "&order=cod.asc&limit=" + EM_PAGINA + "&offset=" + off;
    var r = await fetch(u, { headers: { apikey: EM_GV_KEY, Authorization: "Bearer " + EM_GV_KEY }, cache: "no-store" });
    if (!r.ok) throw new Error("Stocks de Gestión respondió " + r.status);
    var page = await r.json();
    if (!Array.isArray(page)) throw new Error("Stocks de Gestión no devolvió una lista");
    out = out.concat(page);
    if (page.length < EM_PAGINA) break;
  }
  return out;
}
// Unidades por caja de Gestión (vista_uxb_articulo, la misma de Stocks). Mapa por código normalizado.
async function _emLeerUxb() {
  var out = {};
  for (var off = 0; off < 20000; off += EM_PAGINA) {
    var u = EM_GV_URL + "/rest/v1/vista_uxb_articulo?select=cod,uxb&order=cod.asc&limit=" + EM_PAGINA + "&offset=" + off;
    var r = await fetch(u, { headers: { apikey: EM_GV_KEY, Authorization: "Bearer " + EM_GV_KEY }, cache: "no-store" });
    if (!r.ok) throw new Error("uxb de Gestión respondió " + r.status);
    var page = await r.json();
    if (!Array.isArray(page)) throw new Error("uxb de Gestión no devolvió una lista");
    page.forEach(function (x) { var k = _emNorm(x.cod), n = Number(x.uxb) || 0; if (k && n > 0 && !out[k]) out[k] = n; });
    if (page.length < EM_PAGINA) break;
  }
  return out;
}
// Ventas por mes (LK). Se deduplica por (artículo, empresa): en Gestión la Edge Function
// devuelve todo de una vez y no entiende el rango de la página.
async function _emLeerMensual() {
  var vistos = {}, out = [];
  for (var off = 0; off < 50000; off += EM_PAGINA) {
    var resp = await sb.rpc("get_estadistica_madre_mensual").range(off, off + EM_PAGINA - 1);
    if (resp.error) throw resp.error;
    var page = resp.data || [];
    var nuevos = 0;
    page.forEach(function (r) {
      var k = String(r.item || "") + "|" + String(r.empresa || "");
      if (vistos[k]) return;
      vistos[k] = 1; nuevos++; out.push(r);
    });
    if (page.length < EM_PAGINA || nuevos === 0) break;
  }
  return out;
}
async function _emLeerTabla(nombre, cols) {
  var out = [];
  for (var off = 0; off < 20000; off += EM_PAGINA) {
    var resp = await sb.from(nombre).select(cols).order("cod", { ascending: true }).range(off, off + EM_PAGINA - 1);
    if (resp.error) throw resp.error;
    var page = resp.data || [];
    out = out.concat(page);
    if (page.length < EM_PAGINA) break;
  }
  return out;
}

// Arma las filas: UNA por fila visible de Stocks. Exportada para el test.
function _emArmarFilas(stocks, mensual, prods, lokes, uxbMap) {
  var porItem = {};
  (mensual || []).forEach(function (r) {
    var k = _emNorm(r.item);
    if (!k) return;
    var emp = String(r.empresa || "").toLowerCase() === "chef" ? "chef" : "lk";
    porItem[k] = porItem[k] || { lk: {}, chef: {} };
    var meses = r.meses || {};
    Object.keys(meses).forEach(function (ym) {
      if (!/^\d{4}-\d{2}$/.test(ym)) return;
      porItem[k][emp][ym] = (porItem[k][emp][ym] || 0) + (Number(meses[ym]) || 0);
    });
  });
  var prodBy = {};
  (prods || []).forEach(function (p) { var k = _emNorm(p.cod); if (k && !prodBy[k]) prodBy[k] = p; });
  var lokeBy = {};
  (lokes || []).forEach(function (p) { var k = _emNorm(p.cod); if (k && !lokeBy[k]) lokeBy[k] = p; });

  var filas = [];
  (stocks || []).forEach(function (r) {
    var cod = String(r.cod || "").trim();
    if (!cod) return;
    // Mismo filtro que Stocks (_stkSaldosFromView): fuera lo que el backend marcó oculto y vacío.
    if (r.visible_en_stock === false && !(Number(r.stock_total) || 0) && !(Number(r.cajas_pedidas) || 0)) return;
    var suf = _emSufijo(cod);
    var base = _emBase(cod);
    var k = _emNorm(base);
    var ventas = porItem[k] || { lk: {}, chef: {} };
    var byYm = {};
    var fuentes = suf === "CH" ? [ventas.chef] : (suf === "LK" ? [ventas.lk] : [ventas.lk, ventas.chef]);
    fuentes.forEach(function (src) {
      Object.keys(src).forEach(function (ym) { byYm[ym] = (byYm[ym] || 0) + src[ym]; });
    });
    var total = 0;
    Object.keys(byYm).forEach(function (ym) { total += byYm[ym]; });
    var prod = prodBy[k], loke = lokeBy[k];
    var marca = suf || String(r.linea || "").toUpperCase().trim().replace("LOKE", "LK");
    filas.push({
      key: cod.toUpperCase(),
      cod: _emPad(base),
      // El detalle por cliente busca el código con la grafía de LK (026, no 26).
      codLk: prod ? String(prod.cod) : (loke ? String(loke.cod) : _emPad(base)),
      marca: marca,
      desc: r.descripcion || (prod && prod.description) || (loke && loke.description) || "",
      familia: (prod && prod.category) || (loke ? "Loke" : "—"),
      est: Number(r.proy_cajas_mes) || 0,
      secundario: r.es_secundario === true,
      principal: r.familia_principal ? _emPad(_emBase(r.familia_principal)) : "",
      byYm: byYm,
      total: total,
      uxb: (uxbMap && uxbMap[k] > 0) ? uxbMap[k] : null,
    });
  });
  // Ranking por Est Madre (1 = la mayor). El secundario no rankea: su venta está en el principal.
  var rankeables = filas.filter(function (f) { return !f.secundario; })
    .sort(function (a, b) { return b.est - a.est || a.cod.localeCompare(b.cod, "es", { numeric: true }); });
  rankeables.forEach(function (f, i) { f._rank = i + 1; });
  filas.forEach(function (f) { if (f.secundario) f._rank = null; f._est = f.est; });
  return filas;
}

async function cargarEstadisticaMadre(forzar) {
  _emInyectarCss();
  if (!_emPintarPagina()) return;
  _emPintarSwitch();
  if (_estMadreCargando) return;
  if (!forzar && _estMadreRows) { aplicarRangoEstadisticaMadre(); return; }
  _estMadreCargando = true;
  var status = document.getElementById("estMadreStatus");
  var tbody = document.querySelector("#estMadreTable tbody");
  if (tbody) tbody.innerHTML = '<tr><td colspan="8" class="est-madre-empty"><div class="em-loader"><div class="em-spinner"></div>' +
    '<div class="em-loader-text">Leyendo Stocks de Gestión y las ventas…</div></div></td></tr>';
  if (status) { status.textContent = "Cargando…"; status.className = "cliente-lookup-status"; }
  try {
    var res = await Promise.all([
      _emLeerStocks(),
      _emLeerMensual(),
      _emLeerTabla("products", "cod,description,category"),
      _emLeerTabla("loke_products", "cod,description"),
      _emLeerUxb().then(function (m) { _estMadreUxbErr = null; return m; },
        function (e) { _estMadreUxbErr = (e && e.message) || String(e); console.error("[estMadre] uxb", e); return null; }),
    ]);
    if (!res[0].length) throw new Error("Stocks de Gestión vino vacío: no hay lista de artículos");
    _estMadreRows = _emArmarFilas(res[0], res[1], res[2], res[3], res[4]);
    if (_estMadreUxbErr && _estMadreUnidad === "uni") _estMadreUnidad = "caj";
    _emPintarSwitch();
    var ymSet = {};
    _estMadreRows.forEach(function (f) { Object.keys(f.byYm).forEach(function (ym) { ymSet[ym] = 1; }); });
    _estMadreAllYms = Object.keys(ymSet).sort();
    _estMadreLoadedAt = new Date();
    aplicarRangoEstadisticaMadre();
  } catch (e) {
    console.error("[estMadre]", e);
    _estMadreRows = null; _estMadreData = null;
    var msg = (e && e.message) || String(e);
    if (tbody) tbody.innerHTML = '<tr><td colspan="8" class="est-madre-empty">' +
      'No se pudo leer la Estadística Madre: ' + _escH(msg) + '. No se muestra ningún número a medias. ' +
      '<button type="button" class="btn-primary" style="margin-left:10px" onclick="cargarEstadisticaMadre(true)">Reintentar</button></td></tr>';
    if (status) { status.textContent = "Error: " + msg; status.className = "cliente-lookup-status error"; }
  } finally {
    _estMadreCargando = false;
  }
}
window.cargarEstadisticaMadre = cargarEstadisticaMadre;

function aplicarRangoEstadisticaMadre() {
  if (!_estMadreRows || !_estMadreAllYms) return;
  var monthsSel = document.getElementById("estMadreMonths");
  var rango = monthsSel ? Number(monthsSel.value) : 24;
  var yms = _estMadreAllYms.slice();
  if (rango > 0 && yms.length > rango) yms = yms.slice(-rango);
  yms.reverse();
  var items = _estMadreRows.slice();
  _applyEstMadreSort(items);
  _estMadreData = items;
  _estMadreYms = yms;
  filtrarEstadisticaMadre();
  var status = document.getElementById("estMadreStatus");
  if (status) {
    var when = _estMadreLoadedAt ? _estMadreLoadedAt.toLocaleTimeString("es-AR") : "";
    var sinUxb = items.filter(function (f) { return !f.uxb; }).length;
    status.textContent = items.length + " artículos de Stocks · " + yms.length + " meses · leído " + when +
      (_estMadreUnidad === "uni" ? " · en UNIDADES (cajas × uxb de Gestión" + (sinUxb ? "; " + sinUxb + " sin uxb no suman" : "") + ")" : "") +
      (_estMadreUxbErr ? " · no se pudo leer el uxb: el modo unidades está apagado" : "");
    status.className = "cliente-lookup-status";
    status.style.display = "";
  }
  _actualizarSelectorMesesDisruptivas();
}
window.aplicarRangoEstadisticaMadre = aplicarRangoEstadisticaMadre;

function _actualizarSelectorMesesDisruptivas() {
  var select = document.getElementById("estMadreDisruptivasMonth");
  if (!select || !_estMadreYms) return;
  var prev = select.value;
  select.innerHTML = '<option value="">Seleccionar mes...</option>';
  _estMadreYms.forEach(function (ym) {
    var o = document.createElement("option");
    o.value = ym; o.textContent = ym;
    select.appendChild(o);
  });
  if (prev && _estMadreYms.indexOf(prev) >= 0) select.value = prev;
}

function _applyEstMadreSort(items) {
  var col = _estMadreSort.col;
  var dir = _estMadreSort.dir === "asc" ? 1 : -1;
  var porRank = function (a, b) {
    var ra = a._rank == null ? 1e9 : a._rank, rb = b._rank == null ? 1e9 : b._rank;
    if (ra !== rb) return ra - rb;
    return String(a.cod).localeCompare(String(b.cod), "es", { numeric: true });
  };
  if (col === "cod") {
    items.sort(function (a, b) { return String(a.cod).localeCompare(String(b.cod), "es", { numeric: true }) * dir || String(a.marca).localeCompare(String(b.marca)); });
  } else if (col === "marca" || col === "familia") {
    items.sort(function (a, b) {
      var c = String(a[col] || "").toLowerCase().localeCompare(String(b[col] || "").toLowerCase(), "es");
      return c !== 0 ? c * dir : porRank(a, b);
    });
  } else {
    items.sort(function (a, b) { return dir === 1 ? porRank(a, b) : porRank(b, a); });
  }
}
function setEstMadreSort(col) {
  if (_estMadreSort.col === col) _estMadreSort.dir = _estMadreSort.dir === "asc" ? "desc" : "asc";
  else { _estMadreSort.col = col; _estMadreSort.dir = "asc"; }
  aplicarRangoEstadisticaMadre();
}
window.setEstMadreSort = setEstMadreSort;

function _emMesFmt(ym) {
  var m = String(ym).match(/^(\d{4})-(\d{2})/);
  if (!m) return ym;
  var meses = ["Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sept","Oct","Nov","Dic"];
  return meses[Number(m[2]) - 1] + " " + m[1].slice(2);
}
function _emNum(v) { var n = Math.round(Number(v) || 0); return n === 0 ? "—" : n.toLocaleString("es-AR"); }
// Cajas -> lo que se muestra. En unidades, sin uxb devuelve null (nunca un 0 inventado).
function _emV(it, cajas) {
  var c = Number(cajas) || 0;
  if (_estMadreUnidad !== "uni") return c;
  return it.uxb ? c * it.uxb : null;
}
function _emPintarSwitch() {
  var sw = document.getElementById("estMadreUnidadSw");
  if (!sw) return;
  Array.prototype.forEach.call(sw.querySelectorAll("button"), function (b) {
    b.classList.toggle("on", b.dataset.u === _estMadreUnidad);
    if (b.dataset.u === "uni") {
      b.disabled = !!_estMadreUxbErr;
      b.title = _estMadreUxbErr ? "No se pudo leer el uxb de Gestión: " + _estMadreUxbErr
        : "Unidades = cajas × unidades por caja (uxb de Gestión)";
    }
  });
}
function setEstMadreUnidad(u) {
  u = u === "uni" ? "uni" : "caj";
  if (u === "uni" && _estMadreUxbErr) { _emPintarSwitch(); return; }
  _estMadreUnidad = u;
  try { localStorage.setItem("em_unidad", u); } catch (e) {}
  _emPintarSwitch();
  if (_estMadreRows) aplicarRangoEstadisticaMadre();
}
window.setEstMadreUnidad = setEstMadreUnidad;

function _renderEstMadreTable(items, yms) {
  var table = document.getElementById("estMadreTable");
  if (!table) return;
  var thead = table.querySelector("thead");
  var tbody = table.querySelector("tbody");
  var totalsByYm = {};
  yms.forEach(function (ym) { totalsByYm[ym] = 0; });
  var totalEst = 0;
  var uni = _estMadreUnidad === "uni";
  items.forEach(function (it) {
    totalEst += _emV(it, it.est) || 0;
    yms.forEach(function (ym) { totalsByYm[ym] += _emV(it, it.byYm[ym]) || 0; });
  });
  function flecha(col) {
    if (_estMadreSort.col !== col) return ' <span class="est-madre-sort-idle">↕</span>';
    return _estMadreSort.dir === "asc" ? ' <span class="est-madre-sort-active">↑</span>' : ' <span class="est-madre-sort-active">↓</span>';
  }
  function cls(col) { return _estMadreSort.col === col ? " est-madre-sorted" : ""; }
  var prevY = null;
  var fila1 = '<tr>' +
    '<th class="est-madre-th-rank est-madre-sort-th' + cls("rank") + '" onclick="setEstMadreSort(\'rank\')" title="Ordenar por ranking de Est Madre">#' + flecha("rank") + '</th>' +
    '<th class="est-madre-th-cod est-madre-sort-th' + cls("cod") + '" onclick="setEstMadreSort(\'cod\')" title="Ordenar por código">Cod' + flecha("cod") + '</th>' +
    '<th class="est-madre-th-desc">Descripción</th>' +
    '<th class="est-madre-th-marca est-madre-sort-th' + cls("marca") + '" onclick="setEstMadreSort(\'marca\')" title="Ordenar por marca">Marca' + flecha("marca") + '</th>' +
    '<th class="est-madre-th-familia est-madre-sort-th' + cls("familia") + '" onclick="setEstMadreSort(\'familia\')" title="Ordenar por familia">Familia' + flecha("familia") + '</th>' +
    (uni ? '<th class="est-madre-th-em" title="Est Madre en unidades: la columna de Stocks × unidades por caja">Est Madre<br><small>u/mes</small></th>'
         : '<th class="est-madre-th-em" title="Est Madre: cajas por mes, la misma columna de Stocks">Est Madre<br><small>caj/mes</small></th>');
  yms.forEach(function (ym) {
    var y = ym.slice(0, 4);
    fila1 += '<th class="' + ((prevY && y !== prevY) ? "year-start" : "") + '">' + _emMesFmt(ym) + "</th>";
    prevY = y;
  });
  fila1 += "</tr>";
  var fila2 = '<tr class="est-madre-totals-row">' +
    '<th class="est-madre-th-rank"></th><th class="est-madre-th-cod"></th>' +
    '<th class="est-madre-th-desc">Total por mes (' + (uni ? "unidades" : "cajas") + ') →</th><th class="est-madre-th-marca"></th><th class="est-madre-th-familia"></th>' +
    '<th class="est-madre-th-em">' + _emNum(totalEst) + "</th>";
  prevY = null;
  yms.forEach(function (ym) {
    var y = ym.slice(0, 4);
    fila2 += '<th class="' + ((prevY && y !== prevY) ? "year-start" : "") + '">' + _emNum(totalsByYm[ym]) + "</th>";
    prevY = y;
  });
  fila2 += "</tr>";
  thead.innerHTML = fila2 + fila1;

  if (!items.length) {
    tbody.innerHTML = '<tr><td colspan="' + (6 + yms.length) + '" class="est-madre-empty">Ningún artículo coincide.</td></tr>';
    return;
  }
  tbody.innerHTML = items.map(function (it) {
    var pY = null;
    var codEsc = _escH(it.codLk), descEsc = _escH(it.desc);
    var celdas = yms.map(function (ym) {
      var cj = Math.round(it.byYm[ym] || 0);
      var vv = _emV(it, cj);
      var v = vv == null ? null : Math.round(vv);
      var y = ym.slice(0, 4);
      var ys = (pY && y !== pY) ? " year-start" : "";
      pY = y;
      if (cj === 0) return '<td class="' + (ys + " zero").trim() + '">—</td>';
      if (v == null) return '<td class="' + (ys + " em-sin-uxb").trim() + '" title="Sin unidades por caja en Gestión: ' + cj + ' cajas">s/uxb</td>';
      return '<td class="' + (ys + " est-madre-clickable").trim() + '" data-cod="' + codEsc + '" data-ym="' + ym +
        '" data-desc="' + descEsc + '" onclick="mostrarDetalleVentaMadre(this)" title="Click para ver detalle por cliente y provincia">' +
        v.toLocaleString("es-AR") + "</td>";
    }).join("");
    var em = it.secundario
      ? '<td class="est-madre-td-em est-madre-sec" title="Secundario: su venta se suma a la Est Madre de ' + _escH(it.principal) + '">→ ' + _escH(it.principal) + "</td>"
      : (_emV(it, it.est) == null && it.est
        ? '<td class="est-madre-td-em em-sin-uxb" title="Sin unidades por caja en Gestión: ' + Math.round(it.est) + ' cajas">s/uxb</td>'
        : '<td class="est-madre-td-em"' + (it.uxb ? ' title="' + it.uxb + ' u/caja"' : "") + '>' + _emNum(_emV(it, it.est)) + "</td>");
    return '<tr' + (it.secundario ? ' class="est-madre-fila-sec"' : "") + ">" +
      '<td class="est-madre-td-rank">' + (it._rank || "—") + "</td>" +
      '<td class="est-madre-td-cod">' + _escH(it.cod) + "</td>" +
      '<td class="est-madre-td-desc">' + _escH(it.desc) + "</td>" +
      '<td class="est-madre-td-marca">' + _escH(it.marca || "—") + "</td>" +
      '<td class="est-madre-td-familia">' + _escH(it.familia || "—") + "</td>" +
      em + celdas + "</tr>";
  }).join("");
}

// Un término que arranca con dígito busca el código POR EL PRINCIPIO, contra la grafía que se
// ve (031): "03" trae 030/031/035E y nunca 231 (≡ Stocks, v21.02). Lo demás es texto libre.
function filtrarEstadisticaMadre() {
  var tbody = document.querySelector("#estMadreTable tbody");
  if (!tbody || !_estMadreData) return;
  var q = String((document.getElementById("estMadreSearch") || {}).value || "").trim().toLowerCase();
  if (!q) { _renderEstMadreTable(_estMadreData, _estMadreYms); return; }
  var terms = q.split(/[\s,]+/).filter(Boolean);
  var filtrados = _estMadreData.filter(function (it) {
    return terms.some(function (t) {
      if (/^[0-9]/.test(t)) return String(it.cod).toLowerCase().indexOf(t) === 0;
      return (String(it.cod) + " " + it.desc + " " + it.familia + " " + it.marca).toLowerCase().indexOf(t) >= 0;
    });
  });
  _renderEstMadreTable(filtrados, _estMadreYms);
}
window.filtrarEstadisticaMadre = filtrarEstadisticaMadre;

// Excel: todas las filas de Stocks, con su Est Madre y las cajas de TODOS los meses.
function descargarEstadisticaMadreExcel() {
  var btnEl = (typeof event !== "undefined" && event && event.target) || null;
  var texto = btnEl ? btnEl.textContent : "";
  function restaurar() { if (btnEl) { btnEl.disabled = false; btnEl.textContent = texto; } }
  if (typeof XLSX === "undefined") { alert("No se pudo cargar la librería de Excel (xlsx). Recargá la página e intentá de nuevo."); return; }
  if (!_estMadreRows || !_estMadreAllYms || !_estMadreAllYms.length) { alert("No hay datos cargados. Esperá a que termine de cargar la Estadística Madre."); return; }
  if (btnEl) { btnEl.disabled = true; btnEl.textContent = "Generando…"; }
  try {
    /* v27.43: los meses que se están mostrando (selector «meses a mostrar»), del más nuevo al más viejo */
    var yms = (_estMadreYms && _estMadreYms.length) ? _estMadreYms.slice() : _estMadreAllYms.slice().reverse();
    var items = _estMadreRows.slice();
    var sortGuard = _estMadreSort; _estMadreSort = { col: "rank", dir: "asc" };
    _applyEstMadreSort(items);
    _estMadreSort = sortGuard;
    var uni = _estMadreUnidad === "uni";
    var xv = function (it, c) { var v = _emV(it, c); return v == null ? (Number(c) ? "s/uxb" : 0) : Math.round(v); };
    var enc = ["Ranking", "Código", "Descripción", "Marca", "Familia", "UxB", uni ? "Est Madre (u/mes)" : "Est Madre (caj/mes)"]
      .concat(yms.map(function (ym) { return _emMesFmt(ym); }));
    var aoa = [enc];
    var totEst = 0, tot = {};
    yms.forEach(function (ym) { tot[ym] = 0; });
    items.forEach(function (it) { totEst += _emV(it, it.est) || 0; yms.forEach(function (ym) { tot[ym] += _emV(it, it.byYm[ym]) || 0; }); });
    aoa.push(["", "", uni ? "TOTAL POR MES (unidades)" : "TOTAL POR MES (cajas)", "", "", "", Math.round(totEst)].concat(yms.map(function (ym) { return Math.round(tot[ym]); })));
    items.forEach(function (it) {
      aoa.push([it._rank || "", it.cod, it.desc, it.marca || "", it.familia || "", it.uxb || "",
        it.secundario ? "→ " + it.principal : xv(it, it.est)].concat(yms.map(function (ym) { return xv(it, it.byYm[ym]); })));
    });
    var ws = XLSX.utils.aoa_to_sheet(aoa);
    ws["!cols"] = [{ wch: 8 }, { wch: 9 }, { wch: 34 }, { wch: 7 }, { wch: 16 }, { wch: 5 }, { wch: 11 }].concat(yms.map(function () { return { wch: uni ? 9 : 8 }; }));
    ws["!autofilter"] = { ref: XLSX.utils.encode_range({ s: { r: 0, c: 0 }, e: { r: aoa.length - 1, c: enc.length - 1 } }) };
    for (var f = 1; f < aoa.length; f++) {
      for (var c = 0; c < enc.length; c++) {
        var cell = ws[XLSX.utils.encode_cell({ r: f, c: c })];
        if (cell && typeof cell.v === "number") cell.z = "#,##0";
      }
    }
    var wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "Estadistica Madre");
    var h = new Date();
    XLSX.writeFile(wb, "estadistica_madre_" + (uni ? "unidades_" : "") + h.getFullYear() + String(h.getMonth() + 1).padStart(2, "0") + String(h.getDate()).padStart(2, "0") + ".xlsx");
    restaurar();
  } catch (err) {
    console.error("descargarEstadisticaMadreExcel", err);
    alert("Error al generar el Excel: " + (err.message || err));
    restaurar();
  }
}
window.descargarEstadisticaMadreExcel = descargarEstadisticaMadreExcel;

/* ---------- Detalle por celda, mapa de provincias (movidos tal cual de admin.js) ---------- */
function _escH(s) {
  return String(s == null ? "" : s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/* =========================================================
   Mapa Argentina — render del SVG con colores por provincia
   y tooltip al pasar el mouse. SVG en argentina-map-data.js.
   ========================================================= */
function _renderArgentinaMap(provMap, sinProv) {
  var sinProvNote = '';
  if (sinProv && sinProv.unidades > 0) {
    sinProvNote =
      '<div style="margin-top:8px;padding:8px 12px;background:#f8f9fa;border-left:3px solid #bdc3c7;font-size:12px;color:#7f8c8d">' +
      '⚠ ' + sinProv.clientes + ' cliente' + (sinProv.clientes > 1 ? 's' : '') +
      ' sin provincia detectada (' + Math.round(sinProv.unidades).toLocaleString('es-AR') + ' unidades · ' +
      sinProv.pct.toFixed(1) + '% del total)' +
      '</div>';
  }
  return '<h4 style="margin:24px 0 10px;color:#2c3e50;font-size:15px">3. Mapa de provincias</h4>' +
    '<style>' +
    '.ar-map-container { position: relative; display: flex; justify-content: center; padding: 10px; background: #fafbfc; border-radius: 8px; }' +
    '.ar-map-svg { width: 280px; max-width: 100%; height: auto; }' +
    '.ar-map-svg polygon { transition: stroke-width 0.15s, fill 0.15s; }' +
    '.ar-map-svg polygon[data-prov]:hover { stroke: #2c3e50; stroke-width: 1.6; cursor: pointer; }' +
    '.ar-map-tooltip { position: absolute; pointer-events: none; background: #2c3e50; color: white; padding: 8px 12px; border-radius: 6px; font-size: 12px; z-index: 10; box-shadow: 0 4px 12px rgba(0,0,0,0.15); white-space: nowrap; }' +
    '.ar-map-tooltip strong { display:block; font-size:13px; margin-bottom:3px; }' +
    '.ar-map-legend { display:flex; gap:14px; align-items:center; justify-content:center; margin-top:8px; font-size:11px; color:#6b7280; }' +
    '.ar-map-legend-dot { display:inline-block; width:12px; height:12px; border-radius:2px; vertical-align:middle; margin-right:4px; }' +
    '</style>' +
    '<div class="ar-map-container">' +
      '<div id="ar-map-svg-slot" style="display:flex;justify-content:center;align-items:center;min-height:280px;color:#999;font-size:13px">Cargando mapa…</div>' +
      '<div id="ar-map-tooltip" class="ar-map-tooltip" style="display:none"></div>' +
    '</div>' +
    '<div class="ar-map-legend">' +
      '<span><span class="ar-map-legend-dot" style="background:#e2e8f0"></span>Sin ventas</span>' +
      '<span><span class="ar-map-legend-dot" style="background:rgba(108,92,231,0.3)"></span>Baja</span>' +
      '<span><span class="ar-map-legend-dot" style="background:rgba(108,92,231,0.6)"></span>Media</span>' +
      '<span><span class="ar-map-legend-dot" style="background:rgba(108,92,231,1)"></span>Alta</span>' +
    '</div>' +
    sinProvNote;
}

function _wireArgentinaMapTooltip(provMap, totalUnits) {
  var slot = document.getElementById('ar-map-svg-slot');
  if (!slot) return;

  // Cargar (o usar cache) el SVG y inyectar en el slot
  loadArgentinaMapSvg().then(function (svg) {
    if (!document.getElementById('ar-map-svg-slot')) return; // modal cerrado mientras tanto
    slot.innerHTML = svg;
    var svgEl = slot.querySelector('.ar-map-svg');
    if (!svgEl) return;
    _attachArMapHandlers(svgEl, provMap);
  }).catch(function (e) {
    slot.innerHTML = '<div style="color:#999;padding:20px">No se pudo cargar el mapa.</div>';
  });
}

function _attachArMapHandlers(svg, provMap) {
  var tooltip = document.getElementById('ar-map-tooltip');
  if (!tooltip) return;
  var container = svg.closest('.ar-map-container') || svg.parentElement;

  var paths = svg.querySelectorAll('[data-prov]');
  paths.forEach(function (p) {
    var prov = p.getAttribute('data-prov');
    var data = provMap[prov];
    // Color por intensidad: 0% → gris, >0% → púrpura con opacity por pct (cap 30%)
    if (data && data.unidades > 0) {
      var intensity = Math.min(1, Math.max(0.2, data.pct / 30));
      p.setAttribute('fill', 'rgba(108, 92, 231, ' + intensity.toFixed(2) + ')');
    } else {
      p.setAttribute('fill', '#e2e8f0');
    }

    p.addEventListener('mouseenter', function () {
      var d = provMap[prov];
      var content = '<strong>' + _escH(prov) + '</strong>';
      if (d && d.unidades > 0) {
        content += Math.round(d.unidades).toLocaleString('es-AR') + ' unidades · ' +
                   d.pct.toFixed(1) + '%<br>' +
                   d.clientes + ' cliente' + (d.clientes > 1 ? 's' : '');
      } else {
        content += '<span style="opacity:0.7">Sin ventas este mes</span>';
      }
      tooltip.innerHTML = content;
      tooltip.style.display = 'block';
    });
    p.addEventListener('mousemove', function (e) {
      var rect = container.getBoundingClientRect();
      var x = e.clientX - rect.left + 14;
      var y = e.clientY - rect.top + 14;
      tooltip.style.left = x + 'px';
      tooltip.style.top = y + 'px';
    });
    p.addEventListener('mouseleave', function () {
      tooltip.style.display = 'none';
    });
  });
}

/* =========================================================
   ESTADÍSTICA MADRE — Modal detalle de venta por celda
   Click en celda con dato → muestra:
     1. Ventas disruptivas (ratio ≥ 1.5x del prom. habitual del cliente)
     2. Ventas por cliente (cod, razón, provincia, uni, prom. histórico, ratio)
     3. Mapa de provincias (heatmap)
   ========================================================= */
async function mostrarDetalleVentaMadre(cellEl) {
  var cod = cellEl.dataset.cod;
  var ym = cellEl.dataset.ym;
  var desc = cellEl.dataset.desc || "";
  if (!cod || !ym) return;

  var modal = document.getElementById("estMadreModal");
  var title = document.getElementById("estMadreModalTitle");
  var body = document.getElementById("estMadreModalBody");
  if (!modal || !body) return;

  // Formato del mes/año (ej "Ago 25")
  var months = ["Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic"];
  var m = ym.match(/^(\d{4})-(\d{2})/);
  var ymFmt = m ? months[Number(m[2]) - 1] + " " + m[1].slice(2) : ym;

  title.innerHTML = "Detalle ventas — <strong>" + _escH(cod) + "</strong> " +
                    _escH(desc) + " · <strong>" + _escH(ymFmt) + "</strong>";
  body.innerHTML = '<div style="text-align:center;padding:40px;color:#999">Cargando detalle…</div>';
  modal.style.display = "flex";

  // ESC para cerrar
  if (!modal.__escWired) {
    modal.__escWired = true;
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && modal.style.display !== "none") {
        cerrarDetalleVentaMadre();
      }
    });
  }

  try {
    var resp = await sb.rpc("get_estadistica_madre_detail", {
      p_item_code: String(cod),
      p_ym: String(ym),
    });
    if (resp.error) throw resp.error;
    var rows = resp.data || [];

    if (rows.length === 0) {
      body.innerHTML = '<div style="padding:30px;color:#999;text-align:center">No hay ventas registradas para este artículo en este mes.</div>';
      return;
    }

    var totalUnits = rows.reduce(function (s, r) { return s + Number(r.unidades || 0); }, 0);

    // Helpers para diferenciar Loke direct vs vía Chef
    function _isChef(r) { return r && r.via === 'chef'; }
    var totalLoke = rows.filter(function (r) { return !_isChef(r); }).reduce(function (s, r) { return s + Number(r.unidades || 0); }, 0);
    var totalChef = rows.filter(_isChef).reduce(function (s, r) { return s + Number(r.unidades || 0); }, 0);
    var clientesLoke = rows.filter(function (r) { return !_isChef(r); }).length;
    var clientesChef = rows.filter(_isChef).length;

    // Badge "L" (vía Chef) — se inserta al lado del cod_cliente de cada fila Chef
    var CHEF_BADGE = '<span title="Vía Chef (artículo Loekemeyer revendido)" style="background:#f39c12;color:#fff;padding:1px 5px;border-radius:3px;font-size:9px;margin-left:5px;font-weight:700;letter-spacing:0.5px;vertical-align:middle">L</span>';

    // ---- Header summary ----
    var summary =
      '<div style="background:#f0f4f8;padding:14px 18px;border-radius:8px;margin-bottom:20px;display:flex;gap:30px;flex-wrap:wrap;align-items:center">' +
      '<div><div style="font-size:11px;color:#888;text-transform:uppercase;letter-spacing:0.5px;font-weight:600">Total unidades</div>' +
      '<div style="font-size:24px;font-weight:700;color:#2c3e50">' + Math.round(totalUnits).toLocaleString("es-AR") + '</div></div>' +
      '<div><div style="font-size:11px;color:#888;text-transform:uppercase;letter-spacing:0.5px;font-weight:600">Clientes</div>' +
      '<div style="font-size:24px;font-weight:700;color:#2c3e50">' + rows.length + '</div></div>';

    // Breakdown Loke direct + vía Chef (solo si hay algún Chef)
    if (totalChef > 0) {
      summary +=
        '<div style="border-left:1px solid #d1d8e0;padding-left:24px">' +
        '<div style="font-size:11px;color:#888;text-transform:uppercase;letter-spacing:0.5px;font-weight:600">Loke direct</div>' +
        '<div style="font-size:16px;font-weight:700;color:#2c3e50">' + Math.round(totalLoke).toLocaleString("es-AR") + '</div>' +
        '<div style="font-size:11px;color:#999">' + clientesLoke + ' clientes</div>' +
        '</div>' +
        '<div>' +
        '<div style="font-size:11px;color:#f39c12;text-transform:uppercase;letter-spacing:0.5px;font-weight:700">Vía Chef <span style="background:#f39c12;color:#fff;padding:1px 5px;border-radius:3px;font-size:9px;font-weight:700">L</span></div>' +
        '<div style="font-size:16px;font-weight:700;color:#d35400">' + Math.round(totalChef).toLocaleString("es-AR") + '</div>' +
        '<div style="font-size:11px;color:#999">' + clientesChef + ' clientes</div>' +
        '</div>';
    }
    summary += '</div>';

    // ---- 2. Ventas por cliente ----
    // Provincia ahora se ve en el mapa (sección 3); columna comentada acá.
    // Si hay más de 20 filas, el wrapper hace scroll vertical (max-height ~720px ≈ 20 filas + header sticky).
    var clientTableScrollStyle =
      rows.length > 20
        ? "overflow-x:auto;max-height:720px;overflow-y:auto;border:1px solid #e0e0e0;border-radius:6px;scrollbar-gutter:stable"
        : "overflow-x:auto";
    var clientTable =
      '<h4 style="margin:24px 0 10px;color:#2c3e50;font-size:15px">2. Ventas por cliente' +
      (rows.length > 20 ? ' <span style="font-size:12px;color:#888;font-weight:400">(' + rows.length + ' filas — scroll)</span>' : '') +
      '</h4>' +
      '<div style="' + clientTableScrollStyle + '"><table class="em-detail-tbl em-detail-tbl-sticky">' +
      '<thead><tr>' +
      '<th>Cod</th><th>Razón Social</th>' +
      // '<th>Provincia</th>' +  // ← provincia oculta (se ve en el mapa)
      '<th style="text-align:right">Unidades</th>' +
      '<th style="text-align:right">Prom. histórico</th>' +
      '<th style="text-align:right">Ratio</th>' +
      '</tr></thead><tbody>' +
      rows.map(function (r) {
        var ratio = r.ratio != null ? Number(r.ratio).toFixed(2) + "x" : "—";
        var isDisrupt = r.ratio != null && Number(r.ratio) >= 1.5;
        var isChef = _isChef(r);
        var ratioColor = isDisrupt ? "#e74c3c" : "#27ae60";
        var avg = r.avg_monthly_units != null ? Math.round(Number(r.avg_monthly_units)).toLocaleString("es-AR") : "—";
        // Bg: disruptivo > chef > default
        var rowBg = isDisrupt ? "background:#fff5f5" : (isChef ? "background:#fff8e8" : "");
        return '<tr' + (rowBg ? ' style="' + rowBg + '"' : '') + '>' +
          '<td style="font-weight:600;color:#c0392b">' + _escH(r.cod_cliente) + (isChef ? CHEF_BADGE : '') + '</td>' +
          '<td>' + _escH(r.business_name) + '</td>' +
          // '<td>' + _escH(r.provincia) + '</td>' +  // ← provincia oculta
          '<td style="text-align:right;font-weight:600">' + Math.round(Number(r.unidades)).toLocaleString("es-AR") + '</td>' +
          '<td style="text-align:right;color:#666">' + avg + '</td>' +
          '<td style="text-align:right;color:' + ratioColor + ';font-weight:700">' + ratio + '</td>' +
          '</tr>';
      }).join("") +
      '</tbody></table></div>';

    // ---- Mapa de Argentina (reemplaza la tabla de provincias) ----
    var provMap = {};
    rows.forEach(function (r) {
      var prov = r.provincia || "Sin provincia";
      if (!provMap[prov]) provMap[prov] = { unidades: 0, clientes: 0 };
      provMap[prov].unidades += Number(r.unidades || 0);
      provMap[prov].clientes += 1;
    });
    // Anotar % sobre el total
    Object.keys(provMap).forEach(function (p) {
      provMap[p].pct = totalUnits > 0 ? (provMap[p].unidades / totalUnits) * 100 : 0;
    });
    // "Sin provincia" se muestra como nota aparte
    var sinProv = provMap["Sin provincia"];
    var mapBlock = _renderArgentinaMap(provMap, sinProv);

    // ---- 3. Ventas disruptivas (ratio ≥ 1.5x) ----
    var disruptive = rows.filter(function (r) {
      return r.ratio != null && Number(r.ratio) >= 1.5;
    }).sort(function (a, b) { return Number(b.ratio) - Number(a.ratio); });

    var disruptiveBlock;
    if (disruptive.length === 0) {
      disruptiveBlock =
        '<details class="em-card-collapse em-card-disruptive em-card-ok" style="margin-bottom:18px">' +
        '<summary>' +
        '<span class="em-card-title">1. Ventas disruptivas (ratio ≥ 1.5x)</span>' +
        '<span class="em-card-badge em-card-badge-ok">✓ Demanda normal</span>' +
        '<span class="em-card-chevron" aria-hidden="true">▾</span>' +
        '</summary>' +
        '<div class="em-card-content">' +
        '<div style="padding:16px;color:#27ae60;background:#eafaf1;border:1px solid #27ae60;border-radius:6px;font-weight:500">' +
        '✓ Ningún cliente compró más de 1.5x su promedio habitual este mes. Demanda normal.' +
        '</div>' +
        '</div>' +
        '</details>';
    } else {
      var disruptUnits = disruptive.reduce(function (s, r) { return s + Number(r.unidades || 0); }, 0);
      var disruptPct = totalUnits > 0 ? (disruptUnits / totalUnits) * 100 : 0;
      disruptiveBlock =
        '<details class="em-card-collapse em-card-disruptive em-card-warn" style="margin-bottom:18px">' +
        '<summary>' +
        '<span class="em-card-title">1. Ventas disruptivas (ratio ≥ 1.5x)</span>' +
        '<span class="em-card-badge em-card-badge-warn">⚠ ' + disruptive.length + ' cliente' + (disruptive.length > 1 ? 's' : '') +
        ' · ' + disruptPct.toFixed(1) + '% del mes</span>' +
        '<span class="em-card-chevron" aria-hidden="true">▾</span>' +
        '</summary>' +
        '<div class="em-card-content">' +
        '<div style="background:#fdecea;border:1px solid #e74c3c;padding:10px 14px;border-radius:6px;margin-bottom:10px;font-size:13px">' +
        '<strong>' + disruptive.length + '</strong> cliente' + (disruptive.length > 1 ? 's' : '') +
        ' con compra disruptiva · <strong>' + Math.round(disruptUnits).toLocaleString("es-AR") + '</strong> unidades · ' +
        '<strong>' + disruptPct.toFixed(1) + '%</strong> del total del mes' +
        '</div>' +
        '<div style="overflow-x:auto"><table class="em-detail-tbl">' +
        '<thead><tr>' +
        '<th>Cod</th><th>Razón Social</th>' +
        // '<th>Provincia</th>' +  // ← provincia oculta (se ve en el mapa)
        '<th style="text-align:right">Unidades este mes</th>' +
        '<th style="text-align:right">Prom. histórico</th>' +
        '<th style="text-align:right">Ratio</th>' +
        '<th style="text-align:right">Exceso</th>' +
        '</tr></thead><tbody>' +
        disruptive.map(function (r) {
          var exceso = Math.round(Number(r.unidades) - Number(r.avg_monthly_units));
          var isChef = _isChef(r);
          return '<tr style="background:#fff5f5">' +
            '<td style="font-weight:600;color:#c0392b">' + _escH(r.cod_cliente) + (isChef ? CHEF_BADGE : '') + '</td>' +
            '<td>' + _escH(r.business_name) + '</td>' +
            // '<td>' + _escH(r.provincia) + '</td>' +  // ← provincia oculta
            '<td style="text-align:right;font-weight:700">' + Math.round(Number(r.unidades)).toLocaleString("es-AR") + '</td>' +
            '<td style="text-align:right;color:#666">' + Math.round(Number(r.avg_monthly_units)).toLocaleString("es-AR") + '</td>' +
            '<td style="text-align:right;color:#e74c3c;font-weight:700">' + Number(r.ratio).toFixed(2) + 'x</td>' +
            '<td style="text-align:right;color:#e74c3c">+' + exceso.toLocaleString("es-AR") + '</td>' +
            '</tr>';
        }).join("") +
        '</tbody></table></div>' +
        '</div>' +
        '</details>';
    }

    // Orden nuevo: disruptivas arriba → [cliente + mapa side-by-side]
    // El bloque inferior usa grid 2-cols: tabla izq + mapa der.
    // En pantallas chicas (< 900px) se apila vertical.
    var sideBySide =
      '<div class="em-cliente-mapa-grid" style="display:grid;grid-template-columns:minmax(0,1fr) minmax(0,420px);gap:56px;align-items:start">' +
      '<div style="min-width:0">' + clientTable + '</div>' +
      '<div style="min-width:0;padding-left:8px">' + mapBlock + '</div>' +
      '</div>' +
      '<style>@media (max-width:900px){.em-cliente-mapa-grid{grid-template-columns:1fr !important;gap:24px !important}}</style>';
    body.innerHTML = summary + disruptiveBlock + sideBySide;
    // Cablear hover/tooltip del mapa (después de inyectar HTML)
    _wireArgentinaMapTooltip(provMap, totalUnits);
  } catch (e) {
    console.error("mostrarDetalleVentaMadre error", e);
    body.innerHTML =
      '<div style="padding:20px;color:#c0392b;background:#fdecea;border:1px solid #e74c3c;border-radius:8px">' +
      '<strong>Error:</strong> ' + _escH(e.message || String(e)) + '<br><br>' +
      'Verificá que la función <code>get_estadistica_madre_detail</code> esté creada en Supabase.' +
      '</div>';
  }
}
window.mostrarDetalleVentaMadre = mostrarDetalleVentaMadre;

function cerrarDetalleVentaMadre() {
  var modal = document.getElementById("estMadreModal");
  if (modal) modal.style.display = "none";
}
window.cerrarDetalleVentaMadre = cerrarDetalleVentaMadre;

/* ---------- Reporte de ventas disruptivas (movido tal cual de admin.js) ---------- */
// Piso de volumen del reporte de disruptivas, en CAJAS. Por debajo de esto la
// compra no se lista aunque el ratio la marque como disruptiva: un cliente que
// pasa de 1 a 2 cajas da x2,00 y no dice nada del negocio.
// El piso queda en CAJAS aunque el reporte se lea en unidades: es la magnitud
// con la que se compra y se despacha, y no cambia si se corrige un uxb.
var DISRUPTIVAS_MIN_CAJAS = 10;

// Umbral del reporte: se lista la compra cuando supera al promedio personal del
// cliente por este porcentaje. 0.30 = compró un 30% más que su promedio
// (ratio > 1,30). Antes era 0.50 (1,50) y dejaba afuera desvíos que sí importan.
var DISRUPTIVAS_EXCESO_MIN = 0.30;

// Clientes internos: los mismos que ya excluyen las RPC de estadística
// (get_ranking_inactivos, get_estadistica_madre_detail, …). Sus pedidos son
// pruebas y no representan demanda real.
var DISRUPTIVAS_CODS_PRUEBA = ["1", "3878"];

// Generar y descargar reporte de ventas disruptivas por cliente
async function descargarReporteVentasDisruptivas() {
  if (!_estMadreData || !_estMadreYms || _estMadreData.length === 0) {
    alert('No hay datos cargados. Cargá la Est. Madre primero.');
    return;
  }

  var select = document.getElementById("estMadreDisruptivasMonth");
  var mesMasReciente = select ? select.value : '';

  if (!mesMasReciente) {
    alert('Seleccioná un mes para descargar.');
    return;
  }

  if (!_estMadreYms.includes(mesMasReciente)) {
    alert('El mes seleccionado no está disponible en los datos.');
    return;
  }

  // Parsear el mes (YYYY-MM) para obtener fecha
  var parts = mesMasReciente.split('-');
  var year = parseInt(parts[0]), month = parseInt(parts[1]);

  // Corte superior EXCLUSIVO en el primer día del mes siguiente.
  // Antes era new Date(year, month, 0), que es el último día del mes a las
  // 00:00, y con un filtro <= se perdía ese día entero: para 2026-06 eran 6
  // pedidos y 91 líneas que no entraban al reporte sin ninguna señal.
  var finExclusivo = new Date(year, month, 1);

  // Rango de 12 meses anteriores (excluye el mes actual)
  var hace12Meses = new Date(year, month - 13, 1);

  var statusEl = document.getElementById("estMadreStatus");
  var btnEl = event.target;
  var textoOriginal = btnEl.textContent;
  btnEl.disabled = true;
  btnEl.textContent = "Generando...";

  // Query a Supabase para obtener las líneas de pedido del período.
  //
  // PAGINADO a propósito: el REST de Supabase corta en 1000 filas y NO avisa
  // (no devuelve error). Los últimos 12 meses tienen ~13.200 líneas, así que
  // sin paginar el reporte se calculaba sobre el 8% de los datos y salía igual,
  // sin ninguna señal de que faltaba el resto.
  var PAGINA = 1000;
  var data = [];

  try {
    for (var desde = 0; ; desde += PAGINA) {
      var resp = await sb
        .from("order_items")
        .select(
          "cajas, uxb, products(cod, uxb), orders!inner(created_at, customers(business_name, cod_cliente))"
        )
        .gte("orders.created_at", hace12Meses.toISOString())
        .lt("orders.created_at", finExclusivo.toISOString())
        .range(desde, desde + PAGINA - 1);

      if (resp.error) throw resp.error;
      var lote = resp.data || [];
      data = data.concat(lote);
      if (lote.length < PAGINA) break;
    }

    var disruptivasPorProducto = {};

    // Agrupar por producto. El código de artículo sale de products vía
    // product_id: order_items no guarda item_code. Las líneas de la línea Loke
    // van por loke_product_id y quedan sin ficha en products, así que no traen
    // cod y las saltea el guard de abajo.
    data.forEach(function(oi) {
      var prod = oi.products || {};
      var cod = String(prod.cod || "").trim().toUpperCase();
      var qty = Number(oi.cajas || 0);
      // uxb de la línea (el vigente cuando se cargó el pedido), con respaldo al
      // del producto. El reporte se expresa en UNIDADES, pero el piso de abajo
      // se mide en CAJAS, así que hacen falta las dos magnitudes.
      var uxb = Number(oi.uxb || 0) || Number(prod.uxb || 0) || 0;
      var order = oi.orders || {};
      var cli = order.customers || {};
      var cliente = String(cli.cod_cliente || "").trim();
      var clienteNombre = cli.business_name || "Desconocido";
      var fechaOrden = new Date(order.created_at || "");

      if (!cod || !cliente || qty === 0) return;
      if (DISRUPTIVAS_CODS_PRUEBA.indexOf(cliente) !== -1) return;

      // Determinar mes-año de la orden (YYYY-MM)
      var ym = fechaOrden.getFullYear() + "-" + String(fechaOrden.getMonth() + 1).padStart(2, "0");

      if (!disruptivasPorProducto[cod]) {
        disruptivasPorProducto[cod] = { compras: {} };
      }

      if (!disruptivasPorProducto[cod].compras[cliente]) {
        disruptivasPorProducto[cod].compras[cliente] = {
          nombre: clienteNombre,
          porMes: {}
        };
      }

      if (!disruptivasPorProducto[cod].compras[cliente].porMes[ym]) {
        disruptivasPorProducto[cod].compras[cliente].porMes[ym] = { cjs: 0, uni: 0 };
      }

      disruptivasPorProducto[cod].compras[cliente].porMes[ym].cjs += qty;
      disruptivasPorProducto[cod].compras[cliente].porMes[ym].uni += qty * uxb;
    });

    // Procesar datos: calcular promedios y detectar disruptivas
    var reportePorProducto = [];

    Object.keys(disruptivasPorProducto).forEach(function(cod) {
      var comprasPorCliente = disruptivasPorProducto[cod].compras;
      var clientesDisruptivos = [];

      Object.keys(comprasPorCliente).forEach(function(cliente) {
        var clienteData = comprasPorCliente[cliente];
        var porMes = clienteData.porMes;

        var mes = porMes[mesMasReciente];
        if (!mes || mes.cjs === 0) return; // Cliente no compró ese mes

        // Piso de volumen: una compra puede ser disruptiva para el cliente y
        // aun así ser irrelevante en volumen (2 cajas contra un promedio de 1).
        // El piso va en CAJAS aunque el reporte se lea en unidades, porque es
        // la magnitud con la que se compra y se despacha.
        if (mes.cjs <= DISRUPTIVAS_MIN_CAJAS) return;

        // Calcular promedio de 12 meses (excluyendo el mes actual).
        // Se promedia sobre UNIDADES para que el ratio sea el mismo que se lee
        // en el reporte. Con uxb constante da idéntico a promediar cajas; donde
        // el uxb cambió, unidades es lo correcto.
        var ventasAnteriores = [];
        Object.keys(porMes).forEach(function(ym) {
          if (ym !== mesMasReciente) {
            var v = (porMes[ym] && porMes[ym].uni) || 0;
            if (v > 0) ventasAnteriores.push(v);
          }
        });

        // Sin historial = primera compra del artículo por ese cliente. Antes se
        // descartaba; ahora entra marcada como INCORPORACIÓN, que es
        // justamente el caso más disruptivo (pasó de 0 a comprar).
        if (ventasAnteriores.length === 0) {
          clientesDisruptivos.push({
            cliente: cliente,
            nombre: clienteData.nombre,
            unidades: Math.round(mes.uni),
            promedio: 0,
            multiplicador: null,   // sin promedio previo no hay ratio
            incorporacion: true
          });
          return;
        }

        var promedio = ventasAnteriores.reduce(function(a, b) { return a + b; }) / ventasAnteriores.length;
        var multiplicador = mes.uni / promedio;

        if (multiplicador > 1 + DISRUPTIVAS_EXCESO_MIN) {
          clientesDisruptivos.push({
            cliente: cliente,
            nombre: clienteData.nombre,
            unidades: Math.round(mes.uni),
            promedio: Math.round(promedio),
            multiplicador: multiplicador,
            incorporacion: false
          });
        }
      });

      // Incorporaciones primero, después el resto por desvío descendente.
      clientesDisruptivos.sort(function(a, b) {
        if (a.incorporacion !== b.incorporacion) return a.incorporacion ? -1 : 1;
        if (a.incorporacion) return b.unidades - a.unidades;
        return b.multiplicador - a.multiplicador;
      });

      if (clientesDisruptivos.length > 0) {
        reportePorProducto.push({
          cod: cod,
          clientes: clientesDisruptivos
        });
      }
    });

    // Generar reporte
    var report = [];
    report.push("REPORTE DE VENTAS DISRUPTIVAS POR CLIENTE");
    report.push("Mes: " + mesMasReciente);
    report.push("Generado: " + new Date().toLocaleString("es-AR"));
    report.push("");
    report.push("=".repeat(100));
    report.push("");

    if (reportePorProducto.length === 0) {
      report.push("SIN ANOMALÍAS DETECTADAS");
    } else {
      reportePorProducto.forEach(function(prod, idx) {
        report.push((idx + 1) + ". ARTÍCULO " + prod.cod);
        // Solo el total de unidades del mes. El ratio y el promedio no se
        // imprimen: si el cliente está en la lista es porque ya superó el
        // umbral, así que el número no agrega nada a la lectura.
        prod.clientes.forEach(function(c) {
          report.push(
            "  " + c.nombre + " " + c.unidades.toLocaleString("es-AR") + " uni." +
            (c.incorporacion ? " INCORPORACIÓN" : "")
          );
        });
        report.push("");
      });
    }

    var totalIncorp = 0, totalDisrup = 0;
    reportePorProducto.forEach(function(prod) {
      prod.clientes.forEach(function(c) { c.incorporacion ? totalIncorp++ : totalDisrup++; });
    });

    report.push("=".repeat(100));
    report.push(
      "Total: " + totalDisrup + " compra(s) por encima del promedio · " +
      totalIncorp + " incorporación(es), en " + reportePorProducto.length + " artículo(s)."
    );
    report.push(
      "Definición: se lista la compra que supera en más de " +
      Math.round(DISRUPTIVAS_EXCESO_MIN * 100) + "% el promedio personal del cliente " +
      "(ratio > " + (1 + DISRUPTIVAS_EXCESO_MIN).toFixed(2) + "x), calculado sobre los 12 meses previos."
    );
    report.push(
      "INCORPORACIÓN = el cliente compró ese artículo por primera vez (sin historial en los 12 meses previos)."
    );
    report.push(
      "Piso de volumen: solo se listan las compras de más de " + DISRUPTIVAS_MIN_CAJAS + " cajas en el mes."
    );
    report.push("Las cantidades están en UNIDADES (cajas x unidades por caja).");

    var contenido = report.join("\n");

    // Descargar
    var blob = new Blob([contenido], { type: "text/plain;charset=utf-8" });
    var link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = "disruptivas_clientes_" + mesMasReciente + ".txt";
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);

    btnEl.disabled = false;
    btnEl.textContent = textoOriginal;
  } catch (err) {
    console.error("Error generando reporte:", err);
    alert("Error: " + (err.message || "No se pudieron obtener los datos"));
    btnEl.disabled = false;
    btnEl.textContent = textoOriginal;
  }
}
window.descargarReporteVentasDisruptivas = descargarReporteVentasDisruptivas;

// ---- API del módulo (la llama el cargador abrirEstadisticaMadre de cada admin.js) ----
window.EstMadre = {
  version: EST_MADRE_VERSION,
  abrir: function () { return cargarEstadisticaMadre(false); },
  recargar: function () { return cargarEstadisticaMadre(true); },
  _armarFilas: _emArmarFilas,   // para el test
};

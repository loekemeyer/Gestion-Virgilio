"use strict";

/* ============================================================
   Producciones Disruptivas — MIGRADO a schema GP2
   Los datos salen del RPC "GP2".disruptivas_bundle(p_desde, p_hasta)
   (espejo de la produccion vieja en "GP2".produccion).
   El RPC ya aplica TODOS los filtros de negocio y umbrales de premio,
   y devuelve las filas con las claves VIEJAS (Matriz, Legajo, Uni, Fecha,
   Premio, Segundos_Trabajados, Tiempo_Historico, ...) para no tocar el render.
   ============================================================ */

const sb = GP2_SB();   // el cliente GP2 vive en supabase-config.js (2026-09-05)

const fechaDesde = document.getElementById("fechaDesde");
const fechaHasta = document.getElementById("fechaHasta");
const statusEl = document.getElementById("status");
const resultEl = document.getElementById("result");

/* ================= HELPERS ================= */
function n(v) { const x = Number(v); return Number.isFinite(x) ? x : 0; }
function f(v, d = 0) { return GP2N.fmt(v, d); }   /* la regla de numero de la casa (gp2-numero.js) */
const esc = GP2UI.esc;   /* helper de la casa (gp2-ui.js) */
const cls = GP2UI.cls;   /* "pos" | "neg" | "cero" segun el signo (el cero queda gris) */
// Fecha viene del RPC como 'YYYY-MM-DD': formatear a mano (new Date() la parsea
// como medianoche UTC y en AR se mostraba el dia anterior).
function fechaCorta(s) {
  const p = String(s || "").slice(0, 10).split("-");
  return p.length === 3 ? `${+p[2]}/${+p[1]}/${p[0]}` : String(s || "");
}

/* ================= STATE ================= */
let allRows = [];              // disruptivas dentro del rango de fechas activo
let allRowsRaw = [];           // TODAS las disruptivas del bundle (sin filtro de fecha)
let empMap = new Map();        // legajo -> nombre (bundle.empleados)
let selectedEmpleados = new Set();
let lastPositivas = [];
let lastNegativas = [];
const empGrid = document.getElementById("empGrid");

/* ================= INIT ================= */
async function init() {
  fechaHasta.value = GP2UI.hoyAR();   // hoy en Argentina (antes: UTC, corria el dia despues de las 21:00)
  fechaDesde.value = "2020-01-01";

  statusEl.textContent = "Cargando datos...";
  try {
    // GP2: un solo RPC trae el mapa de empleados + todas las disruptivas.
    // No existe tabla Empleados en GP2: el nombre del operario viene embebido.
    const { data: bundle, error } = await sb.rpc("disruptivas_bundle");
    if (error) throw new Error(error.message);

    empMap = new Map();
    const empObj = (bundle && bundle.empleados) || {};
    Object.keys(empObj).forEach(leg => empMap.set(String(leg).trim(), empObj[leg] || ""));

    allRowsRaw = (bundle && bundle.rows) || [];

    // Chips de empleados: en GP2 no hay flag "Activo", asi que se arman con los
    // operarios que efectivamente aparecen en disruptivas (con su conteo).
    const counts = {};
    allRowsRaw.forEach(r => {
      const leg = String(r.Legajo || "").trim();
      if (!leg) return;
      counts[leg] = (counts[leg] || 0) + 1;
    });
    const legajos = Object.keys(counts).sort((a, b) =>
      String(empMap.get(a) || a).localeCompare(String(empMap.get(b) || b), "es"));

    empGrid.innerHTML =
      `<button type="button" class="emp-chip emp-chip-todos active" data-legajo="__todos__">Todos</button>` +
      legajos.map(leg => {
        const nom = String(empMap.get(leg) || ("Leg " + leg)).trim();
        const parts = nom.split(/\s+/);
        const l1 = parts[0] || "";
        const l2 = parts.slice(1).join(" ");
        return `<button type="button" class="emp-chip" data-legajo="${esc(leg)}"><span class="emp-chip-l1">${esc(l1)}</span><span class="emp-chip-l2">${esc(l2)} (${counts[leg]})</span></button>`;
      }).join("");

    const btnTodos = empGrid.querySelector('[data-legajo="__todos__"]');
    btnTodos.addEventListener("click", () => {
      selectedEmpleados.clear();
      empGrid.querySelectorAll(".emp-chip").forEach(b => b.classList.remove("active"));
      btnTodos.classList.add("active");
      if (allRows.length) renderDisruptivas();
    });
    empGrid.querySelectorAll('.emp-chip:not([data-legajo="__todos__"])').forEach(btn => {
      btn.addEventListener("click", () => {
        const leg = btn.dataset.legajo;
        if (selectedEmpleados.has(leg)) { selectedEmpleados.delete(leg); btn.classList.remove("active"); }
        else { selectedEmpleados.add(leg); btn.classList.add("active"); }
        btnTodos.classList.toggle("active", selectedEmpleados.size === 0);
        if (allRows.length) renderDisruptivas();
      });
    });

    empGrid.classList.remove("hidden");
    filtrarPorFecha();
  } catch (err) { statusEl.textContent = "Error: " + err.message; console.error(err); }

  fechaDesde.addEventListener("change", filtrarPorFecha);
  fechaHasta.addEventListener("change", filtrarPorFecha);
}

function filtrarPorFecha() {
  const desde = fechaDesde.value, hasta = fechaHasta.value;
  if (!desde || !hasta) return;
  // Fecha es 'YYYY-MM-DD': comparar como texto evita el corrimiento UTC/AR
  // (con Date, el dia "desde" quedaba excluido del rango).
  allRows = allRowsRaw.filter(r => {
    const ff = String(r.Fecha || "").slice(0, 10);
    return ff >= desde && ff <= hasta;
  });
  renderDisruptivas();
  statusEl.textContent = `${allRows.length} disruptivas en el rango`;
}

/* ================= RENDER ================= */
function renderDisruptivas() {
  let filtered = allRows;
  if (selectedEmpleados.size > 0) {
    filtered = allRows.filter(r => selectedEmpleados.has(String(r.Legajo || "").trim()));
  }
  // El RPC ya filtro esMatriz, Legajo<>1, matrices excluidas, Tiempo_Historico>0
  // y el umbral de premio. Aca solo separamos positivas/negativas para el render.
  const prodRows = filtered;

  const positivas = [];
  const negativas = [];

  prodRows.forEach(r => {
    const premio = n(r.Premio);
    const leg = String(r.Legajo || "").trim();
    const mat = String(r.Matriz || "").trim();
    const item = {
      id: r.id,
      raw: r,
      fecha: r.Fecha ? fechaCorta(r.Fecha) : "",
      legajo: leg,
      nombre: empMap.get(leg) || r.Nombre_Empleado || "",
      matriz: mat,
      descMat: r.Nombre_Matriz || "",
      uni: n(r.Uni),
      segTrab: n(r.Segundos_Trabajados),
      segHist: n(r.Segundos_Historico),
      promHist: n(r.Tiempo_Historico),
      premio: premio
    };
    if (premio > 5 && premio < 9.5) positivas.push(item);
    else if (premio < -5) negativas.push(item);
  });

  const sortMat = (a, b) => {
    const ma = parseInt(a.matriz) || 0, mb = parseInt(b.matriz) || 0;
    if (ma !== mb) return ma - mb;
    return new Date(b.raw.Fecha) - new Date(a.raw.Fecha);
  };
  positivas.sort(sortMat);
  negativas.sort(sortMat);

  lastPositivas = positivas;
  lastNegativas = negativas;
  const btnExcel = document.getElementById("btnExcelDisr");
  if (btnExcel) btnExcel.classList.toggle("hidden", !positivas.length && !negativas.length);

  function buildTable(items, titulo, colorCls) {
    if (!items.length) return `<p style="color:#888;padding:12px;">Sin registros ${titulo.toLowerCase()}.</p>`;
    let h = `
    <div class="informe-wrap" style="margin-bottom:18px;">
      <div class="informe-title">${esc(titulo)} (${items.length})</div>
      <div class="informe-scroll">
        <table class="tbl">
          <thead><tr>
            <th>Fecha</th><th>Leg</th><th>Empleado</th><th>Mat</th><th>Descripcion</th>
            <th>Uni</th><th>T. Prom</th><th>Prom Hist</th><th>Seg Trab</th><th>Seg Hist</th><th>Puntaje</th><th></th>
          </tr></thead>
          <tbody>`;
    items.forEach(i => {
      h += `<tr data-rid="${i.id}">
        <td class="c">${esc(i.fecha)}</td>
        <td class="c b">${esc(i.legajo)}</td>
        <td>${esc(i.nombre)}</td>
        <td class="c b">${esc(i.matriz)}</td>
        <td>${esc(i.descMat)}</td>
        <td class="r">${f(i.uni)}</td>
        <td class="r">${i.uni > 0 ? f(i.segTrab / i.uni, 2) : "-"}</td>
        <td class="r">${f(i.promHist, 2)}</td>
        <td class="r">${f(i.segTrab)}</td>
        <td class="r">${f(i.segHist)}</td>
        <td class="c b ${colorCls}">${f(i.premio, 1)}</td>
        <td class="c" style="white-space:nowrap;">
          <button class="btn-icon btn-ok" title="Revisado" onclick="revisarDisruptiva(${i.id}, this)">&#10003;</button>
          <button class="btn-icon btn-edit" title="Editar" onclick="abrirEditDisruptiva(${i.id})">&#9998;</button>
        </td>
      </tr>`;
    });
    h += `</tbody></table></div></div>`;
    return h;
  }

  const resumen = `
  <div class="resumen">
    <div class="resumen-card"><div class="val pos">${positivas.length}</div><div class="lbl">Puntaje &gt; 5</div></div>
    <div class="resumen-card"><div class="val neg">${negativas.length}</div><div class="lbl">Puntaje &lt; -5</div></div>
    <div class="resumen-card"><div class="val">${prodRows.length}</div><div class="lbl">Total producciones</div></div>
  </div>`;

  const modal = `
  <div id="modalEdit" class="modal-overlay hidden">
    <div class="modal-box">
      <div class="modal-header">Editar produccion</div>
      <div class="modal-body">
        <div class="modal-info" id="modalInfo"></div>
        <div class="modal-fields">
          <div class="field"><label>Hora Inicio</label><input type="time" id="modalHoraIni" step="1"/></div>
          <div class="field"><label>Hora Fin</label><input type="time" id="modalHoraFin" step="1"/></div>
          <div class="field"><label>Tiempo Muerto (hs)</label><input inputmode="decimal" type="number" id="modalTM" min="0" step="0.01"/></div>
          <div id="modalTMDetalle" style="width:100%;font-size:12px;color:#666;margin-top:-4px;"></div>
          <div class="field"><label>Unidades</label><input inputmode="numeric" type="number" id="modalUni" min="0" step="1"/></div>
          <div class="field" style="justify-content:center;"><label style="display:flex;align-items:center;gap:6px;cursor:pointer;"><input type="checkbox" id="modalAnular" style="width:18px;height:18px;cursor:pointer;"/> Anular Tiempo</label></div>
        </div>
        <div class="modal-preview" id="modalPreview"></div>
      </div>
      <div class="modal-footer">
        <button class="btn" onclick="cerrarModal()">Cancelar</button>
        <button class="btn btn-dark" onclick="guardarEditDisruptiva()">Guardar</button>
      </div>
    </div>
  </div>`;

  resultEl.innerHTML = resumen +
    buildTable(positivas, "Producciones con Puntaje > 5", "pos") +
    buildTable(negativas, "Producciones con Puntaje < -5", "neg") +
    modal;

  ["modalHoraIni","modalHoraFin","modalTM","modalUni"].forEach(id => {
    const el = document.getElementById(id);
    if (el) {
      el.addEventListener("input", actualizarPreview);
      el.addEventListener("change", actualizarPreview);
    }
  });
}

/* ================= EDICION ================= */
let editingRow = null;

function abrirEditDisruptiva(id) {
  const r = allRows.find(x => x.id === id);
  if (!r) return;
  editingRow = r;

  const mat = String(r.Matriz || "").trim();
  const nombre = empMap.get(String(r.Legajo || "").trim()) || r.Nombre_Empleado || "";

  document.getElementById("modalInfo").innerHTML = `
    <strong>${esc(nombre)}</strong> &mdash;
    Mat ${esc(mat)} (${esc(r.Nombre_Matriz || "")}) &mdash;
    ${r.Fecha ? fechaCorta(r.Fecha) : ""}`;

  document.getElementById("modalHoraIni").value = r.Hora_Inicio || "";
  document.getElementById("modalHoraFin").value = r.Hora_Fin || "";
  document.getElementById("modalTM").value = +(n(r.Segundos_Tiempo_Muerto) / 3600).toFixed(2);
  document.getElementById("modalUni").value = n(r.Uni);
  document.getElementById("modalAnular").checked = !!r.Anular_Tiempo;

  // PENDIENTE GP2: el detalle de TMs del mismo empleado/fecha requeria todas las
  // filas no-matriz; el bundle solo trae disruptivas, asi que aca no hay TM detalle.
  const detalleEl = document.getElementById("modalTMDetalle");
  detalleEl.innerHTML = '<span style="color:#bbb;">Detalle de TM no disponible en GP2 (pendiente)</span>';

  actualizarPreview();
  document.getElementById("modalEdit").classList.remove("hidden");
}

function cerrarModal() {
  document.getElementById("modalEdit").classList.add("hidden");
  editingRow = null;
}

function timeToSec(t) {
  if (!t) return 0;
  const p = t.split(":").map(Number);
  return (p[0] || 0) * 3600 + (p[1] || 0) * 60 + (p[2] || 0);
}

function calcFromModal() {
  const horaIni = document.getElementById("modalHoraIni").value;
  const horaFin = document.getElementById("modalHoraFin").value;
  const tmHs = GP2N.num(document.getElementById("modalTM").value);   // campos: la regla de numero de la casa
  const tm = Math.round(tmHs * 3600);
  const uni = GP2N.num(document.getElementById("modalUni").value);
  // GP2: el tiempo historico promedio viene por fila (Tiempo_Historico)
  const tProm = n(editingRow.Tiempo_Historico);

  let segBruto = timeToSec(horaFin) - timeToSec(horaIni);
  if (segBruto < 0) segBruto += 86400;
  const segTrab = segBruto - tm;
  const segHist = uni * tProm;
  const premio = segHist > 0 ? (-(segTrab / segHist - 1)) * 10 : 0;

  return { horaIni, horaFin, tm, uni, segTrab, segHist, premio };
}

function actualizarPreview() {
  if (!editingRow) return;
  const c = calcFromModal();

  const origSegTrab = n(editingRow.Segundos_Trabajados);
  const origSegHist = n(editingRow.Segundos_Historico);
  const origPremio = n(editingRow.Premio);
  document.getElementById("modalPreview").innerHTML = `
    <div style="display:flex;gap:16px;margin-top:10px;flex-wrap:wrap;">
      <div><span class="lbl">Seg Trab:</span> <strong>${f(c.segTrab)}</strong></div>
      <div><span class="lbl">Seg Hist:</span> <strong>${f(c.segHist)}</strong></div>
      <div><span class="lbl">Puntaje:</span> <strong class="${cls(c.premio)}">${f(c.premio, 1)}</strong></div>
    </div>
    <div style="display:flex;gap:16px;margin-top:4px;flex-wrap:wrap;color:#94a3b8;font-size:12px;">
      <div><span class="lbl">Anterior:</span> Seg Trab: ${f(origSegTrab)} | Seg Hist: ${f(origSegHist)} | Puntaje: ${f(origPremio, 1)}</div>
    </div>`;
}

async function guardarEditDisruptiva() {
  if (!editingRow) return;
  const id = editingRow.id;
  const c = calcFromModal();
  const anular = document.getElementById("modalAnular").checked;

  try {
    const { error } = await sb.rpc("anular_produccion", {
      row_id: id,
      p_hora_inicio: c.horaIni || null,
      p_hora_fin: c.horaFin || null,
      p_seg_tiempo_muerto: c.tm,
      p_uni: c.uni,
      p_seg_trabajados: c.segTrab,
      p_seg_historico: c.segHist,
      p_premio: c.premio,
      p_anular: anular
    });
    if (error) throw new Error(error.message);

    if (anular) {
      const idx = allRowsRaw.findIndex(x => x.id === id);
      if (idx !== -1) allRowsRaw.splice(idx, 1);
    } else {
      const row = allRowsRaw.find(x => x.id === id);
      if (row) {
        row.Hora_Inicio = c.horaIni; row.Hora_Fin = c.horaFin;
        row.Segundos_Tiempo_Muerto = c.tm; row.Uni = c.uni;
        row.Segundos_Trabajados = c.segTrab; row.Segundos_Historico = c.segHist;
        row.Premio = c.premio; row.Anular_Tiempo = anular;
      }
    }

    cerrarModal();
    filtrarPorFecha();
  } catch (err) { alert("Error al guardar: " + err.message); }
}

/* ================= ACCIONES ================= */
async function revisarDisruptiva(id, btnEl) {
  try {
    const { error } = await sb.rpc("marcar_revisado", { row_id: id });
    if (error) throw new Error(error.message);
    const idx = allRowsRaw.findIndex(r => r.id === id);
    if (idx !== -1) allRowsRaw.splice(idx, 1);
    const tr = btnEl.closest("tr");
    if (tr) { tr.style.transition = "opacity .3s"; tr.style.opacity = "0"; setTimeout(() => { filtrarPorFecha(); }, 300); }
  } catch (err) { alert("Error al marcar revisado: " + err.message); }
}

/* ================= EXCEL ================= */
async function exportarExcelDisruptivas() {
  if (!lastPositivas.length && !lastNegativas.length) return;

  const wb = new ExcelJS.Workbook();
  const border = { top: { style: "medium" }, left: { style: "medium" }, bottom: { style: "medium" }, right: { style: "medium" } };
  const headFill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF111111" } };
  const headFont = { bold: true, size: 12, color: { argb: "FFFFFFFF" } };
  const greenFill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFD4EDDA" } };
  const redFill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFFDE8E8" } };

  const headers = ["Fecha", "Legajo", "Empleado", "Mat", "Descripcion", "Uni", "T. Prom", "Prom Hist", "Seg Trab", "Seg Hist", "Puntaje"];

  function addSheet(name, items, fill) {
    if (!items.length) return;
    const ws = wb.addWorksheet(name);

    const tr = ws.addRow([name + " (" + items.length + ")"]);
    ws.mergeCells(1, 1, 1, headers.length);
    tr.getCell(1).font = { bold: true, size: 16 };
    tr.getCell(1).alignment = { horizontal: "center", vertical: "middle" };
    tr.getCell(1).border = border;
    tr.height = 30;

    const hr = ws.addRow(headers);
    hr.eachCell(function(c) {
      c.fill = headFill;
      c.font = headFont;
      c.alignment = { horizontal: "center", vertical: "middle" };
      c.border = border;
    });

    items.forEach(function(i) {
      const tProm = i.uni > 0 ? +(i.segTrab / i.uni).toFixed(2) : 0;
      const r = ws.addRow([i.fecha, i.legajo, i.nombre, i.matriz, i.descMat, i.uni, tProm, +i.promHist.toFixed(2), i.segTrab, i.segHist, +i.premio.toFixed(1)]);
      r.eachCell(function(c, col) {
        c.font = { size: 11 };
        c.border = border;
        c.alignment = { vertical: "middle", horizontal: col <= 5 ? "center" : "right" };
      });
      const pCell = r.getCell(11);
      pCell.alignment = { horizontal: "center", vertical: "middle" };
      pCell.font = { size: 11, bold: true };
      if (fill) pCell.fill = fill;
    });

    ws.getColumn(1).width = 12;
    ws.getColumn(2).width = 8;
    ws.getColumn(3).width = 22;
    ws.getColumn(4).width = 7;
    ws.getColumn(5).width = 30;
    [6,7,8,9,10,11].forEach(function(c) { ws.getColumn(c).width = 11; });
    ws.getColumn(11).width = 10;
    ws.views = [{ state: "frozen", ySplit: 2 }];
  }

  addSheet("Puntaje mayor a 5", lastPositivas, greenFill);
  addSheet("Puntaje menor a -5", lastNegativas, redFill);

  const buf = await wb.xlsx.writeBuffer();
  const blob = new Blob([buf], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = "Disruptivas " + fechaDesde.value + " a " + fechaHasta.value + ".xlsx";
  a.click();
  URL.revokeObjectURL(url);
}

/* ================= INIT ================= */
init();

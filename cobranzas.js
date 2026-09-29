/* ============================================================================
   SUBMÓDULO COBRANZAS — front (v23.96, pedido de Luis 29/09)
   ----------------------------------------------------------------------------
   Pantalla propia con pestañas internas. La primera es BUSCAR CLIENTE: se tipea
   nombre o código (LK o CH) y se abre la FICHA del cliente con la deuda
   CONSOLIDADA (los códigos de LK y de Chef del mismo cliente suman juntos).

   ⚠ POR QUÉ VIVE EN SU PROPIO ARCHIVO Y NO EN index.html
   El index ya va por 63.000 líneas y 5 MB, tiene un byte NUL adentro (separador
   de _pppGeoCod) y lo editan varias sesiones a la vez. Este módulo va a crecer
   (Luis: "empezando con la de búsqueda de clientes"), así que arranca afuera.
   Se carga con ?v= atado a APP_VERSION — está en SIGUEN_APP_VERSION de
   scripts/bump-version.cjs y tests/version-tokens.cjs.

   ⚠ CONVIVENCIA CON LA PANTALLA VIEJA (openCobros, 7 pestañas)
   NO la reemplaza todavía. Son dos puertas distintas a propósito mientras esto
   se arma; cuando Luis lo dé por bueno, la pestaña "📒 Cuenta corriente" de
   openCobros se retira y queda ésta. Dos módulos que hacen lo mismo para
   siempre es el pozo de Matricería (1.0.67 → 1.0.71): esto es un paso, no un
   estado final.

   ⚠ DATOS
   Lee lo que YA existe en la base (nada nuevo se creó para esto):
     · gv_cobranza_clientes()            → lista con deuda, vencida, a reclamar
     · gv_cobranza_cliente(emp, cod)     → comprobante por comprobante + el pago
     · gv_cobranza_cuenta(emp, cod)      → cuenta corriente (debe/haber/saldo)
     · gv_cobranza_clientes_cuit()       → (empresa, código) → CUIT, para consolidar
     · cobranzas_escalones               → la escala 25/20/15/10/5 de la planilla
   Si la base no contesta (sesión sin supervisor, o mirando el front suelto),
   cae a datos DEMO y lo dice con un chip rojo arriba: un cero no puede
   confundirse con "no pude leer" (regla "una lectura ROTA no es un CERO").
   ============================================================================ */

var _cbz = {
  tab: "clientes",
  q: "",
  empresa: "",          // "" | "lk" | "chef"
  rows: [],             // clientes crudos (una fila por empresa+código)
  grupos: [],           // clientes consolidados (LK + CH del mismo cliente)
  cargando: false,
  demo: false,
  error: null,
  sel: null,            // clave del grupo abierto
  sub: "comp",          // "comp" | "cta" | "escala"
  comp: null,           // comprobantes de la ficha
  cta: null,            // cuenta corriente de la ficha
  abierta: null,        // fila de comprobante desplegada
  escalones: null
};

/* ------------------------------ utilidades ------------------------------- */
function _cbzEsc(s) {
  return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
    return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
  });
}
function _cbzNum(v) { var n = Number(v); return isFinite(n) ? n : 0; }
/* coma decimal, punto de miles (regla del dueño) */
function _cbzPlata(v, dec) {
  var n = Number(v);
  if (!isFinite(n)) return "—";
  return n.toLocaleString("es-AR", { minimumFractionDigits: dec == null ? 0 : dec, maximumFractionDigits: dec == null ? 0 : dec });
}
function _cbzFecha(d) {
  if (!d) return "—";
  var s = String(d).slice(0, 10).split("-");
  return s.length === 3 ? s[2] + "/" + s[1] + "/" + s[0].slice(2) : String(d);
}
function _cbzEmpLabel(e) { return e === "chef" ? "CH" : "LK"; }
/* el nombre se normaliza para poder juntar el mismo cliente de las dos empresas:
   sin acentos, sin puntuación, sin las formas societarias, en mayúscula */
function _cbzNorm(s) {
  return String(s || "")
    .toUpperCase()
    .normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/\b(S\s*R\s*L|SRL|S\s*A\s*S|SAS|S\s*A|SA|CIF|SOCIEDAD ANONIMA|Y CIA|E HIJOS)\b/g, " ")
    .replace(/[^A-Z0-9 ]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}
async function _cbzRpc(fn, args) {
  try {
    if (typeof sb === "undefined" || !sb || !sb.rpc) return { error: "sin cliente Supabase" };
    var r = await sb.rpc(fn, args || {});
    if (r && r.error) return { error: r.error.message || String(r.error) };
    return { data: (r && r.data) || [] };
  } catch (e) { return { error: (e && e.message) || String(e) }; }
}

/* --------------------------------- CSS ----------------------------------- */
function _cbzCss() {
  if (document.getElementById("cbzCss")) return;
  var st = document.createElement("style");
  st.id = "cbzCss";
  st.textContent = [
    "#cbzOv{position:fixed;inset:0;z-index:9600;background:#f1f5f9;display:none;flex-direction:column;font-family:system-ui,Segoe UI,Arial,sans-serif;color:#0f172a;}",
    "#cbzOv *{box-sizing:border-box;}",
    /* ⚠ el index tiene un button{width:100%;padding:16px;font-size:22px;margin-top:14px} global
       (linea ~26): sin esto el boton Cerrar sale de una pantalla de ancho y las pestanas se
       parten en dos renglones. Se neutraliza por contenedor, como el pop-up de Importados (v23.93). */
    "#cbzOv button{width:auto;margin-top:0;padding:6px 13px;font-size:13px;line-height:1.25;}",
    "#cbzOv input{width:auto;margin-top:0;}",
    ".cbz-top{display:flex;align-items:center;gap:14px;padding:10px 16px;background:linear-gradient(90deg,#0f766e,#083344);color:#fff;flex:0 0 auto;flex-wrap:wrap;}",
    ".cbz-top b{font-size:17px;letter-spacing:.2px;}",
    ".cbz-tabs{display:flex;gap:4px;}",
    ".cbz-tab{padding:6px 13px;border-radius:999px;border:none;font-weight:700;font-size:13px;cursor:pointer;background:rgba(255,255,255,.14);color:#e2e8f0;}",
    ".cbz-tab:hover{background:rgba(255,255,255,.26);}",
    ".cbz-tab.on{background:#fff;color:#0f766e;}",
    ".cbz-x{margin-left:auto;background:#dc2626;color:#fff;border:none;border-radius:8px;padding:7px 16px;font-weight:800;cursor:pointer;}",
    ".cbz-body{flex:1;min-height:0;overflow:auto;padding:16px;}",
    ".cbz-wrap{max-width:1180px;margin:0 auto;}",
    /* buscador */
    ".cbz-buscar{display:flex;gap:8px;align-items:center;flex-wrap:wrap;background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:10px 12px;box-shadow:0 1px 2px rgba(15,23,42,.06);}",
    ".cbz-inp{flex:1;min-width:220px;border:1px solid #cbd5e1;border-radius:9px;padding:9px 12px;font-size:15px;outline:none;}",
    ".cbz-inp:focus{border-color:#0f766e;box-shadow:0 0 0 3px rgba(15,118,110,.14);}",
    ".cbz-seg{display:flex;border:1px solid #cbd5e1;border-radius:9px;overflow:hidden;}",
    ".cbz-seg button{border:none;background:#fff;color:#475569;font-weight:700;font-size:13px;padding:8px 13px;cursor:pointer;}",
    ".cbz-seg button.on{background:#0f766e;color:#fff;}",
    ".cbz-hint{color:#64748b;font-size:12px;margin:8px 2px 0;}",
    /* lista de resultados */
    ".cbz-lista{margin-top:12px;background:#fff;border:1px solid #e2e8f0;border-radius:12px;overflow:hidden;}",
    ".cbz-row{display:grid;grid-template-columns:1fr auto auto auto;gap:14px;align-items:center;padding:10px 14px;border-bottom:1px solid #f1f5f9;cursor:pointer;}",
    ".cbz-row:last-child{border-bottom:none;}",
    ".cbz-row:hover{background:#f0fdfa;}",
    ".cbz-row .nom{font-weight:700;font-size:14px;}",
    ".cbz-row .sub{color:#64748b;font-size:11.5px;margin-top:1px;}",
    ".cbz-hrow{display:grid;grid-template-columns:1fr auto auto auto;gap:14px;padding:6px 14px;background:#f8fafc;border-bottom:1px solid #e2e8f0;color:#94a3b8;font-size:10px;font-weight:800;text-transform:uppercase;letter-spacing:.5px;text-align:right;}",
    ".cbz-hrow>div{min-width:92px;}",".cbz-hrow>div:first-child{min-width:0;}",
    ".cbz-cel{text-align:right;font-variant-numeric:tabular-nums;font-size:13px;min-width:92px;}",
    ".cbz-cel .k{display:block;font-size:10px;color:#94a3b8;font-weight:700;text-transform:uppercase;letter-spacing:.4px;}",
    ".cbz-vacio{padding:28px;text-align:center;color:#64748b;}",
    /* chips */
    ".cbz-chip{display:inline-block;font-size:10.5px;font-weight:800;border-radius:5px;padding:2px 6px;vertical-align:middle;}",
    ".cbz-lk{background:#e0f2fe;color:#075985;}",
    ".cbz-ch{background:#fef3c7;color:#92400e;}",
    ".cbz-warn{background:#fee2e2;color:#991b1b;}",
    ".cbz-ok{background:#dcfce7;color:#166534;}",
    ".cbz-info{background:#e0e7ff;color:#3730a3;}",
    /* ficha */
    ".cbz-ficha-top{background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:14px 16px;box-shadow:0 1px 2px rgba(15,23,42,.06);}",
    ".cbz-back{background:#f1f5f9;border:1px solid #cbd5e1;border-radius:8px;padding:6px 11px;font-weight:700;font-size:13px;cursor:pointer;color:#334155;}",
    ".cbz-titulo{font-size:21px;font-weight:800;line-height:1.15;}",
    ".cbz-kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(124px,1fr));gap:1px;background:#e2e8f0;border:1px solid #e2e8f0;border-radius:10px;overflow:hidden;margin-top:12px;}",
    ".cbz-kpi{background:#fff;padding:9px 11px;text-align:center;}",
    ".cbz-kpi .k{font-size:10px;color:#64748b;font-weight:800;text-transform:uppercase;letter-spacing:.5px;}",
    ".cbz-kpi .v{font-size:18px;font-weight:800;font-variant-numeric:tabular-nums;margin-top:2px;line-height:1.1;}",
    ".cbz-kpi .s{font-size:10.5px;color:#94a3b8;margin-top:1px;}",
    ".cbz-rojo{color:#b91c1c;}.cbz-ambar{color:#b45309;}.cbz-verde{color:#047857;}",
    ".cbz-desglose{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px;}",
    ".cbz-dcard{flex:0 1 auto;border:1px solid #e2e8f0;border-radius:9px;padding:7px 12px;background:#f8fafc;font-size:12.5px;}",
    ".cbz-dcard b{font-variant-numeric:tabular-nums;}",
    /* sub-pestañas de la ficha */
    ".cbz-sub{display:flex;gap:4px;margin:14px 0 0;}",
    ".cbz-sub button{border:1px solid #cbd5e1;background:#fff;color:#475569;border-radius:8px;padding:7px 14px;font-weight:700;font-size:13px;cursor:pointer;}",
    ".cbz-sub button.on{background:#0f766e;border-color:#0f766e;color:#fff;}",
    ".cbz-panel{background:#fff;border:1px solid #e2e8f0;border-radius:12px;margin-top:10px;overflow:hidden;box-shadow:0 1px 2px rgba(15,23,42,.06);}",
    /* tablas: ancho segun el dato, sin relleno */
    ".cbz-t{border-collapse:collapse;font-size:13px;width:100%;}",
    ".cbz-t th{background:#f8fafc;color:#475569;font-size:10.5px;text-transform:uppercase;letter-spacing:.4px;padding:7px 9px;border-bottom:1px solid #e2e8f0;white-space:nowrap;text-align:center;}",
    ".cbz-t td{padding:6px 9px;border-bottom:1px solid #f1f5f9;white-space:nowrap;text-align:center;font-variant-numeric:tabular-nums;}",
    ".cbz-t td.l{text-align:left;}",
    ".cbz-t tbody tr:hover{background:#f0fdfa;}",
    ".cbz-t tr.cbz-clic{cursor:pointer;}",
    ".cbz-t tr.cbz-sel{background:#ecfeff;}",
    ".cbz-exp{background:#f8fafc;text-align:left !important;white-space:normal !important;color:#334155;font-size:12.5px;padding:10px 14px !important;}",
    /* escala de descuentos */
    ".cbz-escala{display:grid;grid-template-columns:repeat(auto-fit,minmax(132px,1fr));gap:1px;background:#e2e8f0;border:1px solid #e2e8f0;border-radius:9px;overflow:hidden;}",
    ".cbz-esc{background:#fff;padding:8px 10px;text-align:center;}",
    ".cbz-esc.on{background:#ecfdf5;box-shadow:inset 0 0 0 2px #059669;}",
    ".cbz-esc .k{font-size:11px;color:#475569;font-weight:700;}",
    ".cbz-esc .p{font-size:15px;font-weight:800;color:#0f766e;}",
    ".cbz-esc .v{font-size:12.5px;color:#64748b;font-variant-numeric:tabular-nums;}",
    ".cbz-nota{color:#64748b;font-size:12px;padding:10px 14px;border-top:1px solid #f1f5f9;}",
    ".cbz-pend{padding:34px 16px;text-align:center;color:#64748b;}",
    ".cbz-pend h3{margin:0 0 6px;color:#334155;font-size:16px;}"
  ].join("\n");
  document.head.appendChild(st);
}

/* ------------------------------- pantalla -------------------------------- */
var _CBZ_TABS = [
  { id: "clientes",  t: "👤 Clientes" },
  { id: "reclamos",  t: "⚠ A reclamar" },
  { id: "recibos",   t: "🧾 Recibos" },
  { id: "escalones", t: "📐 Escala" }
];

async function openCobranzas(tab) {
  try { if (typeof requireSupervisor === "function" && !requireSupervisor()) return; } catch (_e) {}
  _cbzCss();
  var ov = document.getElementById("cbzOv");
  if (!ov) { ov = document.createElement("div"); ov.id = "cbzOv"; document.body.appendChild(ov); }
  ov.style.display = "flex";
  ov.innerHTML =
    '<div class="cbz-top">' +
      '<b>💳 Cobranzas</b>' +
      '<div class="cbz-tabs" id="cbzTabs"></div>' +
      '<button class="cbz-x" onclick="cbzClose()">Cerrar</button>' +
    '</div>' +
    '<div class="cbz-body"><div class="cbz-wrap" id="cbzWrap"></div></div>';
  _cbz.tab = _CBZ_TABS.some(function (x) { return x.id === tab; }) ? tab : "clientes";
  _cbz.sel = null; _cbz.abierta = null;
  cbzRender();
  if (!_cbz.rows.length) cbzCargarClientes();
}
function cbzClose() { var ov = document.getElementById("cbzOv"); if (ov) ov.style.display = "none"; }
function cbzSetTab(t) { _cbz.tab = t; _cbz.sel = null; cbzRender(); if (t === "escalones") cbzCargarEscalones(); }

function cbzRender() {
  var tabs = document.getElementById("cbzTabs");
  if (tabs) {
    tabs.innerHTML = _CBZ_TABS.map(function (x) {
      return '<button class="cbz-tab' + (_cbz.tab === x.id ? " on" : "") + '" onclick="cbzSetTab(\'' + x.id + '\')">' + x.t + '</button>';
    }).join("");
  }
  var w = document.getElementById("cbzWrap"); if (!w) return;
  if (_cbz.tab === "clientes")  { w.innerHTML = _cbz.sel ? cbzFichaHtml() : cbzBuscadorHtml(); if (_cbz.sel) cbzFichaCargar(); return; }
  if (_cbz.tab === "escalones") { w.innerHTML = cbzEscalonesHtml(); return; }
  w.innerHTML = cbzPendienteHtml(_cbz.tab);
}

function cbzPendienteHtml(t) {
  var txt = t === "reclamos"
    ? "Los descuentos mal tomados que hay que reclamar, uno por cliente, con el recibo y el importe. Hoy eso vive en la pestaña 🕵 Agente de la pantalla vieja."
    : "Los recibos cargados, con qué facturas cancela cada uno y qué quedó suelto.";
  return '<div class="cbz-panel"><div class="cbz-pend"><h3>Pendiente de armar</h3><div>' + _cbzEsc(txt) +
    '</div><div style="margin-top:10px;font-size:12px;color:#94a3b8;">Se arma cuando definamos qué va en cada pestaña.</div></div></div>';
}

/* ----------------------------- 1) buscador ------------------------------- */
function cbzBuscadorHtml() {
  var h = '<div class="cbz-buscar">' +
      '<input id="cbzQ" class="cbz-inp" placeholder="Buscar por nombre, código (LK o CH) o CUIT…" value="' + _cbzEsc(_cbz.q) + '" ' +
        'oninput="cbzBuscar(this.value)" autocomplete="off">' +
      '<div class="cbz-seg">' +
        '<button class="' + (_cbz.empresa === "" ? "on" : "") + '" onclick="cbzEmpresa(\'\')">Las dos</button>' +
        '<button class="' + (_cbz.empresa === "lk" ? "on" : "") + '" onclick="cbzEmpresa(\'lk\')">LK</button>' +
        '<button class="' + (_cbz.empresa === "chef" ? "on" : "") + '" onclick="cbzEmpresa(\'chef\')">Chef</button>' +
      '</div>' +
      '<button class="cbz-back" onclick="cbzCargarClientes()">↻ Actualizar</button>' +
    '</div>';
  h += '<div class="cbz-hint">' +
    (_cbz.demo ? '<span class="cbz-chip cbz-warn">DEMO — no pude leer la base, estos números son de ejemplo</span> ' : "") +
    (_cbz.error ? '<span class="cbz-chip cbz-warn">' + _cbzEsc(_cbz.error) + '</span> ' : "") +
    'Un cliente con código en LK y en Chef aparece <b>una sola vez</b>, con la deuda consolidada. La identidad la da el <b>CUIT</b>, no el código ni el nombre.</div>';
  h += '<div class="cbz-lista" id="cbzLista">' + cbzListaHtml() + '</div>';
  return h;
}
function cbzEmpresa(e) { _cbz.empresa = e; cbzRender(); setTimeout(function () { var i = document.getElementById("cbzQ"); if (i) i.focus(); }, 0); }
function cbzBuscar(v) {
  _cbz.q = v || "";
  var l = document.getElementById("cbzLista");
  if (l) l.innerHTML = cbzListaHtml();
}
function cbzFiltrados() {
  var q = _cbzNorm(_cbz.q), qraw = String(_cbz.q || "").trim().toLowerCase();
  return _cbz.grupos.filter(function (g) {
    if (_cbz.empresa && !g.cods.some(function (c) { return c.empresa === _cbz.empresa; })) return false;
    if (!qraw) return true;
    if (_cbzNorm(g.nombre).indexOf(q) >= 0) return true;
    var soloNum = qraw.replace(/\D/g, "");
    if (soloNum.length >= 8 && g.cuit && g.cuit.indexOf(soloNum) >= 0) return true;   // por CUIT
    return g.cods.some(function (c) {
      return String(c.cod_cliente).toLowerCase() === qraw ||
             (_cbzEmpLabel(c.empresa) + " " + c.cod_cliente).toLowerCase().indexOf(qraw) >= 0 ||
             _cbzNorm(c.cliente).indexOf(q) >= 0;   // el nombre largo de ISIS también busca
    });
  }).sort(function (a, b) { return b.deuda - a.deuda; });   // por dinero, mayor → menor
}
function cbzListaHtml() {
  if (_cbz.cargando) return '<div class="cbz-vacio">Cargando clientes…</div>';
  var rows = cbzFiltrados();
  if (!rows.length) return '<div class="cbz-vacio">' + (_cbz.q ? 'Ningún cliente con “' + _cbzEsc(_cbz.q) + '”.' : "Sin clientes.") + "</div>";
  var top = rows.slice(0, 80);
  /* el rotulo va UNA vez arriba, no repetido en cada renglon (regla: no repetir) */
  var h = '<div class="cbz-hrow"><div></div><div>Deuda</div><div>Vencida</div><div>A reclamar</div></div>';
  h += top.map(function (g) {
    return '<div class="cbz-row" onclick="cbzAbrir(\'' + _cbzEsc(g.key) + '\')">' +
      '<div><div class="nom">' + _cbzEsc(g.nombre) +
        (g.cods.length > 1 ? ' <span class="cbz-chip cbz-info">LK+CH</span>' : "") +
        (g.agente ? ' <span class="cbz-chip cbz-info" title="Agente de recaudación IIBB">agente</span>' : "") +
        '</div><div class="sub">' + g.cods.map(function (c) {
          return '<span class="cbz-chip ' + (c.empresa === "chef" ? "cbz-ch" : "cbz-lk") + '">' + _cbzEmpLabel(c.empresa) + " " + _cbzEsc(c.cod_cliente) + "</span>";
        }).join(" ") + "</div></div>" +
      '<div class="cbz-cel">' + (g.deuda ? "$ " + _cbzPlata(g.deuda) : "—") + "</div>" +
      '<div class="cbz-cel cbz-rojo">' + (g.vencida ? "$ " + _cbzPlata(g.vencida) : "—") + "</div>" +
      '<div class="cbz-cel cbz-ambar">' + (g.reclamar ? "$ " + _cbzPlata(g.reclamar) : "—") + "</div>" +
    "</div>";
  }).join("");
  if (rows.length > top.length) h += '<div class="cbz-vacio">… y ' + (rows.length - top.length) + " más. Afiná la búsqueda.</div>";
  return h;
}

/* ------------------------- carga + consolidación -------------------------- */
async function cbzCargarClientes() {
  _cbz.cargando = true; _cbz.error = null; cbzRender();
  var rr = await Promise.all([_cbzRpc("gv_cobranza_clientes"), _cbzRpc("gv_cobranza_clientes_cuit")]);
  var r = rr[0], rc = rr[1];
  if (r.error || !r.data || !r.data.length) {
    _cbz.demo = true;
    _cbz.error = r.error ? "No pude leer la base (" + r.error + ") — mostrando datos de ejemplo" : null;
    _cbz.rows = _CBZ_DEMO_CLIENTES.slice();
  } else { _cbz.demo = false; _cbz.rows = r.data; }
  var cuits = {};
  if (!rc.error) (rc.data || []).forEach(function (x) { if (x.cuit) cuits[x.empresa + "|" + x.cod_cliente] = String(x.cuit); });
  if (_cbz.demo) _cbz.rows.forEach(function (x) { if (x.cuit) cuits[x.empresa + "|" + x.cod_cliente] = String(x.cuit); });
  _cbz.cuits = cuits;
  _cbz.grupos = cbzConsolidar(_cbz.rows, cuits);
  _cbz.cargando = false;
  cbzRender();
}
/* Junta los códigos del MISMO cliente de las dos empresas.
   ⚠ LA CLAVE ES EL CUIT, nunca el código ("el cod cliente no significa nada,
   sólo el CUIT vale", v13.76) y tampoco la razón social: ISIS le pega el sufijo
   de la sucursal, así que "Bazar Monica S. CAP I SECC IV" (LK) y "Bazar Monica
   SRL" (CH) son el mismo cliente escrito de dos formas — agrupar por nombre lo
   parte en dos, y dos nombres parecidos de clientes distintos los fusiona.
   Sin CUIT el código va SOLO: no se adivina. Medido el 29/09: 69 CUIT tienen
   código en las dos empresas. */
function cbzConsolidar(rows, cuits) {
  var map = {};
  (rows || []).forEach(function (r) {
    var ck = (cuits || {})[r.empresa + "|" + r.cod_cliente] || (r.cuit ? String(r.cuit) : "");
    var k = ck ? "cuit:" + ck : (r.empresa + "|" + r.cod_cliente);
    var g = map[k];
    if (!g) g = map[k] = { key: k, cuit: ck, nombre: r.cliente || "(sin nombre)", cods: [], deuda: 0, vencida: 0, reclamar: 0, abiertos: 0, dias: 0, agente: false, ultimo: null, ultimoMonto: 0, ancla: null };
    g.cods.push(r);
    g.deuda    += Math.max(0, _cbzNum(r.deuda));
    g.vencida  += _cbzNum(r.vencida);
    g.reclamar += _cbzNum(r.a_reclamar);
    g.abiertos += _cbzNum(r.comprobantes_abiertos);
    g.dias      = Math.max(g.dias, _cbzNum(r.dias_mas_vieja));
    if (r.agente_retencion) g.agente = true;
    if (r.ultimo_pago && (!g.ultimo || r.ultimo_pago > g.ultimo)) { g.ultimo = r.ultimo_pago; g.ultimoMonto = _cbzNum(r.ultimo_pago_monto); }
    if (r.ancla && (!g.ancla || r.ancla > g.ancla)) g.ancla = r.ancla;
    /* de los dos nombres del mismo CUIT se muestra el MÁS CORTO: el largo suele ser
       el de ISIS con el sufijo de la sucursal pegado ("… CAP I SECC IV"). Los dos
       quedan buscables igual (cbzFiltrados mira todos los códigos del grupo). */
    if (r.cliente && r.cliente.length < (g.nombre || "").length) g.nombre = r.cliente;
  });
  return Object.keys(map).map(function (k) { return map[k]; });
}

/* ------------------------------ 2) la ficha ------------------------------
   La ficha se arma con UNA llamada por código: `gv_cobranza_ficha(emp, cod)`,
   que junta las tres fuentes que ya existían y no se hablaban entre sí:

     · DEUDA    → GV_Cobranza_Deuda_Viva = el Excel de deuda que se sube para la
                  Cuarentena (el ancla) + las facturas y NC nuevas de ISIS + lo
                  que la conciliación bancaria ya vio cobrado.
     · PAGOS    → GV_Cobranza_Imputacion = cada recibo del banco cruzado contra
                  las facturas que cancela, con el descuento tomado vs el ganado.
     · ENTREGAS → Facturacion_NP = lo que Gestión facturó (NP, tanda, m³, salida).

   Un grupo con código en LK y en Chef pide las dos y se suman: los totales de la
   cabecera salen de acá, no de la lista. */
function cbzAbrir(key) { _cbz.sel = key; _cbz.sub = "deuda"; _cbz.ficha = null; _cbz.comp = null; _cbz.cta = null; _cbz.abierta = null; cbzRender(); }
function cbzVolver() { _cbz.sel = null; _cbz.ficha = null; _cbz.comp = null; _cbz.cta = null; cbzRender(); }
function cbzSub(s) { _cbz.sub = s; cbzRender(); }
function cbzGrupo() { var k = _cbz.sel; return _cbz.grupos.filter(function (g) { return g.key === k; })[0] || null; }

var _CBZ_SUBS = [
  { id: "deuda",    t: "💳 Deuda" },
  { id: "pagos",    t: "🧾 Pagos y descuentos" },
  { id: "comp",     t: "📄 Explicación" },
  { id: "entregas", t: "🚚 Entregas facturadas" },
  { id: "cta",      t: "📒 Cuenta corriente" }
];

function cbzFichaHtml() {
  var g = cbzGrupo();
  if (!g) return '<div class="cbz-vacio">Cliente no encontrado. <button class="cbz-back" onclick="cbzVolver()">← Volver</button></div>';
  var f = _cbz.ficha;
  var ret = g.cods.reduce(function (m, c) { return Math.max(m, _cbzNum(c.ret_cliente)); }, 0);
  /* los totales los manda la ficha (deuda viva de HOY); la lista es el respaldo
     mientras carga, o si la RPC no contesta */
  var deuda = f ? f.tot.deuda : g.deuda, vencida = f ? f.tot.vencida : g.vencida;
  var abiertos = f ? f.tot.comprobantes : g.abiertos, dias = f ? f.tot.dias : g.dias;
  var cuit = (f && f.cab.cuit) || g.cuit;
  var loc = f && (f.cab.localidad || f.cab.provincia)
    ? [f.cab.localidad, f.cab.provincia].filter(Boolean).join(", ") : "";
  var h = '<div class="cbz-ficha-top">' +
    '<div style="display:flex;align-items:flex-start;gap:12px;flex-wrap:wrap;">' +
      '<button class="cbz-back" onclick="cbzVolver()">← Clientes</button>' +
      '<div style="flex:1;min-width:220px;">' +
        '<div class="cbz-titulo">' + _cbzEsc(g.nombre) + "</div>" +
        '<div style="margin-top:5px;">' + g.cods.map(function (c) {
          return '<span class="cbz-chip ' + (c.empresa === "chef" ? "cbz-ch" : "cbz-lk") + '">' + _cbzEmpLabel(c.empresa) + " " + _cbzEsc(c.cod_cliente) + "</span>";
        }).join(" ") +
        (cuit ? ' <span class="cbz-chip" style="background:#f1f5f9;color:#475569;">CUIT ' + _cbzEsc(cuit) + "</span>" : ' <span class="cbz-chip cbz-warn" title="Sin CUIT no se puede consolidar con la otra empresa">sin CUIT</span>') +
        (loc ? ' <span class="cbz-chip" style="background:#f1f5f9;color:#475569;">' + _cbzEsc(loc) + "</span>" : "") +
        (g.agente ? ' <span class="cbz-chip cbz-info">agente de recaudación</span>' : "") +
        (ret ? ' <span class="cbz-chip cbz-info">retención ' + _cbzPlata(ret * 100, 1) + " %</span>" : "") +
        (_cbz.demo ? ' <span class="cbz-chip cbz-warn">DEMO</span>' : "") +
        "</div>" +
      "</div>" +
    "</div>" +
    '<div class="cbz-kpis">' +
      cbzKpi("Deuda total", "$ " + _cbzPlata(deuda), g.cods.length > 1 ? "consolidada LK + CH" : (f ? "deuda viva" : ""), "") +
      cbzKpi("Vencida", vencida ? "$ " + _cbzPlata(vencida) : "—", "", vencida ? "cbz-rojo" : "") +
      cbzKpi("Comprob.", _cbzPlata(abiertos), "abiertos", "") +
      cbzKpi("Más vieja", dias ? _cbzPlata(dias) : "—", "días", dias > 60 ? "cbz-rojo" : "") +
      cbzKpi("Último pago", g.ultimo ? "$ " + _cbzPlata(g.ultimoMonto) : "—", g.ultimo ? _cbzFecha(g.ultimo) : "", "cbz-verde") +
      cbzKpi("A reclamar", g.reclamar ? "$ " + _cbzPlata(g.reclamar) : "—", "descuento mal tomado", g.reclamar ? "cbz-ambar" : "") +
    "</div>";
  if (g.cods.length > 1) {
    h += '<div class="cbz-desglose">' + g.cods.map(function (c) {
      var d = f && f.porCod[c.empresa + "|" + c.cod_cliente];
      var dd = d ? _cbzNum(d.totales && d.totales.deuda) : Math.max(0, _cbzNum(c.deuda));
      var vv = d ? _cbzNum(d.totales && d.totales.vencida) : _cbzNum(c.vencida);
      return '<div class="cbz-dcard"><span class="cbz-chip ' + (c.empresa === "chef" ? "cbz-ch" : "cbz-lk") + '">' + _cbzEmpLabel(c.empresa) + " " + _cbzEsc(c.cod_cliente) + "</span> " +
        "deuda <b>$ " + _cbzPlata(dd) + "</b>" +
        (vv ? ' · vencida <b class="cbz-rojo">$ ' + _cbzPlata(vv) + "</b>" : "") +
        (_cbzNum(c.a_reclamar) ? ' · reclamar <b class="cbz-ambar">$ ' + _cbzPlata(c.a_reclamar) + "</b>" : "") + "</div>";
    }).join("") + "</div>";
  }
  if (f && f.ancla) h += '<div class="cbz-hint" style="margin:8px 2px 0;">Deuda del Excel de Cuarentena del <b>' +
    _cbzEsc(new Date(f.ancla).toLocaleString("es-AR", { dateStyle: "short", timeStyle: "short" })) +
    "</b>, más las facturas y NC posteriores de ISIS, menos lo que la conciliación bancaria ya vio cobrado.</div>";
  h += "</div>";
  h += '<div class="cbz-sub">' + _CBZ_SUBS.map(function (s) {
    return '<button class="' + (_cbz.sub === s.id ? "on" : "") + '" onclick="cbzSub(\'' + s.id + '\')">' + s.t + "</button>";
  }).join("") + "</div>";
  h += '<div class="cbz-panel" id="cbzPanel"><div class="cbz-vacio">Cargando…</div></div>';
  return h;
}
function cbzKpi(k, v, s, cls) {
  return '<div class="cbz-kpi"><div class="k">' + _cbzEsc(k) + '</div><div class="v ' + (cls || "") + '">' + v + "</div>" +
    (s ? '<div class="s">' + _cbzEsc(s) + "</div>" : "") + "</div>";
}

/* trae la ficha (una llamada por código) y deja todo junto en _cbz.ficha */
async function cbzFichaTraer(g) {
  var rr = await Promise.all(g.cods.map(function (c) { return _cbzRpc("gv_cobranza_ficha", { p_emp: c.empresa, p_cod: c.cod_cliente }); }));
  var f = { porCod: {}, deuda: [], recibos: [], entregas: [], cab: {}, tot: { deuda: 0, vencida: 0, comprobantes: 0, dias: 0 }, ancla: null, err: null };
  rr.forEach(function (r, i) {
    var c = g.cods[i];
    if (r.error) { f.err = r.error; return; }
    var d = r.data;
    if (Array.isArray(d)) d = d[0];           // PostgREST devuelve el jsonb pelado o en array
    if (!d) return;
    f.porCod[c.empresa + "|" + c.cod_cliente] = d;
    var marcar = function (x) { x._emp = c.empresa; x._cod = c.cod_cliente; return x; };
    (d.deuda || []).forEach(function (x) { f.deuda.push(marcar(x)); });
    (d.recibos || []).forEach(function (x) { f.recibos.push(marcar(x)); });
    (d.entregas || []).forEach(function (x) { f.entregas.push(marcar(x)); });
    var t = d.totales || {};
    f.tot.deuda += _cbzNum(t.deuda); f.tot.vencida += _cbzNum(t.vencida);
    f.tot.comprobantes += _cbzNum(t.comprobantes);
    f.tot.dias = Math.max(f.tot.dias, _cbzNum(t.dias_mas_vieja));
    if (t.ancla && (!f.ancla || t.ancla > f.ancla)) f.ancla = t.ancla;
    var cab = d.cabecera || {};
    Object.keys(cab).forEach(function (k) { if (f.cab[k] == null && cab[k] != null) f.cab[k] = cab[k]; });
  });
  var pf = function (k) { return function (a, b) { return String(b[k] || "").localeCompare(String(a[k] || "")); }; };
  f.deuda.sort(pf("fecha")); f.recibos.sort(pf("fecha_pago")); f.entregas.sort(pf("facturado_at"));
  return f;
}

async function cbzFichaCargar() {
  var g = cbzGrupo(); if (!g) return;
  if (!_cbz.ficha) {
    var f = await cbzFichaTraer(g);
    if ((f.err || (!f.deuda.length && !f.recibos.length && !f.entregas.length)) && _cbz.demo) {
      f.deuda = _CBZ_DEMO_DEUDA.slice(); f.recibos = _CBZ_DEMO_PAGOS.slice(); f.entregas = _CBZ_DEMO_ENTREGAS.slice();
      f.tot = { deuda: g.deuda, vencida: g.vencida, comprobantes: g.abiertos, dias: g.dias };
    }
    _cbz.ficha = f;
    if (_cbz.sel === g.key) { var w = document.getElementById("cbzWrap"); if (w) w.innerHTML = cbzFichaHtml(); }
  }
  var pan = document.getElementById("cbzPanel"); if (!pan) return;
  if (_cbz.sub === "deuda")    { pan.innerHTML = cbzDeudaHtml(); return; }
  if (_cbz.sub === "pagos")    { pan.innerHTML = cbzPagosHtml(); return; }
  if (_cbz.sub === "entregas") { pan.innerHTML = cbzEntregasHtml(); return; }
  if (_cbz.sub === "comp") {
    if (_cbz.comp) { pan.innerHTML = cbzCompHtml(); return; }
    var rr = await Promise.all(g.cods.map(function (c) { return _cbzRpc("gv_cobranza_cliente", { p_emp: c.empresa, p_cod: c.cod_cliente }); }));
    var filas = [], err = null;
    rr.forEach(function (r, i) {
      if (r.error) { err = r.error; return; }
      (r.data || []).forEach(function (x) { x._emp = g.cods[i].empresa; x._cod = g.cods[i].cod_cliente; filas.push(x); });
    });
    if ((err || !filas.length) && _cbz.demo) filas = _CBZ_DEMO_COMP.slice();
    filas.sort(function (a, b) { return String(b.orden || b.fecha || "").localeCompare(String(a.orden || a.fecha || "")); });
    _cbz.comp = filas; _cbz.compErr = err;
    pan.innerHTML = cbzCompHtml();
    return;
  }
  if (_cbz.cta) { pan.innerHTML = cbzCtaHtml(); return; }
  var r2 = await Promise.all(g.cods.map(function (c) { return _cbzRpc("gv_cobranza_cuenta", { p_emp: c.empresa, p_cod: c.cod_cliente }); }));
  var mov = [], err2 = null;
  r2.forEach(function (r, i) {
    if (r.error) { err2 = r.error; return; }
    (r.data || []).forEach(function (x) { x._emp = g.cods[i].empresa; mov.push(x); });
  });
  if ((err2 || !mov.length) && _cbz.demo) mov = _CBZ_DEMO_CTA.slice();
  _cbz.cta = mov; _cbz.ctaErr = err2;
  pan.innerHTML = cbzCtaHtml();
}

/* ---- DEUDA (Excel de Cuarentena + ISIS − banco) -------------------------- */
function cbzDeudaHtml() {
  var f = _cbz.ficha; if (!f) return '<div class="cbz-vacio">Cargando…</div>';
  if (f.err && !f.deuda.length) return '<div class="cbz-vacio">No pude leer: ' + _cbzEsc(f.err) + "</div>";
  if (!f.deuda.length) return '<div class="cbz-vacio">Sin deuda abierta. 👌</div>';
  var multi = (cbzGrupo() || { cods: [] }).cods.length > 1;
  var h = '<table class="cbz-t"><thead><tr><th style="text-align:left;">Comprobante</th>' + (multi ? "<th>Emp</th>" : "") +
    "<th>Fecha</th><th>Vence</th><th>Días</th><th style='text-align:left;'>Condición</th>" +
    "<th>De lista</th><th>Del Excel</th><th>Cobrado banco</th><th>Pendiente</th><th>Origen</th></tr></thead><tbody>";
  h += f.deuda.map(function (r) {
    var venc = r.vencido;
    return '<tr' + (venc ? ' style="background:#fff7f7;"' : "") + '>' +
      '<td class="l"><b>' + _cbzEsc(r.comprobante || "") + "</b></td>" +
      (multi ? '<td><span class="cbz-chip ' + (r._emp === "chef" ? "cbz-ch" : "cbz-lk") + '">' + _cbzEmpLabel(r._emp) + "</span></td>" : "") +
      "<td>" + _cbzFecha(r.fecha) + "</td>" +
      '<td class="' + (venc ? "cbz-rojo" : "") + '">' + _cbzFecha(r.vence) + "</td>" +
      "<td>" + (r.dias != null ? r.dias : "—") + "</td>" +
      '<td class="l" style="color:#64748b;">' + _cbzEsc(r.condicion || "—") +
        (_cbzNum(r.dto_cond) ? " · −" + _cbzPlata(_cbzNum(r.dto_cond) * 100, 0) + " %" : "") + "</td>" +
      "<td>" + (r.lista != null ? _cbzPlata(r.lista) : "—") + "</td>" +
      "<td>" + (r.pendiente_ancla != null ? _cbzPlata(r.pendiente_ancla) : "—") + "</td>" +
      '<td class="cbz-verde">' + (_cbzNum(r.cancelado_banco) ? _cbzPlata(r.cancelado_banco) : "—") +
        (r.recibos_banco ? '<div style="font-size:10.5px;color:#94a3b8;">' + _cbzEsc(r.recibos_banco) + "</div>" : "") + "</td>" +
      '<td><b class="' + (venc ? "cbz-rojo" : "") + '">' + _cbzPlata(r.pendiente) + "</b></td>" +
      '<td><span class="cbz-chip ' + (String(r.origen || "").indexOf("isis") >= 0 ? "cbz-info" : "cbz-lk") + '">' + _cbzEsc(r.origen || "—") + "</span></td></tr>";
  }).join("");
  h += "</tbody></table>";
  h += '<div class="cbz-nota">«Del Excel» es lo que decía el archivo de deuda de la Cuarentena; «Cobrado banco» lo que la conciliación ' +
    "encontró después. La fila <b>isis nuevo</b> es una factura posterior al Excel, que el archivo todavía no tenía.</div>";
  return h;
}

/* ---- PAGOS: cada recibo del banco contra las facturas que cancela -------- */
function cbzPagosHtml() {
  var f = _cbz.ficha; if (!f) return '<div class="cbz-vacio">Cargando…</div>';
  if (f.err && !f.recibos.length) return '<div class="cbz-vacio">No pude leer: ' + _cbzEsc(f.err) + "</div>";
  if (!f.recibos.length) return '<div class="cbz-vacio">Sin pagos imputados.</div>';
  var multi = (cbzGrupo() || { cods: [] }).cods.length > 1;
  var h = '<table class="cbz-t"><thead><tr><th>Recibo</th>' + (multi ? "<th>Emp</th>" : "") +
    "<th>Fecha</th><th style='text-align:left;'>Medio</th><th>Pagado</th><th style='text-align:left;'>Facturas</th>" +
    "<th>De lista</th><th>Días</th><th>Dto tomado</th><th>Dto ganado</th><th>Ret.</th><th>A reclamar</th><th>Calidad</th></tr></thead><tbody>";
  h += f.recibos.map(function (r) {
    var mal = _cbzNum(r.a_reclamar) > 0;
    var cal = String(r.calidad || "");
    var chip = cal === "exacta" ? "cbz-ok" : (cal.indexOf("sin imputar") >= 0 ? "cbz-warn" : "cbz-info");
    return "<tr>" +
      "<td><b>" + _cbzEsc(r.recibo || "—") + "</b></td>" +
      (multi ? '<td><span class="cbz-chip ' + (r._emp === "chef" ? "cbz-ch" : "cbz-lk") + '">' + _cbzEmpLabel(r._emp) + "</span></td>" : "") +
      "<td>" + _cbzFecha(r.fecha_pago) + "</td>" +
      '<td class="l" style="color:#64748b;">' + _cbzEsc(r.medio || "—") + "</td>" +
      '<td class="cbz-verde"><b>' + (r.pagado != null ? _cbzPlata(r.pagado) : "—") + "</b></td>" +
      '<td class="l">' + _cbzEsc(r.facturas || "—") + (r.nc ? ' <span class="cbz-chip cbz-info">NC ' + _cbzEsc(r.nc) + "</span>" : "") + "</td>" +
      "<td>" + (r.lista != null ? _cbzPlata(r.lista) : "—") + "</td>" +
      "<td>" + (r.dias != null ? r.dias : "—") +
        (r.atraso != null && _cbzNum(r.atraso) > 0 ? '<div style="font-size:10.5px;" class="cbz-rojo">+' + _cbzPlata(r.atraso) + "</div>" : "") + "</td>" +
      "<td>" + (r.dto_tomado != null ? _cbzPlata(_cbzNum(r.dto_tomado) * 100, 1) + " %" : "—") + "</td>" +
      "<td>" + (r.dto_ganado != null ? _cbzPlata(_cbzNum(r.dto_ganado) * 100, 1) + " %" : "—") + "</td>" +
      "<td>" + (_cbzNum(r.retencion) ? _cbzPlata(_cbzNum(r.retencion) * 100, 2) + " %" : "—") + "</td>" +
      '<td class="cbz-ambar"><b>' + (mal ? _cbzPlata(r.a_reclamar) : "—") + "</b></td>" +
      '<td><span class="cbz-chip ' + chip + '">' + _cbzEsc(cal || "—") + "</span></td></tr>";
  }).join("");
  h += "</tbody></table>";
  h += '<div class="cbz-nota">Sale de la conciliación bancaria imputada: «Dto tomado» es lo que el cliente se descontó al pagar y ' +
    "«Dto ganado» lo que le correspondía por los días. La diferencia es lo que hay que reclamar. <b>Sin imputar</b> = el pago entró " +
    "al banco pero todavía no se pudo cruzar contra una factura.</div>";
  return h;
}

/* ---- ENTREGAS facturadas por Gestión ------------------------------------ */
function cbzEntregasHtml() {
  var f = _cbz.ficha; if (!f) return '<div class="cbz-vacio">Cargando…</div>';
  if (!f.entregas.length) return '<div class="cbz-vacio">Sin entregas facturadas registradas en Gestión.</div>';
  var multi = (cbzGrupo() || { cods: [] }).cods.length > 1;
  var m3 = f.entregas.reduce(function (s, r) { return s + _cbzNum(r.m3); }, 0);
  var h = '<table class="cbz-t"><thead><tr><th>NP</th>' + (multi ? "<th>Emp</th>" : "") +
    "<th>Tanda</th><th>Salió</th><th>m³</th><th>Facturada</th></tr></thead><tbody>";
  h += f.entregas.map(function (r) {
    return "<tr><td><b>" + _cbzEsc(r.np || "") + "</b></td>" +
      (multi ? '<td><span class="cbz-chip ' + (r._emp === "chef" ? "cbz-ch" : "cbz-lk") + '">' + _cbzEmpLabel(r._emp) + "</span></td>" : "") +
      "<td>" + _cbzEsc(r.tanda || "—") + "</td><td>" + _cbzFecha(r.fecha_salida) + "</td>" +
      "<td>" + (r.m3 != null ? _cbzPlata(r.m3, 3) : "—") + "</td>" +
      "<td>" + _cbzFecha(r.facturado_at) + "</td></tr>";
  }).join("");
  h += "</tbody></table>";
  h += '<div class="cbz-nota">Las últimas ' + f.entregas.length + " entregas facturadas por Gestión · <b>" + _cbzPlata(m3, 3) + " m³</b> en total.</div>";
  return h;
}

/* ---- comprobantes: lo que la planilla de cobranza tiene arriba ---------- */
function cbzCompHtml() {
  var f = _cbz.comp || [];
  if (!f.length) return '<div class="cbz-vacio">' + (_cbz.compErr ? "No pude leer: " + _cbzEsc(_cbz.compErr) : "Sin comprobantes.") + "</div>";
  var multi = (cbzGrupo() || { cods: [] }).cods.length > 1;
  var h = '<table class="cbz-t"><thead><tr>' +
    "<th>Fecha</th>" + (multi ? "<th>Emp</th>" : "") + '<th style="text-align:left;">Comprobante</th>' +
    "<th>Facturado</th><th>Pendiente</th><th>Recibo</th><th>Pagado</th><th>Días</th>" +
    "<th>Dto tomado</th><th>Dto ganado</th><th>A reclamar</th><th>Estado</th></tr></thead><tbody>";
  h += f.map(function (r, i) {
    var mal = _cbzNum(r.a_reclamar) > 0, ab = _cbz.abierta === i;
    var est = String(r.estado || "");
    var chip = est === "debe" ? "cbz-lk" : (est === "mal" ? "cbz-warn" : (est.indexOf("suelto") >= 0 ? "cbz-info" : "cbz-ok"));
    var fila = '<tr class="cbz-clic' + (ab ? " cbz-sel" : "") + '" onclick="cbzFila(' + i + ')">' +
      "<td>" + _cbzFecha(r.fecha) + "</td>" +
      (multi ? '<td><span class="cbz-chip ' + (r._emp === "chef" ? "cbz-ch" : "cbz-lk") + '">' + _cbzEmpLabel(r._emp) + "</span></td>" : "") +
      '<td class="l">' + (r.comprobantes ? _cbzEsc(r.comprobantes) : '<i style="color:#94a3b8;">sin factura</i>') + "</td>" +
      "<td>" + (r.facturado != null ? _cbzPlata(r.facturado) : "—") + "</td>" +
      '<td class="' + (_cbzNum(r.pendiente) ? "cbz-rojo" : "") + '">' + (r.pendiente != null ? _cbzPlata(r.pendiente) : "—") + "</td>" +
      "<td>" + (r.pago_recibo ? _cbzEsc(r.pago_recibo) + '<div style="font-size:10.5px;color:#94a3b8;">' + _cbzFecha(r.pago_fecha) + "</div>" : "—") + "</td>" +
      '<td class="cbz-verde">' + (r.pago_monto != null ? _cbzPlata(r.pago_monto) : "—") + "</td>" +
      "<td>" + (r.dias != null ? r.dias : "—") + "</td>" +
      "<td>" + (r.dto_tomado != null ? _cbzPlata(_cbzNum(r.dto_tomado) * 100, 1) + " %" : "—") + "</td>" +
      "<td>" + (r.dto_ganado != null ? _cbzPlata(_cbzNum(r.dto_ganado) * 100, 1) + " %" : "—") + "</td>" +
      '<td class="cbz-ambar"><b>' + (mal ? _cbzPlata(r.a_reclamar) : "—") + "</b></td>" +
      '<td><span class="cbz-chip ' + chip + '">' + _cbzEsc(est || "—") + "</span></td></tr>";
    if (ab) {
      var cols = multi ? 12 : 11;
      fila += '<tr><td class="cbz-exp" colspan="' + cols + '">' +
        (r.explicacion ? _cbzEsc(r.explicacion) : "Sin explicación cargada.") +
        (r.facturado != null ? '<div style="margin-top:9px;">' + cbzEscalaHtml(_cbzNum(r.facturado), r.dias) + "</div>" : "") +
        "</td></tr>";
    }
    return fila;
  }).join("");
  h += "</tbody></table>";
  h += '<div class="cbz-nota">Tocá un renglón para ver la explicación del pago y qué descuento le correspondía según los días.</div>';
  return h;
}
function cbzFila(i) { _cbz.abierta = (_cbz.abierta === i) ? null : i; var p = document.getElementById("cbzPanel"); if (p) p.innerHTML = cbzCompHtml(); }

/* ---- cuenta corriente --------------------------------------------------- */
function cbzCtaHtml() {
  var m = _cbz.cta || [];
  if (!m.length) return '<div class="cbz-vacio">' + (_cbz.ctaErr ? "No pude leer: " + _cbzEsc(_cbz.ctaErr) : "Sin movimientos.") + "</div>";
  var multi = (cbzGrupo() || { cods: [] }).cods.length > 1;
  var h = '<table class="cbz-t"><thead><tr><th>Fecha</th>' + (multi ? "<th>Emp</th>" : "") +
    '<th>Tipo</th><th style="text-align:left;">Comprobante</th><th style="text-align:left;">Condición</th>' +
    "<th>Debe</th><th>Haber</th><th>Saldo</th><th style='text-align:left;'>Detalle</th></tr></thead><tbody>";
  h += m.map(function (r) {
    var t = String(r.tipo || "");
    return "<tr><td>" + _cbzFecha(r.fecha) + "</td>" +
      (multi ? '<td><span class="cbz-chip ' + (r._emp === "chef" ? "cbz-ch" : "cbz-lk") + '">' + _cbzEmpLabel(r._emp) + "</span></td>" : "") +
      '<td><span class="cbz-chip ' + (t === "Pago" ? "cbz-ok" : t === "NC" ? "cbz-info" : "cbz-lk") + '">' + _cbzEsc(t) + "</span></td>" +
      '<td class="l">' + _cbzEsc(r.comprobante || "") + "</td>" +
      '<td class="l" style="color:#64748b;">' + _cbzEsc(r.condicion || "—") + "</td>" +
      "<td>" + (_cbzNum(r.debe) ? _cbzPlata(r.debe) : "") + "</td>" +
      '<td class="cbz-verde">' + (_cbzNum(r.haber) ? _cbzPlata(r.haber) : "") + "</td>" +
      '<td><b class="' + (_cbzNum(r.saldo) > 0 ? "cbz-rojo" : "cbz-verde") + '">' + _cbzPlata(r.saldo) + "</b></td>" +
      '<td class="l" style="color:#64748b;">' + _cbzEsc(r.detalle || "") + "</td></tr>";
  }).join("");
  return h + "</tbody></table>";
}

/* ---- escala de descuentos (el bloque de abajo de la planilla) ----------- */
var _CBZ_ESC_FALLBACK = [
  { orden: 1, label: "Contado (0-14 días)", dias: 14, dto: 0.25 },
  { orden: 2, label: "15 a 30 días",        dias: 30, dto: 0.20 },
  { orden: 3, label: "31 a 45 días",        dias: 45, dto: 0.15 },
  { orden: 4, label: "46 a 60 días",        dias: 60, dto: 0.10 },
  { orden: 5, label: "E-cheq 90 días",      dias: 90, dto: 0.05 },
  { orden: 6, label: "E-cheq 120 días",     dias: 120, dto: 0.00 }
];
function cbzEscalones() { return (_cbz.escalones && _cbz.escalones.length) ? _cbz.escalones : _CBZ_ESC_FALLBACK; }
async function cbzCargarEscalones() {
  if (_cbz.escalones) return;
  try {
    if (typeof sb !== "undefined" && sb && sb.from) {
      var r = await sb.from("cobranzas_escalones").select("orden,escalon,dias,dto,label").order("orden");
      if (!r.error && r.data && r.data.length) _cbz.escalones = r.data.map(function (x) { return { orden: x.orden, label: x.label, dias: x.dias, dto: _cbzNum(x.dto) }; });
    }
  } catch (_e) {}
  if (_cbz.tab === "escalones") cbzRender();
}
/* dias = en cuántos días se cobró; marca el escalón que le corresponde */
function cbzEscalaHtml(importe, dias) {
  var es = cbzEscalones(), d = (dias == null ? null : _cbzNum(dias));
  var gan = null;
  if (d != null) for (var i = 0; i < es.length; i++) { if (d <= es[i].dias) { gan = es[i].orden; break; } }
  var h = '<div class="cbz-escala">' + es.map(function (e) {
    return '<div class="cbz-esc' + (gan === e.orden ? " on" : "") + '">' +
      '<div class="k">' + _cbzEsc(e.label) + "</div>" +
      '<div class="p">−' + _cbzPlata(e.dto * 100, 0) + " %</div>" +
      '<div class="v">' + (importe ? "$ " + _cbzPlata(importe * e.dto) : "&nbsp;") + "</div></div>";
  }).join("") + "</div>";
  if (d != null) h += '<div style="font-size:12px;color:#64748b;margin-top:6px;">Cobrado a los <b>' + _cbzPlata(d) + " días</b> → le corresponde " +
    (gan ? "<b>" + _cbzEsc(es.filter(function (e) { return e.orden === gan; })[0].label) + "</b>" : "<b>ningún descuento</b>") + ".</div>";
  return h;
}
function cbzEscalonesHtml() {
  var es = cbzEscalones();
  return '<div class="cbz-panel"><table class="cbz-t"><thead><tr><th style="text-align:left;">Escalón</th><th>Hasta (días)</th><th>Descuento</th></tr></thead><tbody>' +
    es.map(function (e) {
      return '<tr><td class="l"><b>' + _cbzEsc(e.label) + "</b></td><td>" + _cbzPlata(e.dias) + '</td><td class="cbz-verde"><b>−' + _cbzPlata(e.dto * 100, 0) + " %</b></td></tr>";
    }).join("") +
    '</tbody></table><div class="cbz-nota">Vive en <code>cobranzas_escalones</code>: cambiarla es un <code>update</code>, no un deploy. Las excepciones por cliente (las “coronitas”) están en <code>cobranzas_excepciones</code> y se cruzan por CUIT del padrón.</div></div>';
}

/* ------------------------------ datos DEMO ------------------------------- */
/* Sólo se usan si la base no contesta, y la pantalla lo dice con un chip. */
var _CBZ_DEMO_CLIENTES = [
  { empresa: "lk", cod_cliente: "4045", cuit: "30712345678", cliente: "Bazar Monica S. CAP I SECC IV", deuda: 108058.3, vencida: 0, comprobantes_abiertos: 1, dias_mas_vieja: 59, ultimo_pago: "2026-09-28", ultimo_pago_monto: 472524.71, a_reclamar: 108058.3, ret_cliente: 0, agente_retencion: false },
  { empresa: "chef", cod_cliente: "2211", cuit: "30712345678", cliente: "Bazar Monica SRL", deuda: 331020, vencida: 120400, comprobantes_abiertos: 3, dias_mas_vieja: 41, ultimo_pago: "2026-09-12", ultimo_pago_monto: 250000, a_reclamar: 0, ret_cliente: 0.021, agente_retencion: false },
  { empresa: "lk", cod_cliente: "288", cuit: "30556677889", cliente: "Torres Y Liva S.A Cif", deuda: 44999903, vencida: 13435258, comprobantes_abiertos: 11, dias_mas_vieja: 53, ultimo_pago: "2026-09-18", ultimo_pago_monto: 5693184.16, a_reclamar: 38405798, ret_cliente: 0.021, agente_retencion: false },
  { empresa: "chef", cod_cliente: "2686", cuit: "30998877665", cliente: "Dorinka S.R.L", deuda: 91811721, vencida: 0, comprobantes_abiertos: 19, dias_mas_vieja: 81, ultimo_pago: "2026-09-07", ultimo_pago_monto: 1000, a_reclamar: 0, ret_cliente: 0, agente_retencion: true },
  { empresa: "lk", cod_cliente: "862", cuit: "30111222333", cliente: "Muller y Muller", deuda: 8802249, vencida: 0, comprobantes_abiertos: 2, dias_mas_vieja: 3, ultimo_pago: "2026-09-29", ultimo_pago_monto: 11687939, a_reclamar: 28873448, ret_cliente: 0, agente_retencion: false }
];
var _CBZ_DEMO_COMP = [
  { orden: "2026-07-24", fecha: "2026-07-24", comprobantes: "FCA 0004-00035292", facturado: 1080583.02, pendiente: 108058.31, estado: "mal",
    pago_recibo: "14601", pago_fecha: "2026-09-28", pago_monto: 972524.71, dias: 59, dto_tomado: 0.10, dto_ganado: 0.10, retencion: 0, a_reclamar: 108058.3,
    explicacion: "Dos pagos: $500.000 el 15/09 (53 días) y $472.525 el 28/09 (66 días). Ponderado da 59 días → le corresponde −10 %. Queda una NC de descuento por $108.058 y $0,01 de saldo." },
  { orden: "2026-09-25", fecha: "2026-09-25", comprobantes: "FCA 0004-00036023", facturado: 10603863.77, pendiente: 10603863.77, estado: "debe",
    pago_recibo: null, pago_fecha: null, pago_monto: null, dias: 4, dto_tomado: null, dto_ganado: null, a_reclamar: null,
    explicacion: "Debe $10.603.864 · facturada hace 4 días · vence el 24/11." }
];
var _CBZ_DEMO_DEUDA = [
  { comprobante: "FCA 0004-00035292", fecha: "2026-07-24", vence: "2026-09-22", condicion: "Pago Contado -25%", dto_cond: 0.25,
    lista: 1080583.02, pendiente_ancla: 108058.31, cancelado_banco: 972524.71, pendiente: 108058.31, origen: "excel",
    recibos_banco: "14588+14601", dias: 67, vencido: true },
  { comprobante: "FCA 0004-00035901", fecha: "2026-09-12", vence: "2026-11-11", condicion: "Cta Cte 60", dto_cond: 0,
    lista: 818771.18, pendiente_ancla: 818771.18, cancelado_banco: 0, pendiente: 818771.18, origen: "isis nuevo",
    recibos_banco: null, dias: 17, vencido: false }
];
var _CBZ_DEMO_PAGOS = [
  { recibo: "14601", fecha_pago: "2026-09-28", medio: "transferencia", pagado: 472524.71, facturas: "35292", lista: 1080583.02,
    nc: null, dias: 66, dto_tomado: 0.10, dto_ganado: 0.10, retencion: 0, a_reclamar: 0, calidad: "exacta", plazo: 60, atraso: 6 },
  { recibo: "14588", fecha_pago: "2026-09-15", medio: "deposito", pagado: 500000, facturas: "35292", lista: 1080583.02,
    nc: null, dias: 53, dto_tomado: 0.10, dto_ganado: 0.10, retencion: 0, a_reclamar: 0, calidad: "parcial", plazo: 60, atraso: 0 },
  { recibo: "14512", fecha_pago: "2026-09-08", medio: "e-cheque", pagado: 352168.44, facturas: "35640", lista: 440210.55,
    nc: null, dias: 9, dto_tomado: 0.25, dto_ganado: 0.25, retencion: 0, a_reclamar: 0, calidad: "exacta", plazo: 14, atraso: 0 }
];
var _CBZ_DEMO_ENTREGAS = [
  { np: "LK 0122", tanda: "E30A", fecha_salida: "2026-09-29", m3: 3.119, facturado_at: "2026-09-28" },
  { np: "98619", tanda: "D61A", fecha_salida: "2026-09-08", m3: 4.309, facturado_at: "2026-09-08" }
];
var _CBZ_DEMO_CTA = [
  { fecha: "2026-07-24", tipo: "Factura", comprobante: "FC Electr. A 0004-00035292", condicion: "Pago Contado -25%", debe: 1080583.02, haber: 0, saldo: 1080583.02, detalle: null },
  { fecha: "2026-09-15", tipo: "Pago", comprobante: "Recibo 14588", condicion: null, debe: 0, haber: 500000, saldo: 580583.02, detalle: "Credicoop · Depósito" },
  { fecha: "2026-09-28", tipo: "Pago", comprobante: "Recibo 14601", condicion: null, debe: 0, haber: 472524.71, saldo: 108058.31, detalle: "Santander · Transferencia" },
  { fecha: "2026-09-29", tipo: "NC", comprobante: "NC Dto 10 %", condicion: "a emitir", debe: 0, haber: 108058.3, saldo: 0.01, detalle: "Descuento por pago a 59 días" }
];

/* ------------------------------- exports --------------------------------- */
window.openCobranzas = openCobranzas;
window.cbzClose = cbzClose;
window.cbzSetTab = cbzSetTab;
window.cbzRender = cbzRender;
window.cbzBuscar = cbzBuscar;
window.cbzEmpresa = cbzEmpresa;
window.cbzCargarClientes = cbzCargarClientes;
window.cbzAbrir = cbzAbrir;
window.cbzVolver = cbzVolver;
window.cbzSub = cbzSub;
window.cbzFila = cbzFila;
window.cbzConsolidar = cbzConsolidar;
window.cbzEscalaHtml = cbzEscalaHtml;
window.cbzDeudaHtml = cbzDeudaHtml;
window.cbzPagosHtml = cbzPagosHtml;
window.cbzEntregasHtml = cbzEntregasHtml;
window.cbzFichaTraer = cbzFichaTraer;

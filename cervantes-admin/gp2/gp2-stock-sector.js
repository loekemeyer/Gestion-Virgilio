"use strict";
/* ============================================================
   gp2-stock-sector.js — pantalla de stock por sector.

   Una sola implementacion para todos los sectores con stock por
   componente. Reproduce la estructura de Gestion Productiva Entero:
   Base | Online (Kg/Caj/Uni) | Movimientos | Info, con las celdas de
   movimiento clickeables para ver el detalle.

   El stock sale del motor (GP2.inventario). La pantalla NO recalcula
   stock: solo convierte a kg/cajones con los factores del componente.

   Config: la pantalla StockSector/StockSector_GP2.html?sector=N toma su
   STOCK_CFG del mapa SECTORES de abajo (titulo, nombre del sector para el
   h1, botones del header, filtros y columnas de movimiento). Hasta el
   2026-09-04 eran 9 HTML casi iguales que solo cambiaban ese objeto; ahora
   lo que difiere por sector vive UNICAMENTE aca. Si una pagina define
   window.STOCK_CFG antes de cargar este script, ese objeto pisa al mapa
   (misma forma: sector_id, titulo, columnas, sin_min_max, mostrar_fleje).

   Depende de gp2-ui.js (GP2UI: esc, $, cls, exportarCSV) y gp2-numero.js
   (GP2N.fmt), cargados antes por la pagina (2026-09-04).
   ============================================================ */

(function(){

/* ---------- mapa de sectores (id de GP2.sector -> config de pantalla) ----------
   Campos:
     titulo      lo que ve el usuario en el <title>, el h1 y el nombre del CSV
     sector_nom  segunda parte del h1 ("Bombillas · Sector Bombilla")
     links       botones del header entre "Exportar CSV" y "Atras":
                 [rotulo, href, "destacado"?] — "destacado" = fondo azul (los Control)
     columnas    columnas de Movimientos (Uni): k, label, tipos de movimiento, lado
                 (ent = suma entradas, sal = suma salidas, neto = ent - sal)
     sin_csv     sin boton "Exportar CSV"
     sin_min_max sin Maximo/Capacidad, sin KPI "Bajo minimo", sin filtro "Bajo el
                 maximo" y sin aviso de factores
     buscar      placeholder del buscador (si no es el generico)
     mostrar_fleje  columna "N° Fleje" (ninguna de estas la usa; Flejes tiene su
                 propia pantalla, StockFlejes/Flejes_GP2.html)
   Los hrefs son relativos a StockSector/. */

/* Insumos: entran por compra y salen por consumo de producción o
   por envío a un proveedor / tallerista. */
var COLS_INSUMO = [
  { k:"compras", label:"Compras", tipos:["compra"],                                   lado:"ent" },
  { k:"consumo", label:"Consumo", tipos:["consumo_prod","consumo_tall","produccion","fabricacion"], lado:"sal" },
  { k:"envios",  label:"Envíos",  tipos:["envio_ps","envio_tallerista"],               lado:"sal" }
];
var LINK_RECEPCION = ["Recepción", "../StockFlejes/RecepcionInsumos_GP2.html"];

var SECTORES = {
  /* Mismas columnas de movimiento que Stock SC del programa viejo:
     lo que entra por fabricación y lo que sale hacia PS / talleristas. */
  1: { titulo:"Stock SC", sector_nom:"Sector Crudo",
       links:[["Stock SP", "?sector=2"]],
       columnas:[
         { k:"fabricacion", label:"Fabricación", tipos:["fabricacion","produccion","armado_fabrica"], lado:"neto" },
         { k:"envios",      label:"Envíos",      tipos:["envio_ps","envio_prov","envio_tallerista","envio_tall"], lado:"sal"  }
       ] },
  /* Mismas columnas de movimiento que Stock SP del programa viejo:
     lo que devuelve el PS, lo que se fabrica y lo que sale al tallerista. */
  2: { titulo:"Stock SP", sector_nom:"Sector Procesado",
       links:[["Stock SC", "?sector=1"]],
       columnas:[
         { k:"entregas_ps", label:"Entregas PS",      tipos:["entrega_ps","recepcion_prov"],             lado:"ent"  },
         { k:"fabricacion", label:"Fabricación",      tipos:["fabricacion","produccion","armado_fabrica"], lado:"neto" },
         { k:"envios_tall", label:"Envíos Tallerista", tipos:["envio_tallerista","envio_tall"],           lado:"sal"  },
         { k:"recep_tall",  label:"Recep. Tallerista", tipos:["recepcion_tall","entrega_tallerista"],     lado:"ent"  }
       ] },
  /* Sector Movimiento (3): las piezas intermedias entre matrices ("tras M#").
     Fabricado = entradas por produccion/fabricacion (la matriz que las hace).
     Consumido = salidas por produccion/fabricacion (la matriz siguiente).
     No tienen minimo/maximo (son WIP transitorio, no algo que se repone): el
     renderer oculta esas columnas, el KPI "Bajo minimo" y el aviso de factores
     cuando sin_min_max esta prendido. [usuario 2026-08-31]. Sin CSV ni Recepción. */
  3: { titulo:"Stock en Movimiento", sector_nom:"Sector Movimiento",
       sin_min_max:true, sin_csv:true, links:[],
       buscar:"Buscar por código, matriz o descripción…",
       columnas:[
         { k:"fabricado", label:"Fabricado", tipos:["fabricacion","produccion"], lado:"ent" },
         { k:"consumido", label:"Consumido", tipos:["fabricacion","produccion","consumo_prod"], lado:"sal" }
       ] },
  6:  { titulo:"Partes Plásticas", sector_nom:"Sector Plástico", links:[LINK_RECEPCION], columnas:COLS_INSUMO },
  7:  { titulo:"Bombillas",        sector_nom:"Sector Bombilla", links:[LINK_RECEPCION], columnas:COLS_INSUMO },
  8:  { titulo:"Remaches",         sector_nom:"Sector Remache",
        links:[LINK_RECEPCION, ["Control Remaches", "../StockFlejes/control-remaches.html", "destacado"]],
        columnas:COLS_INSUMO },
  9:  { titulo:"Garage",           sector_nom:"Sector Garage",   links:[LINK_RECEPCION], columnas:COLS_INSUMO },
  10: { titulo:"Cartones",         sector_nom:"Sector Cartón",   links:[LINK_RECEPCION], columnas:COLS_INSUMO },
  11: { titulo:"Cajas",            sector_nom:"Sector Caja",
        links:[LINK_RECEPCION, ["Control Cajas", "../StockFlejes/control-cajas.html", "destacado"]],
        columnas:COLS_INSUMO }
};

/* config de un sector del mapa (null si no existe) */
function configDe(sector_id){
  var base = SECTORES[Number(sector_id)];
  if (!base) return null;
  var cfg = { sector_id: Number(sector_id), mostrar_fleje: false };
  Object.keys(base).forEach(function(k){ cfg[k] = base[k]; });
  return cfg;
}
function sectorDeURL(){
  try { return new URLSearchParams(location.search).get("sector"); } catch(e){ return null; }
}

var CFG = window.STOCK_CFG || configDe(sectorDeURL());
var SB = window.SB_CLIENT;
var $ = GP2UI.$;

/* Completa lo que cambia por sector en el HTML unico: titulo, h1, botones del
   header (CSV + links, antes del "Atras" fijo), filtro "Bajo el maximo", aviso de
   factores y placeholder. Deja el DOM igual al que tenia cada HTML viejo. */
function montarPantalla(){
  document.title = CFG.titulo + " · GP2";
  var h1 = $("titulo");
  if (h1) h1.textContent = CFG.titulo + (CFG.sector_nom ? " · " + CFG.sector_nom : "");

  var hb = $("hbtns");
  if (hb){
    var atras = hb.querySelector('a[href$="GP2_MODULOS.html"]');   // queda ultimo
    var frag = document.createDocumentFragment();
    if (!CFG.sin_csv){
      var b = document.createElement("button");
      b.className = "hlink"; b.id = "btnCSV"; b.type = "button";
      b.textContent = "⬇ Exportar CSV";
      frag.appendChild(b);
    }
    (CFG.links || []).forEach(function(l){
      var a = document.createElement("a");
      a.href = l[1]; a.textContent = l[0];
      if (l[2] === "destacado") a.setAttribute("style", "background:#0b5cad;color:#fff");
      frag.appendChild(a);
    });
    hb.insertBefore(frag, atras);
  }

  if (CFG.sin_min_max){
    var bajo = document.querySelector('.seg-btn[data-f="bajo"]');
    if (bajo) bajo.remove();
    var av = $("avisoFactores");
    if (av) av.remove();
  }
  if (CFG.buscar && $("q")) $("q").placeholder = CFG.buscar;
}

var D = { filas: [], sector: {}, ubicacion_id: null };
var filtro = "todos";

/* ---------- helpers (gp2-ui.js / gp2-numero.js) ---------- */
var esc = GP2UI.esc, clsNum = GP2UI.cls;
function fmt(n,d){ return GP2N.fmt(n, d==null?1:d); }   // esta pantalla muestra hasta 1 decimal
function fmtFecha(f){ if(!f) return ""; try{ return new Date(f).toLocaleDateString("es-AR"); }catch(e){ return f; } }

/* uni es la unidad canonica de las piezas; kg y cajones son derivados */
function kgDe(x){ return x.kg_x_uni ? Number(x.online||0)*Number(x.kg_x_uni) : null; }
function cajDe(x){ return x.uni_x_cajon ? Number(x.online||0)/Number(x.uni_x_cajon) : null; }

/* valor de una columna de movimientos segun su config */
function valorCol(x, col){
  var tot = 0, hubo = false;
  (col.tipos||[]).forEach(function(t){
    var m = (x.mov||{})[t];
    if (!m) return;
    hubo = true;
    if (col.lado === "ent") tot += Number(m.ent||0);
    else if (col.lado === "sal") tot += Number(m.sal||0);
    else tot += Number(m.ent||0) - Number(m.sal||0);
  });
  return hubo ? tot : null;
}

/* ---------- carga ---------- */
async function cargar(){
  var r = await SB.rpc("stock_sector_bundle", { p_sector_id: CFG.sector_id });
  if (r.error){ $("status").textContent = "Error: " + r.error.message; return; }
  D = r.data || { filas: [] };
  avisarFactores();
  render();
  $("status").textContent = (D.filas||[]).length + " componentes en " +
    ((D.sector&&D.sector.nombre)||"el sector") + ".";
}

/* Si el sector no tiene cargados kg_x_uni / uni_x_cajon, las columnas Kg y Caj
   van a salir en "—". Se avisa en vez de dejar al usuario adivinando por qué. */
function avisarFactores(){
  var el = $("avisoFactores");
  if (!el || CFG.sin_min_max) { if (el) el.classList.add("hidden"); return; }
  var filas = D.filas || [];
  if (!filas.length){ el.classList.add("hidden"); return; }
  var sinKg  = filas.filter(function(x){ return !x.kg_x_uni; }).length;
  var sinCaj = filas.filter(function(x){ return !x.uni_x_cajon; }).length;
  if (!sinKg && !sinCaj){ el.classList.add("hidden"); return; }
  var faltan = [];
  if (sinKg)  faltan.push("<b>"+sinKg+"</b> sin <code>kg_x_uni</code>");
  if (sinCaj) faltan.push("<b>"+sinCaj+"</b> sin <code>uni_x_cajon</code>");
  el.innerHTML = "⚠ De " + filas.length + " componentes, " + faltan.join(" y ") +
    ". Las columnas <b>Kg</b> y <b>Caj</b> muestran “—” en esas filas: el stock en " +
    "<b>Uni</b> es correcto igual, solo falta cargar los factores de conversión.";
  el.classList.remove("hidden");
}

/* ---------- filtros ---------- */
function filtradas(){
  var arr = (D.filas||[]).slice();
  var q = String($("q").value||"").trim().toLowerCase();
  if (q) arr = arr.filter(function(x){
    return (String(x.cod||"")+" "+String(x["desc"]||"")).toLowerCase().indexOf(q) >= 0;
  });
  if (filtro === "con")  arr = arr.filter(function(x){ return Number(x.online||0) > 0; });
  if (filtro === "sin")  arr = arr.filter(function(x){ return !(Number(x.online||0) > 0); });
  if (filtro === "bajo") arr = arr.filter(function(x){
    return x.minimo != null && Number(x.online||0) < Number(x.minimo); });
  if (filtro === "mov")  arr = arr.filter(function(x){
    return x.mov && Object.keys(x.mov).length > 0; });
  return arr;
}

/* ---------- render ---------- */
function render(){
  var arr = filtradas(), tb = $("tbody");
  tb.innerHTML = "";
  $("tblEmpty").classList.toggle("hidden", arr.length > 0);

  var tKg=0, tUni=0, tBajo=0, tConMov=0;

  arr.forEach(function(x){
    var kg = kgDe(x), caj = cajDe(x), uni = Number(x.online||0);
    tKg += (kg||0); tUni += uni;
    var bajo = x.minimo != null && uni < Number(x.minimo);
    if (bajo) tBajo++;
    if (x.mov && Object.keys(x.mov).length) tConMov++;

    var celdasMov = (CFG.columnas||[]).map(function(col, i){
      var sep = i===0 ? " sep" : "";
      var v = valorCol(x, col);
      if (v == null) return '<td class="num cero'+sep+'">—</td>';
      // Solo se colorea por signo lo que es un NETO (puede dar negativo).
      // Un envío o una entrega es una cantidad, no algo bueno ni malo.
      var cls = col.lado === "neto" ? (" "+clsNum(v)) : (v < 0 ? " neg" : "");
      return '<td class="num mov-cell'+cls+sep+'" data-cid="'+x.comp_id+'" data-col="'+esc(col.k)+'" '+
             'title="Ver detalle">'+fmt(v,0)+'</td>';
    }).join("");

    var tr = document.createElement("tr");
    if (bajo) tr.className = "bajo";
    tr.innerHTML =
      '<td><span class="cod">'+esc(x.cod)+'</span></td>'+
      '<td>'+esc(x["desc"]||"")+'</td>'+
      '<td class="num sep stk-cell" data-cid="'+x.comp_id+'" title="Ver cómo se compone">'+(kg==null?"—":fmt(kg,0))+'</td>'+
      '<td class="num stk-cell" data-cid="'+x.comp_id+'" title="Ver cómo se compone">'+(caj==null?"—":fmt(caj,1))+'</td>'+
      '<td class="num stk-cell" data-cid="'+x.comp_id+'" title="Ver cómo se compone"><b>'+fmt(uni,0)+'</b></td>'+
      celdasMov +
      '<td class="num sep">'+(x.kg_x_uni?fmt(x.kg_x_uni,6):"—")+'</td>'+
      '<td class="num">'+(x.uni_x_cajon?fmt(x.uni_x_cajon,0):"—")+'</td>'+
      (CFG.sin_min_max ? "" :
        '<td class="num">'+(x.minimo!=null?fmt(x.minimo,0):"—")+'</td>'+
        '<td class="num">'+(x.maximo!=null?fmt(x.maximo,0):"—")+'</td>')+
      (CFG.mostrar_fleje ? '<td class="num">'+(x.n_fleje!=null?esc(x.n_fleje):"—")+'</td>' : "");
    tb.appendChild(tr);
  });

  $("kpis").innerHTML =
    '<div class="kpi"><div class="k">Componentes</div><div class="v">'+arr.length+'</div></div>'+
    '<div class="kpi"><div class="k">Total uni</div><div class="v">'+fmt(tUni,0)+'</div></div>'+
    '<div class="kpi"><div class="k">Total kg</div><div class="v">'+fmt(tKg,0)+'</div></div>'+
    (CFG.sin_min_max ? "" :
      '<div class="kpi"><div class="k">Bajo mínimo</div><div class="v '+(tBajo?"neg":"cero")+'">'+tBajo+'</div></div>')+
    '<div class="kpi"><div class="k">Con movimientos</div><div class="v">'+tConMov+'</div></div>';
}

/* ---------- popup de detalle ---------- */
var DET_LIMIT = 500;
var DET_SEQ = 0; // token: si se abre otro detalle mientras carga, la respuesta vieja no pinta
async function abrirDetalle(comp_id, colKey){
  var miSeq = ++DET_SEQ;
  var fila = (D.filas||[]).filter(function(x){ return String(x.comp_id)===String(comp_id); })[0] || {};
  var col  = (CFG.columnas||[]).filter(function(c){ return c.k===colKey; })[0] || { label:"Movimientos", tipos:[] };

  $("popTitle").innerHTML = '<span class="cod">'+esc(fila.cod||"")+'</span> — '+esc(fila["desc"]||"")+
    '<br><small style="color:#666;font-weight:600">'+esc(col.label)+'</small>';
  $("popBody").innerHTML = '<div class="empty">Cargando…</div>';
  $("popup").classList.add("open");

  /* composicion_stock es la misma RPC del popup de composicion (gp2-composicion.js): su
     lista 'movs' era identica a la de movimientos_componente, que se borro (2026-09-05). */
  var r = await SB.rpc("composicion_stock", {
    p_comp_id: Number(comp_id), p_ubic_id: Number(D.ubicacion_id), p_limit: DET_LIMIT
  });
  if (miSeq !== DET_SEQ) return;
  if (r.error){ $("popBody").innerHTML = '<div class="empty">Error: '+esc(r.error.message)+'</div>'; return; }

  var movs = (r.data && r.data.movs) || [];
  var truncado = movs.length >= DET_LIMIT;
  var rows = movs.filter(function(m){
    return !col.tipos.length || col.tipos.indexOf(m.tipo) >= 0;
  });
  if (!rows.length){ $("popBody").innerHTML = '<div class="empty">Sin movimientos de este tipo.</div>'; return; }

  var tot = rows.reduce(function(s,m){
    return s + (m.signo==="ent" ? Number(m.cantidad||0) : -Number(m.cantidad||0)); }, 0);

  $("popBody").innerHTML =
    '<div class="table-wrap"><table class="t"><thead><tr>'+
      '<th>Fecha</th><th>Tipo</th><th>Contraparte</th><th class="num">Uni</th><th class="num">Caj</th>'+
    '</tr></thead><tbody>'+
    rows.map(function(m){
      var signo = m.signo==="ent" ? "+" : "−";
      var via = m.via ? ' <small style="color:#777">(vía '+esc(m.via)+')</small>' : "";
      var falt = m.faltante ? ' <span style="color:#c2410c;font-weight:800">F</span>' : "";
      return '<tr><td>'+esc(fmtFecha(m.fecha))+'</td>'+
        '<td>'+esc(m.tipo)+via+falt+'</td>'+
        '<td>'+esc(m.contraparte||"—")+'</td>'+
        '<td class="num '+(m.signo==="ent"?"pos":"neg")+'">'+signo+fmt(m.cantidad,0)+'</td>'+
        '<td class="num">'+(m.cajones!=null?fmt(m.cajones,1):"—")+'</td></tr>';
    }).join("")+
    '</tbody><tfoot><tr><td colspan="3">'+rows.length+' movimientos'+
    (truncado?' <small style="color:#c2410c;font-weight:700">(solo los últimos '+DET_LIMIT+' del componente: puede haber más viejos y el total no cerrar)</small>':'')+'</td>'+
    '<td class="num '+clsNum(tot)+'">'+fmt(tot,0)+'</td><td></td></tr></tfoot></table></div>';
}

/* ---------- CSV ---------- */
function exportarCSV(){
  var arr = filtradas();
  if (!arr.length){ alert("No hay filas para exportar."); return; }
  var cols = ["Codigo","Descripcion","Kg","Caj","Uni"]
    .concat((CFG.columnas||[]).map(function(c){ return c.label; }))
    .concat(["Kg x Uni","Uni x Cajon","Minimo","Maximo"]);
  if (CFG.mostrar_fleje) cols.push("N Fleje");
  var filas = [cols];
  arr.forEach(function(x){
    var f = [x.cod||"", x["desc"]||"", kgDe(x), cajDe(x), x.online]
      .concat((CFG.columnas||[]).map(function(c){ return valorCol(x,c); }))
      .concat([x.kg_x_uni, x.uni_x_cajon, x.minimo, x.maximo]);
    if (CFG.mostrar_fleje) f.push(x.n_fleje);
    filas.push(f);
  });
  GP2UI.exportarCSV((CFG.titulo||"stock").toLowerCase().replace(/\s+/g,"_"), filas);
}

/* ---------- eventos ---------- */
/* El thead se arma entero acá: la cantidad de columnas de movimiento
   depende de la config de cada pantalla. */
function renderHead(){
  var cols = CFG.columnas || [];
  var nInfo = (CFG.sin_min_max ? 2 : 4) + (CFG.mostrar_fleje ? 1 : 0);
  $("thead").innerHTML =
    '<tr>'+
      '<th colspan="2">Base</th>'+
      '<th colspan="3" class="num sep" title="Tocá una celda para ver cómo se compone">Online</th>'+
      '<th colspan="'+cols.length+'" class="num sep">Movimientos (Uni)</th>'+
      '<th colspan="'+nInfo+'" class="num sep">Info</th>'+
    '</tr>'+
    '<tr>'+
      '<th>Código</th><th>Descripción</th>'+
      '<th class="num sep">Kg</th><th class="num">Caj</th><th class="num">Uni</th>'+
      cols.map(function(c,i){
        return '<th class="num'+(i===0?" sep":"")+'" title="Tocá una celda para ver el detalle">'+esc(c.label)+'</th>';
      }).join("")+
      '<th class="num sep">Kg × Uni</th><th class="num">Uni × Cajón</th>'+
      /* "Máximo" = lo que TENDRIA QUE HABER en esta ubicacion segun la demanda
         (consumo mensual x los meses de la ubicacion). Se llamaba "Mínimo"
         [usuario 2026-09-03: "el minimo/maximo es lo que tendria que haber en
         cada ubicacion/sector segun la demanda"] — no es un piso, es el nivel
         objetivo. La de al lado es otra cosa: la CAPACIDAD FISICA del lugar
         (5 cajones en crudo/procesado), por eso ya no se llama "Máximo". */
      (CFG.sin_min_max ? "" : '<th class="num">Máximo</th><th class="num">Capacidad</th>')+
      (CFG.mostrar_fleje ? '<th class="num">N° Fleje</th>' : "")+
    '</tr>';
}

function init(){
  if (!CFG){
    // sin ?sector= valido no hay nada que cargar: se dice cual falta y que hay
    var sec = sectorDeURL();
    var lista = Object.keys(SECTORES).map(function(k){ return k + " = " + SECTORES[k].titulo; }).join(", ");
    $("status").textContent = (sec ? "Sector \"" + sec + "\" desconocido." : "Falta el sector en la URL (?sector=N).") +
      " Sectores: " + lista + ".";
    return;
  }
  montarPantalla();
  renderHead();

  $("q").addEventListener("input", render);
  var _csv = $("btnCSV"); if (_csv) _csv.addEventListener("click", exportarCSV);  // opcional: hay pantallas sin CSV

  document.querySelectorAll(".seg-btn").forEach(function(b){
    b.addEventListener("click", function(){
      document.querySelectorAll(".seg-btn").forEach(function(x){ x.classList.remove("active"); });
      b.classList.add("active");
      filtro = b.dataset.f;
      render();
    });
  });

  $("tbody").addEventListener("click", function(e){
    var mov = e.target.closest("td.mov-cell");
    if (mov){ abrirDetalle(mov.dataset.cid, mov.dataset.col); return; }
    // celda de stock online -> composicion: el stock de hoy y el ledger que lo explica
    var stk = e.target.closest("td.stk-cell");
    if (stk && window.GP2Composicion){
      var f = (D.filas||[]).filter(function(x){ return String(x.comp_id)===String(stk.dataset.cid); })[0] || {};
      window.GP2Composicion.abrir({
        SB: SB, comp_id: stk.dataset.cid, ubic_id: D.ubicacion_id,
        cod: f.cod, desc: f["desc"], kg_x_uni: f.kg_x_uni, uni_x_cajon: f.uni_x_cajon
      });
    }
  });

  $("popClose").addEventListener("click", function(){ $("popup").classList.remove("open"); });
  $("popup").addEventListener("click", function(e){
    if (e.target === $("popup")) $("popup").classList.remove("open");
  });

  cargar().catch(function(e){
    $("status").textContent = "Error: " + (e && e.message ? e.message : e);
  });
}

/* el mapa a la vista (tests y el menu lo cruzan contra sus links) */
window.GP2StockSector = { SECTORES: SECTORES, configDe: configDe };

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
else init();

})();

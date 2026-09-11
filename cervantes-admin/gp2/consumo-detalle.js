/* consumo-detalle.js — el sustento del consumo, tocable.
   Donde una pantalla muestra un consumo mensual (Pintores, OC, Punto de Stock),
   tocarlo abre este popup con el desglose POR ARTICULO: que articulos usan la
   parte, cuanto proyecta la Est Madre de cada uno y cuanto le toca a la parte.
   Lee la RPC GP2.consumo_detalle(p_comp_id), que sale de v_consumo_demanda
   (la demanda atribuida articulo por articulo, no el total del primer nodo).

   Uso: GP2ConsumoDetalle.abrir(SB, compId)
   - SB: el cliente supabase de la pagina (creado con schema GP2).
   - compId: componente.id (siempre id, nunca codigo: hay codigos repetidos).
   Depende de gp2-ui.js (GP2UI.esc) y gp2-numero.js (GP2N.fmt), que la pagina
   carga antes que este archivo (2026-09-04). */
"use strict";
window.GP2ConsumoDetalle = (function () {

  var CSS = [
    "#cdOverlay{position:fixed;inset:0;background:rgba(15,23,42,.55);z-index:900;display:flex;align-items:center;justify-content:center;padding:16px}",
    "#cdCard{background:#fff;border-radius:16px;max-width:520px;width:100%;max-height:82vh;overflow:auto;box-shadow:0 18px 50px rgba(0,0,0,.35);padding:18px 18px 14px}",
    "#cdCard h3{margin:0;font-size:17px;font-weight:800;color:#0f172a}",
    "#cdCard .cd-sub{font-size:13px;color:#64748b;margin:2px 0 10px}",
    "#cdCard .cd-total{font-size:15px;font-weight:800;color:#0f172a;background:#f1f5f9;border-radius:10px;padding:8px 12px;margin-bottom:10px}",
    "#cdCard table{width:100%;border-collapse:collapse;font-size:14px}",
    "#cdCard th{text-align:left;font-size:11px;text-transform:uppercase;letter-spacing:.4px;color:#64748b;padding:4px 6px;border-bottom:1px solid #e2e8f0}",
    "#cdCard td{padding:6px;border-bottom:1px solid #f1f5f9;vertical-align:top}",
    "#cdCard td.num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}",
    "#cdCard .cd-bar{height:5px;border-radius:3px;background:#2563eb;margin-top:3px;min-width:2px}",
    "#cdCard .cd-via{font-size:11px;color:#94a3b8}",
    "#cdCard .cd-cerrar{margin-top:12px;width:100%;padding:12px;border:0;border-radius:10px;background:#0f172a;color:#fff;font-size:15px;font-weight:700;cursor:pointer;font-family:inherit}",
    "#cdCard .cd-vacio{color:#64748b;font-size:14px;padding:8px 0}",
    ".cd-tocable{cursor:pointer;text-decoration:underline dotted #94a3b8;text-underline-offset:3px}"
  ].join("\n");

  /* sin decimales por default y "—" cuando no hay valor (el sustento del
     consumo son unidades enteras) */
  function fmt(n, d) { return window.GP2N.fmt(n, d == null ? 0 : d, "—"); }
  var esc = window.GP2UI.esc;

  function asegurarCss() {
    if (document.getElementById("cdCss")) return;
    var st = document.createElement("style");
    st.id = "cdCss";
    st.textContent = CSS;
    document.head.appendChild(st);
  }

  function cerrar() {
    var o = document.getElementById("cdOverlay");
    if (o) o.remove();
  }

  function render(d) {
    cerrar();
    var esFleje = !!d.es_fleje;
    var arts = d.articulos || [];
    var max = 0;
    arts.forEach(function (a) { var v = esFleje ? a.kg_mes : a.uni_mes; if (v > max) max = v; });

    var filas = arts.map(function (a) {
      var v = esFleje ? a.kg_mes : a.uni_mes;
      var ancho = max > 0 && v != null ? Math.max(2, Math.round(v / max * 100)) : 0;
      return "<tr>" +
        "<td><b>" + esc(a.articulo) + "</b> <span class='cd-via'>" + esc(a.familia || "") +
          (a.receta_directa ? " · en receta" : " · vía ruta") + "</span>" +
          (ancho ? "<div class='cd-bar' style='width:" + ancho + "%'></div>" : "") + "</td>" +
        "<td class='num'>" + fmt(a.proy_uni_mes) + "</td>" +
        "<td class='num'><b>" + (esFleje ? fmt(a.kg_mes, 1) + " kg" : fmt(a.uni_mes)) + "</b></td>" +
      "</tr>";
    }).join("");

    var total = esFleje
      ? fmt(d.total_kg_mes, 1) + " kg/mes (" + fmt(d.total_uni_mes) + " piezas)"
      : fmt(d.total_uni_mes) + " uni/mes" +
        (d.uni_x_cajon ? " · " + fmt(d.total_uni_mes / d.uni_x_cajon, 1) + " cajones" : "");

    var o = document.createElement("div");
    o.id = "cdOverlay";
    o.innerHTML =
      "<div id='cdCard'>" +
        "<h3>" + esc(d.codigo || "—") + " — ¿de dónde sale el consumo?</h3>" +
        "<div class='cd-sub'>" + esc(d.descripcion || "") + " · " + esc(d.sector || "") + "</div>" +
        "<div class='cd-total'>Total: " + total + "</div>" +
        (arts.length
          ? "<table><thead><tr><th>Artículo que lo usa</th><th style='text-align:right'>Proyección<br>art/mes</th><th style='text-align:right'>Le pide<br>" + (esFleje ? "kg" : "uni") + "/mes</th></tr></thead><tbody>" + filas + "</tbody></table>"
          : "<div class='cd-vacio'>Ningún artículo de la Est Madre llega a esta parte por las rutas: no hay consumo que sustentar.</div>") +
        "<button type='button' class='cd-cerrar'>Cerrar</button>" +
      "</div>";
    o.addEventListener("click", function (e) { if (e.target === o) cerrar(); });
    o.querySelector(".cd-cerrar").addEventListener("click", cerrar);
    document.body.appendChild(o);
  }

  async function abrir(sb, compId) {
    asegurarCss();
    if (compId == null) return;
    var r = await sb.rpc("consumo_detalle", { p_comp_id: compId });
    if (r.error) { alert("No se pudo traer el detalle: " + r.error.message); return; }
    if (!r.data) { alert("Componente inexistente."); return; }
    render(r.data);
  }

  return { abrir: abrir, cerrar: cerrar };
})();

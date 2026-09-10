"use strict";
/* ============================================================
   gp2-composicion.js — popup "¿cómo se compone este stock?"

   Se toca una celda de stock online (en cualquier pantalla) y se abre
   el detalle: el stock de HOY arriba, y abajo los movimientos que lo
   fueron formando, del más nuevo al más viejo, con fecha y hora y el
   saldo que quedaba después de cada uno.

   El saldo se ancla en el stock online de hoy y se camina hacia atrás:
   asi el saldo mostrado es correcto aunque la lista venga cortada por
   el limite (los movimientos viejos que faltan quedan como "arrastre").

   Uso:
     GP2Composicion.abrir({
       SB: clienteSupabase,
       comp_id: 12,
       ubic_id: 1,                 // ó bien:
       ubic_tipo: 'tallerista', ref_id: 5,
       cod: 'J2', desc: 'Cuerpo Uña c/M p/Pintar',
       kg_x_uni: 0.0178, uni_x_cajon: 1700
     });
   ============================================================ */

window.GP2Composicion = (function () {

  var LIMITE = 300;
  var montado = false;

  /* Helpers de la casa (la pagina los carga antes que este archivo, 2026-09-04):
     gp2-ui.js -> esc y la clase por signo; gp2-numero.js -> fmt (aca sin
     decimales por default: el popup muestra unidades enteras). */
  var esc = window.GP2UI.esc;
  function fmt(n, d) { return window.GP2N.fmt(n, d == null ? 0 : d); }
  function clsNum(n) { return "cp-" + window.GP2UI.cls(n); }

  /* tipo_mov es el nombre tecnico del ledger; en pantalla va en castellano.
     Un tipo nuevo que no este acá se muestra tal cual, no se pierde. */
  var TIPOS = {
    compra: "Compra", consumo: "Consumo de MP en prov. servicio",
    fabricacion: "Fabricación", armado_fabrica: "Armado en fábrica", consumo_prod: "Consumo de producción",
    envio_ps: "Envío a PS", entrega_ps: "Entrega de PS",
    envio_tallerista: "Envío a tallerista", entrega_tallerista: "Entrega de tallerista",
    consumo_tall: "Consumo de tallerista", devolucion_tallerista: "Devolución de tallerista",
    envio_prov_at: "Envío a prov. art. terminado",
    recepcion_virgilio: "Entrega en Virgilio", consumo_virgilio: "Consumo en Virgilio",
    stock_inicial: "Stock inicial", ajuste: "Ajuste"
  };
  function nombreTipo(t) { return TIPOS[t] || String(t || "").replace(/_/g, " "); }

  /* clave del dia en hora LOCAL: con toISOString un movimiento de las 22h (-03:00)
     cae al dia siguiente en UTC y el separador partiria el dia donde no va. */
  function claveLocal(d) {
    return d.getFullYear() + "-" +
           String(d.getMonth() + 1).padStart(2, "0") + "-" +
           String(d.getDate()).padStart(2, "0");
  }
  function dt(f) {
    if (!f) return { dia: "", hora: "", clave: "" };
    var d = new Date(f);
    if (isNaN(d)) return { dia: String(f), hora: "", clave: String(f) };
    return {
      dia: d.toLocaleDateString("es-AR", { day: "2-digit", month: "2-digit", year: "numeric" }),
      hora: d.toLocaleTimeString("es-AR", { hour: "2-digit", minute: "2-digit", hour12: false }),
      clave: claveLocal(d)
    };
  }
  function etiquetaDia(clave) {
    var hoy = new Date();
    var ayer = new Date(hoy); ayer.setDate(ayer.getDate() - 1);
    if (clave === claveLocal(hoy)) return "Hoy";
    if (clave === claveLocal(ayer)) return "Ayer";
    return null;
  }

  /* ---------- montaje (una sola vez, propio, no depende de la página) ---------- */
  function montar() {
    if (montado) return;
    montado = true;

    var css = document.createElement("style");
    css.textContent = [
      "#cpBg{position:fixed;inset:0;background:rgba(15,23,42,.55);display:none;align-items:center;justify-content:center;z-index:9999;padding:16px}",
      "#cpBg.open{display:flex}",
      "#cpBox{background:#fff;border-radius:14px;width:100%;max-width:860px;max-height:92vh;display:flex;flex-direction:column;overflow:hidden;box-shadow:0 20px 50px rgba(0,0,0,.3)}",
      "#cpHead{padding:14px 18px;border-bottom:1px solid #e2e8f0;display:flex;align-items:flex-start;gap:12px}",
      "#cpHead .cp-t{flex:1;min-width:0}",
      "#cpHead .cp-cod{font-weight:800;color:#1e40af;font-family:ui-monospace,Menlo,Consolas,monospace}",
      "#cpHead .cp-desc{font-size:15px;font-weight:700;color:#1e293b;margin-top:2px;overflow-wrap:anywhere}",
      "#cpHead .cp-ubic{font-size:12px;color:#64748b;margin-top:3px}",
      "#cpX{border:1px solid #cbd5e1;background:#f8fafc;border-radius:9px;font-size:20px;line-height:1;padding:5px 11px;cursor:pointer;color:#475569;flex-shrink:0}",
      "#cpHoy{padding:12px 18px;background:#f8fafc;border-bottom:1px solid #e2e8f0;display:flex;gap:10px;flex-wrap:wrap;align-items:flex-end}",
      "#cpHoy .cp-k{font-size:11px;font-weight:700;color:#64748b;text-transform:uppercase;letter-spacing:.5px}",
      "#cpHoy .cp-big{font-size:30px;font-weight:800;line-height:1.05}",
      "#cpHoy .cp-sec{font-size:14px;font-weight:700;color:#475569}",
      "#cpHoy .cp-when{font-size:11px;color:#94a3b8;width:100%}",
      "#cpBody{overflow:auto;padding:0 0 8px}",
      "#cpBody table{width:100%;border-collapse:collapse;font-size:14px}",
      "#cpBody th{position:sticky;top:0;background:#f1f5f9;color:#475569;font-size:11px;text-transform:uppercase;letter-spacing:.4px;padding:8px 10px;text-align:left;border-bottom:1px solid #e2e8f0;z-index:1}",
      "#cpBody td{padding:9px 10px;border-bottom:1px solid #f1f5f9;vertical-align:top}",
      "#cpBody td.num,#cpBody th.num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}",
      "#cpBody .cp-dia td{background:#eef2f7;font-weight:800;color:#334155;font-size:12px;padding:6px 10px;border-bottom:1px solid #e2e8f0}",
      "#cpBody .cp-hora{color:#64748b;font-size:12px;white-space:nowrap}",
      "#cpBody .cp-tipo{font-weight:700;color:#1e293b}",
      "#cpBody .cp-cp{color:#64748b;font-size:12px}",
      "#cpBody .cp-pos{color:#15803d;font-weight:700}",
      "#cpBody .cp-neg{color:#b91c1c;font-weight:700}",
      "#cpBody .cp-cero{color:#94a3b8}",
      "#cpBody .cp-saldo{font-weight:800;color:#0f172a}",
      "#cpBody .cp-arr td{background:#fffbeb;color:#92400e;font-size:12px;font-weight:700;padding:9px 10px}",
      "#cpBody .cp-vacio{padding:24px 18px;color:#94a3b8;text-align:center}",
      "#cpBody .cp-f{color:#c2410c;font-weight:800}",
      "@media (max-width:640px){",
      "  #cpBg{padding:0}",
      "  #cpBox{max-width:none;max-height:100vh;height:100vh;border-radius:0}",
      "  #cpHoy .cp-big{font-size:26px}",
      "  #cpBody table{font-size:13px}",
      "  #cpBody td,#cpBody th{padding:7px 8px}",
      "}"
    ].join("\n");
    document.head.appendChild(css);

    var bg = document.createElement("div");
    bg.id = "cpBg";
    bg.innerHTML =
      '<div id="cpBox">' +
        '<div id="cpHead"><div class="cp-t">' +
          '<div><span class="cp-cod" id="cpCod"></span></div>' +
          '<div class="cp-desc" id="cpDesc"></div>' +
          '<div class="cp-ubic" id="cpUbic"></div>' +
        '</div><button id="cpX" type="button" title="Cerrar">&times;</button></div>' +
        '<div id="cpHoy"></div>' +
        '<div id="cpBody"></div>' +
      '</div>';
    document.body.appendChild(bg);

    document.getElementById("cpX").addEventListener("click", cerrar);
    bg.addEventListener("click", function (e) { if (e.target === bg) cerrar(); });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && bg.classList.contains("open")) cerrar();
    });
  }

  function cerrar() {
    var bg = document.getElementById("cpBg");
    if (bg) bg.classList.remove("open");
  }

  /* ---------- apertura ---------- */
  var ABRIR_SEQ = 0; // token: si se abre otro componente mientras carga, la respuesta vieja no pinta
  async function abrir(o) {
    var miSeq = ++ABRIR_SEQ;
    montar();
    o = o || {};
    var SB = o.SB || window.SB_CLIENT;

    document.getElementById("cpCod").textContent = o.cod || "";
    document.getElementById("cpDesc").textContent = o.desc || "";
    document.getElementById("cpUbic").textContent = "";
    document.getElementById("cpHoy").innerHTML = '<div class="cp-k">Cargando…</div>';
    document.getElementById("cpBody").innerHTML = "";
    document.getElementById("cpBg").classList.add("open");

    var args = { p_comp_id: Number(o.comp_id), p_limit: LIMITE };
    if (o.ubic_id != null) args.p_ubic_id = Number(o.ubic_id);
    if (o.ubic_tipo) { args.p_ubic_tipo = o.ubic_tipo; args.p_ref_id = (o.ref_id == null ? null : Number(o.ref_id)); }

    var r;
    try { r = await SB.rpc("composicion_stock", args); }
    catch (e) { r = { error: { message: String(e && e.message || e) } }; }

    if (miSeq !== ABRIR_SEQ) return;
    if (r.error) {
      document.getElementById("cpHoy").innerHTML = "";
      document.getElementById("cpBody").innerHTML =
        '<div class="cp-vacio">Error: ' + esc(r.error.message) + "</div>";
      return;
    }
    pintar(r.data || {}, o);
  }

  function pintar(d, o) {
    var comp = d.comp || {};
    var online = Number(d.online || 0);
    // El saldo se calcula caminando hacia atras, asi que el orden importa.
    // La RPC ya devuelve del mas nuevo al mas viejo; se reordena igual para no
    // depender de eso (un cambio ahi daria saldos que no cierran, en silencio).
    var movs = (d.movs || []).slice().sort(function (a, b) {
      var fa = new Date(a.fecha).getTime() || 0, fb = new Date(b.fecha).getTime() || 0;
      return fb - fa || (Number(b.id) - Number(a.id));
    });
    var total = Number(d.total_movs || 0);

    // los factores del componente ganan; si la pantalla mandó los suyos, sirven de respaldo
    var kgU = comp.kg_x_uni != null ? Number(comp.kg_x_uni) : (o.kg_x_uni != null ? Number(o.kg_x_uni) : null);
    var uxc = comp.uni_x_cajon != null ? Number(comp.uni_x_cajon) : (o.uni_x_cajon != null ? Number(o.uni_x_cajon) : null);

    document.getElementById("cpCod").textContent = comp.codigo || o.cod || "";
    document.getElementById("cpDesc").textContent = comp.descripcion || o.desc || "";
    document.getElementById("cpUbic").textContent = (d.ubicacion && d.ubicacion.nombre) ? ("en " + d.ubicacion.nombre) : "";

    /* ---- bloque de HOY ---- */
    var extra = [];
    if (kgU) extra.push(fmt(online * kgU, 0) + " kg");
    if (uxc) extra.push(fmt(online / uxc, 1) + " caj");
    var act = d.actualizado_en ? dt(d.actualizado_en) : null;
    document.getElementById("cpHoy").innerHTML =
      '<div><div class="cp-k">Stock hoy</div>' +
        '<div class="cp-big ' + clsNum(online) + '">' + fmt(online, 0) + ' <span style="font-size:15px;font-weight:700">uni</span></div></div>' +
      (extra.length ? '<div style="padding-bottom:5px"><div class="cp-k">Equivale a</div><div class="cp-sec">' + extra.join(" · ") + "</div></div>" : "") +
      '<div style="padding-bottom:5px;margin-left:auto"><div class="cp-k">Movimientos</div><div class="cp-sec">' + fmt(total, 0) + "</div></div>" +
      (act ? '<div class="cp-when">Último cambio de stock: ' + esc(act.dia) + " " + esc(act.hora) + "</div>" : "");

    /* ---- ledger ---- */
    var body = document.getElementById("cpBody");
    if (!movs.length) {
      body.innerHTML = '<div class="cp-vacio">Este stock todavía no tiene movimientos registrados.<br>' +
        "El número de arriba viene de la carga inicial del inventario.</div>";
      return;
    }

    // saldo anclado en el stock de hoy, caminando hacia atrás
    var saldo = online, filas = [], diaActual = null;
    movs.forEach(function (m) {
      var cant = Number(m.cantidad || 0);
      var ent = m.signo === "ent";
      var f = dt(m.fecha);

      if (f.clave !== diaActual) {
        diaActual = f.clave;
        var et = etiquetaDia(f.clave);
        filas.push('<tr class="cp-dia"><td colspan="5">' + esc(f.dia) + (et ? " · " + et : "") + "</td></tr>");
      }

      var via = m.via ? ' <span class="cp-cp">(vía ' + esc(m.via) + ")</span>" : "";
      var falt = m.faltante ? ' <span class="cp-f">F</span>' : "";
      var caj = (m.cajones != null && Number(m.cajones)) ? (" · " + fmt(m.cajones, 1) + " caj") : "";

      filas.push(
        "<tr>" +
          '<td class="cp-hora">' + esc(f.hora) + "</td>" +
          '<td><span class="cp-tipo">' + esc(nombreTipo(m.tipo)) + "</span>" + via + falt +
            '<div class="cp-cp">' + esc(m.contraparte || "—") + caj + "</div></td>" +
          '<td class="num cp-pos">' + (ent ? "+" + fmt(cant, 0) : "") + "</td>" +
          '<td class="num cp-neg">' + (ent ? "" : "−" + fmt(cant, 0)) + "</td>" +
          '<td class="num cp-saldo">' + fmt(saldo, 0) + "</td>" +
        "</tr>"
      );
      // el saldo de la fila de arriba (más vieja) es el de ésta menos su propio delta
      saldo = saldo - (ent ? cant : -cant);
    });

    // lo que quedaba antes del movimiento más viejo mostrado
    var truncado = total > movs.length;
    var arranque = Math.round(saldo * 1e6) / 1e6;
    filas.push(
      '<tr class="cp-arr"><td colspan="4">' +
        (truncado
          ? "Arrastre de " + fmt(total - movs.length, 0) + " movimientos anteriores (no listados)"
          : (arranque === 0
              ? "Arranca en cero: los movimientos de arriba explican todo el stock"
              : "Saldo inicial, cargado sin movimiento")) +
      '</td><td class="num cp-saldo">' + fmt(arranque, 0) + "</td></tr>"
    );

    body.innerHTML =
      "<table><thead><tr>" +
        "<th>Hora</th><th>Movimiento</th>" +
        '<th class="num">Entra</th><th class="num">Sale</th><th class="num">Saldo</th>' +
      "</tr></thead><tbody>" + filas.join("") + "</tbody></table>";
  }

  return { abrir: abrir, cerrar: cerrar };

})();

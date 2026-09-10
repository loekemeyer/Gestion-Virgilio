"use strict";
/* ============================================================
   gp2-envios-common.js — helpers compartidos de las pantallas de
   Envios/Entregas y Controles GP2.

   Antes cada pantalla (Envios Tallerista, Recepcion Tallerista,
   Envios PS, Entrega PS, Entregas Prov AT, Controles) traia su
   propia copia de esc/num/fmt/buffer/fases/tandas: mismo codigo
   pegado 6 veces. Esto lo junta en UN lugar, sin cambiar el
   comportamiento de ninguna pantalla.

   Lo usan (cargar ANTES del script de la pantalla):
     Talleristas/Envios/EnviosTalleristas_GP2.html
     Talleristas/Recepcion/EntregasTalleristas_GP2.html
     Prov Serv/Envios/EnviosPS_GP2.html
     Prov Serv/Entregas/EntregaPS_GP2.html
     Control Envios y Entregas/ControlEnvios_GP2.html
     Talleristas/Control Tall/ControlTalleristas_GP2.html

   Depende de DOS archivos que la pagina carga antes que este (2026-09-04):
     gp2-ui.js     (GP2UI: esc, $, cls, hoyAR)  — los helpers de pantalla
     gp2-numero.js (GP2N: num, fmt)             — la regla de numero
   Aca ya no hay copia de ninguno de los dos: lo que exporta GP2EE es lo
   propio de las pantallas de Envios/Entregas (buffer, fases, tandas,
   grilla, guardado). esc/$ se toman de GP2UI directo.

   Convenciones que fija (y que una pantalla nueva hereda gratis):
     - numeros SIEMPRE formateados es-AR;
     - buffer de carga en localStorage por contraparte (sobrevive F5);
     - fases fase0 (elegir contraparte) / fase1 (cargar) / fase3 (exito)
       con #btnVolver visible solo en fase1;
     - grilla de contrapartes con .prov-btn + .meta;
     - popup de tandas via tandas-popup.js.
   ============================================================ */
(function (global) {

  /* Cliente Supabase apuntando al schema GP2 (el de todas las pantallas GP2). */
  function sb(opts) {
    return global.GP2_SB(opts);   /* el cliente vive en supabase-config.js (2026-09-05) */
  }

  /* Dependencias duras (las 6 pantallas que cargan este archivo cargan antes
     gp2-ui.js y gp2-numero.js): si falta alguna, revienta aca, a la vista. */
  var UI = global.GP2UI, N = global.GP2N;
  var $ = UI.$, esc = UI.esc;

  /* La regla de numero vive en gp2-numero.js (GP2N), una sola vez para todo
     el proyecto (idea 7217). Aca queda el alias para no tocar las pantallas
     que ya llaman GP2EE.num. El parametro modo es historico: se acepta y se
     ignora. */
  function num(v, modo) { return N.num(v); }

  /* es-AR con hasta d decimales (default 1) — el de las pantallas de carga. */
  function fmt(n, d) { return N.fmt(n, d == null ? 1 : d); }

  /* es-AR con hasta d decimales (default 0) — el de los controles/pivotes. */
  function fmt0(n, d) { return N.fmt(n, d == null ? 0 : d); }

  /* cantidad canonica (uni) -> cajones; null si no hay factor. */
  function aCajones(cantidad, uniXCaj) {
    var u = Number(uniXCaj || 0);
    if (!(u > 0)) return null;
    return Number(cantidad || 0) / u;
  }

  /* Fecha de hoy YYYY-MM-DD en Argentina (gp2-ui.js). Se sigue llamando hoyISO
     porque asi la llaman las pantallas; antes era la fecha del dispositivo. */
  function hoyISO() { return UI.hoyAR(); }

  /* Mes actual YYYY-MM en Argentina. */
  function mesAR() { return UI.hoyAR().slice(0, 7); }

  /* Codigo de comprobante de 4 digitos (1000-9999), para el cartel de exito. */
  function genCode() { return String(Math.floor(1000 + Math.random() * 9000)); }

  /* ---------- buffer de carga en localStorage ----------
     Estructura: { "<contraparte_id>": { "<clave item>": {campos...} } }.
     blank() devuelve el item vacio de la pantalla (ej. {caj:"",kg:"",falt:false,tandas:[]}). */
  function buffer(lsKey, blank) {
    var BUF = {};
    function load() {
      try { BUF = JSON.parse(localStorage.getItem(lsKey) || "{}") || {}; }
      catch (e) { BUF = {}; }
      return BUF;
    }
    function save() {
      try { localStorage.setItem(lsKey, JSON.stringify(BUF)); } catch (e) {}
    }
    function de(pid) {
      if (pid == null) return {};
      if (!BUF[pid]) BUF[pid] = {};
      return BUF[pid];
    }
    function item(pid, k) {
      var b = de(pid);
      if (!b[k]) b[k] = blank();
      return b[k];
    }
    function borrar(pid) { delete BUF[pid]; save(); }
    return {
      get all() { return BUF; },
      load: load, save: save, de: de, item: item, borrar: borrar
    };
  }

  /* Los items de un buffer que cumplen el predicado, como [{k, it}]. */
  function cargadasDe(b, pred) {
    var out = [];
    Object.keys(b || {}).forEach(function (k) { if (pred(b[k])) out.push({ k: k, it: b[k] }); });
    return out;
  }

  /* ---------- fases (ids fijos: fase0 / fase1 / fase3 + btnVolver) ---------- */
  function mostrarFase(n) {
    $("fase0").classList.toggle("hidden", n !== 0);
    $("fase1").classList.toggle("hidden", n !== 1);
    $("fase3").classList.toggle("hidden", n !== 3);
    var bv = $("btnVolver");
    if (bv) bv.classList.toggle("hidden", n !== 1);
  }

  /* ---------- grilla de contrapartes (fase 0) ----------
     o.meta(p)  -> html del <span class="meta"> (piezas ya escapadas)
     o.onPick(p)-> click
     o.vacio    -> mensaje si la lista esta vacia */
  function gridContrapartes(elId, lista, o) {
    var g = $(elId);
    g.innerHTML = "";
    (lista || []).forEach(function (p) {
      var b = document.createElement("button");
      b.type = "button";
      b.className = "prov-btn";
      b.innerHTML = esc(p.nombre) + '<span class="meta">' + o.meta(p) + "</span>";
      b.addEventListener("click", function () { o.onPick(p); });
      g.appendChild(b);
    });
    if (!(lista || []).length) g.innerHTML = '<div class="empty">' + (o.vacio || "Sin datos.") + "</div>";
    return g;
  }

  /* ---------- filtro de busqueda ---------- */
  function filtrar(arr, q, textoDe) {
    q = String(q || "").trim().toLowerCase();
    if (!q) return arr;
    return arr.filter(function (x) { return textoDe(x).toLowerCase().indexOf(q) >= 0; });
  }

  function buscarMeta(arr, key, keyDe) {
    for (var i = 0; i < arr.length; i++) if (String(keyDe(arr[i])) === String(key)) return arr[i];
    return null;
  }

  /* ---------- boton Enviar/Registrar ---------- */
  function actualizarEnviar(n, verbo) {
    var btn = $("btnEnviar");
    btn.disabled = (n === 0);
    btn.textContent = n ? (verbo + " (" + n + ")") : verbo;
  }

  /* ---------- tandas ----------
     Totales de las tandas de un item para los campos pedidos. */
  function tandaTotales(it, campos) {
    var ts = it.tandas || [];
    var tot = {};
    campos.forEach(function (c) {
      tot[c] = ts.reduce(function (s, t) { return s + num(t[c]); }, 0);
    });
    return { hayT: ts.length > 0, tot: tot };
  }

  /* Abre tandas-popup y al confirmar deja tandas + totales en el buffer del item.
     o = { titulo, buf, campos:['caj','kg'|'uni'], onDone } */
  function abrirTandas(o) {
    if (typeof tandasPopup === "undefined") { alert("No cargó tandas-popup.js"); return; }
    tandasPopup.open({
      titulo: o.titulo,
      initial: (o.buf.tandas || []).slice(),
      pedirCaj: o.campos.indexOf("caj") >= 0,
      pedirKg: o.campos.indexOf("kg") >= 0,
      pedirUni: o.campos.indexOf("uni") >= 0,
      onConfirm: function (tandas, totales) {
        o.buf.tandas = (tandas || []).filter(function (t) {
          return o.campos.some(function (c) { return num(t[c]) > 0; });
        });
        if (o.buf.tandas.length) {
          o.campos.forEach(function (c) {
            o.buf[c] = String(totales && totales[c] != null ? totales[c] : "");
          });
        }
        o.onDone();
      }
    });
  }

  /* ---------- celdas repetidas de la tabla de carga ---------- */
  function tdInput(campo, valor, hayT, clase, inputmode) {
    return '<td class="num' + (clase ? (" " + clase) : "") + '"><input class="cell-in' + (hayT ? " ro" : "") +
      '" data-f="' + campo + '" inputmode="' + (inputmode || "numeric") + '" value="' + esc(valor) + '"' +
      (hayT ? " readonly" : "") + "></td>";
  }
  function tdTanda(it) {
    var hayT = (it.tandas || []).length > 0;
    return '<td class="ctr"><button type="button" class="tanda-btn' + (hayT ? " on" : "") +
      '" data-a="tandas">' + (hayT ? it.tandas.length : "+") + "</button></td>";
  }
  function tdFalt(it) {
    return '<td class="ctr"><button type="button" class="falt-box' + (it.falt ? " on" : "") +
      '" data-a="falt">' + (it.falt ? "F" : "") + "</button></td>";
  }

  /* ---------- persistencia de la marca F (2026-08-31) ----------
     En el programa viejo la F se anotaba a mano; ahora ademas del buffer
     local se registra en GP2.faltante_marcado: al ACTIVAR la F llama
     marcar_faltante (origen de la pantalla: 'envios_tall' / 'envios_ps');
     al DESACTIVARLA resuelve el ultimo abierto de ese componente+origen.
     Es best-effort y NUNCA bloquea la UI: el buffer local sigue siendo la
     verdad de la pantalla; si la red falla, se ignora en silencio. */
  function persistirFalt(sbCli, activada, compId, origen, nota) {
    try {
      var usuario = null;
      try { usuario = localStorage.getItem("gp2_usuario") || null; } catch (e2) {}
      var p = activada
        ? sbCli.rpc("marcar_faltante", {
            p_comp_id: Number(compId), p_origen: origen,
            p_nota: nota || null, p_usuario: usuario })
        : sbCli.rpc("resolver_faltante", {
            p_comp_id: Number(compId), p_origen: origen });
      if (p && typeof p.then === "function") p.then(function () {}, function () {});
    } catch (e) {}
  }

  /* ---------- exito (fase 3) ---------- */
  function mostrarExito(detalle) {
    $("successCode").textContent = genCode();
    $("successDetail").textContent = detalle;
    mostrarFase(3);
  }

  /* ---------- guardado de a un item por RPC ----------
     Registra item por item; el que entra se saca del buffer YA (o.onOk),
     asi un reintento no lo duplica. Devuelve {ok, errs}. */
  async function guardarItems(items, o) {
    var ok = 0, errs = [];
    for (var i = 0; i < items.length; i++) {
      var it = items[i];
      try {
        var r = await o.rpc(it);
        if (r && r.error) throw r.error;
        ok++;
        o.onOk(it);
      } catch (e) {
        errs.push(o.codDe(it) + ": " + (e && e.message ? e.message : e));
      }
    }
    return { ok: ok, errs: errs };
  }

  /* Solo lo que alguna pantalla llama. Lo que era pass-through a GP2N/GP2UI
     ($, esc, conMiles, autoMiles, autoMilesEn, fechaAR, clsSaldo) o interno
     (genCode) ya no se exporta: se toma de GP2UI / GP2N (2026-09-04). */
  global.GP2EE = {
    sb: sb, num: num, fmt: fmt, fmt0: fmt0,
    aCajones: aCajones, hoyISO: hoyISO, mesAR: mesAR,
    buffer: buffer, cargadasDe: cargadasDe,
    mostrarFase: mostrarFase, gridContrapartes: gridContrapartes,
    filtrar: filtrar, buscarMeta: buscarMeta, actualizarEnviar: actualizarEnviar,
    tandaTotales: tandaTotales, abrirTandas: abrirTandas,
    tdInput: tdInput, tdTanda: tdTanda, tdFalt: tdFalt, persistirFalt: persistirFalt,
    mostrarExito: mostrarExito, guardarItems: guardarItems
  };

})(typeof self !== "undefined" ? self : window);

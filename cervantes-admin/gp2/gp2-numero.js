/* gp2-numero.js — LA REGLA DE NUMERO DE LA CASA, en un solo lugar.
 *
 * Regla [usuario 2026-09-03], textual: "si hay un punto, el punto para el
 * separador de mil; la coma para los decimales" y "en cada lugar que ponga
 * cuatro digitos, que se ponga automatico un separador de miles".
 *
 *   "1.234"     -> 1234        (mil doscientos treinta y cuatro, NO 1,234)
 *   "1.234,5"   -> 1234.5
 *   "12,5"      -> 12.5
 *   "999"       -> 999         (tres digitos: sin separador)
 *   "1000"      -> se ve "1.000"
 *
 * Existe porque la regla estaba escrita SEIS veces y ninguna igual (idea
 * 7217): GP2EE.num decidia "el ultimo separador es el decimal" (leia "1.234"
 * como 1,234), parseNumTol de Altrak/Aperam adivinaba segun cuantos puntos
 * hubiera, tandas-popup leia los cajones con Number() crudo (que hace de
 * "1.000" un 1) y Recepcion Cervantes borraba la coma tecla por tecla, con lo
 * cual "12,5" kg entraban como 125. Ahora la regla se toca UNA vez y vale
 * para todas. Se carga suelto: no depende de nada.
 */
(function (global) {
  "use strict";

  /* Texto -> numero. El punto SIEMPRE es miles; la coma, decimal (una sola:
     de la segunda en adelante se ignoran). Lo que no se entiende vale 0. */
  function num(v) {
    if (v == null || v === "") return 0;
    if (typeof v === "number") return isFinite(v) ? v : 0;
    var s = String(v).trim().replace(/[^\d,.-]/g, "");
    var neg = s.charAt(0) === "-";
    s = s.replace(/-/g, "").replace(/\./g, "");
    var i = s.indexOf(",");
    if (i >= 0) s = s.slice(0, i) + "." + s.slice(i + 1).replace(/,/g, "");
    var n = Number(s);
    if (!isFinite(n)) return 0;
    return neg ? -n : n;
  }

  /* Enteros (cajones, unidades, golpes): misma regla, sin parte decimal. */
  function entero(v) { return Math.trunc(num(v)); }

  /* Numero -> texto con el separador de miles, recien a partir de CUATRO
     digitos enteros. Trabaja sobre lo TIPEADO, asi que respeta la coma a
     medio escribir ("12," sigue siendo "12,"). */
  function conMiles(txt) {
    var s = String(txt == null ? "" : txt);
    var neg = s.charAt(0) === "-";
    s = s.replace(/[^\d,]/g, "");
    var i = s.indexOf(",");
    var ent = i < 0 ? s : s.slice(0, i);
    var dec = i < 0 ? null : s.slice(i + 1).replace(/,/g, "");
    if (ent.length > 3) ent = ent.replace(/\B(?=(\d{3})+(?!\d))/g, ".");
    return (neg ? "-" : "") + ent + (dec === null ? "" : "," + dec);
  }

  /* Igual pero para mostrar un numero ya calculado (no tipeado). nullTxt es lo
     que se muestra cuando NO hay valor (null, undefined o ""): "—", "0", ""...
     Sin nullTxt nada cambia: el vacio se muestra como 0. Es LA fmt de la casa;
     una pantalla que quiera otro default lo envuelve (fmt(n,d){ return
     GP2N.fmt(n, d==null?0:d, "—"); }), no se escribe la suya. El cuarto parametro
     (fijo) deja SIEMPRE esa cantidad de decimales. */
  function fmt(n, dec, nullTxt, fijo) {
    if (nullTxt != null && (n == null || n === "")) return nullTxt;
    var x = Number(n);
    if (!isFinite(x)) x = 0;
    var d = dec == null ? 2 : dec;
    /* fijo = true: siempre esa cantidad de decimales ("1,50" y no "1,5"), para columnas
       alineadas (Control AT, Cierres del dia). */
    return x.toLocaleString("es-AR", fijo ? { minimumFractionDigits: d, maximumFractionDigits: d } : { maximumFractionDigits: d });
  }

  /* Un campo admite coma segun su teclado, que es la convencion de la casa
     (CLAUDE.md): inputmode="decimal" lleva coma, inputmode="numeric" son
     enteros. data-dec="si" / "no" lo fuerza si hiciera falta. */
  function admiteComa(el) {
    var d = el.dataset.dec;
    if (d === "no") return false;
    if (d === "si") return true;
    return el.getAttribute("inputmode") !== "numeric";
  }

  /* Engancha un <input> para que se formatee mientras se tipea SIN mover el
     cursor: se cuenta cuantos digitos hay antes del caret, se reformatea y se
     vuelve a poner el caret despues de esos mismos digitos. Idempotente. */
  function autoMiles(el) {
    if (!el || el.dataset.milesOn === "1") return el;
    el.dataset.milesOn = "1";
    el.addEventListener("input", function () {
      var antes = el.value;
      var crudo = admiteComa(el) ? antes : antes.replace(/,/g, "");
      var salida = conMiles(crudo);
      if (salida === antes) return;
      var caret = el.selectionStart;
      if (caret === null || caret === undefined) { el.value = salida; return; }
      var digitos = (antes.slice(0, caret).match(/[\d,]/g) || []).length;
      var pos = 0, vistos = 0;
      while (pos < salida.length && vistos < digitos) {
        if (/[\d,]/.test(salida.charAt(pos))) vistos++;
        pos++;
      }
      el.value = salida;
      try { el.setSelectionRange(pos, pos); } catch (e) {}
    });
    return el;
  }

  /* Engancha todos los campos numericos que haya adentro de un nodo. */
  function autoMilesEn(nodo) {
    if (!nodo || !nodo.querySelectorAll) return;
    var campos = nodo.querySelectorAll('input[inputmode="numeric"], input[inputmode="decimal"]');
    for (var i = 0; i < campos.length; i++) autoMiles(campos[i]);
  }

  /* Auto-enganche: una pantalla que cargue este archivo ya tiene el formato en
     todos sus campos numericos, incluidas las tablas que se repintan (se
     engancha recien al enfocar). Un campo queda afuera con data-miles="no". */
  if (typeof document !== "undefined" && document.addEventListener) {
    document.addEventListener("focusin", function (ev) {
      var el = ev.target;
      if (!el || el.tagName !== "INPUT" || el.dataset.miles === "no") return;
      var im = el.getAttribute("inputmode");
      if (im === "numeric" || im === "decimal") autoMiles(el);
    });
  }

  global.GP2N = {
    num: num, entero: entero, conMiles: conMiles, fmt: fmt,
    autoMiles: autoMiles, autoMilesEn: autoMilesEn
  };
})(typeof window !== "undefined" ? window : this);

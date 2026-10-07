/* Regresión (Thomas, 2026-10-07) — Pendientes de Recepción: la demora de una tarjeta pasa a
   días y horas desde las 24 hs.

   Antes decía "⏱ 165,5hs" (Blist-Pack, RTO/FC 10208). Ahora dice "⏱ 6d 22hs". Debajo de 24 hs
   queda como siempre (medias horas: "23,5hs"). Sin navegador: se extrae `pendFmtDemora` de
   recepcion.js y se evalúa con un `Date.now()` fijo. Sale 1 si falla. */
const fs = require("fs"), path = require("path");

const src = fs.readFileSync(path.join(__dirname, "..", "recepcion.js"), "utf8");
const m = /function pendFmtDemora\([\s\S]*?\n\}/.exec(src);
if (!m) { console.error("FAIL pend-demora-dias: no encontré pendFmtDemora en recepcion.js"); process.exit(1); }

const AHORA = Date.UTC(2026, 9, 7, 15, 0, 0);
const fmt = new Function("Date", m[0] + "; return pendFmtDemora;")({ now: function () { return AHORA; } });
const hace = function (hs) { return fmt(AHORA - hs * 3600000); };

const fail = [];
const eq = function (qué, dio, esperaba) {
  if (dio !== esperaba) fail.push(qué + ": dio " + JSON.stringify(dio) + ", esperaba " + JSON.stringify(esperaba));
};

// el caso del pedido: 165,5 hs
eq("165,5 hs (el de la captura)", hace(165.5), "6d 22hs");
// el ejemplo de Thomas
eq("29 hs", hace(29), "1d 5hs");
// el borde: 24 hs justas son 1 día, sin "0hs"
eq("24 hs", hace(24), "1d");
eq("48 hs", hace(48), "2d");
// redondeo a la media hora y arrastre al día siguiente (47,6 hs -> 47,5 -> 23,5 de resto -> 24 -> 2d)
eq("47,6 hs", hace(47.6), "2d");
// debajo de 24 hs no cambia nada
eq("23,5 hs", hace(23.5), "23,5hs");
eq("5 hs", hace(5), "5hs");
eq("0,2 hs", hace(0.2), "0hs");
// una hora en el futuro (reloj del celular atrasado) no da negativo
eq("futuro", hace(-3), "0hs");
// el texto viejo no vuelve
if (/\d{3},5hs/.test(hace(165.5))) fail.push("volvió el formato viejo '165,5hs'");

if (fail.length) { console.error("FAIL pend-demora-dias:\n - " + fail.join("\n - ")); process.exit(1); }
console.log("OK pend-demora-dias (" + 10 + " chequeos)");

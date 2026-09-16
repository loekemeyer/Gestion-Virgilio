/* Regresión v18.70 — anular un picking NO puede borrar el stock de otro.

   `anular_picking_virgilio` (la vieja) ponía en cero TODO el picking de la tanda:

       update "Movimientos_Stock" set delta = 0
        where tipo = 'picking' and upper(trim(ref)) = v_tanda and delta <> 0;

   Sin filtrar por legajo ni por fecha. Los eventos PKC sí se borraban sólo los del operario,
   así que la inconsistencia estaba a la vista y nadie la había mirado.

   Por qué importa: existen los «EP fantasma», tandas YA pickeadas que alguien reabre por
   error (6 medidos en 120 días; dos seguían abiertos desde julio y agosto). Anular uno de
   ésos con la versión vieja habría puesto en cero el picking BUENO — en D30A, 36 movimientos
   de una tanda que además ya estaba armada.

   La versión nueva (`gv_anular_picking_virgilio`) mira si la tanda ya tiene TP o TAP:
     · si los tiene → es una reapertura: borra el evento y NO TOCA el stock  → 'ep_fantasma_limpiado'
     · si no        → anulación normal, y el `delta = 0` va acotado al legajo y desde ese EP
   Y la ventana pasó de 24 h a 3 días, que recién ahora es seguro porque lo que protege ya no
   es la fecha sino el guard.

   Chequea, en estático sobre index.html (el comportamiento SQL se probó contra la base):
     1) que se llame a la RPC nueva y no a la vieja, que la sigue usando Producción;
     2) que el front contemple 'ep_fantasma_limpiado' y le diga al operario que NO se tocó
        el stock — si no, el mensaje diría "anulado" y nadie se enteraría de la diferencia.
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");

const fallas = [];

if (!src.includes("rpc/gv_anular_picking_virgilio")) {
  fallas.push("no se llama a rpc/gv_anular_picking_virgilio");
}
if (/rpc\/anular_picking_virgilio/.test(src.replace(/rpc\/gv_anular_picking_virgilio/g, ""))) {
  fallas.push("todavía se llama a la RPC VIEJA rpc/anular_picking_virgilio — ésa pone en cero " +
    "todo el picking de la tanda sin filtrar por legajo");
}
if (!src.includes("ep_fantasma_limpiado")) {
  fallas.push("el front no contempla 'ep_fantasma_limpiado'");
} else {
  // el aviso tiene que decir que el stock NO se tocó
  const i = src.indexOf('r === "ep_fantasma_limpiado"');
  const bloque = i >= 0 ? src.slice(i, i + 500) : "";
  if (!/NO toqu|no se toc/i.test(bloque)) {
    fallas.push("el aviso de 'ep_fantasma_limpiado' no aclara que el stock NO se tocó");
  }
}

if (fallas.length) {
  console.log("anular-picking-fantasma: ✗ FAIL\n  - " + fallas.join("\n  - "));
  process.exit(1);
}
console.log("anular-picking-fantasma: RPC nueva · caso fantasma contemplado · avisa que no toca stock · ✓ OK");

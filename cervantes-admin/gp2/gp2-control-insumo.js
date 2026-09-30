/* gp2-control-insumo.js (GP2CI) — DÓNDE SE CONTROLA cada insumo recibido. UNA sola copia.
   ============================================================================================
   La recepción de un insumo tiene dos pasos: el remito (Recepción de Insumos) y el control físico.
   Flejes y cartones se controlan en la MISMA pantalla de Recepción (pesaje por pallet / conteo de
   paquetes); el resto de los rubros tiene su control en OTRA página, y es esta lista la que dice
   en cuál. Sumar un rubro al control por peso es agregar una línea acá.

   Por qué vive en un archivo propio (2026-09-30) [Nazareno: "Me gustaría que aparezca en el botón
   de control ... Tendrías que poner los de talleristas, p.s. y prov de insumo"]: hasta hoy la lista
   estaba escrita adentro de RecepcionInsumos_GP2.html y sólo se usaba para la redirección
   automática al guardar. Si el operario salía del control, la recepción quedaba sin controlar y
   NINGUNA pantalla lo llevaba de vuelta. Ahora la usan también el Control de la tablet
   (ControlEntregaPS_GP2.html) y el contador del botón "Control" de la Tablet; dos copias de la
   misma lista terminan diciendo cosas distintas.

   Las rutas son relativas a StockFlejes/ (donde viven las pantallas de control). Quien las usa
   desde otra carpeta les pone su prefijo (la Tablet: "../StockFlejes/"). */
(function (w) {
  "use strict";

  var POR_SECTOR = {
    11: "control-cajas.html",              // Cajas: base x pisos + sueltas
    8:  "control-remaches.html",           // Remaches: pesar (8 es el default de esa pantalla)
    6:  "control-remaches.html?sector=6",  // Plásticos: misma pantalla de peso, otro sector
    7:  "control-remaches.html?sector=7",  // Bombillas: idem [usuario 2026-09-03]
    9:  "control-remaches.html?sector=9",  // Garage: remito en uni, control en kg [usuario 2026-09-28]
    14: "control-remaches.html?sector=14"  // Bolsas plásticas: remito y control en kg [usuario 2026-09-28]
  };
  /* Proveedores que se controlan por peso aunque su SECTOR no: Importado vive en el Sector
     Procesado (2) junto a piezas de Eclipse y Charcas que tienen su propio pesaje, así que no
     puede entrar el sector entero [usuario 2026-09-28: "Remito en unidades y control en kg"]. */
  var POR_PROV = {
    "importado": "control-remaches.html?sector=2&prov=Importado"
  };
  /* Los flejes se controlan pesando pallets en la misma Recepción de Insumos, que al abrir ya
     muestra "⚖ Pesar ahora" con lo que quedó sin pesar. */
  var PESAJE = "RecepcionInsumos_GP2.html";

  /* it = {sector_id, proveedor} (un insumo del bundle o un grupo de control_entrega_bundle). */
  function urlDe(it) {
    if (!it) return null;
    return POR_SECTOR[it.sector_id] ||
           POR_PROV[String(it.proveedor || "").trim().toLowerCase()] ||
           null;
  }

  /* Los grupos de control_entrega_bundle.insumos_pend que tienen DÓNDE controlarse, con su url.
     Un grupo sin pantalla (hoy: cartones, o piezas del Sector Procesado de Eclipse/Charcas) no se
     devuelve: un botón que no lleva a ningún control es peor que no mostrarlo. */
  function pendientes(grupos) {
    return (grupos || []).map(function (g) {
      var url = g && g.via === "pesaje" ? PESAJE : urlDe(g);
      return url ? Object.assign({}, g, { url: url }) : null;
    }).filter(Boolean);
  }

  w.GP2CI = { POR_SECTOR: POR_SECTOR, POR_PROV: POR_PROV, PESAJE: PESAJE,
              urlDe: urlDe, pendientes: pendientes };
})(window);

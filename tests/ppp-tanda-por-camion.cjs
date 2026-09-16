/* La tanda de un cliente se parte por CAMIÓN (v18.87, pedido de Luis 2026-09-16).

   Luis: *"claro que se parte en zonas distintas (si un mismo cliente pide para una sucursal
   que tiene en Tucumán y otra en Río Negro, ¿lo pondrías en el mismo camión?). Se factura
   diferente también, es uno de los criterios justamente para parsear qué factura correspondía
   con qué pedido (la zona)."*

   El cambio vive entero en Supabase, así que lo que se puede verificar desde acá es el
   ARTEFACTO: que el archivo que lo describe siga en el repo y siga diciendo lo mismo que se
   aplicó. No reemplaza a la verificación real, que es el centinela de la base:

       select * from public.gv_ppp_tanda_camion_mezclado;   -- vacía = todo bien

   Lo que se cuida acá es lo que ya costó caro una vez: creer que el arreglo estaba en
   `gv_ppp_web_armar_pendientes` (a1) cuando la causa era `ppp_web_armar_tandas`, que agrupaba
   `group by cliente` y tomaba `min(camion)`. Si alguien borra ese bloque del archivo, se
   pierde la única explicación escrita de por qué D69F juntó Balvanera con Ciudadela.

   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");

const p = path.join(__dirname, "..", "sql", "gv_ppp_web_tanda_por_camion_v1887.sql");
const fallas = [];

if (!fs.existsSync(p)) {
  console.log("ppp-tanda-por-camion: ✗ FAIL\n  - falta sql/gv_ppp_web_tanda_por_camion_v1887.sql");
  process.exit(1);
}
const src = fs.readFileSync(p, "utf8");

// 1) los CUATRO lugares que asignaban tanda por cliente
[
  ["gv_ppp_web_tanda_abierta_cliente(\n  p_empresa text, p_cod text, p_fecha date, p_zona text\n)",
   "la base no recibe la zona"],
  ["drop function if exists public.gv_ppp_web_tanda_abierta_cliente(text, text, date)",
   "falta el DROP de la firma de 3 argumentos: un create or replace dejaría las dos y la vieja seguiría ganando"],
  ["gv_ppp_web_tanda_destino", "falta gv_ppp_web_tanda_destino (la tanda destino por NP)"],
  ["gv_ppp_web_juntar_clientes", "falta el candado 'un cliente, un día'"],
  ["gv_web_cliente_un_solo_dia", "falta el trigger"],
  ["ppp_web_armar_tandas", "falta el armador, que es donde estaba la causa real"],
  ["group by cliente, camion", "el armador no agrupa por (cliente, camión): el bug vuelve"],
].forEach(function (x) { if (src.indexOf(x[0]) < 0) fallas.push(x[1]); });

// 2) el corte es el CAMIÓN, no el número de zona (cortar por número fragmenta Capital:
//    una tanda de CABA mezcla Zona 1+2 a propósito y va en el mismo camión).
if (src.indexOf("gv_ppp_web_camion") < 0) fallas.push("el criterio no usa gv_ppp_web_camion (Capital / GBA Sur / GBA Oeste / GBA Norte)");

// 3) los reemplazos de texto van con guard: si el fragmento no aparece exactamente una vez,
//    aborta. Sin eso un cambio de la función de origen deja el parche a medias en silencio.
const guards = (src.match(/raise exception '[^']*No se toco nada|raise exception 'ppp_web_armar_tandas: el fragmento/g) || []).length;
if (guards < 2) fallas.push("los reemplazos de texto perdieron el guard de 'aparece exactamente 1 vez' (" + guards + ")");

// 4) el centinela
if (src.indexOf("gv_ppp_tanda_camion_mezclado") < 0) fallas.push("falta el centinela gv_ppp_tanda_camion_mezclado");

// 5) la convivencia con la regla de Thomas tiene que quedar escrita: el DÍA sigue siendo uno
//    solo por cliente, lo que se parte es la TANDA. Sin esa línea, la próxima sesión lee este
//    archivo y cree que se deshizo la regla del dueño.
if (src.indexOf("el DÍA sigue siendo uno solo por cliente") < 0) {
  fallas.push("no queda escrito que el día sigue siendo uno solo por cliente (regla de Thomas)");
}

if (fallas.length) {
  console.log("ppp-tanda-por-camion: ✗ FAIL\n  - " + fallas.join("\n  - "));
  process.exit(1);
}
console.log("ppp-tanda-por-camion: ✓ OK (los 4 lugares, corte por camión, guards y centinela)");

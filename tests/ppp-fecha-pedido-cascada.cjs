/* Regresión v20.92 — «F. pedido» DE LA PROGRAMACIÓN: LA CASCADA DEL LADO DE LA LECTURA.

   Thomas, 2026-09-22: *"¿Tiene la fecha que recibimos la NP?"*. La tenía, pero 14 de 183 NP
   programadas salían con «—» en la hoja y vacías en el Excel, porque
   `PPP_Web_Programacion.fecha_recep` estaba en NULL.

   La v20.63 arregló la RAÍZ (el armador persiste la fecha). Esto es el lado de la LECTURA y
   cubre lo que aquél no puede: las filas viejas que ya estaban sin fecha, y los otros cuatro
   caminos de escritura de la tabla. La cascada de `gv_ppp_prog_arbol`, rama `web`:
     1. PPP_Web_Programacion.fecha_recep
     2. lk_pedidos_match.fecha_pedido      (la fecha real del pedido de la página)
     3. PPP_Web_NP.creado_at a hora AR     (aproximación: el día en que se numeró la NP)

   Candados sobre `sql/gv_ppp_prog_arbol_fecha_pedido_v2092.sql`. Sale 1 si falla. */
const fs = require("fs");
const path = require("path");

const f = path.join(__dirname, "..", "sql", "gv_ppp_prog_arbol_fecha_pedido_v2092.sql");
const fallos = [];

if (!fs.existsSync(f)) {
  fallos.push("falta sql/gv_ppp_prog_arbol_fecha_pedido_v2092.sql");
} else {
  const s = fs.readFileSync(f, "utf8");

  if (!/coalesce\(w\.fecha_recep::date,/.test(s))
    fallos.push("la rama web dejó de arrancar por w.fecha_recep: la cascada se perdió");
  if (!/lk_pedidos_match lp[\s\S]{0,200}lp\.empresa = w\.empresa and lp\.order_id = w\.order_id/.test(s))
    fallos.push("falta el paso 2 (lk_pedidos_match) o cruza sin empresa — el código de pedido solo no alcanza");
  if (!/"PPP_Web_NP" n[\s\S]{0,200}n\.empresa = w\.empresa and n\.np = w\.np and n\.np_idx = w\.np_idx/.test(s))
    fallos.push("falta el paso 3 (PPP_Web_NP.creado_at) o no cruza por (empresa, np, np_idx)");
  if (!/creado_at at time zone 'America\/Argentina\/Buenos_Aires'/.test(s))
    fallos.push("el creado_at se lee en UTC: antes de las 21 h ART la fecha sale del día siguiente");

  // candado invertido: nunca un fallback inventado
  if (/coalesce\(w\.fecha_recep[\s\S]{0,400}current_date/.test(s))
    fallos.push("la cascada cae en current_date: eso anota el día en que se miró, no el del pedido");

  // el archivo tiene que ser la definición VIVA completa, no un parche por replace()
  if (!/CREATE OR REPLACE FUNCTION public\.gv_ppp_prog_arbol\(p_desde date, p_hasta date\)/.test(s))
    fallos.push("el archivo no trae el CREATE completo: el repo se queda sin la definición viva");
  if (!/security|SET search_path TO 'public', 'pg_temp'/.test(s))
    fallos.push("se perdió el SET search_path de la función");

  // no pisa el arreglo de raíz
  if (!/v20\.63/.test(s))
    fallos.push("el archivo no dice que la v20.63 es el arreglo de raíz: alguien va a creer que esto lo reemplaza");
}

if (fallos.length) {
  console.error("ppp-fecha-pedido-cascada: FALLA\n  - " + fallos.join("\n  - "));
  process.exit(1);
}
console.log("ppp-fecha-pedido-cascada: OK — la cascada de fecha_pedido sigue en pie");

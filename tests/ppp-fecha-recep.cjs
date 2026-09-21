/* Regresión v20.63 — LA FECHA DE RECEPCIÓN LA ESCRIBE EL ARMADOR.

   Thomas, 2026-09-21: *"los pedidos de chef del nuevo formato no tienen fecha de recepcion"*.
   Medido: eran 14 NP, 5 de Chef (order_id de 7 dígitos) y 9 de LK. La fecha viaja desde la
   página hasta `ppp_web_armar_tandas`, que la usa para ordenar la cola FIFO y NO la insertaba
   en `PPP_Web_Programacion`: quedaba a merced del trigger, que la busca en el cache
   `lk_pedidos_match` (que no tiene el pedido recién entrado, ni nunca los de 7 dígitos).

   Candados sobre `sql/gv_fecha_recep_armador_v2063.sql`, que es lo que se aplicó:
   - el armador persiste `s.fecha_recep_real` (la del pedido), no `s.fecha_recep`;
   - el `insert` nombra la columna;
   - el `on conflict` NO pisa una fecha que ya estaba;
   - el centinela existe y sale con `security_invoker`;
   - el UPDATE de las 14 filas viejas queda COMENTADO (protocolo: los datos no se tocan sin
     el sí del dueño).
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");

const f = path.join(__dirname, "..", "sql", "gv_fecha_recep_armador_v2063.sql");
const fallos = [];

if (!fs.existsSync(f)) {
  fallos.push("falta sql/gv_fecha_recep_armador_v2063.sql");
} else {
  const s = fs.readFileSync(f, "utf8");

  // la que se persiste es la del pedido, pelada
  if (!s.includes("s.fecha_recep_real, s.m3"))
    fallos.push("el insert del armador dejó de escribir s.fecha_recep_real: la fecha vuelve a depender del cache");
  if (!/tanda, zona, fecha_entrega, fecha_recep, m3/.test(s))
    fallos.push("la columna fecha_recep no está en la lista del insert");

  // candado invertido: NUNCA la que tiene fallback a hoy
  if (/v_fecha, s\.fecha_recep, s\.m3/.test(s))
    fallos.push("se persiste la fecha CON fallback a current_date: eso anota el día en que se programó");

  // una fecha que ya estaba no se pisa
  if (!s.includes('fecha_recep = coalesce(public."PPP_Web_Programacion".fecha_recep, excluded.fecha_recep)'))
    fallos.push("el on conflict pisa la fecha que ya estaba");

  // el centinela, y cerrado
  if (!/create or replace view public\.gv_ppp_sin_fecha_recep/.test(s))
    fallos.push("falta el centinela gv_ppp_sin_fecha_recep");
  if (!/alter view public\.gv_ppp_sin_fecha_recep set \(security_invoker = true\)/.test(s))
    fallos.push("el centinela quedó sin security_invoker: corre como postgres y saltea la RLS");

  // el parche no puede aplicarse a medias
  if (!/los anclajes no son unicos/.test(s))
    fallos.push("el parche perdió el guard de anclajes: puede aplicarse a medias sobre una definición cambiada");

  // los datos viejos NO se tocan sin permiso: el update va comentado
  const lineasUpdate = s.split("\n").filter((l) => /update public\."PPP_Web_Programacion"/.test(l));
  if (!lineasUpdate.length)
    fallos.push("falta el UPDATE propuesto para las filas viejas");
  if (lineasUpdate.some((l) => !/^\s*--/.test(l)))
    fallos.push("el UPDATE de las filas viejas NO está comentado: los datos no se tocan sin el sí del dueño");
}

if (fallos.length) { console.error("ppp-fecha-recep FALLA:\n - " + fallos.join("\n - ")); process.exit(1); }
console.log("ppp-fecha-recep OK — el armador persiste la fecha del pedido y no inventa la de hoy.");

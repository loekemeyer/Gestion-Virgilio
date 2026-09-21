/* Regresión v20.64 — DÍA SIN REPARTO: el depósito arma, el camión no sale.

   Luis, 2026-09-21: *"hace que la programacion automatica vea que el martes no se programa nada"*.

   Lo medido: la otra sesión vació el martes 22/09 a las 12:27 y **a las 12:45 el armador creó
   E12F para ese mismo día**. La puerta era `gv_ppp_web_dia_camion`, que devuelve el primer día
   que ya tiene camión a esa zona y a propósito no mira el día mínimo (v15.48). Por eso no
   alcanza con correr el piso: hay que decir que ese día NO HAY CAMIÓN.

   Cubre el archivo SQL (la regla) y el front (que el día se vea marcado). El centinela vivo es
   `select * from public.gv_dia_sin_reparto_ocupado;`. Sale 1 si falla. */
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const fallos = [];
const f = path.join(root, "sql", "gv_dia_sin_reparto_v2064.sql");
if (!fs.existsSync(f)) { console.error("FALTA " + f); process.exit(1); }

const sql = fs.readFileSync(f, "utf8");
const vivo = sql.split("\n").map((l) => l.replace(/--.*$/, "")).join("\n");

// 1) las dos preguntas son distintas y no se confunden
if (!/create or replace function public\.gv_es_dia_con_reparto/.test(vivo))
  fallos.push("falta gv_es_dia_con_reparto");
if (!/gv_es_dia_habil\(p_fecha\) and not public\.gv_es_dia_sin_reparto\(p_fecha\)/.test(vivo))
  fallos.push("gv_es_dia_con_reparto no es 'habil Y no sin_reparto'");
// el dia sin reparto NUNCA se carga como no habil: eso moveria el conteo de dias habiles de
// toda la operacion (la espera de cada pedido, los 10 dias del tope, la anticipacion minima).
if (/insert\s+into\s+public\."GV_Dias_No_Habiles"/i.test(vivo))
  fallos.push("el dia sin reparto se esta cargando en GV_Dias_No_Habiles: son dos cosas distintas");

// 2) el que dejaba entrar al pedido nuevo
const camion = (vivo.match(/create or replace function public\.gv_ppp_web_dia_camion[\s\S]*?\n  \$\$;/i) || [""])[0];
if (!camion) fallos.push("el archivo ya no reemplaza gv_ppp_web_dia_camion");
else {
  const n = (camion.match(/gv_es_dia_sin_reparto/g) || []).length;
  if (n < 2) fallos.push("gv_ppp_web_dia_camion tiene " + n + " guard(s) de dia sin reparto: faltan (web e ISIS son dos mitades)");
  if (!/gv_es_super/.test(camion)) fallos.push("gv_ppp_web_dia_camion perdio la regla del super (v18.60)");
}

// 3) la cascada de dias con cupo
const cupo = (vivo.match(/create or replace function public\.gv_ppp_web_proximo_dia_con_cupo[\s\S]*?\nend \$\$;/i) || [""])[0];
if (!cupo) fallos.push("el archivo ya no reemplaza gv_ppp_web_proximo_dia_con_cupo");
else if (!/if public\.gv_es_dia_con_reparto\(v_d\) then/.test(cupo))
  fallos.push("la cascada sigue preguntando por gv_es_dia_habil: no saltea el dia sin reparto");

// 4) el piso NO puede cambiar el conteo de dias habiles, solo el dia al que llega
const minimo = (vivo.match(/create or replace function public\.gv_ppp_web_dia_minimo[\s\S]*?\nend \$\$;/i) || [""])[0];
if (!minimo) fallos.push("el archivo ya no reemplaza gv_ppp_web_dia_minimo");
else {
  if (!/if public\.gv_es_dia_habil\(v_d\) then v_n := v_n - 1/.test(minimo))
    fallos.push("gv_ppp_web_dia_minimo cambio el CONTEO de dias habiles: el deposito trabaja igual, eso no se toca");
  if (!/while public\.gv_es_dia_sin_reparto\(v_d\)/.test(minimo))
    fallos.push("gv_ppp_web_dia_minimo puede terminar en un dia sin reparto");
}

// 5) RETIRA: el nuevo no se programa, el ya programado no se toca
const retiro = (vivo.match(/create or replace function public\.gv_web_retiro_pactado[\s\S]*?\n\$\$;/i) || [""])[0];
if (!retiro) fallos.push("el archivo ya no reemplaza gv_web_retiro_pactado");
else if (!/not public\.gv_es_dia_sin_reparto\(d\.f\)/.test(retiro))
  fallos.push("gv_web_retiro_pactado sigue programando Retira nuevos en un dia sin reparto");

// 6) el centinela mira las DOS mitades y saca lo que ya salio
const cent = (vivo.match(/create view public\.gv_dia_sin_reparto_ocupado[\s\S]*?;\n/i) || [""])[0];
if (!cent) fallos.push("falta el centinela gv_dia_sin_reparto_ocupado");
else {
  if (!/'web'::text as origen/.test(cent) || !/'isis'/.test(cent))
    fallos.push("el centinela mira una sola mitad: el dia cerrado se llena por los dos lados");
  if (!/salidos/.test(cent)) fallos.push("el centinela no saca lo que ya salio: esa fecha es historia, no un pendiente");
  if (!/retira/i.test(cent)) fallos.push("el centinela marca los Retira, y los Retira salen igual");
}
if (!/alter view public\.gv_dia_sin_reparto_ocupado set \(security_invoker = true\)/.test(vivo))
  fallos.push("el centinela quedo sin security_invoker");

// 7) las cuatro reglas en el centinela de reglas
["gv_ppp_web_dia_camion", "gv_ppp_web_proximo_dia_con_cupo", "gv_web_retiro_pactado", "gv_es_dia_con_reparto"]
  .forEach(function (o) {
    if (!new RegExp("'" + o + "','funcion'").test(vivo))
      fallos.push("falta la fila de GV_Reglas_Centinela para " + o);
  });

// 8) el front tiene que MOSTRAR el dia cerrado, o nadie entiende por que quedo vacio
const html = fs.readFileSync(path.join(root, "index.html"), "latin1");
if (!/function pgaSinRepNeed\(\)/.test(html)) fallos.push("el front no carga los dias sin reparto");
if (!/GV_Dias_Sin_Reparto\?select=fecha,motivo/.test(html)) fallos.push("el front no lee GV_Dias_Sin_Reparto");
if (!/\.pga-d\.sinrep>td\{/.test(html)) fallos.push("falta el CSS del dia sin reparto");
if (!/class="pga-sinrep"/.test(html)) fallos.push("falta el chip 'sin reparto' en la fila del dia");
if (!/sinRep !== null \? ' sinrep' : ''/.test(html)) fallos.push("la fila del dia no recibe la clase sinrep");

// 9) v20.83 — EL QUINTO QUE ELIGE FECHA. La v20.64 tapo los cuatro que CALCULAN el dia y dejo
//    afuera gv_ppp_web_dia_cliente, que no calcula: COPIA el dia que el cliente ya tiene. Con el
//    martes 22 cerrado a las 13:38, el armador de las 14:30 igual creo E12H (LK 0193, Pezzali)
//    para ese dia, por los pases (a1) y (a2), que son los unicos que eligen la fecha por ahi.
const f79 = path.join(root, "sql", "gv_dia_sin_reparto_quinta_puerta_v2083.sql");
if (!fs.existsSync(f79)) fallos.push("FALTA " + f79);
else {
  const q = fs.readFileSync(f79, "utf8");
  const qv = q.split("\n").map((l) => l.replace(/--.*$/, "")).join("\n");
  const dc = (qv.match(/create or replace function public\.gv_ppp_web_dia_cliente[\s\S]*?\$function\$;/i) || [""])[0];
  if (!dc) fallos.push("falta gv_ppp_web_dia_cliente en el archivo de la v20.83");
  else if (!/gv_es_dia_con_reparto/.test(dc))
    fallos.push("gv_ppp_web_dia_cliente volvio a copiar el dia sin mirar si sale el camion (el quinto que elige fecha)");
  // y el armado anulado: la fila de Entregas cuenta solo si es POSTERIOR a la anulacion
  const tth = (qv.match(/create or replace function public\.gv_tanda_trabajo_hecho[\s\S]*?\$function\$;/i) || [""])[0];
  if (!tth) fallos.push("falta gv_tanda_trabajo_hecho en el archivo de la v20.83");
  else if (!/GV_Tanda_Anulada/.test(tth) || !/anulado_en/.test(tth))
    fallos.push("un armado ANULADO vuelve a contar como armado: el guard frena una tanda con la pila en cero");
}

if (fallos.length) { console.error("FALLAS:\n - " + fallos.join("\n - ")); process.exit(1); }
console.log("OK ppp-dia-sin-reparto: el dia cerrado no recibe reparto (los CINCO que eligen fecha) y se ve marcado");

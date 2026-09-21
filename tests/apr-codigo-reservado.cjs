/* Regresión v20.60 — EL CÓDIGO DE UN PEDIDO RETENIDO QUEDA RESERVADO.

   Luis, 2026-09-21: *"el problema si vuelve con el codigo viejo es si se pisa con algun pedido
   que haya quedado dentro de la tanda con ese codigo y haya quilombo (como ya hubo)."*

   Medido ese día: `GV_PPP_Web_Retenido.tanda_previa` NO estaba entre las fuentes de
   `gv_tandas_codigos_usados_sync()`, así que al sacar el último pedido de una tanda su código
   desaparecía de todas las tablas vivas y volvía a la bolsa de códigos libres. E50A, E26B y E52A
   estaban las tres sueltas con un pedido esperando para volver ahí.

   Este test cuida el archivo SQL (el fuente de la regla). El centinela vivo es
   `select * from public.gv_reglas_perdidas;`. Sale 1 si falla. */
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const f = path.join(root, "sql", "gv_retenido_codigo_reservado_v2060.sql");
const fallos = [];

if (!fs.existsSync(f)) {
  console.error("FALTA " + f);
  process.exit(1);
}
const sql = fs.readFileSync(f, "utf8");

// el cuerpo sin comentarios: un `-- GV_PPP_Web_Retenido` no es un uso
const vivo = sql.split("\n").map((l) => l.replace(/--.*$/, "")).join("\n");

// 1) la 12.ª fuente del sync
const bloqueSync = (vivo.match(/create or replace function public\.gv_tandas_codigos_usados_sync[\s\S]*?\nend \$\$;/i) || [""])[0];
if (!bloqueSync) fallos.push("el archivo ya no reemplaza gv_tandas_codigos_usados_sync");
else if (!/'retenido'\s+from public\."GV_PPP_Web_Retenido"/.test(bloqueSync))
  fallos.push("el sync perdió la fuente 'retenido': el código de la tanda vuelve a la bolsa mientras su dueño lo espera");

// 2) el generador mira la reserva viva
const bloqueTomado = (vivo.match(/create or replace function public\.gv_ppp_web_codigo_tomado[\s\S]*?\n\$\$;/i) || [""])[0];
if (!bloqueTomado) fallos.push("el archivo ya no reemplaza gv_ppp_web_codigo_tomado");
else {
  if (!/"GV_PPP_Web_Retenido"/.test(bloqueTomado))
    fallos.push("gv_ppp_web_codigo_tomado no mira la reserva viva: hasta que corra el cron el código sale a la bolsa");
  if (!/"GV_Tandas_Codigos_Usados"/.test(bloqueTomado))
    fallos.push("gv_ppp_web_codigo_tomado perdió la memoria de códigos usados (v19.98)");
}

// 3) la vista pregunta por lo VIVO, no por la memoria — si no, la reserva bloquea a su propio dueño
const bloqueVista = (vivo.match(/create or replace view public\.gv_ppp_web_retenido[\s\S]*?;\n/i) || [""])[0];
if (!bloqueVista) fallos.push("el archivo ya no reemplaza la vista gv_ppp_web_retenido");
else {
  if (!/gv_ppp_web_codigo_vivo\(t\.tanda_previa, t\.empresa, t\.order_id\)/.test(bloqueVista))
    fallos.push("la vista no usa gv_ppp_web_codigo_vivo con el dueño: el pedido no podría volver nunca a su tanda");
  if (/gv_ppp_web_codigo_tomado/.test(bloqueVista))
    fallos.push("la vista volvió a preguntarle a la memoria: su propia reserva la bloquearía");
}

// 4) la función nueva existe, exime al dueño y no se come el índice de Movimientos_Stock
const bloqueVivo = (vivo.match(/create or replace function public\.gv_ppp_web_codigo_vivo[\s\S]*?\n\$\$;/i) || [""])[0];
if (!bloqueVivo) fallos.push("falta gv_ppp_web_codigo_vivo");
else {
  if (!/t\.empresa <> lower\(btrim\(p_empresa\)\) or t\.order_id <> p_order_id/.test(bloqueVivo))
    fallos.push("gv_ppp_web_codigo_vivo no exime la reserva del propio dueño");
  if (/upper\(btrim\(coalesce\(m\.ref/.test(bloqueVivo))
    fallos.push("Movimientos_Stock con coalesce: no entra por el índice de `ref` (0,1 ms -> 49 ms)");
}

// 5) la vista no puede quedar sin security_invoker
if (!/alter view public\.gv_ppp_web_retenido set \(security_invoker = true\)/.test(vivo))
  fallos.push("falta el `alter view ... security_invoker`: CREATE OR REPLACE VIEW borra las reloptions");

// 6) y las tres reglas tienen que quedar en el centinela
["gv_tandas_codigos_usados_sync", "gv_ppp_web_codigo_tomado", "gv_ppp_web_retenido"].forEach((o) => {
  if (!new RegExp("'" + o + "','(funcion|vista)'").test(vivo))
    fallos.push("falta la fila de GV_Reglas_Centinela para " + o);
});

if (fallos.length) {
  console.error("FALLAS:\n - " + fallos.join("\n - "));
  process.exit(1);
}
console.log("OK apr-codigo-reservado: la reserva del retenido ocupa el código y su dueño puede volver");

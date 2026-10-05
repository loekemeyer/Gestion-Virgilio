/* v26.74 (Luis, 05/10, D17; en la base los marcadores dicen v26.68 — llave, no cambiar): «que entre la parte de cada uno».
   El puntaje 1-10 de picking ya no deja afuera la tanda FRENADA: cada operario entra con SUS tramos
   (gv_picking_tanda_calc_frenada), el tramo del freno sin cola, y la ventana de PKC de un tramo no se
   solapa con la del vecino (si alguien retoma a los 2 min, el ±5 min contaba esas líneas dos veces).

   A) el SQL del repo trae las piezas (y el candado invertido: la exclusión de la v26.62 no vuelve)
   B) el pop-up del Mon. Admin marca la frenada con ⏸ y explica por qué (corre popPuntaje de admin.html)
   C) la TV no lleva nada de esto (el puntaje es sólo del admin) */
const fs = require("fs");
const path = require("path");
const ROOT = path.join(__dirname, "..");
const fallas = [];

/* ── A) SQL ─────────────────────────────────────────────────────────────── */
const sql = fs.readFileSync(path.join(ROOT, "sql/gv_picking_puntaje_frenada_v2674.sql"), "utf8");
for (const [marca, por] of [
  ["create or replace function public.gv_picking_tanda_calc_frenada(p_tanda text, p_legajo text)", "la función por tramos"],
  ["x.cola_min := 0; x.real_min := x.neto_sh", "el tramo del FRENO no lleva cola"],
  ["greatest(0, v_tail - v_ctope)", "la espera hasta el freno se topea como la cola"],
  ["v26.68-ventana", "la ventana de PKC sin solape"],
  ["perform set_config('gv.pkc_desde', '', true)", "la ventana se limpia después de cada tramo (no se filtra al resto del refresco)"],
  ["current_setting('gv.pkc_desde', true)", "gv_picking_tanda_calc lee la ventana fijada"],
  ["lag(e.ts_cliente) over w prev_tp, lead(e.ts_inicio) over w next_ep", "la frontera con el tramo vecino (de cualquier legajo)"],
  ["r := public.gv_picking_tanda_calc_frenada(t.tanda, t.leg);", "el refresco mide la frenada por tramos"],
  ["where opcion in ('TP','PKF')", "el refresco también mira el PKF"],
  ["where e.opcion in ('TP','PKF') and e.ts_cliente = t.tp", "el puntaje acepta el PKF del que frenó como cierre"],
  ["'frenada', g.cola_tipo = 'frenada'", "el detalle dice qué tanda es frenada"],
  ["volatile security definer", "calc_frenada es volatile (toca set_config)"],
]) if (!sql.includes(marca)) fallas.push("A) falta en el SQL: " + por + " («" + marca + "»)");
// candado invertido: el reemplazo del puntaje SACA la exclusión v26.62 (no la vuelve a escribir)
const reemplazo = sql.slice(sql.indexOf("-- 3) el puntaje"), sql.indexOf("-- 4) centinelas"));
const nuevo = reemplazo.split("$a$").filter((_, i) => i % 2 === 1)[1] || "";
if (/GV_Tanda_Freno/.test(nuevo)) fallas.push("A) el puntaje nuevo NO puede excluir las tandas de GV_Tanda_Freno (D17)");

/* ── B) pop-up del Mon. Admin ───────────────────────────────────────────── */
const adm = fs.readFileSync(path.join(ROOT, "monitor/admin.html"), "utf8");
const i0 = adm.indexOf("function popPuntaje("), i1 = adm.indexOf("function instrumentar()");
if (i0 < 0 || i1 < 0) fallas.push("B) no encuentro popPuntaje en admin.html");
else {
  const esc = (s) => String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;");
  const n1 = (x) => (Math.round((Number(x) || 0) * 10) / 10).toFixed(1).replace(".", ",");
  const t = (tanda, fr) => ({ tanda, fecha: "05/10", nivel: "Alta", grado: 7, lineas: 13, cajas: 40, paradas: 11, esc: 6, tamano: 20.3, real: 23.4, indice: 0.87, frenada: fr });
  const run = (det) => new Function("esc", "n1", "PUNT", "PUNT_ERR", adm.slice(i0, i1) + "; return popPuntaje('104');")(
    esc, n1, { "104": { nombre: "Isidro", tandas: 12, indice_ult: 1.1, puntaje_ult: 6, indice_per: 1.1, puntaje_per: 6, publicable: true, tramos: [1.1], detalle: det } }, "");
  const con = run([t("ZZ99Z", true), t("F13E", false)]);
  if (!con.includes("ZZ99Z ⏸")) fallas.push("B) la tanda frenada no lleva ⏸ en el pop-up");
  if (con.includes("F13E ⏸")) fallas.push("B) una tanda sin freno salió con ⏸");
  if (!con.includes("tanda frenada: entra sólo la parte que pickeó este operario")) fallas.push("B) falta la nota de la frenada");
  const sin = run([t("F13E", false)]);
  if (sin.includes("⏸") || sin.includes("tanda frenada")) fallas.push("B) sin frenadas no tiene que haber ⏸ ni nota");
}

/* ── C) la TV no lleva el puntaje ───────────────────────────────────────── */
const tv = fs.readFileSync(path.join(ROOT, "monitor/tv.html"), "utf8");
if (tv.includes("popPuntaje") || tv.includes("gv_picking_tanda_calc_frenada")) fallas.push("C) tv.html no puede llevar el puntaje de picking");

if (fallas.length) { console.log("puntaje-frenada: ✗ FAIL\n  - " + fallas.join("\n  - ")); process.exit(1); }
console.log("puntaje-frenada: ✓ OK (SQL por tramos y sin solape · ⏸ en el pop-up del admin · la TV sin puntaje)");

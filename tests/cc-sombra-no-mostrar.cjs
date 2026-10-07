// v27.89 (Luis, 07/10/2026): la cuenta corriente se valida en MODO SOMBRA y NO se muestra al cliente.
// Candado estatico sobre sql/gv_cc_sombra_v2789.sql: los parametros de la regla y que nada quede abierto a anon/authenticated.
const fs = require("fs");
const path = require("path");
const sql = fs.readFileSync(path.join(__dirname, "..", "sql", "gv_cc_sombra_v2789.sql"), "utf8")
  .replace(/--[^\n]*/g, "");
const fallas = [];
const exige = (cond, msg) => { if (!cond) fallas.push(msg); };
exige(/\('tolerancia',\s*1,/.test(sql), "tolerancia por cliente = $1");
exige(/\('racha_objetivo',\s*20,/.test(sql), "racha objetivo = 20 dias habiles");
exige(/\('planify_employee',\s*52,/.test(sql), "la tarea va al Planify de Luis (52)");
exige(/not exists \(select 1 from "GV_CC_Sombra_Aviso" where empresa = e\) then/.test(sql), "una sola tarea por empresa");
exige(!/grant\s+[^;]*\bto\s+(anon|authenticated|public)\b/i.test(sql), "nada se le abre a anon/authenticated/public");
for (const f of ["gv_cc_sombra_estimar", "gv_cc_sombra_racha", "gv_cc_sombra_tick"])
  exige(new RegExp("revoke execute on function public\\." + f + "\\([^)]*\\) from public, anon, authenticated").test(sql), "revoke de " + f);
exige(/enable row level security/.test(sql) && /revoke all on public\."GV_CC_Ancla"/.test(sql), "tablas con RLS y sin grants");
// v27.93 (Luis, 07/10): el cruce va por CORTE de datos y la racha suma los dias cubiertos por cruces OK
const sql2 = fs.readFileSync(path.join(__dirname, "..", "sql", "gv_cc_sombra_corte_v2793.sql"), "utf8").replace(/--[^\n]*/g, "");
exige(/d\.fecha > v_corte and d\.fecha <= p_corte_nuevo/.test(sql2), "lo posterior al Excel se mide por corte de datos, no por la hora de subida");
exige(/exit when not c\.ok/.test(sql2) && /gv_es_dia_habil/.test(sql2), "la racha suma dias habiles cubiertos y la corta solo un cruce con diferencia");
exige(!/grant\s+[^;]*\bto\s+(anon|authenticated|public)\b/i.test(sql2), "v27.93 no abre nada a anon/authenticated/public");
for (const f of ["gv_cc_sombra_corte", "gv_cc_sombra_estimar"])
  exige(new RegExp("revoke execute on function public\\." + f + "\\([^)]*\\) from public, anon, authenticated").test(sql2), "revoke de " + f + " (v27.93)");
if (fallas.length) { console.error("cc-sombra-no-mostrar: FALLA\n - " + fallas.join("\n - ")); process.exit(1); }
console.log("cc-sombra-no-mostrar: OK (" + 14 + " chequeos)");

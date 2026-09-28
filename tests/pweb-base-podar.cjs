// v23.00 (problema 578): las escrituras de la foto de picking web (PPP_Web_Base) tienen que
// PODAR lo que la NP ya no trae, no sólo sumar. Candado estático sobre los dos que viven en
// el repo (el tercero, gv_ppp_web_tanda_programar, tiene su fila en GV_Reglas_Centinela).
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
let fallas = 0;
function chk(nombre, cond) { console.log((cond ? "OK   " : "FALLA") + " " + nombre); if (!cond) fallas++; }

const idx = fs.readFileSync(path.join(root, "index.html"), "latin1");
const i0 = idx.indexOf("async function pppGuardarWeb(");
const cuerpo = i0 >= 0 ? idx.slice(i0, idx.indexOf("\n}\n", i0)) : "";
chk("pppGuardarWeb existe", i0 >= 0);
chk("pppGuardarWeb poda con gv_ppp_web_base_podar", /rpc\/gv_ppp_web_base_podar/.test(cuerpo));
chk("la poda va despues del upsert de PPP_Web_Base",
  cuerpo.indexOf("PPP_Web_Base?on_conflict") >= 0 &&
  cuerpo.indexOf("gv_ppp_web_base_podar") > cuerpo.indexOf("PPP_Web_Base?on_conflict"));

const ef = fs.readFileSync(path.join(root, "supabase/functions/gv-ppp-web-tandas-diarias/index.ts"), "utf8");
const up = ef.indexOf("PPP_Web_Base?on_conflict");
chk("la Edge Function poda despues del upsert", up >= 0 && ef.indexOf('"gv_ppp_web_base_podar"') > up);

const sql = fs.readFileSync(path.join(root, "sql/gv_ppp_web_base_podar_v2300.sql"), "utf8");
chk("la poda no toca una tanda empezada (legajo real)", /not in \('0','1'\)/.test(sql) && /not s\.empezada/.test(sql));
chk("lo borrado queda en GV_PPP_Web_Base_Podado", /insert into public\."GV_PPP_Web_Base_Podado"/.test(sql));

process.exit(fallas ? 1 : 0);

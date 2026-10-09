// v28.96 (Luis, 09/10): el Ingreso a racks (modo 📦 Importación) descuenta el pedido de importación en viaje.
// Candado estático sobre el SQL del repo (la regla vive en la base: racks_plani_ingreso → gv_imp_imputar_ingreso_racks).
const fs = require("fs");
const s = fs.readFileSync(__dirname + "/../sql/gv_imp_ingreso_racks_v2896.sql", "utf8").replace(/--[^\n]*/g, "");
const ok = [], ko = [];
function chk(n, c) { (c ? ok : ko).push(n); }
chk("racks_plani_ingreso llama a la imputación con el id del movimiento", /gv_imp_imputar_ingreso_racks\(v_mid/.test(s));
chk("la imputación nunca frena el ingreso (exception when others)", /perform public\.gv_imp_imputar_ingreso_racks\(v_mid[\s\S]*?exception when others/.test(s));
chk("suma lo llegado al bache", /unidades_llegadas = unidades_llegadas \+ v_uni/.test(s));
chk("no mueve stock (sin insert a Movimientos_Stock en la imputación)",
  !/gv_imp_imputar_ingreso_racks[\s\S]*?insert into public\."Movimientos_Stock"[\s\S]*?end \$f\$/.test(s));
chk("idempotente por movimiento", /'irmov_' \|\| p_mov_id/.test(s) && /client_id = v_cid/.test(s));
chk("bache con reingreso más próximo", /order by bb\.fecha_reingreso nulls last/.test(s));
chk("sin fila de destino (Anular no saca el stock del rack)", !/GV_Imp_Recepcion_Destino/.test(s));
chk("recalcula el pedido en curso", /gv_importados_resync_calc\(b\.importado_id\)/.test(s));
ok.forEach(n => console.log("  ✓ " + n));
ko.forEach(n => console.log("  ✗ " + n));
process.exit(ko.length ? 1 : 0);

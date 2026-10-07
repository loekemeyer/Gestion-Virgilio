// v25.61 (Luis, 01/10) — equivalencias importado <-> componente GP2 y stock NEGATIVO en importación.
// Candado estático: (a) el fetch pide stock_total_neto + stock_gp2 y los usa; (b) la pantalla no pone
// piso en 0 al stock (D12); (c) el desglose y la celda muestran lo de Cervantes; (d) el SQL está en el repo.
const fs = require("fs"), path = require("path");
const R = p => fs.readFileSync(path.join(__dirname, "..", p), "latin1");
const idx = R("index.html"), imp = fs.readFileSync(path.join(__dirname, "..", "importacion.js"), "utf8");
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log("  ✗", m); } else console.log("  ✓", m); };
ok(/stock_total,stock_gp2,stock_conv,stock_total_neto,(piezas_share,piezas_reparto,(piezas_grupo,)?)?pedido_curso/.test(idx), "a) el fetch de importados pide stock_gp2, stock_conv y stock_total_neto");
ok(/o\.stockUni - o\.stockIns - o\.stockGp2 - \(o\.stockConv \|\| 0\)/.test(idx), "a) el stock propio no cuenta dos veces lo convertible (v26.03)");
ok(/o\.stockUni \+= \(r\.stock_total_neto != null\)/.test(idx), "a) el stock usa stock_total_neto (sin piso, con GP2)");
ok(/stockGp2U: Math\.round\(o\.stockGp2\)/.test(idx), "a) el ítem lleva stockGp2U");
ok(/o\.stockUni - o\.stockIns - o\.stockGp2/.test(idx), "a) el stock propio no cuenta dos veces lo de GP2");
ok(!/Math\.max\(0, Number\(it\.stockUni\)/.test(imp), "b) ninguna cuenta de importación pone piso en 0 al stock");
ok(/🏭 Cervantes \(GP2\)/.test(imp) && /it\.stockGp2U > 0\) stockTxt/.test(imp), "c) desglose y celda muestran el stock de GP2");
const sql = R("sql/gv_importados_equiv_gp2_v2561.sql");
// v28.43 (Luis, 07/10): GRJ31 y la parte 323ES van 100 % al 838E (se retiran el 20/80 de la v25.61 y el pool de la v26.99)
const sql42 = fs.readFileSync(path.join(__dirname, "..", "sql", "gv_piezas_reparto_em_v2843.sql"), "utf8");
ok(/GRJ31 y la parte 323ES van 100 % al 838E/.test(sql42) && /838E ← GRJ31 \+ 838E \(GP2\) \+ 323ES \(parte\)/.test(sql42), "d) GRJ31: 100 % al 838E (v28.43)");
ok(/stock_total_neto/.test(sql) && /GV_Importados_Equiv_GP2/.test(sql), "d) la vista suma GP2 y expone el neto");
if (fails) { console.log("FALLA pedimp-equiv-gp2:", fails); process.exit(1); }
console.log("OK pedimp-equiv-gp2");

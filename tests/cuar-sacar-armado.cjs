// v28.45 (Luis, 07/10) — «🐊 Sacarlo a cuarentena» según la TANDA entera:
//   pendiente → pierde tanda y día · proceso → NO se puede · armada → sale SOLO con su armado a una
//   tanda nueva SIN DÍA (figura en A Programar con badge; v30.38: aprobado se programa SOLO si se puede, si no cartel y día a mano).
// Candado estático sobre index.html y el SQL (el backend se probó en transacción abortada).
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
const html = fs.readFileSync(path.join(root, "index.html"), "utf8");
const sql = fs.readFileSync(path.join(root, "sql/gv_cuarentena_sacar_armado_v2845.sql"), "utf8");
let fail = 0;
function ok(c, m) { if (!c) { fail++; console.log("✗ " + m); } else console.log("✓ " + m); }
function fn(name) {
  const i = html.indexOf("function " + name + "(");
  if (i < 0) return "";
  const j = html.indexOf("\nfunction ", i + 10), k = html.indexOf("\nasync function ", i + 10);
  const end = Math.min(j < 0 ? html.length : j, k < 0 ? html.length : k);
  return html.slice(i, end);
}
const cargar = html.slice(html.indexOf("const pChef = aprTraerPedidos(\"chef\");"), html.indexOf("const pChef = aprTraerPedidos(\"chef\");") + 4000);
ok(/gv_cuarentena_armado_lista/.test(cargar), "A Programar lee los pedidos sacados con su armado");
ok(/if \(!_apr\.cuarArm\[aprKey\(x\.empresa, x\.order_id\)\]\) fuera\.add/.test(cargar), "el pedido armado retenido NO cuenta como programado");
ok((cargar.match(/aprMarcarCuarArm\(_apr\.pedidosTodos\)/g) || []).length === 2, "se marca en LK+ISIS y otra vez cuando llega Chef");
ok((html.match(/aprCuarArmChip\(p\)/g) || []).length >= 2, "badge en A Programar y en Cuarentena");
const gen = fn("aprGenerarTanda");
ok(/_cArmSel/.test(gen) && /return aprCuarArmAsignar\(_cArmSel\[0\], fecha\)/.test(gen), "soltarlo en un día va por la tanda sin día, no arma tanda nueva");
ok(gen.indexOf("_cuarRet.length") < gen.indexOf("_cArmSel"), "sin aprobar sigue frenado por cuarentena antes de darle día");
ok(/gv_cuarentena_armado_asignar_dia/.test(fn("aprCuarArmAsignar")), "el día se asigna con gv_cuarentena_armado_asignar_dia");
ok(/gv_cuarentena_sacar_chequeo/.test(fn("cuarComAbrir")), "al sacar a cuarentena se mira la tanda entera");
ok(/s\.chk\.estado === "proceso"\)\) \? "disabled"/.test(html), "con la tanda en proceso el botón queda deshabilitado");
ok(/separá sus cajas del pallet/.test(fn("cuarSacarAvisoHtml")) && /No se imprime ningún papel/.test(fn("cuarSacarAvisoHtml")), "armada: avisa separar el pallet, sin papel");
const lib = fn("cuarLiberarConfirmar");
// v30.38 (Luis, 14/10): aprobado, el armado se programa SOLO si se puede; el cartel queda sólo para lo que no
ok(/p\._cuarArm/.test(lib) && /gv_cuarentena_armado_auto/.test(lib), "al aprobar un armado se intenta programar solo (gv_cuarentena_armado_auto)");
ok(/r_resultado === "programado"/.test(lib) && /window\.alert/.test(lib) && /no se pudo programar solo/.test(lib), "si no se pudo programar solo, salta el cartel de asignar a mano");
const sqlAuto = fs.readFileSync(path.join(root, "sql/gv_cuarentena_armado_auto_v3038.sql"), "utf8");
ok(/gv_ppp_web_dia_grupo/.test(sqlAuto) && /gv_cuarentena_liberados_familia/.test(sqlAuto) && /gv_es_super/.test(sqlAuto), "auto: día del armador, sólo aprobado, súper a mano");
ok(/cron\.schedule\('gv-cuarentena-armado-auto'/.test(sqlAuto), "auto: cron de respaldo cada 10 min");
ok(!/window\.print|remitoPrintDoc|gvImprimirAuto/.test(fn("cuarDevolverConfirmar") + fn("cuarSacarAvisoHtml") + fn("aprCuarArmAsignar")), "no se imprime ningún papel de cuarentena");
ok(/EN_PROCESO/.test(sql) && /gv_ppp_espera_fecha\(\)/.test(sql) && /gv_ppp_web_desprogramar/.test(sql), "devolver: proceso frena, armado sin día, pendiente como siempre");
ok(/gv_cuarentena_liberados_familia/.test(sql), "el día se asigna sólo aprobado");
// v30.41 (Luis D2): el aprobado que pasó más de ventana_dias en cuarentena vuelve al feed del armador
const edge = fs.readFileSync(path.join(root, "supabase/functions/gv-ppp-web-tandas-diarias/index.ts"), "utf8");
ok(/gv_cuarentena_liberados_viejos/.test(edge) && (edge.match(/await traerLkConViejos\(desde, ventana\)/g) || []).length === 3 &&
   (edge.match(/await traerChefConViejos\(ventana\)/g) || []).length === 3, "el armador suma los aprobados viejos en los 3 caminos (dry, intradía, normal)");
ok(/finally \{ _tdfParaChef = tdf; \}/.test(edge), "la segunda lectura de LK no pisa los pedidos de TdF de Chef");
const sqlExc = fs.readFileSync(path.join(root, "sql/gv_cuarentena_ventana_exc_v3044.sql"), "utf8");
ok(/from public\."GV_Cuarentena_Ventana_Exc" x/.test(sqlExc) && /after insert on public\."GV_Cuarentena_Log"/.test(sqlExc),
   "la excepción de ventana es sólo la foto del 14/10 + lo que entra a cuarentena desde ahí (sin basura vieja)");
process.exit(fail ? 1 : 0);

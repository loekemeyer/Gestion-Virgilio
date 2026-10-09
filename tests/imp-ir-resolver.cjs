// v29.11 (Luis, 09/10): el operario NO elige el pedido al recibir importación por Ingreso a racks; se resuelve
// en Importación → 📥 Recibido. Candado sobre el SQL + corre la pantalla con la RPC mockeada.
const fs = require("fs"), vm = require("vm");
const ok = [], ko = [];
function chk(n, c) { (c ? ok : ko).push(n); }
const sql = fs.readFileSync(__dirname + "/../sql/gv_imp_ir_resolver_v2913.sql", "utf8").replace(/--[^\n]*/g, "");
chk("SQL: con 2+ pedidos en viaje queda a elegir (no descuenta)", /if v_ncand > 1 then[\s\S]*?'a_elegir'[\s\S]*?return/.test(sql));
chk("SQL: el pedido elegido entra por gv.ir_bache", /current_setting\('gv\.ir_bache', true\)/.test(sql) && /set_config\('gv\.ir_bache', p_bache_id::text, true\)/.test(sql));
chk("SQL: cambiar de pedido devuelve lo llegado al anterior", /unidades_llegadas = greatest\(0, unidades_llegadas - r\.unidades::int\)/.test(sql));
chk("SQL: la recepción vieja libera su client_id", /client_id = client_id \|\| '~x' \|\| id/.test(sql));
chk("SQL: asignar y avisos son de supervisor", /gv_imp_ir_asignar[\s\S]*?es_supervisor_virgilio/.test(sql) && /gv_imp_ir_avisos[\s\S]*?es_supervisor_virgilio/.test(sql));
chk("SQL: no mueve stock", !/insert into public\."Movimientos_Stock"/.test(sql));
const js = fs.readFileSync(__dirname + "/../importacion.js", "utf8");
chk("JS: las 3 RPC van con la sesión", /"gv_imp_ir_avisos", "gv_imp_ir_asignar", "gv_imp_ir_visto"\]/.test(js));
const idx = fs.readFileSync(__dirname + "/../index.html", "latin1");
chk("panel: badge impIrBadge en Importación", /id="impIrBadge"/.test(idx) && /impIrLoadBadge\(\)/.test(idx));
// corre la pantalla
const html = { v: "" };
const el = { set innerHTML(v) { html.v = v; }, get innerHTML() { return html.v; }, style: {}, textContent: "" };
const calls = [];
const rows = [
  { mov_id: 1, ts: "2026-10-09T13:00:00Z", cod: "404E", cajas: 10, unidades: null, sector: "Y30", legajo: "104", operario: "Jhonny", resultado: "a_elegir", pendiente: true,
    candidatos: [{ bache_id: 131, pedido_ref: "PI B260601-2", proveedor: "Becky", unidades: 896, llegadas: 0 }, { bache_id: 999, pedido_ref: "PI X", unidades: 500, llegadas: 0 }] },
  { mov_id: 2, ts: "2026-10-09T12:00:00Z", cod: "958E", cajas: 260, unidades: 3120, sector: "Y02", legajo: "104", resultado: "imputado", bache_id: 54, pedido_ref: "PI B260601", proveedor: "Becky", pendiente: true, candidatos: [{ bache_id: 54, pedido_ref: "PI B260601", unidades: 2880, llegadas: 3120, actual: true }] },
  { mov_id: 3, ts: "2026-10-08T12:00:00Z", cod: "932E", cajas: 144, unidades: 1728, resultado: "imputado", pendiente: false, revisado_en: "2026-10-09T10:00:00Z", candidatos: [] }
];
const ctx = {
  console, Date, Math, Number, String, Array, JSON, Promise, isNaN, alert: () => {}, confirm: () => true,
  document: { getElementById: () => el, querySelector: () => null, addEventListener: () => {} },
  window: {}, localStorage: { getItem: () => null, setItem: () => {} },
  escapeHtml: s => String(s == null ? "" : s), _stkPopShell: () => {}, setTimeout: () => {},
};
vm.createContext(ctx);
try { vm.runInContext(js, ctx); } catch (e) { /* el archivo trae más cosas; alcanza con que defina las funciones */ }
ctx._pedImpRpc = async (fn, body) => { calls.push([fn, body]); if (fn === "gv_imp_ir_avisos") return rows; return { ok: true }; };
ctx.pedImpReload = () => {};
(async () => {
  try {
    await vm.runInContext("openImpRecibidoOp()", ctx);
    const h = html.v;
    chk("pantalla: muestra la solapa 📥 Recibido con el badge", /📥 Recibido/.test(h) && /2<\/span>/.test(h));
    chk("pantalla: el renglón a elegir dice ⚠ elegir pedido", /⚠ elegir pedido/.test(h));
    chk("pantalla: ofrece los dos pedidos en viaje", /PI B260601-2/.test(h) && /PI X/.test(h));
    chk("pantalla: lo revisado no se ve por defecto", !/932E/.test(h));
    vm.runInContext("impIrSel('1','131')", ctx);
    await vm.runInContext("impIrGuardar('1')", ctx);
    const a = calls.filter(c => c[0] === "gv_imp_ir_asignar")[0];
    chk("pantalla: ↔ manda el pedido elegido", a && a[1].p_mov_id === 1 && a[1].p_bache_id === 131);
  } catch (e) { ko.push("pantalla: " + e.message); }
  ok.forEach(n => console.log("  ✓ " + n));
  ko.forEach(n => console.log("  ✗ " + n));
  process.exit(ko.length ? 1 : 0);
})();

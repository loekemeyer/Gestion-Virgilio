// v30.76 (Luis, 14/10): la col H (sucursal) del Excel ISIS sale del PADRÓN VIVO, no de la etiqueta
// con la que entró el pedido. Caso 4142 Poy Ignacio: «Poy Ignacio — ROJAS» → «General Paz 215 - Rojas».
// Corre _facXlsSucViva de verdad con fetch simulado y mira que _facXlsArmar use su resultado.
const fs = require("fs"), vm = require("vm");
const src = Buffer.from(fs.readFileSync(__dirname + "/../index.html", "latin1"), "latin1").toString("utf8");
let fallos = 0; const ok = (c, m) => { console.log((c ? "OK  " : "FAIL") + " " + m); if (!c) fallos++; };
const i = src.indexOf("async function _facXlsSucViva(");
ok(i > 0, "existe _facXlsSucViva");
const fn = src.slice(i, src.indexOf("\n}\n", i) + 2);
async function correr(conSesion, falla) {
  const ctx = { llamadas: [], SUPABASE_URL: "https://x", SUPABASE_KEY: "k", JSON, String, setTimeout: () => 0, clearTimeout() {} };
  ctx.facNpEsWeb = (np) => /^\s*(LK|CH)\s/i.test(String(np));
  ctx._facNpKey = (np) => String(np).trim().toUpperCase();
  ctx.facAuthWriteHeaders = async () => (conSesion ? { Authorization: "Bearer s", "Content-Type": "application/json" } : null);
  ctx.fetch = async (url, o) => {
    ctx.llamadas.push(url);
    if (falla) throw new Error("sin red");
    if (/gv_fac_xls_sucursal/.test(url)) {
      ctx.body = JSON.parse(o.body);
      return { ok: true, json: async () => [
        { np: "LK 0367", sucursal: "General Paz 215 - Rojas", como: "padron" },
        { np: "LK 0097", sucursal: null, como: "ambiguo" }] };
    }
    return { ok: true, json: async () => ({ ok: true }) };
  };
  vm.createContext(ctx); vm.runInContext(fn + "\nthis._run = _facXlsSucViva;", ctx);
  const r = await ctx._run(["LK 0367", "LK 0097", "4321"]);
  return { r, ctx };
}
(async () => {
  let { r, ctx } = await correr(true, false);
  ok(ctx.llamadas[0].endsWith("/functions/v1/gv-sync-padron-direcciones"), "primero refresca el padrón (LK + Chef)");
  ok(ctx.llamadas[1].endsWith("/rest/v1/rpc/gv_fac_xls_sucursal"), "después pide la sucursal por RPC");
  ok(JSON.stringify(ctx.body.p_nps) === '["LK 0367","LK 0097"]', "sólo manda las NP web (la de ISIS no)");
  ok(r["LK 0367"].suc === "General Paz 215 - Rojas", "LK 0367 → la etiqueta del padrón");
  ok(r["LK 0097"].suc === "", "ambiguo → vacío (no adivina)");
  ({ r, ctx } = await correr(false, false));
  ok(ctx.llamadas.length === 1 && /gv_fac_xls_sucursal/.test(ctx.llamadas[0]), "sin sesión no dispara la sync pero igual resuelve");
  ({ r } = await correr(true, true));
  ok(Object.keys(r).length === 0, "sin red: no rompe, queda la etiqueta del pedido");
  const a = src.indexOf("async function _facXlsArmar(");
  const body = src.slice(a, src.indexOf("\nfunction _facXlsDescargar(", a));
  ok(/_facXlsSucViva\(nps\)/.test(body), "_facXlsArmar pide el padrón vivo");
  ok(/if \(_viva && _viva\.suc\) suc = _viva\.suc;/.test(body), "el padrón vivo pisa la etiqueta del pedido");
  ok(/\/\\s—\\s\/\.test\(suc\)\) \{ sucSinDir\.push\(np\); suc = ""; \}/.test(body), "«Razón — X» sin padrón → vacío y aviso");
  ok(body.indexOf("_viva.suc") < body.indexOf("out.push({"), "se resuelve antes de armar la fila");
  const sql = fs.readFileSync(__dirname + "/../sql/gv_fac_xls_sucursal_v3076.sql", "utf8");
  ok(/security definer/i.test(sql) && /gv_destino_score/.test(sql) && /grant execute .* to anon/i.test(sql), "SQL: security definer, mismo puntaje que el destino, anon puede ejecutar");
  process.exit(fallos ? 1 : 0);
})();

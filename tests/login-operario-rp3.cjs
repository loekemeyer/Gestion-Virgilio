/* v31.78 (Luis, 16/10) — DESDE EL SÁB 17/10 00:01 EL CÓDIGO DE LA TV NO ABRE GESTIÓN: «Login Operario» → RP3.0.
   Pedido: *"el login con ingreso por Código TV quiero que el sábado 17 a las 00:01 deje de aparecer en la landing
   (quede inusable) y lo reemplace un botón que sea Login Operario que vincule a la página de RP3.0"*.
   Se chequea, corriendo la pantalla:
     (a) antes del corte: se ve el código de la TV y no el botón;
     (b) después del corte: el código desaparece, aparece «Login Operario» y loginConClaveTv() no llama al servidor;
     (c) el botón lleva a https://rp.loeke-erp.com/;
     (d) la pantalla abierta antes del corte cambia sola (re-chequeo) y un «migrado» del servidor también la cambia;
     (e) el corte por defecto es 2026-10-17 00:01 (-03) y el servidor también corta (sql).
   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
let fail = 0;
const ok = (c, m) => { console.log((c ? "✓ " : "✗ ") + m); if (!c) fail++; };
const URL_IDX = "file://" + path.join(__dirname, "..", "index.html");
(async () => {
  const b = await chromium.launch();
  const vis = (p, id) => p.evaluate((id) => { const e = document.getElementById(id); return !!e && getComputedStyle(e).display !== "none" && e.offsetParent !== null; }, id);

  async function pagina(corte, validar) {
    const p = await b.newPage({ viewport: { width: 400, height: 800 } });
    const llamadas = [];
    await p.addInitScript((c) => { window.GV_CLAVE_TV_CORTE_TS = c; }, corte);
    await p.route("**/rest/v1/**", (r) => {
      const u = r.request().url();
      if (/rpc\/gv_tv_clave_validar/.test(u)) { llamadas.push(u); return r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(validar || { ok: false }) }); }
      return r.abort();
    });
    await p.route("https://rp.loeke-erp.com/**", (r) => r.fulfill({ status: 200, contentType: "text/html", body: "<title>RP3</title>RP3.0" }));
    await p.goto(URL_IDX, { waitUntil: "domcontentloaded" });
    await p.waitForTimeout(300);
    return { p, llamadas };
  }

  // (a) antes
  const A = await pagina(8e15);
  ok(await vis(A.p, "tvClaveInput") && !(await vis(A.p, "loginOperarioRp")), "(a) antes del corte: código de la TV visible, sin botón");
  // (d) un «migrado» del servidor cambia la pantalla
  await A.p.unroute("**/rest/v1/**");
  await A.p.route("**/rest/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ ok: false, error: "migrado" }) }));
  await A.p.evaluate(async () => { document.getElementById("tvClaveInput").value = "1234"; await window.loginConClaveTv(); });
  ok(!(await vis(A.p, "tvClaveInput")) && await vis(A.p, "loginOperarioRp"), "(d) «migrado» del servidor (index viejo) → botón Login Operario");

  // (b) después
  const B = await pagina(0);
  ok(!(await vis(B.p, "tvClaveInput")) && !(await vis(B.p, "legajoLoginRow")), "(b) después del corte: el código de la TV no aparece");
  const txt = await B.p.evaluate(() => (document.getElementById("loginOperarioRp") || {}).textContent || "");
  ok(await vis(B.p, "loginOperarioRp") && /Login Operario/.test(txt), "(b) aparece «Login Operario»");
  await B.p.evaluate(async () => { document.getElementById("tvClaveInput").value = "1234"; await window.loginConClaveTv(); await window.loginConNombre(); await window.loginConLegajoTv(); });
  const ses = await B.p.evaluate(() => localStorage.getItem("vir_legajo_auth"));
  ok(B.llamadas.length === 0 && !ses, "(b) inusable: no valida contra el servidor ni deja sesión");
  // (c) navega a RP3.0
  await Promise.all([B.p.waitForURL(/rp\.loeke-erp\.com/, { timeout: 5000 }).catch(() => {}), B.p.click("#loginOperarioRp")]);
  ok(/^https:\/\/rp\.loeke-erp\.com\//.test(B.p.url()), "(c) el botón lleva a RP3.0: " + B.p.url());

  // (d) pantalla abierta antes del corte cambia sola
  const D = await pagina(8e15);
  await D.p.evaluate(() => { window.GV_CLAVE_TV_CORTE_TS = Date.now() - 1; });
  await D.p.waitForFunction(() => getComputedStyle(document.getElementById("loginOperarioRp")).display !== "none", null, { timeout: 35000 }).catch(() => {});
  ok(await vis(D.p, "loginOperarioRp") && !(await vis(D.p, "tvClaveInput")), "(d) la pantalla abierta cambia sola al pasar el corte");

  // (e) fechas
  const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
  ok(html.indexOf('Date.parse("2026-10-17T00:01:00-03:00")') >= 0, "(e) corte del front: 17/10/2026 00:01 (-03)");
  const sql = fs.readFileSync(path.join(__dirname, "..", "sql", "gv_login_operario_rp3_v3178.sql"), "utf8");
  ok(/timestamptz '2026-10-17 00:01:00-03'/.test(sql) && /'migrado'/.test(sql), "(e) corte del servidor en gv_tv_clave_validar");

  await b.close();
  if (fail) { console.error("\n" + fail + " chequeo(s) fallaron."); process.exit(1); }
  console.log("\nOK — Login Operario → RP3.0.");
})().catch((e) => { console.error(e); process.exit(1); });

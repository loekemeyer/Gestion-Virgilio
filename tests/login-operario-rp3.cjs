/* v31.78 (Luis, 16/10) — DESDE EL SÁB 17/10 00:01 EL CÓDIGO DE LA TV NO ABRE GESTIÓN: «Login Operario» → RP3.0.
   Pedido: *"el login con ingreso por Código TV quiero que el sábado 17 a las 00:01 deje de aparecer en la landing
   (quede inusable) y lo reemplace un botón que sea Login Operario que vincule a la página de RP3.0"*.
   Se chequea, corriendo la pantalla:
     (a) antes del corte: se ve el código de la TV y no el botón;
     (b) después del corte: el código desaparece, aparece «Login Operario» y loginConClaveTv() no llama al servidor;
     (c) el botón lleva a https://rp.loeke-erp.com/;
     (d) la pantalla abierta antes del corte cambia sola (re-chequeo) y un «migrado» del servidor también la cambia;
     (e) el corte por defecto es 2026-10-17 00:01 (-03) y el servidor también corta (sql);
     (f) v31.84: la sesión de operario abierta al corte manda la cola y recién ahí se cierra;
     (g) v31.84: con una tarea abierta no se inventa nada: pide «Terminar Día».
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

  // (f) sesión de operario abierta al corte, sin tareas: manda la cola y RECIÉN AHÍ cierra la sesión
  async function operario(abiertas) {
    const p = await b.newPage({ viewport: { width: 400, height: 800 } });
    const st = { srvOk: false, recibidos: [] };
    await p.addInitScript(() => { window.GV_CLAVE_TV_CORTE_TS = 8e15; });
    await p.route("**/rest/v1/**", (r) => {
      const u = r.request().url();
      if (/Registros_Produccion_Virgilio/.test(u) && r.request().method() === "POST") {
        if (!st.srvOk) return r.fulfill({ status: 503, body: "" });
        try { st.recibidos.push(JSON.parse(r.request().postData() || "{}").client_id); } catch (_e) {}
        return r.fulfill({ status: 201, body: "" });
      }
      return r.fulfill({ status: 200, contentType: "application/json", body: "[]" });
    });
    await p.goto(URL_IDX, { waitUntil: "domcontentloaded" });
    await p.waitForTimeout(300);
    await p.evaluate((abiertas) => {
      localStorage.removeItem("legajo_queue_virgilio_v1");
      window.tvElegirOperario({ legajo: "104", nombre: "J. Colombia" });
      if (abiertas) { const s = getLegajoState("104") || {}; s.toggles = Object.assign({}, s.toggles, { CR: new Date().toISOString() }); setLegajoState("104", s); }
      _enqueueReportRaw({ id: "corte-t1", legajo: "104", opcion: "CR", descripcion: "prueba", texto: "", ts: Date.now() });
    }, abiertas);
    await p.waitForTimeout(500);
    return { p, st };
  }
  const F = await operario(false);
  const colaAntes = await F.p.evaluate(() => readQueue().length);
  await F.p.evaluate(() => { window.GV_CLAVE_TV_CORTE_TS = 0; window.gvAplicarCorteClaveTv(); });
  await F.p.waitForTimeout(800);
  const mientras = await F.p.evaluate(() => ({ ses: !!localStorage.getItem("vir_legajo_auth"), ov: (document.getElementById("gvCorteOverlay") || {}).textContent || "" }));
  ok(colaAntes === 1 && mientras.ses && /pendiente|señal/.test(mientras.ov), "(f) con la cola sin salir, la sesión NO se cierra y avisa: " + mientras.ov.slice(0, 60));
  F.st.srvOk = true;
  await F.p.waitForFunction(() => !localStorage.getItem("vir_legajo_auth"), null, { timeout: 15000 }).catch(() => {});
  const despues = await F.p.evaluate(() => ({ ses: !!localStorage.getItem("vir_legajo_auth"), cola: readQueue().length }));
  ok(F.st.recibidos.indexOf("corte-t1") >= 0 && despues.cola === 0 && !despues.ses, "(f) mandó lo pendiente y después cerró la sesión");
  ok(await vis(F.p, "loginOperarioRp"), "(f) queda en el ingreso con «Login Operario»");

  // (g) con una tarea abierta: no inventa cierres, pide Terminar Día y la sesión sigue
  const G = await operario(true);
  G.st.srvOk = true;
  await G.p.evaluate(() => { window.GV_CLAVE_TV_CORTE_TS = 0; window.gvAplicarCorteClaveTv(); });
  await G.p.waitForTimeout(800);
  const g = await G.p.evaluate(() => ({ ses: !!localStorage.getItem("vir_legajo_auth"), ov: (document.getElementById("gvCorteOverlay") || {}).textContent || "", tog: Object.keys((getLegajoState("104") || {}).toggles || {}) }));
  ok(g.ses && /Terminar Día/.test(g.ov) && g.tog.indexOf("CR") >= 0, "(g) tarea abierta → pide Terminar Día, no cierra nada solo");
  await G.p.click("#gvCorteBtn");
  const tdVis = await G.p.evaluate(() => document.getElementById("terminarDiaModal").classList.contains("show"));
  ok(tdVis, "(g) el botón abre el Terminar Día de siempre");

  // (e) fechas
  const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
  ok(html.indexOf('Date.parse("2026-10-17T00:01:00-03:00")') >= 0, "(e) corte del front: 17/10/2026 00:01 (-03)");
  const sql = fs.readFileSync(path.join(__dirname, "..", "sql", "gv_login_operario_rp3_v3178.sql"), "utf8");
  ok(/timestamptz '2026-10-17 00:01:00-03'/.test(sql) && /'migrado'/.test(sql), "(e) corte del servidor en gv_tv_clave_validar");

  await b.close();
  if (fail) { console.error("\n" + fail + " chequeo(s) fallaron."); process.exit(1); }
  console.log("\nOK — Login Operario → RP3.0.");
})().catch((e) => { console.error(e); process.exit(1); });

/* v23.82 (Luis, 29/09) — CLAVE DE LA TV PARA ENTRAR COMO OPERARIO.
   Pedido: *"en el monitor de tv … aparezca chiquito una clave de 4 digitos. Quiero que los operarios
   pongan esa clave y despues elijan su nombre o pongan + si no estan y aparezca para elegir por legajo"*.
   Se chequea, corriendo la pantalla (RPC mockeadas):
     (a) la TV (monitor/tv.html) pide gv_tv_clave_actual y muestra la clave;
     (b) en el celular, una clave incorrecta NO deja pasar;
     (c) la clave correcta muestra la lista de nombres y tocar uno entra con ese legajo;
     (d) «+ No estoy en la lista» muestra el legajo; y el legajo sin clave NO entra.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
let fail = 0;
const ok = (c, m) => { console.log((c ? "✓ " : "✗ ") + m); if (!c) fail++; };
const CLAVE = "4821";
const OPS = [{ legajo: "104", nombre: "Jhonny Cartaya" }, { legajo: "77", nombre: "Juan Perez" }];
(async () => {
  const b = await chromium.launch();

  // (a) TV
  const tv = await b.newPage({ viewport: { width: 1920, height: 1080 } });
  let pidioClave = false;
  await tv.route("**/rest/v1/**", (r) => {
    if (/rpc\/gv_tv_clave_actual/.test(r.request().url())) {
      pidioClave = true;
      return r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ clave: CLAVE, cambia_en_s: 500 }) });
    }
    return r.fulfill({ status: 200, contentType: "application/json", body: "[]" });
  });
  await tv.goto("file://" + path.join(__dirname, "..", "monitor", "tv.html") + "?key=tv", { waitUntil: "domcontentloaded" });
  await tv.waitForFunction((c) => { const e = document.getElementById("tvClave"); return e && e.textContent.indexOf(c) >= 0; }, CLAVE, { timeout: 8000 }).catch(() => {});
  const txtTv = await tv.evaluate(() => (document.getElementById("tvClave") || {}).textContent || "");
  ok(pidioClave && txtTv.indexOf(CLAVE) >= 0, "(a) la TV muestra la clave (" + txtTv + ")");

  // (b)-(d) celular
  const p = await b.newPage({ viewport: { width: 400, height: 800 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => {
    const u = r.request().url();
    if (/rpc\/gv_tv_clave_validar/.test(u)) {
      const body = JSON.parse(r.request().postData() || "{}");
      const j = body.p_clave === CLAVE ? { ok: true, operarios: OPS } : { ok: false };
      return r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(j) });
    }
    if (/Empleados\?/.test(u)) return r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify([{ Legajo: "300", Empleado: "Nuevo Operario" }]) });
    return r.abort();
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const res = await p.evaluate(async (CLAVE) => {
    const out = {};
    const ses = () => { try { const o = JSON.parse(localStorage.getItem("vir_legajo_auth") || "null"); return o && o.legajo ? o : null; } catch (_e) { return null; } };
    localStorage.removeItem("vir_legajo_auth");
    const err = () => (document.getElementById("legajoLoginError") || {}).textContent || "";
    const vis = (id) => { const e = document.getElementById(id); return !!e && !e.classList.contains("hidden"); };
    // (d-bis) legajo sin clave
    document.getElementById("legajoLoginInput").value = "300";
    await window.loginWithLegajo();
    out.sinClave = { entro: !!ses(), err: err() };
    // (b) clave mala
    document.getElementById("tvClaveInput").value = "0000";
    await window.loginConClaveTv();
    out.mala = { lista: vis("tvNombreStep"), err: err() };
    // (c) clave buena
    document.getElementById("tvClaveInput").value = CLAVE;
    await window.loginConClaveTv();
    const btns = Array.from(document.querySelectorAll("#tvNombreLista button")).map((x) => x.textContent);
    out.buena = { lista: vis("tvNombreStep"), btns: btns };
    // (d) «+»
    window.tvMostrarLegajo();
    out.mas = { legajo: vis("tvLegajoStep"), lista: vis("tvNombreStep") };
    document.getElementById("legajoLoginInput").value = "300";
    await window.loginWithLegajo();
    out.porLegajo = ses();
    localStorage.removeItem("vir_legajo_auth");
    // (c) elegir nombre
    window.tvElegirOperario({ legajo: "104", nombre: "Jhonny Cartaya" });
    out.porNombre = ses();
    out.sesion = localStorage.getItem("vir_legajo_auth");
    return out;
  }, CLAVE);
  ok(!res.sinClave.entro && /clave/i.test(res.sinClave.err), "(d) el legajo sin clave NO entra: «" + res.sinClave.err + "»");
  ok(!res.mala.lista && /incorrecta/i.test(res.mala.err), "(b) clave incorrecta no deja pasar");
  ok(res.buena.lista && res.buena.btns.join("|") === "Jhonny Cartaya|Juan Perez", "(c) clave buena muestra los nombres: " + res.buena.btns.join(", "));
  ok(res.mas.legajo && !res.mas.lista, "(d) «+» muestra el legajo");
  ok(res.porLegajo && res.porLegajo.legajo === "300", "(d) con clave, el legajo entra");
  ok(res.porNombre && res.porNombre.legajo === "104" && /104/.test(res.sesion || ""), "(c) tocar el nombre entra con su legajo");
  ok(!errs.length, "sin errores de JS" + (errs.length ? ": " + errs[0] : ""));
  await b.close();
  if (fail) { console.error("\n" + fail + " chequeo(s) fallaron."); process.exit(1); }
  console.log("\nOK — clave de la TV.");
})().catch((e) => { console.error(e); process.exit(1); });

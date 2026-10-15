/* v31.01 (Luis, 15/10) — avisos de sistema C2 / C4 / C5 en POP-UP para Luis.
   A) Con «Luis» elegido en el selector de rol (gv_sup_quien) y sesión de Google: pide
      gv_popup_pendientes, salta el pop-up, registra «mostrado» y, al Aceptar, «aceptado»
      con p_quien = 'luis'; con dos avisos, muestra el segundo al aceptar el primero.
   B) Con otro rol (o sin rol) NO pide nada ni salta nada.
   C) Sin sesión de Google no llama a la base (las RPC exigen supervisor).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const calls = [];
    const avisos = [
      { id: 11, codigo: "C4", texto: "GESTIÓN — UN MISMO CELULAR CON 2 OPERARIOS\n<b>x</b>", creado_at: "2026-10-15T13:15:00Z" },
      { id: 12, codigo: "C2", texto: "La clave pública intentó escribir en Racks_Bajadas", creado_at: "2026-10-15T13:20:00Z" }
    ];
    window.fetch = function (url, opt) {
      url = String(url);
      const m = url.match(/rpc\/(gv_popup_\w+)/);
      if (m) calls.push({ fn: m[1], body: JSON.parse((opt && opt.body) || "{}"), auth: opt && opt.headers && opt.headers.Authorization });
      const data = m && m[1] === "gv_popup_pendientes" ? avisos : null;
      return Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve(data ? JSON.stringify(data) : ""), json: () => Promise.resolve(data || []) });
    };
    const out = {};
    const vis = () => { const o = document.getElementById("gvPopupOverlay"); return !!(o && o.style.display !== "none"); };
    // C) sin sesión
    window.sbAuth = { getAccessToken: async () => null };
    localStorage.setItem("gv_sup_quien", "luis");
    await gvPopupTick();
    out.sinSesionCalls = calls.length;
    // B) otro rol
    window.sbAuth = { getAccessToken: async () => "tok-google" };
    localStorage.setItem("gv_sup_quien", "marianela");
    await gvPopupTick();
    out.otroRolCalls = calls.length; out.otroRolVis = vis();
    // A) Luis
    localStorage.setItem("gv_sup_quien", "luis");
    await gvPopupTick();
    await new Promise((res) => setTimeout(res, 50));
    out.vis1 = vis();
    const ov = document.getElementById("gvPopupOverlay");
    out.txt1 = ov ? ov.textContent : "";
    out.inyecta = !!(ov && ov.querySelector("b"));
    document.getElementById("gvPopupAceptar").click();
    await new Promise((res) => setTimeout(res, 50));
    out.txt2 = vis() ? document.getElementById("gvPopupOverlay").textContent : "";
    document.getElementById("gvPopupAceptar").click();
    await new Promise((res) => setTimeout(res, 50));
    out.visFin = vis();
    // un segundo tick no vuelve a encolar los ya vistos en esta página
    await gvPopupTick();
    out.visTick2 = vis();
    out.calls = calls;
    return out;
  });
  const ev = (e) => r.calls.filter((c) => c.fn === "gv_popup_evento" && c.body.p_evento === e);
  const ok = {
    "C sin sesión no llama": r.sinSesionCalls === 0,
    "B otro rol no llama": r.otroRolCalls === 0 && !r.otroRolVis,
    "A pide pendientes de luis con la sesión": r.calls.some((c) => c.fn === "gv_popup_pendientes" && c.body.p_persona === "luis" && c.auth === "Bearer tok-google"),
    "A salta el primero (C4)": r.vis1 && /C4/.test(r.txt1) && /2 OPERARIOS/.test(r.txt1) && /quedan 1/.test(r.txt1),
    "A no inyecta HTML del texto": !r.inyecta,
    "A al aceptar pasa al segundo (C2)": /Racks_Bajadas/.test(r.txt2),
    "A se cierra al aceptar el último": !r.visFin && !r.visTick2,
    "log mostrado x2": ev("mostrado").length === 2,
    "log aceptado x2 con quien=luis y dispositivo": ev("aceptado").length === 2 && ev("aceptado").every((c) => c.body.p_quien === "luis" && c.body.p_dispositivo && c.body.p_app_version)
  };
  const fallas = Object.keys(ok).filter((k) => !ok[k]);
  if (errs.length) fallas.push("pageerror: " + errs.join(" | "));
  await b.close();
  if (fallas.length) { console.error("FALLA popup-avisos-luis:\n - " + fallas.join("\n - ") + "\n" + JSON.stringify(r, null, 1).slice(0, 1500)); process.exit(1); }
  console.log("OK popup-avisos-luis (" + Object.keys(ok).length + " chequeos)");
})();

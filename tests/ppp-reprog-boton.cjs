/* v14.36 — En el cartel rojo de atrasados ("N pedidos NO salieron — hay que reprogramarlos")
   cada pedido tiene un botón "📅 Reprogramar" que abre el pop-up de días y lo reprograma
   CON SU NÚMERO de ISIS (gv_ppp_isis_programar → GV_PPP_Prog_Override; no renumera, no toca
   la tabla compartida). Caso testigo: Cencosud sin tanda que no salió.
   (a) el botón aparece por pedido (sólo supervisor/edición);
   (b) tocarlo abre el pop-up con reprogNps = [np], sin tanda;
   (c) elegir un día llama gv_ppp_isis_programar con p_nps=[np] y p_fecha=ISO — NUNCA la vía web;
   (d) si el backend rechaza, se avisa y el pop-up NO se cierra.
   Sin red. Sale 1 si falla. */
const path = require("path");
const { chromium } = require("/opt/node22/lib/node_modules/playwright");
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {}; const calls = [];
    try { localStorage.clear(); } catch (_e) {}
    const ok = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o),
      headers: { get: (h) => String(h).toLowerCase() === "content-range" ? "0-0/1" : null } });
    window.confirm = () => true; window.alert = () => {};
    window.__isSupervisor = true;
    window.sbAuth = { getAccessToken: async () => "h." + btoa(JSON.stringify({ email: "sup@x" })) + ".s" };
    window._pppEmitError = function () {};
    window.getActivityStatus = async () => ({ pickingStarted: new Set(), pickingDone: new Set(), armadoStarted: new Set(), armadoDone: new Set(), pickingEnCursoBy: new Map(), armadoEnCursoBy: new Map() });

    const hab = _pppDiasHabiles(6).map((d) => d.date);
    const iso = (dt) => dt.getFullYear() + "-" + String(dt.getMonth() + 1).padStart(2, "0") + "-" + String(dt.getDate()).padStart(2, "0");
    const anteayer = new Date(hab[0].getTime()); anteayer.setDate(anteayer.getDate() - 5);
    // Un vencido de Cencosud SIN TANDA (no salió) + uno al día para que no quede vacío.
    const rows = [
      { np: "44609", tanda: "", tipo: "", fecha_recep: "2026-09-01", cod: "2444", razon_social: "Cencosud S.A.", m3: 0.6, direccion: "Alberdi 100", barrio: "Soldati", fecha_entrega: iso(anteayer), zona: "Zona 1 - CABA Sur" },
      { np: "44700", tanda: "E92A", tipo: "", fecha_recep: "2026-09-01", cod: "1004", razon_social: "Al Dia", m3: 1.1, direccion: "Sáenz 1100", barrio: "Pompeya", fecha_entrega: iso(hab[0]), zona: "Zona 1 - CABA Sur" }
    ];
    window.fetch = async (url, opt) => {
      const u = String(url); const m = /\/rpc\/([a-z_]+)/.exec(u);
      if (m) {
        calls.push({ fn: m[1], body: JSON.parse((opt && opt.body) || "{}") });
        if (m[1] === "gv_ppp_isis_programar") {
          if (window.__falla) return { ok: false, status: 400, json: async () => ({ message: "Un súper no se junta con clientes." }), text: async () => '{"message":"x"}', headers: { get: () => null } };
          return ok([{ codigo: "E13A", np_programadas: 1, m3: 0.6, aviso: null }]);
        }
        if (m[1] === "gv_ppp_web_calendario") return ok([{ dia: "2026-09-14", habil: true, m3: 1, tandas: 1, np: 1, cupo: 6, resta: 5 }]);
        return ok([]);
      }
      if (u.indexOf("gv_ppp_programacion_diaria") >= 0) return ok(rows);
      return ok([]);
    };

    await pppLoadProgFromSupabase();
    await pppRefreshControlado(); await pppRefreshArmado(); await pppRefreshEnSalida(); await pppRefreshValor();

    // Abrir la lista de atrasados en Programación
    _pppTab = "plan"; _pppPlanDay = null; _pppPlanClasica = false; pppRenderProg();
    pppPlanAbrir("venc");
    let h = document.getElementById("pppPreview").innerHTML;
    // (a) el botón por pedido
    out.tieneBoton = /pn-reprog-btn/.test(h) && /pppReprogAbrir\('44609'\)/.test(h);
    out.hintNuevo = /Reprogramalo a un día con/.test(h);

    // (b) abrir el pop-up
    pppReprogAbrir("44609");
    out.reprogNps = (_pppMov && _pppMov.reprogNps) ? _pppMov.reprogNps.join(",") : "";
    out.sinTanda = !!(_pppMov && !_pppMov.tanda);
    out.overlay = !!document.querySelector("#pppMovOverlay.show");
    out.titulo = (document.getElementById("pppMovTitle") || {}).textContent || "";
    await new Promise((res) => setTimeout(res, 50));   // deja cargar el calendario

    // (c) elegir un día → gv_ppp_isis_programar con las NP
    calls.length = 0;
    await pppReprogElegir("2026-09-14");
    out.calls = calls.map((c) => c.fn);
    out.cuerpo = (calls.find((c) => c.fn === "gv_ppp_isis_programar") || {}).body || null;
    out.cerrado = !document.querySelector("#pppMovOverlay.show");

    // (d) backend rechaza → no cierra
    window.__falla = true;
    pppReprogAbrir("44609");
    await new Promise((res) => setTimeout(res, 50));
    await pppReprogElegir("2026-09-14");
    out.noCierraSiFalla = !!document.querySelector("#pppMovOverlay.show");
    return out;
  });
  await b.close();

  const fails = [];
  const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fails.push(m); };
  chk(r.tieneBoton, "cada pedido del cartel rojo tiene el botón 📅 Reprogramar → pppReprogAbrir(np)");
  chk(r.hintNuevo, "el texto de ayuda invita a reprogramar a un día");
  chk(r.reprogNps === "44609" && r.sinTanda, "tocarlo abre el pop-up con reprogNps=[np] y sin tanda");
  chk(r.overlay, "el pop-up de días queda visible");
  chk(/Reprogramar 44609/.test(r.titulo), "el título dice a quién se reprograma: " + JSON.stringify(r.titulo));
  chk(r.calls.indexOf("gv_ppp_isis_programar") >= 0, "elegir un día llama gv_ppp_isis_programar");
  chk(r.calls.indexOf("gv_ppp_web_tanda_nueva") < 0 && r.calls.indexOf("gv_ppp_web_tanda_agregar") < 0, "NUNCA por la vía web (no renumera → no duplica en ISIS)");
  chk(!!r.cuerpo && String(r.cuerpo.p_nps) === "44609" && r.cuerpo.p_fecha === "2026-09-14", "manda las NP y el día: " + JSON.stringify(r.cuerpo));
  chk(r.cerrado, "al reprogramar OK, el pop-up se cierra");
  chk(r.noCierraSiFalla, "si el backend rechaza, el pop-up NO se cierra");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));
  if (fails.length) { console.error("\nFALLARON " + fails.length + ":\n· " + fails.join("\n· ")); process.exit(1); }
  console.log("\nppp-reprog-boton OK");
})();

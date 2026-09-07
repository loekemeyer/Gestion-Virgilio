/* v13.87 — Mover una tanda de día DESDE LA APP (dueño: "esa solicitud la tengo que poder hacer desde la app").
   El botón "📅 Fecha de toda la tanda → Aplicar" de la solapa Programación guardaba en localStorage: se veía en
   ese navegador y el operario nunca se enteraba. Ahora llama a `gv_ppp_tanda_mover`, que persiste para todos.
   (a) pide confirmación diciendo la tanda, el día y cuántos pedidos, y si el día destino abre un segundo camión
       lo avisa (gv_ppp_web_camion_nuevo, el mismo criterio de A Programar);
   (b) si se dice que no, no llama a la RPC de mover ni toca nada;
   (c) al aceptar manda p_tanda / p_fecha, muestra el aviso que devuelve el backend y recarga desde Supabase;
   (d) si el backend rechaza (tanda ya empezada), lo muestra y NO deja el cambio en localStorage.
   RPC interceptadas por fetch, sin red. Sale 1 si falla. */
const path = require("path");
const { chromium } = require("/opt/node22/lib/node_modules/playwright");
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {}; const calls = []; const preg = [];
    const ok = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => null } });
    window.alert = (m) => { (out.alerts = out.alerts || []).push(String(m)); };
    window.facAuthWriteHeaders = async () => ({ apikey: "x", Authorization: "Bearer x", "Content-Type": "application/json" });
    window.pppLoadProgFromSupabase = async () => { out.recargo = (out.recargo || 0) + 1; };
    window._faltMiLegajo = () => "12";
    window.fetch = async (url, opt) => {
      const u = String(url); const m = /\/rpc\/([a-z_]+)/.exec(u);
      if (m) {
        calls.push({ fn: m[1], body: JSON.parse((opt && opt.body) || "{}") });
        if (m[1] === "gv_ppp_web_camion_nuevo") return ok(window.__cam || []);
        if (m[1] === "gv_ppp_tanda_mover") {
          if (window.__falla) return { ok: false, status: 400, json: async () => ({ message: "La tanda D62A ya está empezada (23 evento(s) de operarios): no se puede mover de día." }), text: async () => '{"message":"La tanda D62A ya está empezada (23 evento(s) de operarios): no se puede mover de día."}', headers: { get: () => null } };
          return ok([{ movidas: 2, np_web: 0, np_isis: 2, m3: 4.041, aviso: "El 09/09 queda con 7.247 m³, por encima del cupo de 6 m³." }]);
        }
        return ok([]);
      }
      return ok([]);
    };
    // la tanda a mover, como la ve la solapa Programación
    _pppParsed.prog = [
      { np: "98650", tanda: "D66B", razon_social: "Osa Distribuidora SRL  Chemelo", zona: "Zona 1 - CABA Sur", barrio: "Barracas", direccion: "x", fecha_entrega: "10/09/2026", m3: 2.71, programmed: true },
      { np: "98667", tanda: "D66B", razon_social: "Osa Distribuidora SRL  Chemelo", zona: "Zona 1 - CABA Sur", barrio: "Barracas", direccion: "x", fecha_entrega: "10/09/2026", m3: 1.331, programmed: true }
    ];
    const inp = document.createElement("input"); inp.type = "date"; inp.id = "T_d"; inp.value = "2026-09-09";
    document.body.appendChild(inp);

    // (a)+(b) pregunta, y si se dice que no, no mueve
    window.__cam = [{ camion: "Capital", ya_va: false, paradas: 2, camiones_dia: 2, es_super: false }];
    window.confirm = (m) => { preg.push(String(m)); return false; };
    calls.length = 0;
    await pppTandaFecha("T", "D66B");
    out.pregunta = preg[0] || "";
    out.noMovio = calls.filter((c) => c.fn === "gv_ppp_tanda_mover").length;

    // (c) al aceptar: manda tanda y fecha, muestra el aviso y recarga
    window.confirm = () => true; calls.length = 0;
    await pppTandaFecha("T", "D66B");
    const c = calls.find((x) => x.fn === "gv_ppp_tanda_mover") || { body: {} };
    out.movio = { tanda: c.body.p_tanda, fecha: c.body.p_fecha, por: c.body.p_por };
    out.status = (document.getElementById("pppStatus") || {}).textContent || "";
    out.edits = JSON.stringify(pppLoadEdits());

    // (d) el backend rechaza → se avisa y no queda nada en localStorage
    window.__falla = true; calls.length = 0;
    await pppTandaFecha("T", "D66B");
    out.errStatus = (document.getElementById("pppStatus") || {}).textContent || "";
    out.editsTrasError = JSON.stringify(pppLoadEdits());
    window.__falla = false;
    return out;
  });
  await b.close();

  const fails = [];
  const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fails.push(m); };
  chk(/¿Mover TODA la tanda D66B al 09\/09\/2026\?/.test(r.pregunta) && /2 pedido\(s\)/.test(r.pregunta), "pregunta con la tanda, el día y cuántos pedidos");
  chk(/ya salen 2 camión\(es\) y esto abre otro: Capital/.test(r.pregunta) && /segundo camión/.test(r.pregunta), "avisa si el día destino abre un segundo camión");
  chk(/Lo ven todos/.test(r.pregunta), "aclara que el cambio lo ven todos");
  chk(r.noMovio === 0, "si se dice que no, no llama a gv_ppp_tanda_mover");
  chk(r.movio.tanda === "D66B" && r.movio.fecha === "2026-09-09" && r.movio.por === "12", "al aceptar manda tanda, fecha y legajo (" + JSON.stringify(r.movio) + ")");
  chk(/Tanda D66B movida al 09\/09\/2026: 2 pedido\(s\) · 4.041 m³/.test(r.status), "el estado dice qué se movió (" + r.status.slice(0, 70) + ")");
  chk((r.alerts || []).some((a) => /por encima del cupo/.test(a)), "muestra el aviso que devolvió el backend");
  chk(r.recargo >= 1, "recarga la programación desde Supabase");
  chk(r.edits === "{}", "NO guarda la fecha en localStorage (antes sí, y sólo lo veía ese navegador)");
  chk(/No se pudo mover/.test(r.errStatus) && /ya está empezada/.test(r.errStatus), "si el backend rechaza, lo dice (" + r.errStatus.slice(0, 60) + ")");
  chk(r.editsTrasError === "{}", "y tampoco deja nada en localStorage");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));
  if (fails.length) { console.error("\nFALLARON " + fails.length + ":\n· " + fails.join("\n· ")); process.exit(1); }
  console.log("\nppp-mover-tanda OK");
})();

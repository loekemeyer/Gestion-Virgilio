/* v29.69 (Luis, 13/10/2026) — EL CÓDIGO QUE NO TIENE GÓNDOLA EN EL MAPA.
   "si el modulo de pickeo los promptea a pickear un codigo para el que no tiene registro de lugar
    y el que pickea lo agarra, debería preguntarle de que gondola lo agarro y debería aparecerle la
    sugerencia al admin para ajustar gondolas de la misma forma que le aparece para ajustar stock."

   Corre el picking de verdad (index.html) y mide:
     (a) el paso de un código SIN góndola lleva el aviso, y el que SÍ tiene no;
     (b) al confirmar «✓ Puse», pregunta de qué góndola lo sacó — y el PKC ya se mandó ANTES
         (si el celular muere en la pregunta, lo pickeado no se pierde);
     (c) anotar emite PKG = "COD|lo que escribió|TANDA" y avanza;
     (d) «No sé» avanza sin emitir nada, y no vuelve a preguntar por ese código;
     (e) con góndola no pregunta nunca;
     (f) «Faltan» con 0 cajas NO pregunta (no la agarró);
     (g) el cuadro del admin: lee gv_gondola_sugerida_pendientes y ✓ llama a _resolver.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await (await b.newContext({ viewport: { width: 430, height: 880 }, serviceWorkers: "block" })).newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    for (let i = 0; i < 60 && typeof window.pkRender !== "function"; i++) await espera(100);
    const out = {}; const sent = [];
    window.enqueueReport = function (pl) { sent.push(pl); };
    window.trySendOneReport = null;
    window.updatePendingIndicator = function () {};
    // el modal que usa el picking
    let m = document.getElementById("tandaModal");
    if (!m) { m = document.createElement("div"); m.id = "tandaModal";
      m.innerHTML = '<div class="tanda-modal-body"></div><div class="tanda-modal-foot"></div>';
      document.body.appendChild(m); }
    const body = () => m.querySelector(".tanda-modal-body");

    const armar = () => { _pk = {
      tanda: "E20A", legajo: "277", idx: 0, mode: "item", excOk: true, results: {}, gondDone: {},
      items: [{ art: "232", key: "232", esp: 6, sector: "—" },     // sin celda en el Mapa
              { art: "501", key: "501", esp: 3, sector: "A12" }]   // con celda
    }; };

    // (a) el aviso del paso
    armar(); pkRender();
    out.avisoSinGond = /no tiene g.ndola en el Mapa/i.test(body().textContent);
    out.puro = typeof window.pkSinGondola === "function" &&
               pkSinGondola({ sector: "—" }) === true && pkSinGondola({ sector: "A12" }) === false &&
               pkSinGondola({ sector: "—", isExc: true }) === false;
    _pk.idx = 1; pkRender();
    out.avisoConGond = /no tiene g.ndola en el Mapa/i.test(body().textContent);

    // (b) confirmar: el PKC sale ANTES de preguntar
    armar(); pkRender(); pkOk();
    out.pkcAntes = sent.length === 1 && sent[0].opcion === "PKC";
    out.pregunta = /De qu. g.ndola lo sacaste/i.test(body().textContent) && _pk.mode === "gond";
    out.noAvanzo = _pk.idx === 0;

    // (c) anotar → PKG y avanza
    out.hayInput = !!document.getElementById("pkGondInp");
    out.bodyGond = body().textContent.slice(0, 80);
    if (out.hayInput) { document.getElementById("pkGondInp").value = "f9"; pkGondSubmit(); }
    const pkg = sent.filter((x) => x.opcion === "PKG");
    out.pkg = pkg.length === 1 ? pkg[0].texto : "";
    out.pkgOk = out.pkg === "232|F9|E20A";
    out.pkgSinTsInicio = pkg.length === 1 && pkg[0].ts_inicio_iso === null;
    out.avanzo = _pk.idx === 1 && _pk.mode === "item";

    // (d) «No sé»: no emite y no vuelve a preguntar
    armar(); pkRender(); pkOk();
    const n0 = sent.length;
    pkGondSkip();
    out.skipSinPkg = sent.length === n0 && _pk.idx === 1;
    _pk.idx = 0; pkRender(); pkOk();
    out.noRepregunta = _pk.mode !== "gond" && _pk.idx === 1;

    // (e) con góndola: nunca pregunta
    armar(); _pk.idx = 1; pkRender(); pkOk();
    out.conGondNoPregunta = _pk.mode !== "gond";

    // (f) Faltan con 0 → no pregunta (no la agarró)
    armar(); pkRender(); pkF(); pkRender();
    const inp = document.getElementById("pkFqty"); if (inp) inp.value = "0";
    pkConfirmF();
    out.cero = _pk.mode !== "gond" && _pk.idx === 1;
    // y Faltan con 2 sí pregunta
    armar(); pkRender(); pkF(); pkRender();
    const inp2 = document.getElementById("pkFqty"); if (inp2) inp2.value = "2";
    pkConfirmF();
    out.faltanPregunta = _pk.mode === "gond";

    // (g) el cuadro del admin
    const pedidos = [];
    window.sb = { rpc: async (n, a) => {
      pedidos.push(n + ":" + JSON.stringify(a || {}));
      if (n === "gv_gondola_sugerida_pendientes") return { data: [{
        client_id: "pkg_277_E20A_232", ts: new Date().toISOString(), legajo: "277", nombre: "Jhonny Cartaya",
        tanda: "E20A", cod: "232", cod_base: "232", descripcion: "Palo Amasar 40cm", sector_dicho: "f9",
        sector: "F09", sector_ok: true, ocupada_por: "437E", tiene_gondola: false, veces: 1, cajas: 6 }], error: null };
      return { data: { ok: true, estado: "aceptada" }, error: null };
    } };
    await window.gsLoad(); await espera(60);
    const box = document.getElementById("gsAside");
    out.cuadro = box && box.style.display !== "none" ? box.textContent.replace(/\s+/g, " ").trim() : "";
    out.cuadroOk = /232 . F09/.test(out.cuadro) && /esa celda hoy tiene 437E/.test(out.cuadro);
    window.prompt = (q) => (/celda va/.test(q) ? "F09" : "40");
    window.confirm = () => true; window.alert = () => {};
    await window.gsResolver(0, true); await espera(60);
    out.resolver = pedidos.filter((x) => /gv_gondola_sugerida_resolver/.test(x))[0] || "";
    out.resolverOk = /"p_aceptar":true/.test(out.resolver) && /"p_sector":"F09"/.test(out.resolver) && /"p_cajas_max":40/.test(out.resolver);
    return out;
  });

  await b.close();
  const fallos = []; const ok = (c, m) => { if (!c) fallos.push(m); };
  ok(r.puro, "(a) pkSinGondola no distingue bien (sector, excedente)");
  ok(r.avisoSinGond, "(a) falta el aviso en el paso del código sin góndola");
  ok(!r.avisoConGond, "(a) el aviso salió en un código que SÍ tiene góndola");
  ok(r.pkcAntes, "(b) el PKC no salió ANTES de preguntar la góndola");
  ok(r.pregunta, "(b) no preguntó de qué góndola lo sacó");
  ok(r.noAvanzo, "(b) avanzó de paso antes de preguntar");
  ok(r.pkgOk, "(c) el evento PKG salió como «" + r.pkg + "» (esperaba 232|F9|E20A)");
  ok(r.pkgSinTsInicio, "(c) el PKG lleva ts_inicio: abriría una tarea en el monitor");
  ok(r.avanzo, "(c) no avanzó después de anotar");
  ok(r.skipSinPkg, "(d) «No sé» emitió un evento o no avanzó");
  ok(r.noRepregunta, "(d) volvió a preguntar por el mismo código");
  ok(r.conGondNoPregunta, "(e) preguntó por un código que tiene góndola");
  ok(r.cero, "(f) preguntó la góndola con 0 cajas levantadas");
  ok(r.faltanPregunta, "(f) no preguntó con «Faltan» y 2 cajas");
  ok(r.cuadroOk, "(g) el cuadro del admin: «" + r.cuadro + "»");
  ok(r.resolverOk, "(g) el ✓ no llamó bien a gv_gondola_sugerida_resolver: " + r.resolver);
  if (errs.length) fallos.push("errores de página: " + errs.join(" · "));

  if (fallos.length) { console.error("PK GÓNDOLA SUGERIDA — FALLA:\n  " + fallos.join("\n  ")); process.exit(1); }
  console.log("pk-gondola-sugerida OK — pregunta, emite PKG, no repregunta y el admin la da de alta.");
})();

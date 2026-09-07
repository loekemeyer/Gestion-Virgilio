/* v14.04 — "📅 Mover de día" abre un POP-UP con un botón por día y los m³ de cada uno.
   Dueño 07/09: "cuando toco el botón, que me abra un pop up para ponerme los botones de cada día y
   cuántos m³ tiene cada uno". Antes abría un <input type=date> pelado: había que saber de memoria
   cómo venía cada día.
   (a) el botón de la tanda llama a pppMoverAbrir, no al panel viejo;
   (b) el pop-up trae un botón por día con m³ / cupo y cuánto queda, y una barra de carga;
   (c) el día donde YA está la tanda se marca "está acá" y no se puede elegir; el no hábil tampoco;
   (d) tocar un día mueve la tanda a ESE día (gv_ppp_tanda_mover) y cierra el pop-up;
   (e) si el backend rechaza (tanda empezada) NO cierra: deja ver el error y volver a elegir;
   (f) sigue avisando si el día destino abre un segundo camión.
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
    const iso = (d) => d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    const hoy = new Date(), dd = (n) => { const x = new Date(hoy.getTime()); x.setDate(x.getDate() + n); return iso(x); };
    // calendario de mentira: hoy, +1 (donde está la tanda), +2 lleno, +3 no hábil, +4 libre
    const CAL = [
      { dia: dd(0), m3: 1.0, cupo: 6, habil: true,  tandas: 1 },
      { dia: dd(1), m3: 4.041, cupo: 6, habil: true, tandas: 2 },
      { dia: dd(2), m3: 7.2, cupo: 6, habil: true,  tandas: 3 },
      { dia: dd(3), m3: 0,   cupo: 6, habil: false, tandas: 0 },
      { dia: dd(4), m3: 2.5, cupo: 6, habil: true,  tandas: 1 }
    ];
    window.fetch = async (url, opt) => {
      const u = String(url); const m = /\/rpc\/([a-z_]+)/.exec(u);
      if (m) {
        calls.push({ fn: m[1], body: JSON.parse((opt && opt.body) || "{}") });
        if (m[1] === "gv_ppp_web_calendario") return ok(CAL);
        if (m[1] === "gv_ppp_web_camion_nuevo") return ok(window.__cam || []);
        if (m[1] === "gv_ppp_tanda_mover") {
          if (window.__falla) return { ok: false, status: 400, json: async () => ({ message: "La tanda D66B ya está empezada (23 evento(s) de operarios): no se puede mover de día." }), text: async () => '{"message":"La tanda D66B ya está empezada (23 evento(s) de operarios): no se puede mover de día."}', headers: { get: () => null } };
          return ok([{ movidas: 2, np_web: 0, np_isis: 2, m3: 4.041, aviso: "" }]);
        }
        return ok([]);
      }
      return ok([]);
    };
    // la tanda, como la ve Programación: está en dd(1)
    const f1 = dd(1).split("-");
    _pppParsed = { prog: [
      { np: "98650", tanda: "D66B", cod: "2533", razon_social: "Osa Distribuidora", zona: "Zona 1 - CABA Sur", barrio: "Villa Lugano", direccion: "x", fecha_entrega: f1[2] + "/" + f1[1] + "/" + f1[0], m3: 2.71, programmed: true },
      { np: "98667", tanda: "D66B", cod: "2533", razon_social: "Osa Distribuidora", zona: "Zona 1 - CABA Sur", barrio: "Villa Lugano", direccion: "x", fecha_entrega: f1[2] + "/" + f1[1] + "/" + f1[0], m3: 1.331, programmed: true }
    ], aprogramar: [] };

    // (a) el botón de la tanda apunta al pop-up
    window.__isSupervisor = true;
    const bloques = _pppTandaBlocksHtml("k", _pppParsed.prog);
    out.botonAbrePopup = /pppMoverAbrir\('D66B'\)/.test(bloques) && !/pppSetMode\('[^']*','edit'\)"[^>]*>📅 Mover de día/.test(bloques);

    // (b)+(c) el pop-up
    pppMoverAbrir("D66B");
    for (let i = 0; i < 40 && (!_pppMov || _pppMov.cargando); i++) await new Promise((r) => setTimeout(r, 25));
    const h = document.getElementById("pppMovBody").innerHTML;
    out.abre = document.getElementById("pppMovOverlay").classList.contains("show");
    out.titulo = document.getElementById("pppMovTitle").textContent;
    out.sub = /<b>2<\/b> pedidos · <b>4,0 m³<\/b>/.test(h);
    out.diasClickeables = (h.match(/onclick="pppMovElegir\('/g) || []).length;   // hoy, +2 y +4 (no el actual, no el no hábil)
    out.m3PorDia = /4,0 \/ 6,0 m³/.test(h) && /quedan 2,0 m³/.test(h);           // el día donde está: 4,041 de 6
    out.marcaActual = /mv-tag aca">está acá/.test(h);
    out.actualNoClickeable = !new RegExp("pppMovElegir\\('" + dd(1) + "'\\)").test(h);
    out.noHabil = /No hábil/.test(h) && !new RegExp("pppMovElegir\\('" + dd(3) + "'\\)").test(h);
    out.lleno = /mv-tag lleno">completo/.test(h) && /pasado por 1,2 m³/.test(h);
    out.barra = /<div class="mv-bar"><i style="width:/.test(h);

    // (f)+(d) elegir un día: avisa del segundo camión, mueve y cierra
    window.__cam = [{ camion: "Capital", ya_va: false, paradas: 2, camiones_dia: 2, es_super: false }];
    window.confirm = (m) => { preg.push(String(m)); return true; };
    calls.length = 0;
    await pppMovElegir(dd(4));
    const c = calls.find((x) => x.fn === "gv_ppp_tanda_mover") || { body: {} };
    out.pregunta = preg[0] || "";
    out.movio = { tanda: c.body.p_tanda, fecha: c.body.p_fecha };
    out.cerroAlMover = !document.getElementById("pppMovOverlay").classList.contains("show");

    // (e) si el backend rechaza, NO cierra
    window.__falla = true;
    pppMoverAbrir("D66B");
    for (let i = 0; i < 40 && (!_pppMov || _pppMov.cargando); i++) await new Promise((r) => setTimeout(r, 25));
    await pppMovElegir(dd(4));
    for (let i = 0; i < 40 && _pppMov.cargando; i++) await new Promise((r) => setTimeout(r, 25));
    out.sigueAbierto = document.getElementById("pppMovOverlay").classList.contains("show");
    out.dijoElError = (out.alerts || []).some((a) => /ya está empezada/.test(a));
    window.__falla = false; pppMovCerrar();
    out.cierra = !document.getElementById("pppMovOverlay").classList.contains("show");
    return out;
  });
  await b.close();

  const fails = [];
  const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fails.push(m); };
  chk(r.botonAbrePopup, "el botón 📅 Mover de día abre el pop-up (ya no el campo de fecha pelado)");
  chk(r.abre && /Mover la tanda D66B/.test(r.titulo), "el pop-up abre con la tanda en el título (" + r.titulo + ")");
  chk(r.sub, "dice cuántos pedidos y cuántos m³ tiene la tanda");
  chk(r.m3PorDia, "cada día muestra sus m³ sobre el cupo y cuánto queda");
  chk(r.barra, "y una barra con la carga del día");
  chk(r.marcaActual && r.actualNoClickeable, "el día donde ya está se marca 'está acá' y no se puede elegir");
  chk(r.noHabil, "el día no hábil se muestra y no se puede elegir");
  chk(r.lleno, "un día pasado de cupo se marca 'completo' y dice por cuánto");
  chk(r.diasClickeables === 3, "quedan 3 días elegibles (hoy, el lleno y el libre): " + r.diasClickeables);
  chk(/ya salen 2 camión\(es\) y esto abre otro: Capital/.test(r.pregunta), "avisa si el día elegido abre un segundo camión");
  chk(r.movio.tanda === "D66B" && !!r.movio.fecha, "mueve la tanda al día que se tocó (" + JSON.stringify(r.movio) + ")");
  chk(r.recargo >= 1, "recarga la programación desde Supabase");
  chk(r.cerroAlMover, "y cierra el pop-up");
  chk(r.sigueAbierto && r.dijoElError, "si el backend rechaza, dice por qué y NO cierra");
  chk(r.cierra, "el botón Cerrar cierra");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));
  if (fails.length) { console.error("\nFALLARON " + fails.length + ":\n· " + fails.join("\n· ")); process.exit(1); }
  console.log("\nppp-mover-popup OK");
})();

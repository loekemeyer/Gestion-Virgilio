/* v13.61 — A Programar en PLANILLA (formato de la hoja de ISIS) + la PPP entera en una pantalla.
   Dueño: "simulame un formato más similar al de PPP" · "no quiero tener que poner el nombre de tanda yo"
   · "no puede haber tanda armada sin fecha" · "no quiero barras de scroll en ninguna parte de la PPP".
   Estado inyectado a mano; las RPC se interceptan para ver el ORDEN de llamadas al generar una tanda. */
const path = require("path");
const { chromium } = require("/opt/node22/lib/node_modules/playwright");
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 800 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    _apr.listo = true; _apr.vista = "planilla";
    _apr.pedidos = [
      { order_id: 1117, empresa: "lk", cod: "R01", razon_social: "Riesgo Marcelo Fabian", zona: "Zona 3 - CABA Oeste", fecha_recep: "2026-09-04", localidad: "Mataderos", direccion: "Bragado 5742 - Mataderos",
        m3: 0.367, m3_parcial: false, lineas: 52, cajas: 120, np_total: 2,
        bloques: [ { np_idx: 1, m3: 0.246, lineas: 34, cajas: 80, items: [{ art: "027", cajas: 8 }] }, { np_idx: 2, m3: 0.121, lineas: 18, cajas: 40, items: [{ art: "801", cajas: 6 }] } ] },
      { order_id: 1200, empresa: "lk", cod: "", razon_social: "", zona: "Retira", fecha_recep: "", localidad: "", direccion: "Retira", m3: 0, m3_parcial: true, lineas: 0, cajas: 0, np_total: 1, bloques: [] },
      { order_id: 218, empresa: "chef", cod: "310", razon_social: "Chen Li Yu", zona: "Super", fecha_recep: "2026-09-05", localidad: "", direccion: "CD Pilar", m3: 0.5, m3_parcial: false, lineas: 3, cajas: 3, np_total: 1, bloques: [{ np_idx: 1, m3: 0.5, lineas: 3, cajas: 3, items: [] }] }
    ];
    _apr.salida = { 1117: { dia: "2026-09-15", motivo: "job", detalle: "Zona automática" }, 1200: { dia: null, motivo: "retira", detalle: "" } };
    _apr.tandas = []; _apr.items = {}; _apr.sel = {};
    _apr.progIsis = [ { tanda: "D68A", fecha_entrega: "2026-09-14 00:00:00", m3: 1.2 }, { tanda: "D68B", fecha_entrega: "2026-09-14 00:00:00", m3: 0.8 }, { tanda: "D99A", fecha_entrega: "30/08/2026", m3: 5 } ];
    _apr.prog = [
      { empresa: "lk", order_id: 1344, tanda: "E01A", fecha_entrega: "2026-09-14", m3: 0.99, zona: "Zona 1 - CABA Sur" },
      { empresa: "lk", order_id: 1345, tanda: "E01B", fecha_entrega: "2026-09-14", m3: 0.48, zona: "Zona 1 - CABA Sur" },
      { empresa: "lk", order_id: 1349, tanda: "D68G", fecha_entrega: "2026-09-14", m3: 0.11, zona: "Zona 5 - GBA Oeste" }
    ];
    _apr.cal = [
      { dia: "2026-09-08", habil: true,  m3: 8.87, tandas: 2, np: 2, cupo: 6, resta: 0,    pasado: false, muy_pronto: true, m3_isis: 8.87, tandas_isis: 2, np_isis: 2 },
      { dia: "2026-09-12", habil: false, m3: 0,    tandas: 0, np: 0, cupo: 6, resta: 6,    pasado: false },
      { dia: "2026-09-14", habil: true,  m3: 6.58, tandas: 8, np: 20, cupo: 6, resta: 0,   pasado: false, m3_isis: 3.14, tandas_isis: 6, np_isis: 13 },
      { dia: "2026-09-15", habil: true,  m3: 4.01, tandas: 7, np: 12, cupo: 6, resta: 1.99, pasado: false, m3_isis: 1.51, tandas_isis: 3, np_isis: 5 }
    ];
    _pppTab = "prog";
    document.getElementById("pppOverlay").classList.add("show");
    aprRender();
    out.html = document.getElementById("pppPreview").innerHTML;

    // tildar dos → botón habilitado con m³
    aprSelToggle("lk:1117", true); aprSelToggle("chef:218", true);
    out.html2 = document.getElementById("pppPreview").innerHTML;

    // generar con LK + Chef mezclados → mensaje, sin RPC
    const calls = [];
    window.fetch = async (url, opt) => {
      const u = String(url); const m = /\/rpc\/([a-z_]+)/.exec(u);
      if (m) {
        calls.push({ fn: m[1], body: JSON.parse((opt && opt.body) || "{}") });
        const ok = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => null } });
        if (m[1] === "gv_ppp_web_tanda_nueva") return ok("E09A");
        if (m[1] === "gv_ppp_web_tanda_agregar") return ok([{ n_np: 2, m3: 0.367, n_avisos: 0 }]);
        if (m[1] === "gv_ppp_web_tanda_programar") {
          if (window.__fallaProgramar) return { ok: false, status: 400, json: async () => ({ message: "cupo lleno" }), text: async () => '{"message":"cupo lleno"}', headers: { get: () => null } };
          return ok([{ np_programadas: 2, m3: 0.367, lineas_base: 52, aviso_dia: null }]);
        }
        return ok(null);
      }
      return { ok: true, status: 200, json: async () => [], text: async () => "[]", headers: { get: () => "0-0/0" } };
    };
    window.confirm = () => true;
    // sesión de supervisor de mentira (aprQuien lee el mail del JWT)
    window.sbAuth = { getAccessToken: async () => "h." + btoa(JSON.stringify({ email: "test@x" })) + ".s" };
    const peds0 = JSON.parse(JSON.stringify(_apr.pedidos));
    const reset = () => { _apr.pedidos = JSON.parse(JSON.stringify(peds0)); _apr.listo = true; _apr.err = ""; _apr.msg = ""; _apr.msgErr = false; };
    await aprGenerarTanda("2026-09-15");
    out.mezcla = { msg: _apr.msg, err: _apr.msgErr, calls: calls.length };

    // sólo LK → nueva → agregar → programar, con la fecha
    reset(); _apr.sel = { "lk:1117": true }; calls.length = 0;
    await aprGenerarTanda("2026-09-15");
    out.ok = { msg: _apr.msg, err: _apr.msgErr, fns: calls.map((c) => c.fn).filter((f) => /^gv_ppp_web_tanda_/.test(f)), fecha: (calls[2] || {}).body && calls[2].body.p_fecha, codigo: (calls[2] || {}).body && calls[2].body.p_codigo, items: JSON.stringify(((calls[2] || {}).body || {}).p_items), sel: Object.keys(_apr.sel).length };

    // programar falla → la tanda se descarta (ninguna queda sin fecha)
    reset(); _apr.sel = {}; calls.length = 0; window.__fallaProgramar = true;
    await aprProgramarFila("lk:1117", "2026-09-15");
    out.falla = { msg: _apr.msg, err: _apr.msgErr, fns: calls.map((c) => c.fn).filter((f) => /^gv_ppp_web_tanda_/.test(f)) };
    window.__fallaProgramar = false;

    // sin fecha → no llama a nada
    reset(); _apr.sel = { "lk:1117": true }; calls.length = 0;
    await aprGenerarTanda("");
    out.sinFecha = { msg: _apr.msg, calls: calls.length };

    // ajuste a pantalla: nada scrollea adentro del overlay
    await new Promise((res) => setTimeout(res, 500));
    const body = document.querySelector("#pppOverlay .planim-body");
    out.fit = { zoom: body.style.zoom, sh: body.scrollHeight, ch: body.clientHeight, sw: body.scrollWidth, cw: body.clientWidth };
    out.conScroll = [...document.querySelectorAll("#pppOverlay *")].filter((e) => { const cs = getComputedStyle(e); return /auto|scroll/.test(cs.overflowY + cs.overflowX) && (e.scrollHeight > e.clientHeight + 1 || e.scrollWidth > e.clientWidth + 1); }).map((e) => e.className || e.id);
    return out;
  });

  const fallos = [];
  const chk = (cond, msg) => { console.log((cond ? "ok   " : "MAL  ") + msg); if (!cond) fallos.push(msg); };
  const h = r.html;
  chk(/aprp-tbl/.test(h) && !/apr-wrap/.test(h), "la planilla reemplaza a las tres columnas");
  chk(h.includes("LK 1117") && h.includes("LK 1117-2"), "una fila por NP: LK 1117 y LK 1117-2");
  chk((h.match(/class="b2"/g) || []).length === 1, "el bloque 2 va como fila secundaria (↳)");
  chk(/aprp-tipo rep">REP</.test(h) && /aprp-tipo ret">RET</.test(h) && /aprp-tipo sup">SUP</.test(h), "Tipo REP / RET / SUP (v13.64: no dice WEB)");
  chk(h.includes("CH 0218"), "la NP de Chef se etiqueta CH 0218");
  chk(/apr-chip-sal[^>]*>🤖 se arma solo → mar 15\/9/.test(h), "Observaciones = qué va a pasar (se arma solo → mar 15/9)");
  chk(/🏭 retira/.test(h), "retira: a mano");
  chk(!/sin fecha/i.test(h.replace(/ninguna queda sin fecha/gi, "")), "no hay sección de tandas sin fecha");
  chk(!/aprNuevaTanda/.test(h), "no hay botón de tanda vacía");
  // días: sólo hábiles, abiertos y no 'muy pronto' → 14 (lleno) y 15 (quedan 1,99)
  const opts = (h.match(/<option value="2026-[^"]+"[^>]*>[^<]*<\/option>/g) || []);
  chk(opts.length >= 2 && !opts.some((o) => /2026-09-08|2026-09-12/.test(o)), "el día 8 (muy pronto) y el sábado 12 no se ofrecen");
  chk(opts.some((o) => /mar 15\/9 · quedan 1,99/.test(o)) && opts.some((o) => /lun 14\/9 · lleno/.test(o)), "opciones 'mar 15/9 · quedan 1,99' y 'lun 14/9 · lleno'");
  chk(/aprp-gen"[^>]*disabled/.test(h), "sin tildados el botón está apagado");
  chk(/Generar tanda con los 2 tildados/.test(r.html2) && /0,87 m³/.test(r.html2) && !/aprp-gen"[^>]*disabled/.test(r.html2), "con 2 tildados: 'Generar tanda con los 2 tildados · 0,87 m³' habilitado");
  chk(/aprp-tag"[^>]*>E01 · 2 t · 1,47</.test(h) && /aprp-tag"[^>]*>D68 · 3 t · 2,11</.test(h), "v13.64: camiones del día web e ISIS JUNTOS (E01 · 2 t · 1,47, D68 · 3 t · 2,11)");
  chk(!/D99/.test(h) && !/ISIS/.test(h) && !/Gestión\)/.test(h), "v13.64: sin fila con fecha rara y sin 'ISIS' / 'Gestión' en la planilla");
  chk(/<b>8<\/b> t · <b>20<\/b> NP/.test(h), "programación: tandas · NP del día, todo junto");
  chk(/class="queda">1,99</.test(h) && /class="lleno">lleno</.test(h) && /class="pronto">muy pronto</.test(h), "quedan / lleno / muy pronto");
  chk(r.mezcla.err === true && /una sola empresa/.test(r.mezcla.msg) && r.mezcla.calls === 0, "LK + Chef tildados juntos → aviso, sin RPC");
  chk(r.ok.fns.join(">") === "gv_ppp_web_tanda_nueva>gv_ppp_web_tanda_agregar>gv_ppp_web_tanda_programar", "generar = nueva → agregar → programar (" + r.ok.fns.join(">") + ")");
  chk(r.ok.fecha === "2026-09-15" && r.ok.codigo === "E09A", "programa con la fecha elegida y el código que dio la base");
  chk(/"order_id":1117,"np_idx":1,"items":\[\{"art":"027"/.test(r.ok.items) && /"np_idx":2,"items":\[\{"art":"801"/.test(r.ok.items), "los artículos de los dos bloques viajan al programar");
  chk(/✅ E09A programada para el mar 15\/9: 2 NP · 0,367 m³/.test(r.ok.msg) && r.ok.err === false && r.ok.sel === 0, "mensaje verde y se destilda");
  chk(r.falla.fns.join(">") === "gv_ppp_web_tanda_nueva>gv_ppp_web_tanda_agregar>gv_ppp_web_tanda_programar>gv_ppp_web_tanda_descartar" && /se descartó/.test(r.falla.msg) && r.falla.err === true, "si programar falla, la tanda se descarta (ninguna sin fecha) " + JSON.stringify(r.falla));
  chk(r.sinFecha.calls === 0 && /Elegí el día/.test(r.sinFecha.msg), "sin fecha no se arma nada");
  chk(r.fit.sh <= r.fit.ch + 1 && r.fit.sw <= r.fit.cw + 1, "la PPP entra entera en la pantalla (zoom " + r.fit.zoom + ")");
  chk(r.conScroll.length === 0, "ningún elemento del overlay scrollea (" + r.conScroll.join(",") + ")");
  chk(!/undefined|NaN/.test(h + r.html2), "sin 'undefined' ni 'NaN'");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));

  await b.close();
  if (fallos.length) { console.error("\nFALLARON " + fallos.length + ":\n· " + fallos.join("\n· ")); process.exit(1); }
  console.log("\napr-planilla OK");
})();

/* v13.65 — (a) la PPP entra ENTERA en una pantalla (dueño: "no quiero barras de scroll en ninguna parte");
   (b) soltar un PEDIDO en un DÍA arma la tanda (código automático) y la programa en un paso; si programar
   falla, la tanda se descarta (dueño: "no puede haber tanda armada sin fecha"). Estado inyectado; las RPC se
   interceptan para ver el orden de llamadas. */
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
    _apr.listo = true;
    const mk = (i) => ({ order_id: 1351 + i, empresa: i % 4 === 3 ? "chef" : "lk", cod: String(1000 + i), razon_social: "Cliente " + i, zona: "Zona 1 - CABA Sur", fecha_recep: "2026-09-04", localidad: "Barracas", direccion: "Montes de Oca " + i, m3: 0.4, m3_parcial: false, lineas: 10, cajas: 12, np_total: 1, bloques: [{ np_idx: 1, m3: 0.4, lineas: 10, cajas: 12, items: [{ art: "027", cajas: 2 }] }] });
    _apr.pedidos = []; for (let i = 0; i < 8; i++) _apr.pedidos.push(mk(i));
    _apr.salida = {}; _apr.tandas = []; _apr.items = {};
    _apr.cal = [
      { dia: "2026-09-14", habil: true, m3: 6.58, tandas: 13, np: 32, cupo: 6, resta: 0, pasado: false },
      { dia: "2026-09-15", habil: true, m3: 4.01, tandas: 7, np: 12, cupo: 6, resta: 1.99, pasado: false }
    ];
    _pppTab = "prog";
    document.getElementById("pppOverlay").classList.add("show");
    aprRender();
    await new Promise((res) => setTimeout(res, 600));
    const body = document.querySelector("#pppOverlay .planim-body");
    out.fit = { zoom: body.style.zoom, sh: body.scrollHeight, ch: body.clientHeight, sw: body.scrollWidth, cw: body.clientWidth };
    out.conScroll = [...document.querySelectorAll("#pppOverlay *")].filter((e) => { const cs = getComputedStyle(e); return /auto|scroll/.test(cs.overflowY + cs.overflowX) && (e.scrollHeight > e.clientHeight + 1 || e.scrollWidth > e.clientWidth + 1); }).map((e) => e.className || e.id);
    out.html = document.getElementById("pppPreview").innerHTML;
    // con 30 pedidos no entra ni al 70 %: piso de legibilidad y recién ahí scrollea
    for (let i = 8; i < 30; i++) _apr.pedidos.push(mk(i));
    aprRender();
    await new Promise((res) => setTimeout(res, 600));
    out.fit30 = { zoom: body.style.zoom, ov: body.style.overflowY, sh: body.scrollHeight, ch: body.clientHeight };
    _apr.pedidos.length = 8;

    // pedido → día
    const calls = [];
    window.fetch = async (url, opt) => {
      const u = String(url); const m = /\/rpc\/([a-z_]+)/.exec(u);
      const ok = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => null } });
      if (m) {
        calls.push({ fn: m[1], body: JSON.parse((opt && opt.body) || "{}") });
        if (m[1] === "gv_ppp_web_tanda_nueva") return ok("E09A");
        if (m[1] === "gv_ppp_web_tanda_agregar") return ok([{ n_np: 1, m3: 0.4, n_avisos: 0 }]);
        if (m[1] === "gv_ppp_web_tanda_programar") {
          if (window.__falla) return { ok: false, status: 400, json: async () => ({ message: "cupo lleno" }), text: async () => '{"message":"cupo lleno"}', headers: { get: () => null } };
          return ok([{ np_programadas: 1, m3: 0.4, lineas_base: 10, aviso_dia: null }]);
        }
        return ok(null);
      }
      return { ok: true, status: 200, json: async () => [], text: async () => "[]", headers: { get: () => "0-0/0" } };
    };
    window.confirm = () => true;
    window.sbAuth = { getAccessToken: async () => "h." + btoa(JSON.stringify({ email: "test@x" })) + ".s" };
    const peds0 = JSON.parse(JSON.stringify(_apr.pedidos));
    const reset = () => { _apr.pedidos = JSON.parse(JSON.stringify(peds0)); _apr.listo = true; _apr.err = ""; _apr.msg = ""; _apr.msgErr = false; };
    const tandaFns = () => calls.map((c) => c.fn).filter((f) => /^gv_ppp_web_tanda_/.test(f));

    // el drop de verdad: aprDropDia con _apr.drag cargado
    reset(); calls.length = 0;
    _apr.drag = _apr.pedidos[0]; _apr.dragTanda = null;
    const fake = { preventDefault() {}, stopPropagation() {}, currentTarget: document.createElement("div") };
    aprDropDia(fake, "2026-09-15");
    await new Promise((res) => setTimeout(res, 300));
    out.drop = { fns: tandaFns(), fecha: (calls.find((c) => c.fn === "gv_ppp_web_tanda_programar") || { body: {} }).body.p_fecha, cod: (calls.find((c) => c.fn === "gv_ppp_web_tanda_programar") || { body: {} }).body.p_codigo, emp: (calls[0] || { body: {} }).body.p_empresa, msg: _apr.msg, err: _apr.msgErr, items: JSON.stringify((calls.find((c) => c.fn === "gv_ppp_web_tanda_programar") || { body: {} }).body.p_items) };

    // falla al programar → descartar
    reset(); calls.length = 0; window.__falla = true;
    await aprGenerarTanda("2026-09-15", ["chef:1354"]);
    out.falla = { fns: tandaFns(), msg: _apr.msg, err: _apr.msgErr, emp: (calls[0] || { body: {} }).body.p_empresa };
    window.__falla = false;

    // aprOver acepta el pedido sobre un día
    _apr.drag = _apr.pedidos[0]; _apr.dragTanda = null;
    let prevented = false; const el = document.createElement("div");
    aprOver({ preventDefault() { prevented = true; }, dataTransfer: {}, currentTarget: el }, "dia");
    out.over = { prevented, on: el.classList.contains("apr-drop-on") };
    return out;
  });

  const fallos = [];
  const chk = (cond, msg) => { console.log((cond ? "ok   " : "MAL  ") + msg); if (!cond) fallos.push(msg); };
  chk(r.fit.sh <= r.fit.ch + 1 && r.fit.sw <= r.fit.cw + 1, "con 8 pedidos la PPP entra entera (zoom " + r.fit.zoom + ")");
  chk(Number(r.fit.zoom) >= 0.7, "y sigue legible (zoom ≥ 0,70)");
  chk(r.conScroll.length === 0, "ningún elemento del overlay scrollea (" + r.conScroll.join(",") + ")");
  chk(Number(r.fit30.zoom) >= 0.7 && r.fit30.ov === "auto" && r.fit30.sh > r.fit30.ch, "con 30 pedidos no baja del 70 %: ahí sí scrollea (zoom " + r.fit30.zoom + ")");
  chk(/apr-wrap apr-2col/.test(r.html) && !/apr-col-tandas/.test(r.html) && !/aprNuevaTanda/.test(r.html), "v13.69: sin tandas sin fecha → dos columnas (pedidos | días), sin botones LK/Chef");
  chk(r.drop.fns.join(">") === "gv_ppp_web_tanda_nueva>gv_ppp_web_tanda_agregar>gv_ppp_web_tanda_programar", "pedido soltado en un día = nueva → agregar → programar (" + r.drop.fns.join(">") + ")");
  chk(r.drop.fecha === "2026-09-15" && r.drop.cod === "E09A" && r.drop.emp === "lk", "con el día del drop, el código que dio la base y la empresa del pedido");
  chk(/"art":"027"/.test(r.drop.items), "los artículos viajan al programar");
  chk(/✅ E09A programada para el mar 15\/9: 1 NP · 0,400 m³/.test(r.drop.msg) && r.drop.err === false, "mensaje verde");
  chk(r.falla.fns.join(">") === "gv_ppp_web_tanda_nueva>gv_ppp_web_tanda_agregar>gv_ppp_web_tanda_programar>gv_ppp_web_tanda_descartar" && /se descartó/.test(r.falla.msg) && r.falla.err === true && r.falla.emp === "chef",
      "si programar falla, la tanda se descarta (ninguna sin fecha) y la empresa es la del pedido (chef)");
  chk(r.over.prevented && r.over.on, "aprOver acepta un pedido sobre un día");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));
  await b.close();
  if (fallos.length) { console.error("\nFALLARON " + fallos.length + ":\n· " + fallos.join("\n· ")); process.exit(1); }
  console.log("\napr-fit OK");
})();

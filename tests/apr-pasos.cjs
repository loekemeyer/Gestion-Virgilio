/* v13.81 — A Programar en DOS PASOS (dueño, desde el celular: "se ve todo muy chiquitito; hagamos dos pasos: armar la
   tanda y después elegir el día") + carga progresiva ("tardan mucho en aparecer pedidos").
   (a) paso 1: tildar pedidos → botonera "Armar tanda → elegir día"; empresa mixta no pasa;
   (b) paso 2: los días se tocan; "Programar ✓" arma + programa en una sola operación (nueva → agregar → programar) y
       vuelve al paso 1 con la selección vacía; si programar falla, descarta y se queda en el paso 2;
   (c) en celular (ancho < 900) no hay zoom: se lee a tamaño normal;
   (d) aprCargar muestra LK apenas llega y Chef después (cargandoChef), sin las llamadas por CUIT de v13.76.
   RPC y feeds interceptados por fetch. Sale 1 si falla. */
const path = require("path");
const { chromium } = require("/opt/node22/lib/node_modules/playwright");
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 430, height: 930 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const calls = [];
    const ok = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => "0-0/0" } });
    window.confirm = () => true; window.alert = () => {};
    window.sbAuth = { getAccessToken: async () => "h." + btoa(JSON.stringify({ email: "test@x" })) + ".s" };
    window.pwebLkToken = async () => "tok";
    let chefResolve; const chefWait = new Promise((res) => { chefResolve = res; });
    window.fetch = async (url, opt) => {
      const u = String(url); const m = /\/rpc\/([a-z_]+)/.exec(u);
      if (m) {
        calls.push({ fn: m[1], body: JSON.parse((opt && opt.body) || "{}") });
        if (m[1] === "gv_pedidos_web_np_chef_admin") { await chefWait; return ok([{ empresa: "chef", order_id: 218, np_idx: 1, cod: "2715", razon_social: "Gifel S.R.L.", fecha_recep: "2026-09-08", direccion: "x", lineas: 5, cajas: 6, items: [{ art: "701", cajas: 1 }], m3: 0.2, m3_parcial: false, localidad: "Barracas" }]); }
        if (m[1] === "gv_ppp_web_tanda_nueva") return ok("E09A");
        if (m[1] === "gv_ppp_web_tanda_agregar") return ok([{ n_np: 1, m3: 0.4, n_avisos: 0 }]);
        if (m[1] === "gv_ppp_web_tanda_programar") {
          if (window.__falla) return { ok: false, status: 400, json: async () => ({ message: "cupo lleno" }), text: async () => '{"message":"cupo lleno"}', headers: { get: () => null } };
          return ok([{ np_programadas: 2, m3: 0.7, lineas_base: 20, aviso_dia: null }]);
        }
        if (m[1] === "gv_ppp_web_calendario") return ok([{ dia: "2026-09-15", habil: true, m3: 3.77, tandas: 6, np: 11, cupo: 6, resta: 2.23 }, { dia: "2026-09-16", habil: true, m3: 0, tandas: 0, np: 0, cupo: 6, resta: 6 }]);
        return ok([]);
      }
      if (u.indexOf("v_pedidos_web_np") >= 0) return ok([
        { empresa: "lk", order_id: 1401, np_idx: 1, cod: "111", razon_social: "Bazar Colucci S.A.", fecha_recep: "2026-09-08", direccion: "x", lineas: 5, cajas: 6, items: [{ art: "027", cajas: 2 }], m3: 0.25, m3_parcial: false, localidad: "Barracas" },
        { empresa: "lk", order_id: 1402, np_idx: 1, cod: "222", razon_social: "Sucesión de Zapata", fecha_recep: "2026-09-08", direccion: "x", lineas: 5, cajas: 6, items: [{ art: "505", cajas: 1 }], m3: 0.45, m3_parcial: false, localidad: "Barracas" }
      ]);
      return ok([]);
    };
    _pppTab = "prog";
    document.getElementById("pppOverlay").classList.add("show");

    // (d) carga progresiva: LK aparece antes de que Chef conteste
    // la solapa dispara su propia carga al abrirse (con la red cortada): esperar a que termine antes de la nuestra
    for (let i = 0; i < 40 && _apr.cargando; i++) await new Promise((res) => setTimeout(res, 100));
    _apr.cargando = false; _apr.listo = false; _apr.err = "";
    const pCarga = aprCargar();
    await new Promise((res) => setTimeout(res, 700));
    const prev = document.getElementById("pppPreview");
    out.lkAntes = { err: _apr.err, listo: _apr.listo, n: (_apr.pedidos || []).length, chef: _apr.cargandoChef, barra: (document.querySelector(".apr-bar") || {}).innerHTML || "", html: prev.innerHTML.indexOf("Bazar Colucci") >= 0 };
    chefResolve(); await pCarga; await new Promise((res) => setTimeout(res, 200));
    out.conChef = { n: (_apr.pedidos || []).length, chef: _apr.cargandoChef, gifel: _apr.pedidos.some((x) => x.empresa === "chef") };
    out.sinCuit = !calls.some((c) => /gv_cuits_de_chef|gv_cuits_con_fc_lk/.test(c.fn));

    // (c) celular: sin zoom
    const body = document.querySelector("#pppOverlay .planim-body");
    out.zoom = body.style.zoom; out.ov = body.style.overflowY;

    // (a) paso 1 — v13.85: el reloj de cuánto lleva esperando cada pedido
    const iso = (n) => { const d = new Date(); d.setDate(d.getDate() - n); return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); };
    _apr.pedidos[0].fecha_recep = iso(0);
    _apr.pedidos[1].fecha_recep = iso(2);
    if (_apr.pedidos[2]) _apr.pedidos[2].fecha_recep = iso(6);
    aprRender();
    out.reloj = [...document.querySelectorAll(".apr-card .apr-chip-esp")].map((e) => e.className.replace("apr-chip apr-chip-esp", "").trim() + "|" + e.textContent.trim());
    out.relojTitulo = (document.querySelector(".apr-col-t .apr-chip-esp") || {}).textContent || "";
    _apr.pedidos[0].fecha_recep = iso(1); aprRender();
    out.ayer = (document.querySelector(".apr-card .apr-chip-esp") || {}).textContent || "";
    _apr.pedidos.forEach((x, i) => { x.fecha_recep = iso(i === 0 ? 0 : 2); }); aprRender();
    out.p1 = { chks: prev.querySelectorAll("input.apr-sel-chk").length, foot: !!prev.querySelector(".apr-foot"), btnOff: !!(prev.querySelector(".apr-foot-btn") || {}).disabled, dias: prev.querySelectorAll(".apr-dia").length };
    aprSel("lk:1401"); aprSel("lk:1402");
    out.p1sel = { txt: prev.querySelector(".apr-foot-txt").textContent, btnOff: !!prev.querySelector(".apr-foot-btn").disabled, marcadas: prev.querySelectorAll(".apr-card-sel").length };
    // empresa mixta no pasa
    aprSel("chef:218"); aprPasoDia();
    out.mixta = { paso: _apr.paso, msg: _apr.msg };
    aprSel("chef:218"); _apr.msg = ""; _apr.msgErr = false;

    // (b) paso 2
    aprPasoDia();
    out.p2 = { paso: _apr.paso, dias: prev.querySelectorAll(".apr-dia").length, chips: prev.querySelectorAll(".apr-sel-chip").length, btnOff: !!prev.querySelector(".apr-foot-btn").disabled, tocable: !!prev.querySelector('.apr-dia[onclick*="aprElegirDia"]') };
    aprElegirDia("2026-09-15");
    out.p2dia = { sel: prev.querySelectorAll(".apr-dia-sel").length, btnOff: !!prev.querySelector(".apr-foot-btn").disabled, txt: prev.querySelector(".apr-foot-txt").textContent };
    // v13.84: día completo / muy pronto y tanda chica → PREGUNTA (y se puede decir que no)
    const preg = [];
    window.confirm = (m) => { preg.push(String(m)); return false; };
    _apr.cal.push({ dia: "2026-09-11", habil: true, m3: 10.07, tandas: 12, np: 36, cupo: 6, resta: 0 });
    _apr.cal.push({ dia: "2026-09-08", habil: true, m3: 8.87, tandas: 2, np: 2, cupo: 6, resta: 0, muy_pronto: true, dia_minimo: "2026-09-11" });
    _apr.m3Min = 0.6;
    calls.length = 0;
    aprElegirDia("2026-09-11"); await aprConfirmar();
    out.pregLleno = { txt: preg[preg.length - 1] || "", rpc: calls.length };
    aprElegirDia("2026-09-11"); aprElegirDia("2026-09-08"); await aprConfirmar();
    out.pregPronto = { txt: preg[preg.length - 1] || "", rpc: calls.length };
    // el día libre con 0,70 m³ (> 0,60) no pregunta nada
    preg.length = 0; aprElegirDia("2026-09-08"); aprElegirDia("2026-09-16");
    window.confirm = () => true;
    calls.length = 0; await aprConfirmar();
    out.sinPreg = { preg: preg.length, fns: calls.map((c) => c.fn).filter((f) => /^gv_ppp_web_tanda_/.test(f)).join(">") };
    // tanda chica: un solo pedido de 0,25 m³
    _apr.sel = {}; aprSel("lk:1401"); _apr.paso = 2; _apr.diaSel = "2026-09-16";
    preg.length = 0; window.confirm = (m) => { preg.push(String(m)); return true; };
    calls.length = 0; await aprConfirmar();
    out.pregChica = { txt: preg[0] || "", programo: calls.some((c) => c.fn === "gv_ppp_web_tanda_programar") };
    window.confirm = () => true;

    // falla → descarta y se queda en el paso 2
    _apr.sel = {}; aprSel("lk:1401"); aprSel("lk:1402"); _apr.paso = 2; _apr.diaSel = "2026-09-15";
    calls.length = 0; window.__falla = true;
    await aprConfirmar();
    out.falla = { fns: calls.map((c) => c.fn).filter((f) => /^gv_ppp_web_tanda_/.test(f)).join(">"), paso: _apr.paso, err: _apr.msgErr, sel: aprSelKeys().length };
    window.__falla = false;
    // ok → paso 1, selección vacía
    _apr.paso = 2; _apr.diaSel = "2026-09-15"; calls.length = 0;
    await aprConfirmar();
    out.okk = { fns: calls.map((c) => c.fn).filter((f) => /^gv_ppp_web_tanda_/.test(f)).join(">"), fecha: (calls.find((c) => c.fn === "gv_ppp_web_tanda_programar") || { body: {} }).body.p_fecha, paso: _apr.paso, sel: aprSelKeys().length, msg: _apr.msg, err: _apr.msgErr };
    return out;
  });
  await b.close();
  if (process.env.APR_DEBUG) console.log(JSON.stringify(r, null, 1));

  const fallos = [];
  const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fallos.push(m); };
  chk(r.lkAntes.listo && r.lkAntes.n === 2 && r.lkAntes.chef === true && r.lkAntes.html && /cargando Chef/.test(r.lkAntes.barra), "LK se muestra antes de que Chef conteste, con 'cargando Chef…' en la barra");
  chk(r.conChef.n === 3 && r.conChef.chef === false && r.conChef.gifel, "Chef se suma después");
  chk(r.sinCuit, "sin las llamadas por CUIT de v13.76 (regla apagada)");
  chk(r.zoom === "1" && r.ov === "auto", "en celular no hay zoom y scrollea (zoom " + r.zoom + ", " + r.ov + ")");
  chk(r.p1.chks === 3 && r.p1.foot && r.p1.btnOff && r.p1.dias === 0, "paso 1: tildes, botonera deshabilitada sin selección y sin días");
  // v13.85 (dueño: "poné un reloj que diga hace cuánto llegó un pedido")
  chk(r.reloj[0] === "|⏱ hoy", "el pedido de hoy dice 'hoy', sin color (" + r.reloj[0] + ")");
  chk(r.reloj[1] === "medio|⏱ hace 2 días", "a los 2 días, ámbar (" + r.reloj[1] + ")");
  chk(r.reloj[2] === "viejo|⏱ hace 6 días", "a los 6 días, rojo (" + r.reloj[2] + ")");
  chk(/el más viejo, hace 6 días/.test(r.relojTitulo), "el título de la columna avisa cuál es el más viejo (" + r.relojTitulo + ")");
  chk(r.ayer === "⏱ ayer", "un pedido de ayer dice 'ayer' (" + r.ayer + ")");
  chk(/2 pedidos · 0,70 m³ · LK/.test(r.p1sel.txt) && !r.p1sel.btnOff && r.p1sel.marcadas === 2, "con 2 tildados: '2 pedidos · 0,70 m³ · LK' y botón habilitado");
  chk(r.mixta.paso === 1 && /una sola empresa/.test(r.mixta.msg), "LK + Chef juntos no pasan al paso 2");
  chk(r.p2.paso === 2 && r.p2.dias === 2 && r.p2.chips === 2 && r.p2.btnOff && r.p2.tocable, "paso 2: días tocables, resumen de los pedidos, Programar deshabilitado hasta tocar un día");
  chk(r.p2dia.sel === 1 && !r.p2dia.btnOff && /→ mar 15\/9/.test(r.p2dia.txt), "tocar el día lo marca y habilita Programar");
  chk(/ya está completo/.test(r.pregLleno.txt) && r.pregLleno.rpc === 0, "un día COMPLETO pregunta y, si se dice que no, no llama a nada");
  chk(/antes de la anticipación mínima/.test(r.pregPronto.txt) && r.pregPronto.rpc === 0, "un día MUY PRONTO pregunta (v13.84: ya no lo bloquea)");
  chk(r.sinPreg.preg === 0 && /gv_ppp_web_tanda_programar/.test(r.sinPreg.fns), "un día libre con 0,70 m³ no pregunta nada");
  chk(/0,25 m³, menos de los 0,60/.test(r.pregChica.txt) && r.pregChica.programo, "una tanda de menos de 0,60 m³ pregunta y, si se acepta, programa");
  chk(r.falla.fns === "gv_ppp_web_tanda_nueva>gv_ppp_web_tanda_agregar>gv_ppp_web_tanda_agregar>gv_ppp_web_tanda_programar>gv_ppp_web_tanda_descartar" && r.falla.paso === 2 && r.falla.err && r.falla.sel === 2, "si programar falla: descarta la tanda y se queda en el paso 2 con la selección");
  chk(r.okk.fns === "gv_ppp_web_tanda_nueva>gv_ppp_web_tanda_agregar>gv_ppp_web_tanda_agregar>gv_ppp_web_tanda_programar" && r.okk.fecha === "2026-09-15" && r.okk.paso === 1 && r.okk.sel === 0 && /✅ E09A programada para el mar 15\/9/.test(r.okk.msg) && !r.okk.err, "Programar ✓ = nueva → agregar ×2 → programar, y vuelve al paso 1 vacío");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));
  if (fallos.length) { console.error("\nFALLARON " + fallos.length + ":\n· " + fallos.join("\n· ")); process.exit(1); }
  console.log("\napr-pasos OK");
})();

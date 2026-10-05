/* v26.24 (Luis, 02/10) — HELPER LOCAL DE IMPRESIÓN (http://127.0.0.1:17777, SumatraPDF).
   Levanta un helper FALSO en 127.0.0.1 (mismo contrato: GET / y POST /print?tipo=, CORS con
   Access-Control-Allow-Private-Network) y corre index.html de verdad: lo que mide es el PDF que
   le LLEGA al helper, no el texto del código.
     A. Helper apagado (default) → la hoja sale por el navegador y el helper no recibe nada.
     B. Helper prendido → POST /print?tipo=armado con Content-Type application/pdf y un PDF A4
        real (%PDF, 1 página, la imagen NO está en blanco); el navegador no imprime.
     C. Tres hojas seguidas → llegan EN ORDEN y de a una (nunca 2 a la vez).
     D. Una hoja larga → el PDF tiene 2+ páginas.
     E. El helper contesta ok:false sin imprimir nada → la hoja sale por el navegador.
     F. El helper imprimió una parte (impreso con algo) → NO se repite por el navegador.
     G. Helper cerrado (nadie escucha el puerto) → sale por el navegador y queda «no contesta».
     H. El puerto es configurable; uno inválido vuelve al 17777.
     I. La estación (psPoll) manda el armado al helper; pkHojaImprimir manda picking;
        facMaybePrintFacturado manda facturado.
     J. Sin respuesta en el tiempo de espera → NO se repite por el navegador (puede haber salido).
     K. v26.28 — en ⚙️ Configuración hay UN botón «Helper de impresión» (y nada más del helper): abre
        el pop-up con el estado (🟢) y el puerto; Desconectar lo apaga; Conectar a un puerto muerto NO
        lo prende; Conectar al puerto vivo lo prende. La Cola de impresión no habla del helper.
     L. gvHelperVigilar arranca la estación sola con helper + auto de la estación.
     M. v26.26 — el programa de la v26.12 se sacó: ni 🧩 Impresoras, ni cola en la base, ni gv_imp_encolar.
     O. v26.65 — lo AUTOMÁTICO (gvImprimirAuto) sale sólo por el helper: con ok:false NO abre el cuadro y no
        marca; si salió, marca; sin helper no hace nada; con el helper que no contesta la estación (psPoll)
        no imprime ni abre el cuadro y corre los cursores (queda en la Cola de impresión NP).
   Sale 1 si algo falla. */
const path = require("path");
const http = require("http");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const H = { reqs: [], modo: "ok", demora: 0, activos: 0, maxActivos: 0 };
// v26.58 — los mismos headers y el mismo ping que el helper real v1.2.0 (Responder() de ImpresionVirgilio.cs).
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-Virgilio-Tipo", "Access-Control-Allow-Private-Network": "true",
  "Access-Control-Max-Age": "86400" };
const helper = http.createServer((req, res) => {
  if (req.method === "OPTIONS") { res.writeHead(204, cors); return res.end(); }
  if (req.method === "GET" && req.url === "/") { res.writeHead(200, Object.assign({ "Content-Type": "text/plain" }, cors)); return res.end("Impresion Virgilio OK v1.2.0"); }
  if (req.method === "POST" && req.url.indexOf("/print?") === 0) {
    const chunks = [];
    H.activos++; H.maxActivos = Math.max(H.maxActivos, H.activos);
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => {
      const buf = Buffer.concat(chunks);
      const tipo = new URL(req.url, "http://x").searchParams.get("tipo");
      const txt = buf.toString("latin1");
      H.reqs.push({ tipo, ct: req.headers["content-type"], pdf: txt.indexOf("%PDF-") === 0, paginas: (txt.match(/\/Type \/Page[^s]/g) || []).length,
        a4: /\/MediaBox \[0 0 595\.2\d* 841\.8\d*\]/.test(txt), kb: Math.round(buf.length / 1024) });
      const modo = H.modo;
      setTimeout(() => {
        H.activos--;
        let j = { ok: true, tipo, impreso: ["HP Deposito"], errores: [], motivo: "" };
        if (modo === "sinregla") j = { ok: false, tipo, impreso: [], errores: [], motivo: "sin regla para " + tipo };
        if (modo === "parcial") j = { ok: false, tipo, impreso: ["HP Deposito"], errores: ["Brother: offline"], motivo: "1 de 2" };
        res.writeHead(200, Object.assign({ "Content-Type": "application/json" }, cors)); res.end(JSON.stringify(j));
      }, H.demora);
    });
    return;
  }
  res.writeHead(404, cors); res.end("no");
});

(async () => {
  await new Promise((r) => helper.listen(0, "127.0.0.1", r));
  const PUERTO = helper.address().port;
  const muerto = http.createServer(); await new Promise((r) => muerto.listen(0, "127.0.0.1", r));
  const PUERTO_MUERTO = muerto.address().port; await new Promise((r) => muerto.close(r));   // nadie escucha ahí

  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  await p.waitForFunction(() => !!(window.jspdf && window.jspdf.jsPDF), null, { timeout: 15000 });

  const ctl = async (k, v) => { H[k] = v; };
  const n = () => H.reqs.length;
  const out = {};

  // red: lo de 127.0.0.1 va de verdad al helper falso; Supabase stubbeado
  await p.evaluate(() => {
    const real = window.fetch.bind(window);
    window.__S = { talRows: [], tpRows: [], imptRows: [], facRows: [], nav: [], imgs: [] };
    window.fetch = function (url, opts) {
      const u = String(url);
      if (u.indexOf("http://127.0.0.1:") === 0) return real(url, opts);
      const ok = function (j) { return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve(j); } }); };
      if (u.indexOf("opcion=eq.IMPT") >= 0) return ok(window.__S.imptRows);
      if (u.indexOf("/Facturacion_NP?") >= 0) return ok(window.__S.facRows);
      if (u.indexOf("opcion=eq.TAL") >= 0) return ok(window.__S.talRows);
      if (u.indexOf("opcion=eq.TP") >= 0) return ok(window.__S.tpRows);
      return ok([]);
    };
    window.facAuthWriteHeaders = async function () { return { apikey: "k", Authorization: "Bearer jwt", "Content-Type": "application/json" }; };
    window._remitoPrintNavegador = function (inner) { window.__S.nav.push(String(inner)); };
    window.colaImpLoadBadge = function () {}; window.colaImpMarcarImpresas = function () {}; window.facShowToast = function () {};
    // captura lo que se pega en el PDF para medir que la hoja NO salga en blanco
    // los métodos de jsPDF viven en jsPDF.API (se copian a cada instancia), no en el prototype
    const J = window.jspdf.jsPDF.API; const add = J.addImage;
    J.addImage = function (data) { if (typeof data === "string") window.__S.imgs.push(data); return add.apply(this, arguments); };
    window.__tinta = async function (dataUrl) {
      const img = new Image(); await new Promise(function (ok, mal) { img.onload = ok; img.onerror = mal; img.src = dataUrl; });
      const c = document.createElement("canvas"); c.width = img.width; c.height = img.height;
      const cx = c.getContext("2d"); cx.drawImage(img, 0, 0); const d = cx.getImageData(0, 0, c.width, c.height).data;
      let t = 0; for (let i = 0; i < d.length; i += 16) if (d[i] + d[i + 1] + d[i + 2] < 300) t++;
      return t;
    };
    window.__espera = function (cond, ms) { return new Promise(function (ok) { const t0 = Date.now(); (function v() { if (cond() || Date.now() - t0 > ms) ok(); else setTimeout(v, 40); })(); }); };
  });
  const HOJA = '<div class="rmt-sec">HOJA DE PRUEBA</div><table class="rmt-table"><tr><td class="rmt-cc">501</td><td>12</td></tr><tr><td class="rmt-cc">438E</td><td>4</td></tr></table>';

  // ---- A. apagado (default)
  out.A_apagadoDefault = await p.evaluate(() => gvHelperActivo() === false && gvHelperCfg().puerto === 17777);
  await p.evaluate((h) => { window.__S.nav.length = 0; remitoPrintDoc(h, "armado", "98010"); }, HOJA);
  await p.waitForTimeout(300);
  out.A_navegador = (await p.evaluate(() => window.__S.nav.length)) === 1 && n() === 0;

  // ---- H. puerto configurable
  out.H_puerto = await p.evaluate((pt) => {
    gvHelperGuardar({ on: true, puerto: 70000 }); const inval = gvHelperCfg().puerto === 17777;
    gvHelperGuardar({ puerto: pt }); return inval && gvHelperCfg().puerto === pt && gvHelperUrl("/x") === "http://127.0.0.1:" + pt + "/x";
  }, PUERTO);
  out.H_ping = await p.evaluate(() => helperVivo());

  // ---- B. prendido → PDF real al helper
  await p.evaluate((h) => { window.__S.nav.length = 0; window.__S.imgs.length = 0; return gvHelperEncolar("armado", h, "98010"); }, HOJA);
  const rb = H.reqs[0] || {};
  const tintaB = await p.evaluate(() => window.__S.imgs.length ? window.__tinta(window.__S.imgs[0]) : 0);
  out.B_pdf = n() === 1 && rb.tipo === "armado" && rb.ct === "application/pdf" && rb.pdf && rb.paginas === 1 && rb.a4;
  out.B_noBlanco = tintaB > 200;
  out.B_sinNavegador = (await p.evaluate(() => window.__S.nav.length)) === 0;
  out.B_viaRemitoPrintDoc = await p.evaluate(async (h) => { remitoPrintDoc(h, "picking", "E50A"); await _gvHelper.cadena; return true; }, HOJA) && H.reqs[1] && H.reqs[1].tipo === "picking";

  // ---- C. tres en fila, en orden
  H.reqs.length = 0; H.maxActivos = 0; await ctl("demora", 250);
  await p.evaluate(async (h) => { remitoPrintDoc(h, "picking", "1"); remitoPrintDoc(h, "armado", "2"); remitoPrintDoc(h, "facturado", "3"); await _gvHelper.cadena; }, HOJA);
  out.C_orden = H.reqs.map((x) => x.tipo).join(",") === "picking,armado,facturado";
  out.C_deAUna = H.maxActivos === 1;
  await ctl("demora", 0);

  // ---- D. hoja larga → 2+ páginas
  H.reqs.length = 0;
  await p.evaluate(async () => {
    let filas = ""; for (let i = 0; i < 160; i++) filas += '<tr><td class="rmt-cc">' + (500 + i) + '</td><td>' + i + '</td><td>Lío ' + i + '</td></tr>';
    remitoPrintDoc('<div class="rmt-sec">LARGA</div><table class="rmt-table">' + filas + '</table>', "picking", "LARGA"); await _gvHelper.cadena;
  });
  out.D_variasPaginas = (H.reqs[0] || {}).paginas >= 2;

  // ---- E. ok:false sin imprimir → navegador
  H.reqs.length = 0; await ctl("modo", "sinregla");
  await p.evaluate(async (h) => { window.__S.nav.length = 0; remitoPrintDoc(h, "facturado", "LK 0300"); await _gvHelper.cadena; }, HOJA);
  out.E_alNavegador = n() === 1 && (await p.evaluate(() => window.__S.nav.length === 1 && _gvHelper.log[0].alNavegador === true && /sin regla/.test(_gvHelper.log[0].motivo)));

  // ---- F. parcial → no se repite
  await ctl("modo", "parcial");
  await p.evaluate(async (h) => { window.__S.nav.length = 0; remitoPrintDoc(h, "armado", "98011"); await _gvHelper.cadena; }, HOJA);
  out.F_parcialNoRepite = await p.evaluate(() => window.__S.nav.length === 0 && _gvHelper.log[0].alNavegador === false);
  await ctl("modo", "ok");

  // ---- G. helper cerrado → navegador
  out.G_cerrado = await p.evaluate(async (args) => {
    gvHelperGuardar({ puerto: args.muerto }); window.__S.nav.length = 0;
    remitoPrintDoc(args.h, "armado", "98012"); await _gvHelper.cadena;
    const r = window.__S.nav.length === 1 && _gvHelper.vivo === false && /no disponible/.test(_gvHelper.log[0].motivo) && /no contesta/i.test(_gvHelperEstadoTxt());
    gvHelperGuardar({ puerto: args.vivo }); return r;
  }, { muerto: PUERTO_MUERTO, vivo: PUERTO, h: HOJA });

  // ---- I. los caminos del pipeline
  H.reqs.length = 0;
  out.I_estacionArmado = await p.evaluate(async () => {
    localStorage.setItem("ps_auto_virgilio", "1"); _ps = null;
    window._armadoRemitoDataForItems = async function (items) { return items.map(function (x) { return armadoRemitoData({ np: x.np, tanda: x.tanda, cod: "1", rs: "Cliente", salePpp: "2026-10-02", fecha: "2026-10-02", resumen: x.resumen }); }); };
    window.__S.talRows = [{ texto: "98020|1|E50A|C=3X2|L1", ts_cliente: "2099-01-01T12:00:00-03:00", legajo: "104" }];
    window.__S.tpRows = [];
    await psPoll(true);
    await window.__espera(function () { return _gvHelper.log.some(function (e) { return e.ref === "98020"; }); }, 8000);
    await _gvHelper.cadena; return true;
  }) && H.reqs.some((x) => x.tipo === "armado");
  out.I_picking = await p.evaluate(async () => {
    window.pkHojaDatos = async function (ts) { return ts.map(function (t) { return { tanda: t }; }); };
    window.pkHojaHtml = function (d) { return '<div class="rmt-sec">PICKING ' + d.tanda + '</div>'; };
    await pkHojaImprimir(["E51A"], false); await _gvHelper.cadena;
    return _gvHelper.log[0].ref === "E51A" && _gvHelper.log[0].tipo === "picking";
  }) && H.reqs.some((x) => x.tipo === "picking");
  out.I_facturado = await p.evaluate(async () => {
    window.facFacturadoInner = async function (np) { return '<div class="rmt-sec">FACTURADO ' + np + '</div>'; };
    window._facIsMobile = function () { return false; }; _facPrintGlobal = "1";
    // v26.32 — la PC que factura NO imprime: el facturado lo saca la estación de la PC del helper
    const antes = _gvHelper.log.length; window.__S.nav.length = 0;
    await facMaybePrintFacturado("LK 0399", "E52A"); await _gvHelper.cadena;
    const noImprimeQuienFactura = _gvHelper.log.length === antes && window.__S.nav.length === 0;
    // primera vez en la PC: arranca desde ahora, no vuelca lo facturado antes
    localStorage.removeItem("ps_lastseen_fac_virgilio"); _ps.lastSeenFac = "";
    const ya = new Date(Date.now() - 60000).toISOString(), ahora = new Date(Date.now() + 1000).toISOString();
    window.__S.facRows = [{ np: "LK 0398", tanda: "E52A", facturado_at: ya }];
    await psPoll(true); await new Promise(function (ok) { setTimeout(ok, 300); }); await _gvHelper.cadena;
    const sinVolcar = _gvHelper.log.length === antes && !!localStorage.getItem("ps_lastseen_fac_virgilio");
    // después: lo nuevo sale por el helper como facturado, una sola vez
    _psSetLastFac(ya);
    window.__S.facRows = [{ np: "LK 0400", tanda: "E52A", facturado_at: ahora }, { np: "LK 0400", tanda: "E52A", facturado_at: ahora }];
    await psPoll(true);
    await window.__espera(function () { return _gvHelper.log.some(function (e) { return e.ref === "LK 0400"; }); }, 8000); await _gvHelper.cadena;
    const n400 = _gvHelper.log.filter(function (e) { return e.ref === "LK 0400"; });
    await psPoll(true); await new Promise(function (ok) { setTimeout(ok, 300); }); await _gvHelper.cadena;
    const r = noImprimeQuienFactura && sinVolcar && n400.length === 1 && n400[0].tipo === "facturado" && n400[0].ok === true &&
      _gvHelper.log.filter(function (e) { return e.ref === "LK 0400"; }).length === 1;
    window.__S.facRows = [];
    return r;
  }) && H.reqs.filter((x) => x.tipo === "facturado").length === 1;

  // ---- J. sin respuesta a tiempo → no se repite
  await ctl("demora", 1500);
  out.J_timeoutNoRepite = await p.evaluate(async (h) => {
    GV_HELPER_ESPERA_MS = 400; window.__S.nav.length = 0;
    remitoPrintDoc(h, "armado", "98030"); await _gvHelper.cadena; GV_HELPER_ESPERA_MS = 60000;
    return window.__S.nav.length === 0 && /no contestó/.test(_gvHelper.log[0].motivo) && _gvHelper.log[0].alNavegador === false;
  }, HOJA);
  await ctl("demora", 0); await p.waitForTimeout(1300);

  // ---- K. ⚙️ Configuración: UN botón «Helper de impresión» → pop-up para conectar
  H.reqs.length = 0;
  out.K_boton = await p.evaluate(async () => {
    window.__isSupervisor = true; window.requireSupervisor = function () { return true; }; openConfiguracion();
    const cfg = document.getElementById("configOverlay");
    const btns = Array.from(cfg.querySelectorAll("button")).filter(function (x) { return /Helper de impresi/.test(x.textContent); });
    const sinTarjeta = !document.getElementById("gvHelperCfgRow") && cfg.innerHTML.indexOf("127.0.0.1") < 0;
    if (btns.length !== 1 || !sinTarjeta) return false;
    btns[0].click();
    await window.__espera(function () { var o = document.getElementById("gvHelperOv"); return o && o.classList.contains("show") && /🟢/.test(o.textContent); }, 6000);
    const o = document.getElementById("gvHelperOv");
    return !!o && o.classList.contains("show") && /🟢/.test(o.textContent) && !!o.querySelector("#gvHelperPuerto") &&
      !document.getElementById("configOverlay").classList.contains("show");
  });
  out.K_desconectar = await p.evaluate(async () => {
    const b = document.getElementById("gvHelperDesconectar"); if (!b) return false;
    b.click(); await window.__espera(function () { return !gvHelperActivo(); }, 2000);
    return !gvHelperActivo() && !psIsAuto() && /Desconectado/.test(document.getElementById("gvHelperEst").textContent) && !document.getElementById("gvHelperDesconectar");
  });
  out.K_conectarMuerto = await p.evaluate(async (pt) => {
    document.getElementById("gvHelperPuerto").value = String(pt);
    await gvHelperConectar();
    return !gvHelperActivo() && /✗/.test(document.getElementById("gvHelperMsg").textContent);
  }, PUERTO_MUERTO);
  out.K_conectar = await p.evaluate(async (pt) => {
    document.getElementById("gvHelperPuerto").value = String(pt);
    document.getElementById("gvHelperConectar").click();
    await window.__espera(function () { return gvHelperActivo() && /🟢/.test((document.getElementById("gvHelperEst") || {}).textContent || ""); }, 4000);
    const ok = gvHelperActivo() && psIsAuto() && gvHelperCfg().puerto === pt && /✓/.test(document.getElementById("gvHelperMsg").textContent);   // v26.30: conectar = imprime sola
    closeHelperImpresion();
    return ok && !document.getElementById("gvHelperOv").classList.contains("show");
  }, PUERTO);
  out.K_colaSinHelper = await p.evaluate(async () => {
    try { openPrintStation(); } catch (_e) {}
    await new Promise(function (ok) { setTimeout(ok, 300); });
    const body = document.getElementById("psBody"); const txt = body ? body.innerHTML : "";
    if (_ps && _ps.timer) { clearInterval(_ps.timer); _ps.timer = null; }
    closePrintStation();
    return !!txt && !/helper/i.test(txt);
  });

  // ---- L. la estación arranca sola con helper + auto
  out.L_vigilar = await p.evaluate(async () => {
    if (_ps && _ps.timer) { clearInterval(_ps.timer); _ps.timer = null; }
    window.__isSupervisor = true; window.__tvKioskMode = false; localStorage.setItem("ps_auto_virgilio", "1");
    await gvHelperVigilar(); await window.__espera(function () { return !!(_ps && _ps.timer); }, 3000);   // psStart es async
    const r = !!(_ps && _ps.timer);
    if (_ps && _ps.timer) { clearInterval(_ps.timer); _ps.timer = null; }
    gvHelperGuardar({ on: false }); await gvHelperVigilar(); await new Promise(function (ok) { setTimeout(ok, 600); });
    const apagado = !(_ps && _ps.timer);
    return r && apagado;
  });

  // ---- N. v26.30 — señal de prueba IMPT: llega por el sondeo de la estación y sale por el helper con su tipo
  H.reqs.length = 0;
  out.N_senalPrueba = await p.evaluate(async () => {
    if (_ps && _ps.timer) { clearInterval(_ps.timer); _ps.timer = null; }
    gvHelperGuardar({ on: true }); localStorage.setItem("ps_auto_virgilio", "1"); _gvHelper.log.length = 0;
    window.__S.talRows = []; window.__S.tpRows = [];
    window.__S.imptRows = [
      { id: "a1", texto: "picking", descripcion: "test picking", ts_cliente: "2099-01-02T10:00:00-03:00" },
      { id: "a2", texto: "armado", descripcion: "test armado", ts_cliente: "2099-01-02T10:00:01-03:00" },
      { id: "a3", texto: "facturado", descripcion: "test factura", ts_cliente: "2099-01-02T10:00:02-03:00" },
      { id: "a4", texto: "cualquiera", descripcion: "no va", ts_cliente: "2099-01-02T10:00:03-03:00" }];
    await psPoll(true);
    await window.__espera(function () { return _gvHelper.log.length >= 3; }, 15000); await _gvHelper.cadena;
    const tipos = _gvHelper.log.map(function (e) { return e.tipo; }).sort().join(",");
    const antes = _gvHelper.log.length;
    _ps.lastSeenImpt = "";   // vuelve a leer las mismas: no se repiten (dedup por id)
    await psPoll(true); await new Promise(function (ok) { setTimeout(ok, 400); }); await _gvHelper.cadena;
    return tipos === "armado,facturado,picking" && _gvHelper.log.length === antes &&
      /test factura/.test(_psHojaPrueba("test factura"));
  }) && ["picking", "armado", "facturado"].every((t) => H.reqs.filter((x) => x.tipo === t).length === 1);
  out.N_sinHelperNoImprime = await p.evaluate(async () => {
    gvHelperGuardar({ on: false }); _gvHelper.log.length = 0; window.__S.nav.length = 0;
    window.__S.imptRows = [{ id: "b1", texto: "armado", descripcion: "test armado", ts_cliente: "2099-01-03T10:00:00-03:00" }];
    _ps.lastSeenImpt = ""; await psPoll(true); await new Promise(function (ok) { setTimeout(ok, 400); });
    return _gvHelper.log.length === 0 && window.__S.nav.length === 0;
  });

  // ---- O. v26.65 (Luis, 05/10) — lo AUTOMÁTICO sale sólo por el helper conectado y respondiendo: nunca el
  //         cuadro, y la hoja se marca impresa sólo si salió (si no, queda pendiente en la Cola de impresión NP).
  H.reqs.length = 0; await ctl("modo", "sinregla");
  out.O_autoNoCuadro = await p.evaluate(async (h) => {
    gvHelperGuardar({ on: true }); window.__S.nav.length = 0; window.__S.marcas = [];
    window.colaImpMarcarImpresas = function (nps) { window.__S.marcas = window.__S.marcas.concat(nps); };
    const r = await gvImprimirAuto("armado", h, "98040", "98040");
    return r.ok === false && window.__S.nav.length === 0 && window.__S.marcas.length === 0 && _gvHelper.log[0].alNavegador === false && _gvHelper.log[0].auto === true;
  }, HOJA) && n() === 1;
  await ctl("modo", "ok");
  out.O_autoMarcaSiSalio = await p.evaluate(async (h) => {
    window.__S.marcas = [];
    const r = await gvImprimirAuto("facturado", h, "LK 0401", "FAC LK 0401");
    return r.ok === true && window.__S.marcas.join() === "FAC LK 0401" && window.__S.nav.length === 0;
  }, HOJA);
  out.O_sinHelperNoHaceNada = await p.evaluate(async (h) => {
    gvHelperGuardar({ on: false }); window.__S.marcas = []; const antes = _gvHelper.log.length;
    const r = await gvImprimirAuto("armado", h, "98041", "98041");
    gvHelperGuardar({ on: true });
    return r.ok === false && _gvHelper.log.length === antes && window.__S.nav.length === 0 && window.__S.marcas.length === 0;
  }, HOJA);
  // helper prendido pero que no contesta: la estación no imprime nada, no abre el cuadro y corre los cursores
  H.reqs.length = 0;
  out.O_helperMuertoEstacion = await p.evaluate(async (pt) => {
    if (_ps && _ps.timer) { clearInterval(_ps.timer); _ps.timer = null; }
    const vivo = gvHelperCfg().puerto;
    gvHelperGuardar({ on: true, puerto: pt }); window.__S.nav.length = 0; window.__S.marcas = []; _gvHelper.log.length = 0;
    window.__S.talRows = [{ texto: "98050|1|E60A|C=3X2|L1", ts_cliente: "2099-02-01T12:00:00-03:00", legajo: "104" }];
    window.__S.tpRows = [{ texto: "E60A", ts_cliente: "2099-02-01T11:00:00-03:00" }];
    _ps.lastSeen = "2026-01-01T00:00:00-03:00";
    await psPoll(true); await new Promise(function (ok) { setTimeout(ok, 500); });
    const r = window.__S.nav.length === 0 && _gvHelper.log.length === 0 && window.__S.marcas.length === 0 &&
      _ps.lastSeen > "2026-10-01" && /no contesta/.test(_ps.lastErr || "");
    gvHelperGuardar({ puerto: vivo }); window.__S.talRows = []; window.__S.tpRows = [];
    return r;
  }, PUERTO_MUERTO) && n() === 0;

  // ---- M. el programa de la v26.12 no volvió (Luis, 02/10: "me quedo con mi helper, sacá lo otro")
  out.M_sinPrograma = await p.evaluate(() => {
    const cfg = document.getElementById("configOverlay");
    return typeof window.openImpresoras === "undefined" && typeof window.gvImpEncolar === "undefined" &&
      typeof window.gvImpModo === "undefined" && !!cfg && cfg.innerHTML.indexOf("openImpresoras") < 0 &&
      typeof window.gvHelperPrueba === "undefined" && typeof window.gvHelperCardHtml === "undefined";
  });
  out.M_sinRpcPrograma = !require("fs").readFileSync(require("path").join(__dirname, "..", "index.html"), "latin1").match(/gv_imp_(encolar|config|regla_guardar|trabajos|agente)/);

  await b.close(); helper.close();
  const fallas = Object.keys(out).filter((k) => out[k] !== true);
  const errReales = errs.filter((e) => !/Failed to fetch|NetworkError|AbortError|ERR_/.test(e));
  console.log(JSON.stringify(out, null, 1));
  if (errReales.length) console.log("pageerror:", errReales.slice(0, 5));
  if (fallas.length || errReales.length) { console.log("✗ imp-helper-local: " + fallas.join(", ")); process.exit(1); }
  console.log("✓ imp-helper-local (" + Object.keys(out).length + " chequeos)");
})().catch((e) => { console.error(e); process.exit(1); });

/* v13.77 — Tierra del Fuego (dueño: "el pedido se arma como Loeke, con una L al final, y después va a ISIS de CH,
   no de LK"). Una NP de la página LK cuya entrega es en Tierra del Fuego sale de la vista de LK con
   isis_empresa = 'chef' y cod_isis = código Chef del mismo CUIT. Facturación: (a) la fila del Excel va al archivo
   CH, con el código Chef y tope 15; (b) los artículos ya vienen con L desde la vista (acá: 505L en Entregas);
   (c) una NP LK común sigue en el archivo LK con su código; (d) sin respuesta de LK, nada cambia.
   Todo con fetch stubbeado. Sale 1 si falla. */
const path = require("path");
const { chromium } = require("/opt/node22/lib/node_modules/playwright");
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    window.alert = function (m) { (out.alerts = out.alerts || []).push(String(m)); }; window.confirm = function () { return true; };
    window.__isSupervisor = true;
    window.requireSupervisor = function () { return true; };
    window.pwebLkToken = async function () { return "tok"; };
    function J(data) { return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve(data); } }); }
    const urls = [];
    const ent = [
      { id: 1, np: "LK 0030", cod_art: "505L", cajas_pedidas: 2, cajas_entregadas: 2 },
      { id: 2, np: "LK 0030", cod_art: "438EL", cajas_pedidas: 1, cajas_entregadas: 1 },
      { id: 3, np: "LK 0031", cod_art: "505", cajas_pedidas: 3, cajas_entregadas: 3 }
    ];
    window.fetch = function (url) {
      url = String(url); urls.push(url);
      if (url.indexOf("Entregas_Virgilio") >= 0) return J(ent);
      if (url.indexOf("PPP_Web_Programacion") >= 0) return J([
        { np: 30, np_idx: 1, empresa: "lk", order_id: 1400, fecha_recep: "2026-09-08" },
        { np: 31, np_idx: 1, empresa: "lk", order_id: 1401, fecha_recep: "2026-09-08" }
      ]);
      if (url.indexOf("v_pedidos_web_np") >= 0 && url.indexOf("isis_empresa=eq.chef") >= 0) return J(window.__sinLk ? [] : [{ order_id: 1400, cod_isis: "2600" }]);
      if (url.indexOf("clientes_vendedor") >= 0) return J([{ cod_cliente: "1941", vend: "7" }]);
      return J([]);
    };
    window.supaFetchAllSafe = async function (ep) { const r = await window.fetch(ep); return r.json(); };
    _facLastTandas = [{ tanda: "E01A", pedidos: [
      { np: "LK 0030", cod: "1941", razonSocial: "Alesso Vilarino Liliana" },
      { np: "LK 0031", cod: "111", razonSocial: "Cliente LK" }
    ] }];

    const filas = await _facXlsArmar(["LK 0030", "LK 0031"]);
    const by = {}; filas.forEach(function (x) { by[x.np] = x; });
    out.tdf = by["LK 0030"] ? { cod: by["LK 0030"].cod, codLk: by["LK 0030"].codLk, isisEmp: by["LK 0030"].isisEmp, tope: by["LK 0030"].tope, tdf: by["LK 0030"].tdf, vend: by["LK 0030"].vend, arts: by["LK 0030"].lineas.map(function (l) { return l.art; }) } : null;
    out.lk = by["LK 0031"] ? { cod: by["LK 0031"].cod, isisEmp: by["LK 0031"].isisEmp, tope: by["LK 0031"].tope, tdf: by["LK 0031"].tdf } : null;
    out.pidioLk = urls.some(function (u) { return u.indexOf("v_pedidos_web_np") >= 0 && u.indexOf("order_id=in.(") >= 0 && u.indexOf("1400") >= 0; });
    // sin respuesta de LK → todo LK, como antes
    window.__sinLk = true;
    const filas2 = await _facXlsArmar(["LK 0030"]);
    out.sinLk = filas2[0] ? { cod: filas2[0].cod, isisEmp: filas2[0].isisEmp, tope: filas2[0].tope } : null;
    window.__sinLk = false;
    // bajar: dos archivos, la de TdF en el CH
    const nombres = [];
    const origCreate = URL.createObjectURL; URL.createObjectURL = function () { return "blob:test"; };
    const origAppend = document.body.appendChild.bind(document.body);
    document.body.appendChild = function (el) { if (el && el.tagName === "A" && el.download) { nombres.push(el.download); el.click = function () {}; } return origAppend(el); };
    window.facAuthWriteHeaders = async function () { return { apikey: "x", Authorization: "Bearer x", "Content-Type": "application/json" }; };
    window.facMarcarFacturada = async function () { return true; };
    window.facShowToast = function () {};
    window.facNpEsWeb = function () { return true; };
    _facXlsSel = new Set(["LK 0030", "LK 0031"]);
    await facXlsBajar();
    URL.createObjectURL = origCreate;
    out.nombres = nombres;
    return out;
  });
  await b.close();

  const fails = [];
  if (!r.tdf) fails.push("no armó la NP de Tierra del Fuego");
  else {
    if (r.tdf.cod !== "2600" || r.tdf.codLk !== "1941") fails.push("la NP de TdF no lleva el código Chef (2600) guardando el LK (1941): " + JSON.stringify(r.tdf));
    if (r.tdf.isisEmp !== "CH" || r.tdf.tope !== 15 || !r.tdf.tdf) fails.push("la NP de TdF no va al archivo CH con tope 15: " + JSON.stringify(r.tdf));
    if (r.tdf.arts.join(",") !== "438EL,505L") fails.push("los artículos con L no llegan crudos al Excel: " + r.tdf.arts.join(","));
    if (r.tdf.vend !== "7") fails.push("el vendedor sigue siendo el de LK (7): " + r.tdf.vend);
  }
  if (!r.lk || r.lk.cod !== "111" || r.lk.isisEmp !== "LK" || r.lk.tope !== 18 || r.lk.tdf) fails.push("una NP LK común cambió: " + JSON.stringify(r.lk));
  if (!r.pidioLk) fails.push("no consultó a LK por isis_empresa=chef con los order_id");
  if (!r.sinLk || r.sinLk.cod !== "1941" || r.sinLk.isisEmp !== "LK" || r.sinLk.tope !== 18) fails.push("sin respuesta de LK tendría que seguir como LK: " + JSON.stringify(r.sinLk));
  if (!(r.nombres.some((n) => /_LK_/.test(n)) && r.nombres.some((n) => /_CH_/.test(n)))) fails.push("esperaba un archivo LK y uno CH: " + r.nombres.join(", "));
  if (!(r.alerts || []).some((a) => /Tierra del Fuego/.test(a) && /1941 → Chef 2600/.test(a))) fails.push("falta el aviso de Tierra del Fuego: " + JSON.stringify(r.alerts));
  if (errs.length) fails.push("pageerror: " + errs.join(" | "));
  if (fails.length) { console.error("FAIL fac-tdf:\n - " + fails.join("\n - ")); process.exit(1); }
  console.log("OK fac-tdf: NP LK de Tierra del Fuego → archivo CH con código Chef, tope 15, artículos con L; NP LK común igual; sin LK, igual que antes");
})();

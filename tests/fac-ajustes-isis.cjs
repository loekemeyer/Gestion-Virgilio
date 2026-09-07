/* v13.78 — Checklist manual de ISIS en Facturación (dueño: "cuando se va a facturar por Chef hay que hacer ajuste
   negativo de stock de LK en ISIS LK y ajuste positivo en CH; y para vos en GV, descontá directo stock de LK").
   (a) el panel lista las NP con artículos L que faltan ajustar (vista gv_fac_ajustes_isis), con art_lk→art_ch ×cajas
       y dos tildes (ISIS LK −, ISIS CH +); (b) tildar escribe en GV_Fac_Ajustes_ISIS (np, paso, legajo), destildar
       borra; con los dos pasos la NP sale del panel; (c) sin NP pendientes el panel se oculta; (d) el drenaje de
       "a facturar" al facturar matchea un artículo con L (438EL) con su código de góndola Loeke (438E LK) y
       manda empresa LK. Todo con fetch stubbeado. Sale 1 si falla. */
const path = require("path");
const { chromium } = require("/opt/node22/lib/node_modules/playwright");
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1400, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    window.alert = function () {}; window.confirm = function () { return true; };
    window.facAuthWriteHeaders = async function (extra) { return Object.assign({ apikey: "x", Authorization: "Bearer x", "Content-Type": "application/json" }, extra || {}); };
    window.facShowToast = function (m) { (out.toasts = out.toasts || []).push(String(m)); };
    function J(data) { return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve(data); } }); }
    const writes = [];
    const vista = [
      { np: "CH 0003", cod_cliente: "2701", tanda: "E01A", armada_at: "2026-09-08T10:00:00Z", cajas: 3, articulos: [{ art_ch: "438EL", art_lk: "438E", cajas: 1 }, { art_ch: "505L", art_lk: "505", cajas: 2 }], razon_social: "P&M Bazar", facturado_at: "2026-09-08T12:00:00Z", lk_neg_at: null, lk_neg_por: null, ch_pos_at: null, ch_pos_por: null, completo: false },
      { np: "LK 0030", cod_cliente: "1941", tanda: "E01B", armada_at: "2026-09-08T10:00:00Z", cajas: 2, articulos: [{ art_ch: "505L", art_lk: "505", cajas: 2 }], razon_social: "Alesso Vilarino", facturado_at: null, lk_neg_at: "2026-09-08T11:00:00Z", lk_neg_por: "12", ch_pos_at: null, ch_pos_por: null, completo: false }
    ];
    window.fetch = function (url, opts) {
      url = String(url); const m = (opts && opts.method) || "GET";
      if (url.indexOf("gv_fac_ajustes_isis") >= 0) return J(vista);
      if (url.indexOf("GV_Fac_Ajustes_ISIS") >= 0) { writes.push({ m, url, body: opts && opts.body ? JSON.parse(opts.body) : null }); return J([]); }
      // drenaje: TAL de la NP + stock a_facturar de la tanda
      if (url.indexOf("opcion=eq.TAL") >= 0) return J([{ texto: "CH 0003|E01A|x|lio1=438ELx1,505Lx2,097x3", ts_cliente: "2026-09-08T10:00:00Z" }]);
      if (url.indexOf("Movimientos_Stock") >= 0 && url.indexOf("tipo=eq.facturado") >= 0) return J([]);
      if (url.indexOf("Movimientos_Stock") >= 0 && url.indexOf("deposito=eq.a_facturar") >= 0) return J([
        { cod_art: "438E LK", descripcion: "Colador", delta: 5, ref: "E01A" }, { cod_art: "505", descripcion: "Bandeja", delta: 4, ref: "E01A" }, { cod_art: "097", descripcion: "x", delta: 3, ref: "E01A" }
      ]);
      return J([]);
    };
    window.supaFetchAllSafe = async function (ep) { const r = await window.fetch(ep); return r.json(); };

    // (a) panel
    await facAjustesIsisCargar(true);
    const box = document.getElementById("facAjustesIsis");
    out.visible = box && box.style.display !== "none";
    out.filas = box ? box.querySelectorAll("tbody tr").length : 0;
    out.html = box ? box.innerHTML : "";
    out.chks = [...(box ? box.querySelectorAll("input.fa-chk") : [])].map(function (c) { return c.getAttribute("data-np") + "/" + c.getAttribute("data-paso") + "=" + (c.checked ? 1 : 0); });

    // (b) tildar y destildar
    const c1 = box.querySelector('input.fa-chk[data-np="CH 0003"][data-paso="lk_neg"]');
    c1.checked = true; await facAjustesIsisToggle(c1);
    const c2 = document.querySelector('input.fa-chk[data-np="CH 0003"][data-paso="ch_pos"]');
    c2.checked = true; await facAjustesIsisToggle(c2);
    out.writes = writes.map(function (w) { return w.m + " " + (w.body ? w.body.np + "/" + w.body.paso : w.url.replace(/^.*GV_Fac_Ajustes_ISIS/, "")); });
    out.filasTras = document.getElementById("facAjustesIsis").querySelectorAll("tbody tr").length;
    const c3 = document.querySelector('input.fa-chk[data-np="LK 0030"][data-paso="lk_neg"]');
    c3.checked = false; await facAjustesIsisToggle(c3);
    out.destilde = writes[writes.length - 1].m + " " + writes[writes.length - 1].url.replace(/^.*GV_Fac_Ajustes_ISIS/, "");

    // (c) sin pendientes → oculto
    _facAjustes.rows = []; facAjustesIsisRender();
    out.ocultoSinFilas = document.getElementById("facAjustesIsis").style.display === "none";

    // (d) drenaje con L
    const moved = [];
    window.stockMove = async function (rows) { moved.push(...rows); return true; };
    await stockSalidaFacturadoNP("CH 0003", "E01A", "12");
    out.moved = moved.map(function (r) { return r.cod_art + ":" + r.delta + ":" + (r.empresa || "-"); });
    return out;
  });
  await b.close();

  const fails = [];
  if (!r.visible || r.filas !== 2) fails.push("el panel tendría que mostrar 2 NP: visible=" + r.visible + " filas=" + r.filas);
  if (!/438E→438EL ×1/.test(r.html) || !/505→505L ×2/.test(r.html)) fails.push("faltan los artículos art_lk→art_ch ×cajas");
  if (!/P&amp;M Bazar/.test(r.html) || !/facturada 08\/09/.test(r.html) || !/armada, sin facturar/.test(r.html)) fails.push("faltan cliente / estado de facturación");
  if (r.chks.join(",") !== "CH 0003/lk_neg=0,CH 0003/ch_pos=0,LK 0030/lk_neg=1,LK 0030/ch_pos=0") fails.push("tildes mal: " + r.chks.join(","));
  if (!/hecho 08\/09 · 12/.test(r.html)) fails.push("el paso hecho no muestra fecha y legajo");
  if (r.writes.slice(0, 2).join("|") !== "POST CH 0003/lk_neg|POST CH 0003/ch_pos") fails.push("tildar no escribe np/paso: " + r.writes.join("|"));
  if (r.filasTras !== 1) fails.push("con los dos pasos la NP tendría que salir del panel: " + r.filasTras);
  if (!/^DELETE \?np=eq\.LK%200030&paso=eq\.lk_neg$/.test(r.destilde)) fails.push("destildar no borra la fila: " + r.destilde);
  if (!r.ocultoSinFilas) fails.push("sin pendientes el panel sigue visible");
  const mv = r.moved.join(",");
  if (!/438E LK:-1:LK/.test(mv) || !/505:-2:LK/.test(mv) || !/097:-3:CH/.test(mv)) fails.push("drenaje con L mal: " + mv);
  if (errs.length) fails.push("pageerror: " + errs.join(" | "));
  if (fails.length) { console.error("FAIL fac-ajustes-isis:\n - " + fails.join("\n - ")); process.exit(1); }
  console.log("OK fac-ajustes-isis: panel con NP pendientes, tildes que escriben/borran, se oculta sin pendientes, drenaje de a_facturar matchea la L con la góndola Loeke y empresa LK");
})();

/* v26.12 (Luis, 02/10) — IMPRESIÓN POR PROGRAMA EN LA PC (sin kiosco).
   Corre index.html de verdad con la red stubbeada y mide el DESVÍO, no el texto:
     A. remitoDocHtml arma un documento completo (CSS de impresión + hoja + auto-ajuste).
     B. Sin regla → todo como hoy: el armado sale por el navegador (remitoPrintDoc), nada al programa.
     C. Armado y picking al programa → se encolan (gv_imp_encolar) y el navegador NO imprime,
        aunque este equipo no tenga la estación prendida.
     D. Regla apagada → no sale por ningún lado.
     E. Config ilegible → psPoll no avanza (no marca ni imprime): se reintenta.
     F. Facturado al programa → se encola también desde un celular; sin regla, el celular no imprime.
     G. Un envío que falla queda guardado y el reintento lo manda.
     H. Configuración → Impresoras dibuja las 3 hojas y elegir la PC guarda su impresora predeterminada.
   Sale 1 si algo falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    localStorage.clear();
    const S = { cfg: { pcs: [], reglas: [], clave: null }, cfgFalla: false, talRows: [], tpRows: [], encolados: [], guardados: [], encolarFalla: false };
    window.fetch = function (url, opts) {
      const u = String(url);
      const ok = function (j) { return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve(j); } }); };
      if (u.indexOf("rpc/gv_imp_config") >= 0) {
        if (S.cfgFalla) return Promise.resolve({ ok: false, status: 500, json: function () { return Promise.resolve({ message: "x" }); } });
        return ok(JSON.parse(JSON.stringify(S.cfg)));
      }
      if (u.indexOf("rpc/gv_imp_encolar") >= 0) {
        const bd = JSON.parse(opts.body);
        if (S.encolarFalla) return Promise.resolve({ ok: false, status: 503, json: function () { return Promise.resolve({ message: "caido" }); } });
        S.encolados.push(bd);
        return ok({ estado: "encolado", id: S.encolados.length, impresora: "HP Deposito", pc: "DEPOSITO", pc_viva: true });
      }
      if (u.indexOf("rpc/gv_imp_regla_guardar") >= 0) { S.guardados.push(JSON.parse(opts.body)); return ok({}); }
      if (u.indexOf("rpc/gv_imp_trabajos") >= 0) return ok([]);
      if (u.indexOf("opcion=eq.TAL") >= 0) return ok(S.talRows);
      if (u.indexOf("opcion=eq.TP") >= 0) return ok(S.tpRows);
      return ok([]);
    };
    window.facAuthWriteHeaders = async function () { return { apikey: "k", Authorization: "Bearer jwt", "Content-Type": "application/json" }; };
    const printed = [];
    window.remitoPrintDoc = function (inner) { printed.push(String(inner)); };
    window.armadoRemitoInnerHtml = function (d, tipo) { return "REMITO-" + (tipo || "ARMADO") + "-" + d.np; };
    window._armadoRemitoDataForItems = async function (items) { return items.map(function (x) { return { np: x.np, rs: "Test", total: 1, nLios: 1 }; }); };
    window.pkHojaDatos = async function (tandas) { return tandas.map(function (t) { return { tanda: t }; }); };
    window.pkHojaHtml = function (d) { return "HOJA-PICKING-" + d.tanda; };
    window.colaImpLoadBadge = function () {};
    window.colaImpMarcarImpresas = function () {};
    window.facShowToast = function () {};
    const espera = function (ms) { return new Promise(function (res) { setTimeout(res, ms); }); };
    const cfgArmado = function (auto, conPicking) {
      const reg = [{ tipo: "armado", pc: "DEPOSITO", impresora: "HP Deposito", auto: auto, copias: 1 }];
      if (conPicking) reg.push({ tipo: "picking", pc: "DEPOSITO", impresora: "HP Deposito", auto: true, copias: 1 });
      return { pcs: [{ pc: "DEPOSITO", vivo: true, impresoras: [{ nombre: "HP Deposito", predeterminada: true }, { nombre: "Brother", predeterminada: false }], pendientes: 0, version: "1", chrome: "c" }], reglas: reg, clave: "AB12-CD34" };
    };
    const reset = function () { localStorage.clear(); _ps = null; printed.length = 0; S.encolados.length = 0; _gvImp.cfg = null; _gvImp.ts = 0; };

    // ---- A. documento completo
    const doc = remitoDocHtml("HOLA-HOJA");
    out.A_doc = doc.indexOf("<!doctype html>") === 0 && doc.indexOf("HOLA-HOJA") > 0 && doc.indexOf("@page") > 0 &&
                doc.indexOf("scrollHeight<=1010") > 0 && /<\/script><\/body><\/html>$/.test(doc);

    // ---- B. sin regla: como hoy (navegador, sólo con la estación prendida o "Revisar ahora")
    reset(); S.cfg = { pcs: [], reglas: [], clave: null };
    S.talRows = [{ texto: "98010|1|D12B|C=3X2|L1", ts_cliente: "2099-01-01T12:00:00-03:00", legajo: "1" }];
    S.tpRows = [];
    await psPoll(true); await espera(50);
    out.B_navegador = printed.length === 1 && printed[0].indexOf("98010") > 0 && S.encolados.length === 0 && gvImpModo("armado") === "navegador";

    // ---- C. armado + picking al programa, SIN estación del navegador en este equipo
    reset(); S.cfg = cfgArmado(true, true);
    S.talRows = [{ texto: "98011|1|D12B|C=3X2|L1", ts_cliente: "2099-01-01T12:00:00-03:00", legajo: "1" }];
    S.tpRows = [{ texto: "E50A", ts_cliente: "2099-01-01T12:01:00-03:00" }];
    out.C_psAutoApagado = psIsAuto() === false;
    await psPoll(false); await espera(50);
    const arm = S.encolados.filter(function (x) { return x.p_tipo === "armado"; });
    const pk = S.encolados.filter(function (x) { return x.p_tipo === "picking"; });
    out.C_armadoEncolado = arm.length === 1 && arm[0].p_ref === "98011" && arm[0].p_html.indexOf("REMITO-ARMADO-98011") > 0 && arm[0].p_html.indexOf("<!doctype html>") === 0 && !arm[0].p_pc;
    out.C_pickingEncolado = pk.length === 1 && pk[0].p_ref === "E50A" && pk[0].p_html.indexOf("HOJA-PICKING-E50A") > 0;
    out.C_navegadorNoImprime = printed.length === 0;
    out.C_log = !!(_ps && _ps.log[0] && /HP Deposito/.test(_ps.log[0].nota));

    // ---- D. regla apagada: no sale
    reset(); S.cfg = cfgArmado(false, false);
    S.talRows = [{ texto: "98012|1|D12B|C=3X2|L1", ts_cliente: "2099-01-01T12:00:00-03:00", legajo: "1" }];
    S.tpRows = [];
    await psPoll(true); await espera(50);
    out.D_apagado = printed.length === 0 && S.encolados.length === 0 && gvImpModo("armado") === "apagado";

    // ---- E. config ilegible: no avanza ni imprime
    reset(); S.cfgFalla = true;
    S.talRows = [{ texto: "98013|1|D12B|C=3X2|L1", ts_cliente: "2099-01-01T12:00:00-03:00", legajo: "1" }];
    _psEnsure(); _ps.lastSeen = "2099-01-01T00:00:00-03:00";
    await psPoll(true); await espera(50);
    out.E_noAvanza = printed.length === 0 && S.encolados.length === 0 && _ps.lastSeen === "2099-01-01T00:00:00-03:00" && /configuración/.test(_ps.lastErr || "");
    S.cfgFalla = false;

    // ---- F. facturado al programa (también desde un celular); sin regla el celular no imprime
    reset();
    window.facFacturadoInner = async function (np) { return "FAC-" + np; };
    const mob = _facIsMobile; window._facIsMobile = function () { return true; };
    S.cfg = { pcs: cfgArmado(true).pcs, reglas: [{ tipo: "facturado", pc: "DEPOSITO", impresora: "Brother", auto: true, copias: 2 }], clave: null };
    await facMaybePrintFacturado("LK 0300", "E60A");
    out.F_facturadoEncolado = S.encolados.length === 1 && S.encolados[0].p_tipo === "facturado" && S.encolados[0].p_ref === "LK 0300" && S.encolados[0].p_html.indexOf("FAC-LK 0300") > 0;
    reset(); S.cfg = { pcs: [], reglas: [], clave: null };
    await facMaybePrintFacturado("LK 0301", "E60A");
    out.F_celularSinRegla = S.encolados.length === 0 && printed.length === 0;
    window._facIsMobile = mob;

    // ---- G. envío fallido → guardado → reintento
    reset(); S.cfg = cfgArmado(true, false); S.encolarFalla = true;
    await gvImpCfgCargar(true);
    S.talRows = [{ texto: "98014|1|D12B|C=3X2|L1", ts_cliente: "2099-01-01T12:00:00-03:00", legajo: "1" }];
    await psPoll(false); await espera(50);
    const pend1 = JSON.parse(localStorage.getItem("gv_imp_pend_v1") || "[]");
    out.G_guardado = pend1.length === 1 && pend1[0].ref === "98014" && pend1[0].tipo === "armado";
    S.encolarFalla = false;
    const n = await gvImpReintentarPendientes();
    const pend2 = JSON.parse(localStorage.getItem("gv_imp_pend_v1") || "[]");
    out.G_reintento = n === 1 && pend2.length === 0 && S.encolados.length === 1 && S.encolados[0].p_ref === "98014";

    // ---- H. pantalla Impresoras
    reset(); window.__isSupervisor = true;
    S.cfg = { pcs: cfgArmado(true).pcs, reglas: [], clave: "AB12-CD34" };
    openImpresoras(); await espera(150);
    const ov = document.getElementById("gvImpOv");
    const filas = ov ? Array.from(ov.querySelectorAll(".gi-tbl tr")).map(function (tr) { return tr.textContent; }) : [];
    out.H_tresHojas = ["Picking", "Armado", "Facturado"].every(function (t) { return filas.some(function (f) { return f.indexOf(t) >= 0; }); });
    out.H_clave = !!(ov && ov.textContent.indexOf("AB12-CD34") >= 0);
    out.H_pcConectada = !!(ov && /DEPOSITO/.test(ov.textContent) && /conectada/.test(ov.textContent));
    await gvImpCambiar("armado", "pc", "DEPOSITO");
    const g = S.guardados[S.guardados.length - 1] || {};
    out.H_guardaPredeterminada = g.p_tipo === "armado" && g.p_pc === "DEPOSITO" && g.p_impresora === "HP Deposito" && g.p_auto === false;
    closeImpresoras();
    return out;
  });
  const fallas = Object.keys(r).filter(function (k) { return r[k] !== true; });
  const pass = fallas.length === 0 && errs.length === 0;
  console.log("imp-programa:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL " + fallas.join(","));
  await b.close(); process.exit(pass ? 0 : 1);
})();

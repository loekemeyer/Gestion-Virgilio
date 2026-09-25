/* v22.53 (Luis, 2026-09-25) — Facturación · ♻ RECUPERAR PEDIDO.
   Completar la facturación de una NP ya facturada (entró mercadería entre la factura y la entrega).
   R1) el botón verde está en el grupo de Excel / JSON / Cruce / Cerrar.
   R2) la lista trae las NP facturadas; «Sólo con faltantes» esconde las completas; el buscador
       filtra por varias palabras (cliente + NP).
   R3) al abrir la NP, lo completado después de facturar (sugerido) viene tildado, y una cantidad
       mayor que el pendiente se topea.
   R4) «Marcar como facturado» avisa que ya se facturó a mano y graba el lote con modo 'marcado'.
   R5) «Excel ISIS» graba el lote con modo 'excel' ANTES de bajar, y el archivo lleva SÓLO los
       códigos marcados con esas cajas (no lo entregado de la NP entera).
   Todo con fetch y RPC stubbeados, sin red. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1300, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const confirms = [];
    window.alert = function () {}; window.confirm = function (m) { confirms.push(String(m)); return true; };
    window.requireSupervisor = function () { return true; };
    window.facQuien = async function () { return "Luis"; };
    function J(data) { return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve(data); } }); }
    window.sbAuth = { getAccessToken: async function () { return "tok"; } };
    const llamadas = [];
    window.fetch = function (url, opt) {
      url = String(url);
      const mr = url.match(/\/rest\/v1\/rpc\/([a-z0-9_]+)/);
      if (mr) {
        const fn = mr[1], body = opt && opt.body ? JSON.parse(opt.body) : {};
        llamadas.push({ fn: fn, body: body });
        const res = window.__rpc(fn, body);
        return Promise.resolve({ ok: true, status: 200, text: function () { return Promise.resolve(JSON.stringify(res)); }, json: function () { return Promise.resolve(res); } });
      }
      if (url.indexOf("Entregas_Virgilio") >= 0) return J([
        { id: 1, np: "98017", cod_art: "026", cajas_pedidas: 1, cajas_entregadas: 1 },
        { id: 2, np: "98017", cod_art: "280", cajas_pedidas: 2, cajas_entregadas: 2 },
        { id: 3, np: "98017", cod_art: "534", cajas_pedidas: 1, cajas_entregadas: 1 }]);
      if (url.indexOf("ppp_base_pedidos") >= 0) return J([{ pedido: "98017", fecha: "2026-07-22" }]);
      return J([]);
    };
    window.supaFetchAllSafe = async function (ep) { const x = await window.fetch(ep); return x.json(); };
    window.gvRestTodo = async function () { return []; };

    window.__rpc = function (fn, body) {
      if (fn === "gv_fac_recuperar_lista") return [
        { np: "98017", empresa: "lk", tanda: "D10A", cod_cliente: "151", razon_social: "Solia Alejandro", fecha_salida: "2026-07-23", facturado_at: "2026-07-24T12:00:00Z", lineas: 3, cajas_fc: 1, lineas_falto: 2, cajas_falto: 3, cajas_completadas_despues: 3, cajas_complementadas: 0, lotes: 0, lotes_sin_factura: 0 },
        { np: "98100", empresa: "lk", tanda: "D11A", cod_cliente: "200", razon_social: "Otro Cliente", fecha_salida: "2026-07-25", facturado_at: "2026-07-26T12:00:00Z", lineas: 4, cajas_fc: 8, lineas_falto: 0, cajas_falto: 0, cajas_completadas_despues: 0, cajas_complementadas: 0, lotes: 0, lotes_sin_factura: 0 }];
      if (fn === "gv_fac_recuperar_detalle") return [
        { cod_art: "026", descripcion: "Cuchara", pedidas: 1, entregadas_al_fc: 1, falto_al_fc: 0, completado_despues: 0, complementado: 0, pendiente: 0, sugerido: 0 },
        { cod_art: "280", descripcion: "Manga", pedidas: 2, entregadas_al_fc: 0, falto_al_fc: 2, completado_despues: 2, complementado: 0, pendiente: 2, sugerido: 2 },
        { cod_art: "534", descripcion: "Espátula", pedidas: 1, entregadas_al_fc: 0, falto_al_fc: 1, completado_despues: 1, complementado: 0, pendiente: 1, sugerido: 1 }];
      if (fn === "gv_fac_complemento_lista") return [];
      if (fn === "gv_fac_complemento_registrar") return "00000000-0000-0000-0000-000000000001";
      return [];
    };
    const bajadas = [];
    window._facXlsDescargarXlsx = function (filas, emp) { bajadas.push({ emp: emp, filas: JSON.parse(JSON.stringify(filas)), antesDeRegistrar: !llamadas.some(function (l) { return l.fn === "gv_fac_complemento_registrar" && l.body.p_modo === "excel"; }) }); return "archivo.xlsx"; };
    window.facDescRegistrar = async function () {};
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));

    // R1
    const btn = document.getElementById("facBtnRecuperar");
    const grupo = btn && btn.parentElement;
    out.R1_boton = !!btn && /Recuperar pedido/.test(btn.textContent) && grupo && grupo.classList.contains("fac-top-acts")
      && !!grupo.querySelector("#facBtnXlsIsis") && !!grupo.querySelector("#facBtnCruce") && !!grupo.querySelector(".fac-close-btn");
    out.R1_verde = !!btn && /rgb\(22, 163, 74\)/.test(getComputedStyle(btn).backgroundColor);

    // R2
    facRecAbrir(); await espera(80);
    let box = document.getElementById("frecBox").innerHTML;
    out.R2_lista = /98017/.test(box) && !/98100/.test(box);
    facRecSet("soloFalt", false); box = document.getElementById("frecBox").innerHTML;
    out.R2_todas = /98017/.test(box) && /98100/.test(box);
    _frec.q = "solia 98017"; facRecRender(); box = document.getElementById("frecBox").innerHTML;
    out.R2_buscar = /98017/.test(box) && !/98100/.test(box);

    // R3
    await facRecAbrirNp("98017"); await espera(30);
    out.R3_sugeridos = _frec.sel["280"] === 2 && _frec.sel["534"] === 1 && _frec.sel["026"] == null;
    facRecCant(1, "9");
    out.R3_tope = _frec.sel["280"] === 2;

    // R4
    await facRecMarcar(); await espera(30);
    const reg1 = llamadas.filter(function (l) { return l.fn === "gv_fac_complemento_registrar"; });
    out.R4_modo = reg1.length === 1 && reg1[0].body.p_modo === "marcado" && reg1[0].body.p_np === "98017";
    out.R4_items = reg1.length === 1 && JSON.stringify(reg1[0].body.p_items) === JSON.stringify([{ cod: "280", cajas: 2 }, { cod: "534", cajas: 1 }]);
    out.R4_aviso = confirms.some(function (m) { return /YA facturaste/.test(m) && /NO hay que volver a facturarlos/.test(m); });

    // R5 — sólo el 534 x 1
    _frec.sel = { "534": 1 };
    await facRecExcel(); await espera(30);
    const reg2 = llamadas.filter(function (l) { return l.fn === "gv_fac_complemento_registrar" && l.body.p_modo === "excel"; });
    out.R5_registra = reg2.length === 1 && JSON.stringify(reg2[0].body.p_items) === JSON.stringify([{ cod: "534", cajas: 1 }]);
    out.R5_orden = bajadas.length === 1 && bajadas[0].antesDeRegistrar === false;
    const lin = bajadas.length ? bajadas[0].filas[0].lineas : [];
    out.R5_lineas = bajadas.length === 1 && lin.length === 1 && lin[0].art === "534" && Number(lin[0].cajas) === 1 && bajadas[0].filas[0].cod === "151";
    return out;
  });
  await b.close();
  const fallas = Object.keys(r).filter((k) => r[k] !== true);
  if (errs.length) console.log("pageerror:", errs.slice(0, 3));
  console.log(fallas.length ? "fac-recuperar-pedido: FALLA " + JSON.stringify(r) : "fac-recuperar-pedido: OK — " + Object.keys(r).length + " chequeos");
  process.exit(fallas.length || errs.length ? 1 : 0);
})();

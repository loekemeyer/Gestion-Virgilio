/* v27.20 — ADS · Alertas Damián Stock (Luis, 06/10/2026). Corre la pantalla de verdad (ads.js
   dentro de index.html) con las RPC mockeadas y mide:
     (a) el botón está en el panel con su badge violeta a la IZQUIERDA (gv_ads_badge) y el semáforo a la
         derecha (gv_ads_badge_stock): rojo = quiebre a 10 · naranja = recién a 20 · amarillo = recién a 30;
     (b) Entregas talleristas: agrupa por tallerista, suma pedido/entregado, ordena por % (peor
         primero) y marca en rojo el que queda debajo del umbral; al tocarlo abre sus artículos;
     (c) Stock: por defecto muestra sólo el quiebre a 10 días, los chips cuentan 10/20/30 y la
         columna de % del tallerista sale de la pestaña 1;
     (d) una lectura VACÍA o con error se dice, no se dibuja como «todo bien»;
     (e) el botón Cerrar no hereda el button{width:100%} global. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

const TALL = [
  { proveedor: "Lucho", pkey: "lucho", codigo: "505", descripcion: "Cuchillo", ocs: 2, pedido: 350, entregado: 250, pct: 0.7143, desde: "2026-09-09", hasta: "2026-09-23", ult_fecha: "2026-09-23", ult_cant: 200, ult_rec: 100, ult_estado: "anulada" },
  { proveedor: "Oscar", pkey: "oscar", codigo: "506", descripcion: "Abrelata", ocs: 2, pedido: 100, entregado: 10, pct: 0.1, desde: "2026-09-09", hasta: "2026-09-23", ult_fecha: "2026-09-23", ult_cant: 90, ult_rec: 0, ult_estado: "anulada" },
  { proveedor: "Oscar", pkey: "oscar", codigo: "280", descripcion: "Manga", ocs: 1, pedido: 50, entregado: 20, pct: 0.4, desde: "2026-09-16", hasta: "2026-09-16", ult_fecha: "2026-09-16", ult_cant: 50, ult_rec: 20, ult_estado: "anulada" }
];
const STOCK = [
  { cod: "505", cod_base: "505", linea: "LK", descripcion: "Cuchillo", terminado: 50, racks: 0, a_guardar: 0, disponible: 50, proy_mes: 300, comp10: 20, comp20: 40, comp30: 60, saldo10: -70, saldo20: -190, saldo30: -310, dias_cubre: 0, oc_fecha: "2026-09-30", oc_prov: "Lucho", oc_cant: 174, oc_rec: 87, oc_estado: "pendiente", oc_rec_v: 90 },
  { cod: "506", cod_base: "506", linea: "LK", descripcion: "Abrelata", terminado: 100, racks: 0, a_guardar: 0, disponible: 100, proy_mes: 90, comp10: 0, comp20: 0, comp30: 20, saldo10: 70, saldo20: 40, saldo30: -10, dias_cubre: 27, oc_fecha: null, oc_prov: null, oc_cant: null, oc_rec: null, oc_estado: null },
  { cod: "501", cod_base: "501", linea: "LK", descripcion: "Untar", terminado: 500, racks: 0, a_guardar: 0, disponible: 500, proy_mes: 30, comp10: 0, comp20: 0, comp30: 0, saldo10: 490, saldo20: 480, saldo30: 470, dias_cubre: 500, oc_fecha: null, oc_prov: null, oc_cant: null, oc_rec: null, oc_estado: null }
];

(async () => {
  const b = await chromium.launch();
  const p = await (await b.newContext({ viewport: { width: 1400, height: 900 }, serviceWorkers: "block" })).newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async ({ TALL, STOCK }) => {
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    for (let i = 0; i < 50 && typeof window.openAds !== "function"; i++) await espera(100);
    let modo = "ok";
    window.sb = { rpc: async (n, a) => {
      if (modo === "vacio") return { data: [], error: null };
      if (n === "gv_ads_config") return { data: { n_ocs: 7, umbral: 0.5, incluir_actual: false }, error: null };
      if (n === "gv_ads_talleristas") { window.__incArg = a && a.p_incluir_actual; return { data: TALL, error: null }; }
      if (n === "gv_ads_oc_fechas") return { data: [{ n: 1, fecha: "2026-10-07" }, { n: 2, fecha: "2026-09-30" }], error: null };
      if (n === "gv_ads_stock3") return { data: STOCK, error: null };
      if (n === "gv_ads_badge") return { data: 1, error: null };
      if (n === "gv_ads_badge_stock") return { data: { q10: 80, q20: 98, q30: 127 }, error: null };
      return { data: null, error: { message: "?" } };
    } };
    const out = {};
    const btn = [...document.querySelectorAll(".sup-action-btn")].find((x) => /openAds/.test(x.getAttribute("onclick") || ""));
    out.boton = !!btn && /ADS/.test(btn.textContent) && !!btn.querySelector("#adsBadge");
    window.adsLoadBadge(); await espera(50);
    const bd = document.getElementById("adsBadge");
    out.badge = bd && bd.style.display !== "none" ? bd.textContent : "";
    out.badgeIzq = bd ? (bd.style.left === "2px" && bd.style.right === "auto") : false;
    const sem = document.getElementById("adsSemaf");
    out.semaf = sem && sem.style.display !== "none" ? [...sem.querySelectorAll(".ads-sem")].map((x) => x.textContent + "|" + x.style.background) : [];
    window.openAds(); await espera(150);
    out.rango = [...document.querySelectorAll("#adsOv .ads-bar select option")].map((o) => o.textContent);
    out.rangoSel = (document.querySelector("#adsOv .ads-bar select") || {}).value;
    out.sinInc = !document.querySelector("#adsOv .ads-bar input[type=checkbox]") && window.__incArg === true;
    const filas = [...document.querySelectorAll("#adsOv tr.t")];
    out.orden = filas.map((f) => f.cells[0].textContent.replace(/[▸▾ ]/g, ""));
    out.oscarRojo = filas[0] && filas[0].classList.contains("al");
    out.oscarPct = filas[0] && filas[0].cells[4].textContent;
    out.oscarPed = filas[0] && filas[0].cells[2].textContent;
    filas[0].click(); await espera(50);
    out.sub = document.querySelectorAll("#adsOv tr.sub tbody tr").length;
    out.subCols = [...document.querySelectorAll("#adsOv tr.sub thead th")].map((t) => t.textContent);
    const ug = document.querySelector("#adsOv tr.sub th.ug"), u1 = document.querySelector("#adsOv tr.sub td.u1"), u3 = document.querySelector("#adsOv tr.sub td.u3");
    out.recuadro = !!(ug && ug.colSpan === 3 && u1 && u3 && getComputedStyle(u1).borderLeftWidth === "2px" && getComputedStyle(u3).borderRightWidth === "2px");
    const f1 = document.querySelector("#adsOv tr.sub tbody tr");
    out.subFila = f1 ? [...f1.cells].slice(-3).map((c) => c.textContent) : [];
    const cerrar = [...document.querySelectorAll("#adsOv .ads-top button")].find((x) => x.textContent === "Cerrar");
    out.cerrarAncho = cerrar ? cerrar.getBoundingClientRect().width : 9999;
    window.adsTab("stock"); await espera(50);
    out.chips = [...document.querySelectorAll("#adsOv .chip")].map((c) => c.textContent);
    const fs = [...document.querySelectorAll("#adsOv .ads-body table tbody tr")];
    out.stockCods = fs.map((f) => f.cells[0].textContent);
    out.pctTall = fs[0] ? fs[0].cells[11].textContent : "";
    out.cols10 = [...document.querySelectorAll("#adsOv .ads-body > table > thead th")].map((t) => t.textContent);
    out.fila10 = fs[0] ? [...fs[0].cells].slice(2, 10).map((c) => c.textContent) : [];
    // v27.34: Excel por rango y de talleristas (se lee el archivo que se baja)
    const bajados = [];
    window.gvXlsxBajar = (bytes, nombre) => {
      const wb = window.XLSX.read(bytes, { type: "array" });
      const cfb = window.XLSX.CFB.read(new Uint8Array(bytes), { type: "array" });
      const iS = cfb.FullPaths.findIndex((p) => /sheet1\.xml$/.test(p));
      const xml = new TextDecoder().decode(new Uint8Array(cfb.FileIndex[iS].content));
      const iY = cfb.FullPaths.findIndex((p) => /styles\.xml$/.test(p));
      const sty = iY < 0 ? "" : new TextDecoder().decode(new Uint8Array(cfb.FileIndex[iY].content));
      bajados.push({ nombre, xml, sty, filas: window.XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { header: 1 }) });
    };
    out.btnXl = [...document.querySelectorAll("#adsOv .ads-bar button.xl")].map((x) => x.textContent);
    await window.adsExcelStock(10); await window.adsExcelStock(30); await window.adsExcelTall();
    out.xl = bajados.map((x) => ({ n: x.nombre.replace(/_\d{8}\.xlsx$/, ""), cab: x.filas[0], f1: x.filas[1], len: x.filas.length,
      anchos: [...x.xml.matchAll(/<col [^>]*width="([\d.]+)"/g)].map((m) => Number(m[1])),
      alto1: /<row r="1"[^>]* ht="72"/.test(x.xml), congela: /state="frozen"/.test(x.xml), ajusta: /fitToWidth="1"/.test(x.xml),
      a2: (x.xml.match(/<c r="A2"( s="\d+")?/) || [])[1] || "", b2: (x.xml.match(/<c r="B2"( s="\d+")?/) || [])[1] || "", c2: (x.xml.match(/<c r="C2"( s="\d+")?/) || [])[1] || "", negr: /<font><b\/>/.test(x.sty || ""), grilla: /<border><left style="thin">/.test(x.sty || "") && !/<xf numFmtId="0" fontId="\d" fillId="0" borderId="0" xfId="0" applyFont/.test(x.sty || "") }));
    window.adsHoriz(30); await espera(30);
    out.stock30 = [...document.querySelectorAll("#adsOv .ads-body table tbody tr")].map((f) => f.cells[0].textContent);
    const f30 = document.querySelector("#adsOv .ads-body > table tbody tr");
    out.fila30 = f30 ? [...f30.cells].slice(2, 7).map((c) => c.textContent) : [];
    modo = "vacio"; window.adsClose(); window.openAds(); await espera(150);
    out.vacio = document.querySelector("#adsOv .err") ? document.querySelector("#adsOv .err").textContent : "";
    return out;
  }, { TALL, STOCK });
  await b.close();
  const fallas = [];
  if (r.rango.length !== 12 || r.rango[0] !== "1 - 07.10.26" || r.rango[1] !== "2 - 30.09.26" || r.rango[2] !== "3 - sin OC") fallas.push("(g) selector de rango 1..12 con fecha: " + JSON.stringify(r.rango));
  if (r.rangoSel !== "4") fallas.push("(g) el rango abre en 4: " + r.rangoSel);
  if (!r.sinInc) fallas.push("(g) la OC en curso tiene que entrar siempre, sin casilla");
  if (!r.boton) fallas.push("(a) falta el botón ADS con su badge");
  if (r.badge !== "1") fallas.push("(a) badge no pinta: " + r.badge);
  if (!r.badgeIzq) fallas.push("(a) el badge violeta no va a la izquierda");
  const semOk = r.semaf.length === 3 && /^8010d\|/.test(r.semaf[0]) && /rgb\(220, 38, 38\)/.test(r.semaf[0])
    && /^9820d\|/.test(r.semaf[1]) && /rgb\(234, 88, 12\)/.test(r.semaf[1]) && /^12730d\|/.test(r.semaf[2]) && /rgb\(250, 204, 21\)/.test(r.semaf[2]);
  if (!semOk) fallas.push("(a) semáforo rojo/naranja/amarillo: " + JSON.stringify(r.semaf));
  if (JSON.stringify(r.orden) !== JSON.stringify(["Oscar", "Lucho"])) fallas.push("(b) orden: " + JSON.stringify(r.orden));
  if (!r.oscarRojo || r.oscarPct !== "20 %" || r.oscarPed !== "150") fallas.push("(b) Oscar: " + r.oscarPct + " / " + r.oscarPed);
  if (r.sub !== 2) fallas.push("(b) artículos al abrir: " + r.sub);
  if (JSON.stringify(r.subCols.slice(-4)) !== JSON.stringify(["Última OC", "Fecha", "Pedida", "Recibida"])) fallas.push("(b) columnas de la última OC separadas: " + JSON.stringify(r.subCols));
  if (!r.recuadro) fallas.push("(b) la última OC (fecha, pedida, recibida) no va en un recuadro");
  if (JSON.stringify(r.subFila) !== JSON.stringify(["23/09", "90", "0"])) fallas.push("(b) fila última OC: " + JSON.stringify(r.subFila));
  if (r.cerrarAncho > 200) fallas.push("(e) Cerrar ancho " + r.cerrarAncho);
  if (JSON.stringify(r.chips) !== JSON.stringify(["10 días · 1", "20 días · 1", "30 días · 2", "todos · 3"])) fallas.push("(c) chips " + JSON.stringify(r.chips));
  if (JSON.stringify(r.stockCods) !== JSON.stringify(["505"])) fallas.push("(c) quiebre 10 d: " + JSON.stringify(r.stockCods));
  if (String(r.pctTall).trim() !== "Lucho (350)") fallas.push("(c) Dist un solo tallerista, sin % y con cajas: " + r.pctTall);
  const C10 = ["Cód.","Descripción","Stk","Comprom.10 d","Est. Madre10 d","Saldo10 d","Período (4 OC)","Fechaúlt. OC","Pedidoperíodo","Recibidoperíodo","%","Entregaest. OC","Proporción"];
  if (JSON.stringify(r.cols10) !== JSON.stringify(C10)) fallas.push("(c) columnas stock: " + JSON.stringify(r.cols10));
  if (JSON.stringify(r.fila10) !== JSON.stringify(["50","20","100","-70","30/09","350","250","71 %"])) fallas.push("(c) fila a 10 d: " + JSON.stringify(r.fila10));
  if (JSON.stringify(r.fila30) !== JSON.stringify(["50","60","300","-310","30/09"])) fallas.push("(c) fila a 30 d: " + JSON.stringify(r.fila30));
  if (JSON.stringify(r.stock30) !== JSON.stringify(["505", "506"])) fallas.push("(c) quiebre 30 d: " + JSON.stringify(r.stock30));
  if (JSON.stringify(r.btnXl) !== JSON.stringify(["10 días", "20 días", "30 días"])) fallas.push("(f) botones Excel por rango: " + JSON.stringify(r.btnXl));
  const x10 = r.xl && r.xl[0], x30 = r.xl && r.xl[1], xt = r.xl && r.xl[2];
  if (!x10 || x10.n !== "ADS_stock_10d" || x10.len !== 2 || x10.cab[2] !== "Saldo 10 d" || x10.cab[3] !== "Stk" || JSON.stringify(x10.f1.slice(0, 10)) !== JSON.stringify(["505", "Cuchillo", -70, 50, 20, 100, "30/09", 350, 250, 71])) fallas.push("(f) Excel stock 10 d: " + JSON.stringify(x10));
  if (!x10 || !xt || !x10.grilla || !xt.grilla) fallas.push("(r) Excel ADS: todas las celdas con borde (cuadrícula al imprimir)");
  if (!x10 || x10.c2 !== ' s="5"' || !x10.negr) fallas.push("(q) Excel stock: el Saldo (C) en negrita: " + JSON.stringify(x10 && [x10.c2, x10.negr]));
  if (!x30 || x30.n !== "ADS_stock_30d" || x30.len !== 3) fallas.push("(f) Excel stock 30 d: " + JSON.stringify(x30));
  if (!xt || !/^ADS_talleristas_/.test(xt.n) || xt.len !== 4 ||
      JSON.stringify(xt.cab) !== JSON.stringify(["Tallerista","Cód.","Descripción","OC evaluadas","Pedido","Recibio Virgilio","%","Fecha última OC","Pedido última OC","Recibido última OC"])) fallas.push("(f) Excel talleristas: " + JSON.stringify(xt && xt.cab));
  // v27.90 (Luis): el % de talleristas va como TEXTO «71%», entero
  const ft = xt && xt.f1; if (!ft || !/^\d+%$/.test(String(ft[6]))) fallas.push("(g) % talleristas como texto: " + JSON.stringify(ft));
  // v27.40: el formato de Luis (anchos chicos, rótulo de 45, congelado, entra a lo ancho; texto a la izq., números centrados)
  if (!xt || JSON.stringify(xt.anchos) !== JSON.stringify([12.7109375, 12.42578125, 23, 7.42578125, 7.5703125, 7.5703125, 8.42578125, 8.28515625, 7.5703125, 8.28515625]) ||
      !xt.alto1 || !xt.congela || !xt.ajusta || xt.a2 !== ' s="3"' || xt.b2 !== ' s="2"') fallas.push("(g) formato Excel talleristas: " + JSON.stringify(xt && [xt.anchos, xt.alto1, xt.congela, xt.ajusta, xt.a2, xt.b2]));
  // v27.87 (Luis): los anchos y rótulos son los de su Excel «ADS_stock_10d_20261007_1»
  if (!x10 || JSON.stringify(x10.anchos) !== JSON.stringify([11.28515625, 14.85546875, 5.28515625, 5.140625, 7.140625, 6, 7.7109375, 8.7109375, 6.28515625, 5.28515625, 6.140625, 19.140625, 27.42578125]) || x10.cab[2] !== "Saldo 10 d" || x10.cab[4] !== "Comprom 10 d" || x10.cab[5] !== "E M 10 d" || x10.cab[12] !== "Proporción") fallas.push("(g) anchos Excel stock: " + JSON.stringify(x10 && x10.anchos));
  // v27.59 D16 (Luis): sin stock que cubra lo comprometido = 0 días aunque no tenga Est. Madre; con sobrante y sin Est. Madre = «sin venta»
  {
    const src = require("fs").readFileSync(path.join(__dirname, "..", "ads.js"), "utf8");
    const ctx = { _adsPctCod: () => [], _adsPct: (x) => Math.round(x * 100) + " %" };
    const vm = require("vm"); vm.createContext(ctx);
    vm.runInContext(src.slice(src.indexOf("function _adsStockCalc"), src.indexOf("/* v27.34")), ctx);
    const corto = ctx._adsStockCalc({ disponible: 5, proy_mes: 0, comp10: 8, saldo10: -3 }, 10);
    const vende = ctx._adsStockCalc({ disponible: 50, proy_mes: 30, comp10: 20, saldo10: 20 }, 10);
    ctx._adsN = (v) => Number(v).toLocaleString("es-AR");
    ctx._adsPctCod = () => [{ proveedor: "Garcia", pedido: 140 }, { proveedor: "Poly", pedido: 107 }];
    const dist = ctx._adsStockCalc({ disponible: 5, proy_mes: 0, comp10: 0, saldo10: 5 }, 10).dist;
    // v27.79: entrega estimada proporcional al ritmo de cada uno (10 días de período, H = 10)
    // reloj fijo al mediodía AR: la cuenta usa el mediodía de «desde», así los días dan 10 justos a cualquier hora (antes 49 o 50 según la hora)
    const _hoy = new Date(Date.now() - 3 * 36e5).toISOString().slice(0, 10), _T = Date.parse(_hoy + "T12:00:00-03:00");
    vm.runInContext("Date.now = function () { return " + _T + "; };", ctx);
    const d10 = new Date(_T - 10 * 864e5 - 3 * 36e5).toISOString().slice(0, 10);
    ctx._adsPctCod = () => [{ proveedor: "A", pedido: 200, entregado: 50, desde: d10, ult_cant: 200, ult_rec: 0 }, { proveedor: "B", pedido: 30, entregado: 20, desde: d10, ult_cant: 15, ult_rec: 0 }];
    const cEst = ctx._adsStockCalc({ disponible: 5, proy_mes: 0, comp10: 0, saldo10: 5 }, 10), est = cEst.estH;
    // v27.91 (Luis): cada tallerista en su sub-fila del Excel, descripción sin ajuste, borde del rótulo, escala 74
  { const _s = require("fs").readFileSync(__dirname + "/../ads.js", "utf8");
    if (!/c\.estCaj\.join\("\\n"\), c\.dist\.join\("\\n"\)/.test(_s) || !/izqSin: \[1\], negrita: \[2\]/.test(_s) || !/bordeRot: true, escala: 68, margenStd: true/.test(_s)) fallas.push("(l) formato stock v27.91"); }
  { const _m = src.match(/function _adsEstSinPct[\s\S]*?\n\}/); const _f = _m && new Function(_m[0] + "; return _adsEstSinPct;")();
    if (!_f || JSON.stringify(_f(["A 83 % (50)", "Lucho (350)"])) !== JSON.stringify(["50", "350"])) fallas.push("(m) Excel: entrega estimada sólo cajas"); }
  { const _sv = ctx._adsPctCod; ctx._adsPctCod = function () { return [
      { proveedor: "German", pedido: 20, entregado: 10, desde: "2026-09-23", ult_fecha: "2026-09-23" },
      { proveedor: "Pettofrezza", pedido: 66, entregado: 10, desde: "2026-09-23", ult_fecha: "2026-10-07" }]; };
    const c609 = ctx._adsStockCalc({ cod: "609", disponible: 0, proy_mes: 30, comp10: 5, saldo10: -10 }, 10);
    ctx._adsPctCod = _sv;
    if (c609.estCaj.length !== 1 || !/^Pettofrezza: \d+$/.test(c609.estCaj[0])) fallas.push("(o) 609 Excel: " + JSON.stringify(c609.estCaj));
    if (c609.estDist.length !== 1 || !/^Pettofrezza/.test(c609.estDist[0])) fallas.push("(n) 609: sólo estima el tallerista de la OC actual: " + JSON.stringify(c609.estDist)); }
  { const _s2 = require("fs").readFileSync(path.join(__dirname, "..", "ads.js"), "utf8");
    if ((_s2.match(/vertical="center"/g) || []).length < 4) fallas.push("(p) Excel: el texto a la izquierda va centrado en vertical (v28.00)"); }
  if (JSON.stringify(cEst.estDist) !== JSON.stringify(["A 83 % (50)", "B 17 % (10)"])) fallas.push("(k) entrega estimada por tallerista: " + JSON.stringify(cEst.estDist));
    if (est < 57 || est > 61) fallas.push("(j) entrega estimada (A 200×25 % = 50 + B 15×67 % = 10): " + est);
    ctx._adsPctCod = () => [{ proveedor: "Garcia", pedido: 140 }, { proveedor: "Poly", pedido: 107 }];
    if (JSON.stringify(dist) !== JSON.stringify(["Garcia 57 % (140)", "Poly 43 % (107)"])) fallas.push("(i) proporción con cajas: " + JSON.stringify(dist));
    if (corto.pedP !== null || vende.pctP !== null) fallas.push("(h) sin OC en el período: " + JSON.stringify([corto, vende]));
  }
  if (!/vac/i.test(r.vacio)) fallas.push("(d) lectura vacía no se dice: " + r.vacio);
  if (errs.length) fallas.push("errores de página: " + errs.slice(0, 3).join(" | "));
  if (fallas.length) { console.error("✗ ADS:\n  " + fallas.join("\n  ")); process.exit(1); }
  console.log("✓ ADS: botón + badge violeta, talleristas por % con umbral, quiebres 10/20/30, lectura vacía avisada");
})();

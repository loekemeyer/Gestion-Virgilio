/* v26.66 (Luis, 05/10) — COLA DE IMPRESIÓN NP: todas las NP (pasadas y presentes) con las hojas que
   se pueden imprimir porque está la data. "En caso de que sea de la tanda, es de la tanda, si es de la
   NP, es de la NP": el PICKING va una vez por TANDA (marca «PK <tanda>»), el ARMADO (marca = la NP) y el
   FACTURADO (marca «FAC <np>») por NP. Corre index.html de verdad con la RPC gv_cola_impresion_lista
   stubbeada y mide:
     A. por día → tanda (la tanda y su picking ocupan UNA celda para todas sus NP) → NP; «—» sin datos;
        ✓ con la hora en lo impreso; rojo en lo pendiente y ⚠ si hace +24 h.
     B. «Imprimir pendientes (N)» cuenta el picking una vez por tanda.
     C. el badge del panel: N pendientes, rojo si alguna hace +24 h; una lectura rota no lo apaga.
     D. tocar una hoja la muestra y «Imprimir» la manda (remitoPrintDoc con su tipo) y la marca.
     E. «Imprimir pendientes» manda del día más viejo al más nuevo: picking de la tanda, después lo de cada NP.
     F. «Sólo pendientes» y la búsqueda.
     G. una lectura rota dice «No se pudo leer», no «No hay NP».
   Sale 1 si algo falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const out = {};

  await p.evaluate(() => {
    const hace = function (h) { return new Date(Date.now() - h * 3600000).toISOString(); };
    window.__fix = function () {
      return [
        { fecha: "2026-10-06", np: "LK 0301", empresa: "LK", tanda: "E70A", cod_cliente: "4182", razon_social: "Bazar Uno SRL",
          pick_ts: hace(30), pick_leg: "104", pick_impreso_en: hace(29), pick_pend: false,
          arm_ts: hace(28), arm_resumen: "A=501X2", arm_leg: "94", arm_arts: [], arm_falt: [], arm_impreso_en: hace(27), arm_pend: false,
          fac_ts: null, fac_impreso_en: null, fac_pend: false },
        { fecha: "2026-10-06", np: "LK 0302", empresa: "LK", tanda: "E70A", cod_cliente: "4183", razon_social: "Bazar Dos",
          pick_ts: hace(30), pick_leg: "104", pick_impreso_en: hace(29), pick_pend: false,
          arm_ts: hace(30), arm_resumen: "A=438EX1", arm_leg: "94", arm_arts: [], arm_falt: [], arm_impreso_en: null, arm_pend: true,
          fac_ts: null, fac_impreso_en: null, fac_pend: false },
        { fecha: "2026-10-05", np: "98700", empresa: "LK", tanda: "E60B", cod_cliente: "1651", razon_social: "Inc SA",
          pick_ts: hace(3), pick_leg: "277", pick_impreso_en: null, pick_pend: true,
          arm_ts: hace(2), arm_resumen: "A=505X5", arm_leg: "94", arm_arts: [], arm_falt: [], arm_impreso_en: hace(2), arm_pend: false,
          fac_ts: hace(1), fac_impreso_en: null, fac_pend: true },
        { fecha: "2026-10-05", np: "98701", empresa: "LK", tanda: "E60B", cod_cliente: "1652", razon_social: "Otro Cliente",
          pick_ts: hace(3), pick_leg: "277", pick_impreso_en: null, pick_pend: true,
          arm_ts: null, arm_resumen: null, arm_leg: null, arm_arts: [], arm_falt: [], arm_impreso_en: null, arm_pend: false,
          fac_ts: null, fac_impreso_en: null, fac_pend: false },
        { fecha: "2026-10-05", np: "CH 0050", empresa: "CH", tanda: null, cod_cliente: "2211", razon_social: "Sin Nada",
          pick_ts: null, pick_leg: null, pick_impreso_en: null, pick_pend: false,
          arm_ts: null, arm_resumen: null, arm_leg: null, arm_arts: [], arm_falt: [], arm_impreso_en: null, arm_pend: false,
          fac_ts: null, fac_impreso_en: null, fac_pend: false }
      ];
    };
    window.__S = { rpcOk: true, rpc: [], marcas: [], prints: [] };
    window.fetch = function (url, opts) {
      const u = String(url);
      const ok = function (j) { return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve(j); } }); };
      if (u.indexOf("/rpc/gv_cola_impresion_lista") >= 0) {
        window.__S.rpc.push(JSON.parse(opts.body));
        return window.__S.rpcOk ? ok(window.__fix()) : Promise.resolve({ ok: false, status: 500, json: function () { return Promise.resolve({}); } });
      }
      if (u.indexOf("Impresion_NP") >= 0 && opts && opts.method === "POST") {
        JSON.parse(opts.body).forEach(function (r) { window.__S.marcas.push(r.np + "|" + r.gv_origen); });
        return Promise.resolve({ ok: true, status: 201 });
      }
      return ok([]);
    };
    window.pkHojaDatos = async function (ts) { return ts.map(function (t) { return { tanda: t }; }); };
    window.pkHojaHtml = function (d) { return "PICKING-" + d.tanda; };
    window._armadoRemitoDataForItems = async function (items) { return items.map(function (x) { return { np: x.np, resumen: x.resumen }; }); };
    window.armadoRemitoInnerHtml = function (d) { return "ARMADO-" + d.np; };
    window.facFacturadoInner = async function (np) { return "FACTURADO-" + np; };
    window.remitoPrintDoc = function (inner, tipo, ref) { window.__S.prints.push(tipo + ":" + inner); };
    window.gvHelperActivo = function () { return true; };   // sin esperas entre hojas
    window.confirm = function () { return true; };
    window.getEmpleadosNombres = async function () { return new Map(); };
  });

  // ---- A. la vista
  out.A = await p.evaluate(async () => {
    await openColaImpHistorial();
    const body = document.getElementById("colaImpBody");
    const dias = body.querySelectorAll(".ci-dia").length;
    const tablas = body.querySelectorAll("table.ci-t");
    const t1 = tablas[0], t2 = tablas[1];
    const celTanda = Array.from(t1.querySelectorAll("td.ci-tanda"));
    const tandaUna = celTanda.length === 1 && celTanda[0].textContent === "E70A" && celTanda[0].getAttribute("rowspan") === "2";
    const filas1 = t1.querySelectorAll("tbody tr");
    const pickOk = /✓/.test(filas1[0].children[1].textContent) && filas1[0].children[1].querySelector(".ci-b.ok");
    const armPend = filas1[1].querySelector("td:nth-last-child(2) .ci-b.pend");
    const armPendViejo = armPend && /⚠/.test(armPend.textContent);
    const filas2 = t2.querySelectorAll("tbody tr");
    const sinNada = Array.from(filas2).find(function (tr) { return /CH 0050/.test(tr.textContent); });
    const guiones = sinNada ? sinNada.querySelectorAll(".ci-no").length : 0;
    const pickPendE60B = /🖨 Imprimir/.test(filas2[0].children[1].textContent) && filas2[0].children[1].querySelector(".ci-b.pend");
    const rango = window.__S.rpc[0] && window.__S.rpc[0].p_desde < window.__S.rpc[0].p_hasta;
    const tandaE60B = Array.from(t2.querySelectorAll("td.ci-tanda")).filter(function (x) { return x.textContent === "E60B"; });
    return dias === 2 && tandaUna && tandaE60B.length === 1 && tandaE60B[0].getAttribute("rowspan") === "2" && !!pickOk && !!armPend && !!armPendViejo && guiones === 3 && !!pickPendE60B && rango;
  });

  // ---- B. pendientes: el picking cuenta UNA vez por tanda
  out.B = await p.evaluate(() => /\(3\)/.test(document.getElementById("colaImpBtnPend").textContent));

  // ---- C. badge
  out.C = await p.evaluate(async () => {
    let bd = document.getElementById("colaImpBadge");
    if (!bd) { bd = document.createElement("span"); bd.id = "colaImpBadge"; document.body.appendChild(bd); }
    await colaImpHistBadge();
    const okBadge = bd.textContent === "⚠ 3" && bd.style.display !== "none" && /185, 28, 28|b91c1c/.test(bd.style.background);
    window.__S.rpcOk = false; await colaImpHistBadge(); window.__S.rpcOk = true;
    return okBadge && bd.textContent === "⚠ 3" && bd.style.display !== "none";   // lectura rota: no se apaga
  });

  // ---- D. tocar una hoja → se ve → Imprimir → sale con su tipo y se marca
  out.D = await p.evaluate(async () => {
    window.__S.prints.length = 0; window.__S.marcas.length = 0;
    const btn = Array.from(document.querySelectorAll("#colaImpBody .ci-b.pend")).find(function (x) { return /colaImpVer\('arm'/.test(x.getAttribute("onclick")); });
    btn.click();
    await new Promise(function (ok) { setTimeout(ok, 150); });
    const ov = document.getElementById("gvHojaOv");
    const muestra = ov && ov.classList.contains("show") && /ARMADO-LK 0302/.test(ov.textContent);
    ov.querySelector("button.pr").click();
    await new Promise(function (ok) { setTimeout(ok, 50); });
    const fila = Array.from(document.querySelectorAll("#colaImpBody tr")).find(function (tr) { return /LK 0302/.test(tr.textContent); });
    return muestra && window.__S.prints.join() === "armado:ARMADO-LK 0302" && window.__S.marcas.join() === "LK 0302|cola" &&
      !!fila.querySelector(".ci-b.ok") && /\(2\)/.test(document.getElementById("colaImpBtnPend").textContent);
  });

  // ---- E. imprimir pendientes: del día más viejo, picking de la tanda primero, después la NP
  out.E = await p.evaluate(async () => {
    await openColaImpHistorial(true);   // vuelve a leer: LK 0302 vuelve a figurar pendiente en el fixture
    window.__S.prints.length = 0; window.__S.marcas.length = 0;
    await colaImprimirPendientes();
    const pend = document.querySelectorAll("#colaImpBody .ci-b.pend").length;
    return window.__S.prints.join() === "picking:PICKING-E60B,facturado:FACTURADO-98700,armado:ARMADO-LK 0302" &&
      window.__S.marcas.join() === "PK E60B|cola,FAC 98700|cola,LK 0302|cola" && pend === 0 &&
      /3 hoja/.test(document.getElementById("colaImpStatus").textContent);
  });

  // ---- F. sólo pendientes y búsqueda
  out.F = await p.evaluate(async () => {
    await openColaImpHistorial(true);
    const sp = document.getElementById("colaImpSoloPend"); sp.checked = true; colaImpRender();
    const nps = Array.from(document.querySelectorAll("#colaImpBody td.ci-np")).map(function (x) { return x.textContent; }).sort().join();
    sp.checked = false;
    const q = document.getElementById("colaImpQ"); q.value = "bazar dos"; colaImpRender();
    const nps2 = Array.from(document.querySelectorAll("#colaImpBody td.ci-np")).map(function (x) { return x.textContent; }).join();
    q.value = ""; colaImpRender();
    return nps === "98700,98701,LK 0302" && nps2 === "LK 0302";
  });

  // ---- G. lectura rota
  out.G = await p.evaluate(async () => {
    window.__S.rpcOk = false; _colaImp = null;
    await openColaImpHistorial();
    const txt = document.getElementById("colaImpBody").textContent + " " + document.getElementById("colaImpStatus").textContent;
    window.__S.rpcOk = true;
    return /No se pudo leer/.test(txt) && !/No hay NP/.test(txt);
  });

  // ---- H. v27.61: la cola principal vuelve a la de antes (NP armadas sin imprimir + picking) y abre el submódulo
  out.H = await p.evaluate(async () => {
    const f0 = window.fetch;
    window.fetch = function (url, opts) {
      const u = String(url);
      const ok = function (j) { return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve(j); } }); };
      if (u.indexOf("gv_vista_cola_impresion") >= 0) return ok([{ np: "LK 0400", tanda: "F10A", razon_social: "Bazar Tres", armado_ts: new Date(Date.now() - 30 * 3600000).toISOString(), vencido: true, resumen: "A=501X1", armador_leg: "94", arts_fallback: [], faltantes_fallback: [] }]);
      if (u.indexOf("vista_cola_impresion") >= 0) return ok([{ np: "LK 0400", vencido: true }]);
      return f0(url, opts);
    };
    window.pkHojaPendientes = async function () { return [{ tanda: "F11B", legajo: "104", ts: new Date().toISOString() }]; };
    window.pkHojaImprimir = async function (ts) { window.__S.prints.push("picking:" + ts.join()); };
    colaImpClose();
    await openColaImpresion();
    const vb = document.getElementById("colaImpVBody").textContent;
    const vista = /LK 0400/.test(vb) && /F11B/.test(vb) && /Imprimir todas \(2\)/.test(vb) && /Por día/.test(vb);
    window.__S.prints.length = 0; window.__S.marcas.length = 0;
    await colaImprimirTodas();
    const imp = window.__S.prints.join() === "picking:F11B,armado:ARMADO-LK 0400" && window.__S.marcas.join() === "LK 0400|cola";
    const bd = document.getElementById("colaImpBadge"); await colaImpLoadBadge();
    const badge = bd.textContent === "⚠ 1";
    Array.from(document.querySelectorAll("#colaImpVBody button")).find(function (x) { return /Por día/.test(x.textContent); }).click();
    await new Promise(function (ok) { setTimeout(ok, 100); });
    const sub = document.getElementById("colaImpOv").style.display !== "none" && document.getElementById("colaImpVOv").style.display === "none";
    window.fetch = f0;
    return vista && imp && badge && sub;
  });

  await b.close();
  const fallas = Object.keys(out).filter((k) => out[k] !== true);
  console.log("cola-impresion-np:", JSON.stringify(out), "· pageerrors:", errs.length ? errs.join("|") : "none");
  if (fallas.length || errs.length) { console.log("✗ cola-impresion-np: " + fallas.join(", ")); process.exit(1); }
  console.log("✓ cola-impresion-np (" + Object.keys(out).length + " bloques)");
})().catch((e) => { console.error(e); process.exit(1); });

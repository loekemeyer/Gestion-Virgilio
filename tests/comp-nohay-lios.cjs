/* v20.97 (Luis, 2026-09-22) — «No hay más» desde la pantalla de LÍOS.

   Hasta hoy el armador contaba caja por caja en Líos pero sólo podía contar HASTA CERO: la
   única salida para "hay menos de lo que dice el picking" estaba en Separar, una pantalla
   antes y redactada como aviso al pickeador. Resultado: 24 eventos FAL en 47 días contra 764
   TAL (3%) y `cajas_entregadas` = pedidas con el pallet a medio llenar.

   Chequea:
   - NO toca lo que ya está en un lío CERRADO (ése es el pozo: marcar de más como faltante).
   - El lío a medio armar (cur) vuelve a "sin poner" y entra en el faltante.
   - El faltante se anota con el código CRUDO del pedido (438EL), que es la clave de faltMap;
     con el resuelto (438E LK) no matchea y se pierde en Entregas_Virgilio.
   - El stock y el aviso al picking usan el código de GÓNDOLA (438E LK), no el crudo.
   - Cancelar el confirm no toca absolutamente nada.
   - NO duplica lógica: pasa por _compDifResolve (candado estático).
   - REGRESIÓN: la llamada de 2 argumentos (Separar) sigue leyendo el input del diálogo.
   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const SRC = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
const est = {
  // el objeto de cada código lleva el CRUDO además del resuelto
  raw_en_codes: /codes\.push\(\{ cod: pkResolveArt\(it\.art, npKey\), raw: String\(it\.art\)/.test(SRC),
  // el faltante manual se anota con el crudo
  falt_crudo: /_compAddFaltManual\(n\.np, c\.raw \|\| c\.cod, qty, n\.cod, n\.rs\)/.test(SRC),
  // el botón vive en la pantalla de Líos
  boton_en_lios: /class="cmpl-nomas" onclick="_compViewNoMas\(\)"/.test(SRC),
  // candado invertido: _compSinMas NO puede registrar el faltante por su cuenta
  sinmas_usa_difresolve: /function _compSinMas\([\s\S]{0,2600}?_compDifResolve\("menos", "no", real\)/.test(SRC),
  sinmas_no_llama_falt: !(/function _compSinMas\([\s\S]{0,2600}?_compAddFaltManual\(/.test(SRC)),
};

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    const wait = (ms) => new Promise((res) => setTimeout(res, ms));
    window.alert = function () {};
    window._compRenderSep = function () {};
    window._compRenderLios = function () {};
    window._compRecalc = function () {};
    window._compPersist = function () {};
    window.trySendOneReport = function () { return Promise.resolve({ ok: false }); };
    window.esOperadorPrueba = function () { return false; };
    window._stkGondolaSaldoVivo = async function () { return 0; };
    let evs = []; window.enqueueReport = function (pl) { evs.push(pl); };
    let movs = []; window.stockMove = function (rows) { movs.push.apply(movs, rows); return Promise.resolve(); };

    // sale=6, ya cerró 4 en un lío, le quedan `rest`+`cur` sin poner
    function setup(rest, cur, raw, cod) {
      evs = []; movs = [];
      _comp = {
        legajo: "8", tanda: "E29B", liosNpIdx: 0, liosView: "nomas", _difMovs: [], arts: [], hayFalt: false,
        nps: [{ np: "LK 0142", cod: "2533", rs: "OSA", liosArr: [{ items: [{ cod: cod, qty: 4 }], cajas: 4 }],
                codes: [{ cod: cod, raw: raw, sale: 6, rest: rest, cur: cur, sep: true }] }]
      };
      return _comp.nps[0].codes[0];
    }

    // ---- CASO 1: 2 sin poner (rest=2) → faltan 2, y las 4 ya armadas NO se tocan ----
    window.confirm = function () { return true; };
    let c = setup(2, 0, "501", "501");
    _compSinMas(0);
    await wait(40);
    out.c1_sale = c.sale === 4;            // lo que de verdad se armó
    out.c1_rest = c.rest === 0 && c.cur === 0;
    out.c1_falt = _comp.arts.length === 1 && _comp.arts[0].nps[0].asig === 2 && _comp.arts[0].falta === 2;
    out.c1_np = _comp.arts[0].nps[0].np === "LK 0142";
    out.c1_hayFalt = _comp.hayFalt === true;
    out.c1_liosDone = _comp.nps[0].liosDone === true;
    out.c1_view = _comp.liosView === "armar";

    // ---- CASO 2: el lío a medio armar (cur) también entra en el faltante ----
    c = setup(1, 1, "501", "501");
    _compSinMas(0);
    await wait(40);
    out.c2_sale = c.sale === 4 && c.rest === 0 && c.cur === 0;
    out.c2_falt = _comp.arts[0].nps[0].asig === 2;

    // ---- CASO 3: el faltante va con el CRUDO; el stock y el aviso, con el de GÓNDOLA ----
    c = setup(2, 0, "438EL", "438E LK");
    _compSinMas(0);
    await wait(40);
    out.c3_art_crudo = String(_comp.arts[0].art) === "438EL";
    const fal = evs.filter((e) => e.opcion === "FAL")[0];
    const npd = evs.filter((e) => e.opcion === "NPD")[0];
    out.c3_fal_crudo = !!fal && fal.texto.split("|")[1] === "438EL";
    out.c3_npd_gondola = !!npd && npd.texto.split("|")[1] === "438E LK" && npd.texto.split("|")[2] === "menos";
    const sep = movs.filter((m) => m.deposito === "separar_pedidos");
    out.c3_stock = sep.length === 1 && sep[0].delta === -2 && sep[0].cod_art === "438E LK" && sep[0].ref === "E29B";

    // ---- CASO 4: cancelar el confirm NO toca nada ----
    window.confirm = function () { return false; };
    c = setup(2, 0, "501", "501");
    _compSinMas(0);
    await wait(40);
    out.c4_intacto = c.sale === 6 && c.rest === 2 && _comp.arts.length === 0 && evs.length === 0 && movs.length === 0;

    // ---- CASO 5 (REGRESIÓN): 2 argumentos → sigue leyendo el input del diálogo de Separar ----
    window.confirm = function () { return true; };
    setup(6, 0, "501", "501");
    _comp.sepDif = { mode: "dialog", npIdx: 0, ci: 0, tipo: "menos" };
    const inp = document.createElement("input"); inp.id = "csep-difreal"; inp.value = "5";
    const old = document.getElementById("csep-difreal"); if (old) old.remove();
    document.body.appendChild(inp);
    _compDifResolve("menos", "no");        // sin 3er argumento
    await wait(40);
    out.c5_lee_input = _comp.nps[0].codes[0].sale === 5 && _comp.arts[0].nps[0].asig === 1;   // qty = 6 - 5
    inp.remove();
    return out;
  });
  const dyn = Object.keys(r).every((k) => r[k] === true);
  const sta = Object.keys(est).every((k) => est[k] === true);
  const pass = dyn && sta && errs.length === 0;
  console.log("comp-nohay-lios:", JSON.stringify(r), "· estatico:", JSON.stringify(est),
              "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();

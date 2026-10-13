/* v29.78 (Luis, 13/10) — SUB-POSICIONES DE RACK: «si alguien guarda algo a un rack que ya esta
   ocupado por otro codigo, promptee para decir de que lado lo dejan … que separe ese rack en
   Izq y Der (una subdivision de racks)» · «pongamos la posibilidad de, por ejemplo, Y25-1, Y25-2».

   Se prueba, corriendo la pantalla de Ingreso a racks de verdad:
     A) rack ENTERO ocupado por OTRO código → ofrece PARTIRLO (2, 3, 4) y no deja ingresar ahí.
     B) ✂ en 2 partes → pregunta en qué parte está lo que ya hay, llama a gv_rack_partir con el
        rack, las partes y esa parte, y deja al operario parado en la parte LIBRE.
     C) rack YA partido con la parte ocupada → ofrece la parte libre, NO ofrece partir de nuevo.
     D) la dirección con «-» sobrevive al tipeo y es la que viaja a racks_plani_ingreso.
     E) candados: las lecturas piden `partes`, Stocks resuelve con gv_rack_dir, el Mapa tiene ✂.
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const root = path.join(__dirname, "..");
  const src = fs.readFileSync(path.join(root, "index.html"), "latin1");
  let fails = 0;
  const ok = (c, m) => { console.log((c ? "  ok  " : "  FALLA ") + m); if (!c) fails++; };

  // ── E) candados estáticos ────────────────────────────────────────────────────────
  ok(/racksFetchPlani\(\)[\s\S]{0,200}select=sector,emp,cod_art,master_cajas,innercajas,estado,rack,parte,partes/.test(src),
     "E1 · racksFetchPlani pide rack/parte/partes");
  ok(/gv_rack_celda[\s\S]{0,300}pos_rack,parte,partes/.test(src), "E2 · el Mapa pide pos_rack/parte/partes");
  ok(/_stkRackDirDe[\s\S]{0,300}rpc\/gv_rack_dir/.test(src) && src.indexOf("_stkRackSectorDe") < 0,
     "E3 · Stocks resuelve la dirección con gv_rack_dir (y no quedó el viejo gv_rack_sector)");
  ok(/async function prkPartir\(sector\)[\s\S]{0,2000}gv_rack_partir/.test(src), "E4 · el Mapa puede partir/unir un rack");
  ok(/function irSetSec\(v\)[\s\S]{0,160}\[\^A-Z0-9-\]/.test(src), "E5 · el campo Sector del ingreso acepta el «-» de la parte");
  ok(/function rkbSetPos\([\s\S]{0,200}v29\.78/.test(src), "E6 · Bajar de racks deja escribir la parte");

  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/*.supabase.co/**", (r) => r.abort());
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "load" });
  await p.waitForFunction(() => ["showIngresoRacksModal", "irPartir", "irSetSec"].every((f) => typeof window[f] === "function"), { timeout: 25000 });

  const r = await p.evaluate(async () => {
    const out = {}; const wait = (ms) => new Promise((res) => setTimeout(res, ms));
    const alerts = []; window.alert = function (m) { alerts.push(String(m)); };
    const prompts = []; let resp = "1"; window.prompt = function (m) { prompts.push(String(m)); return resp; };
    window.confirm = function () { return true; };
    window.loadArtNombres = async function () { return {}; };
    window.stockFetchSaldos = async function () { return {}; };
    window.irFetchCxM = async function () { return {}; };
    window.trySendOneReport = async function () { return { ok: true }; };

    // el rack AB05 arranca ENTERO con 816E adentro; AD05 libre
    let partido = false;
    window.racksFetchPlani = async function () {
      return partido
        ? [{ sector: "AB05-1", rack: "AB05", parte: 1, partes: 2, estado: "ocupado", cod_art: "816E", innercajas: 208 },
           { sector: "AB05-2", rack: "AB05", parte: 2, partes: 2, estado: "libre", cod_art: null },
           { sector: "AD05", rack: "AD05", parte: null, partes: 1, estado: "libre", cod_art: null }]
        : [{ sector: "AB05", rack: "AB05", parte: null, partes: 1, estado: "ocupado", cod_art: "816E", innercajas: 208 },
           { sector: "AD05", rack: "AD05", parte: null, partes: 1, estado: "libre", cod_art: null }];
    };
    const rpc = [];
    window.fetch = async function (url, opt) {
      const u = String(url); const body = JSON.parse((opt && opt.body) || "{}");
      const j = (v) => ({ ok: true, status: 200, text: async () => JSON.stringify(v), json: async () => v });
      if (u.indexOf("gv_stock_cod_conocido") >= 0) return j(true);
      if (u.indexOf("gv_codigo_baja_de") >= 0) return j(null);
      if (u.indexOf("gv_rack_sector") >= 0) return j(null);
      if (u.indexOf("gv_rack_partir") >= 0) { rpc.push({ fn: "partir", body: body }); partido = true; return j({ ok: true, sector: body.p_sector, partes: body.p_partes }); }
      if (u.indexOf("racks_plani_ingreso") >= 0) { rpc.push({ fn: "ingreso", body: body }); return j("ok"); }
      return { ok: false, status: 500, text: async () => "x", json: async () => null };
    };

    localStorage.clear();
    await showIngresoRacksModal("104");
    await wait(30);
    const warn = () => { const w = document.querySelector("#irBody .ir-warn"); return w ? w.innerText : ""; };
    const btn = () => document.querySelector("#irBody .ir-fin");
    const poner = async (cod, sec) => { if (typeof window._irCodChk === "function") await _irCodChk(cod); irSetModo("import"); irSetCod(cod); irSetSec(sec); irSetI(10); await wait(10); };

    // A) rack entero ocupado por otro código
    await poner("999", "AB05");
    const wA = warn();
    out.aOfrecePartir = /816E/.test(wA) && /partes/i.test(wA) && !!document.querySelector('#irBody .ir-chip[onclick*="irPartir(2)"]');
    out.aTresOpciones = ["irPartir(2)", "irPartir(3)", "irPartir(4)"].every(function (x) { return wA !== "" && !!document.querySelector('#irBody .ir-chip[onclick*="' + x + '"]'); });
    out.aIzqDer = /izquierda a derecha/i.test(document.getElementById("irBody").innerText);
    out.aNoDeja = !!btn() && btn().disabled === true;

    // B) partir en 2: pregunta dónde está lo que ya hay y manda el RPC
    prompts.length = 0; resp = "1";
    await irPartir(2);
    await wait(20);
    const pp = rpc.filter(function (x) { return x.fn === "partir"; })[0] || { body: {} };
    out.bPregunta = prompts.length === 1 && /816E/.test(prompts[0]) && /1 a 2/.test(prompts[0]);
    out.bRpc = pp.body.p_sector === "AB05" && pp.body.p_partes === 2 && pp.body.p_parte_actual === 1 && pp.body.p_legajo === "104";
    out.bQuedaEnLaLibre = String(_ir && _ir.sector) === "AB05-2";
    out.bAvisa = alerts.some(function (m) { return /AB05-1/.test(m) && /AB05-2/.test(m); });

    // C) ya partido: la parte ocupada ofrece la libre, no ofrece partir de nuevo
    await poner("999", "AB05-1");
    const wC = warn();
    out.cOfreceLaLibre = /816E/.test(wC) && /2 partes/.test(wC) && !!document.querySelector('#irBody .ir-chip[onclick*="AB05-2"]');
    out.cNoOfrecePartir = !document.querySelector('#irBody .ir-chip[onclick*="irPartir"]');

    // D) la dirección con «-» sobrevive al tipeo y es la que viaja
    irSetSec("ab05-2"); await wait(5);
    out.dTipeo = String(_ir && _ir.sector) === "AB05-2";
    await poner("999", "AB05-2");
    out.dDeja = !!btn() && btn().disabled === false;
    await irRevisar(); await wait(5);
    await irCargar(); await wait(20);
    const ing = rpc.filter(function (x) { return x.fn === "ingreso"; })[0] || { body: {} };
    out.dViaja = ing.body.p_sector === "AB05-2" && Number(ing.body.p_inner) === 10;
    return out;
  });
  await b.close();

  ok(r.aOfrecePartir, "A1 · rack entero ocupado: dice quién lo ocupa y ofrece ✂ partirlo");
  ok(r.aTresOpciones, "A2 · ofrece 2, 3 y 4 partes");
  ok(r.aIzqDer, "A3 · dice que se numeran de izquierda a derecha");
  ok(r.aNoDeja, "A4 · con el rack ocupado no deja ingresar ahí");
  ok(r.bPregunta, "B1 · pregunta en qué parte está el código que ya estaba");
  ok(r.bRpc, "B2 · gv_rack_partir con el rack, las partes, la parte actual y el legajo");
  ok(r.bQuedaEnLaLibre, "B3 · después de partir, el operario queda en la parte LIBRE (AB05-2)");
  ok(r.bAvisa, "B4 · avisa dónde quedó cada cosa");
  ok(r.cOfreceLaLibre, "C1 · rack ya partido: ofrece la parte libre");
  ok(r.cNoOfrecePartir, "C2 · …y no ofrece volver a partirlo");
  ok(r.dTipeo, "D1 · el «-» de la parte sobrevive al tipeo");
  ok(r.dDeja, "D2 · con la parte libre deja ingresar");
  ok(r.dViaja, "D3 · la DIRECCIÓN con la parte es la que viaja a racks_plani_ingreso");
  ok(errs.length === 0, "sin errores de JS" + (errs.length ? ": " + errs[0] : ""));
  console.log(fails ? "\n" + fails + " falla(s)" : "\nOK");
  process.exit(fails ? 1 : 0);
})();

/* Test de regresión (v25.40, Thomas 30/09, D4) — lo que CERVANTES manda a Virgilio llega como
   aviso Sí / No donde Virgilio recibe.

   *"lo que manda Cervantes llega a Gestión Virgilio como aviso Sí/No donde recibe"*.

   A) Recepción de Mercadería → Log/ Fabr (los TERMINADOS de Fábrica), corriendo recepcion.js:
      - el aviso aparece arriba de los códigos, SÓLO los de la línea elegida (el de CH no sale en LK),
      - ✓ Llegó suma las cajas a la carga (y agrega el código si no estaba en la lista),
      - ↩ Deshacer las saca,
      - ✕ No llegó llama a gv_envio_cervantes_denegar y lo saca del aviso,
      - al ENVIAR se encola el Sí (gv_envio_cervantes_confirmar) con el código y el remito,
        y sólo de lo que quedó cargado.
   B) Recibir Insumos (index.html), con las funciones de verdad:
      - el Sí precarga la cantidad en el insumo que dice la RPC, o crea uno nuevo (TMP-…) con la
        categoría y la unidad de Virgilio,
      - el No llama a denegar, y lo que se dijo que llegó sigue a la recepción de siempre
        (origen "Cervantes"),
      - al confirmar, se cierran sólo los avisos de lo que se grabó.
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
const vm = require("vm");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado (ver tests/smoke.cjs)."); process.exit(2); }
}

const root = path.join(__dirname, "..");
const src = fs.readFileSync(path.join(root, "recepcion.js"), "utf8");
const fail = [];
const ok = (c, m) => { if (!c) fail.push(m); };

const PEND = [
  { id: 11, creado_en: "2026-09-30T18:00:00Z", grupo: "terminado", cod_gp2: "058", descripcion: "Cierra Bolsa x2", cantidad: 36, unidad: "uni", cajas: 3, articulos_por_caja: 12, cod_gv: "058", empresa: "LK", cod_origen: "articulo" },
  { id: 12, creado_en: "2026-09-30T18:05:00Z", grupo: "terminado", cod_gp2: "941E", descripcion: "Cuchara", cantidad: 12, unidad: "uni", cajas: 1, articulos_por_caja: 12, cod_gv: "941E", empresa: "LK", cod_origen: "articulo" },
  { id: 13, creado_en: "2026-09-30T18:06:00Z", grupo: "terminado", cod_gp2: "718", descripcion: "Chef", cantidad: 24, unidad: "uni", cajas: 1, articulos_por_caja: 24, cod_gv: "718", empresa: "CH", cod_origen: "articulo" },
  { id: 14, creado_en: "2026-09-30T18:07:00Z", grupo: "insumo", cod_gp2: "PC12", descripcion: "Pieza", cantidad: 5, unidad: "uni", cajas: null, articulos_por_caja: null, cod_gv: null, empresa: null, cod_origen: null, categoria_gv: "partes_plasticas", unidad_gv: "Uni" }
];

const FAKE_CLIENT = `
window.__inserts = []; window.__rpc = [];
window.__PEND = ${JSON.stringify(PEND)};
function __q(table) {
  const o = {};
  ["select","gte","lte","eq","neq","in","not","or","ilike","order","limit","single","update","delete","maybeSingle"]
    .forEach(function (m) { o[m] = function () { return o; }; });
  o.insert = function (rows) { window.__inserts.push({ table: table, rows: rows });
                               return Promise.resolve({ data: rows, error: null }); };
  o.then = function (res, rej) { return Promise.resolve({ data: [], error: null }).then(res, rej); };
  return o;
}
window.supabase = { createClient: function () {
  return {
    from: __q,
    rpc: function (fn, args) {
      window.__rpc.push({ fn: fn, args: args || null });
      if (fn === "gv_envios_cervantes_pendientes") return Promise.resolve({ data: window.__PEND, error: null });
      if (fn === "gv_envio_cervantes_denegar") return Promise.resolve({ data: { ok: true, revertido: true }, error: null });
      if (fn === "gv_envio_cervantes_confirmar") return Promise.resolve({ data: { ok: true, confirmados: (args && args.p_ids || []).length }, error: null });
      return Promise.resolve({ data: [], error: null });
    },
    auth: {
      getSession: function () { return Promise.resolve({ data: { session: { fake: true } } }); },
      signInAnonymously: function () { return Promise.resolve({ data: { session: { fake: true } }, error: null }); }
    },
    storage: { from: function () { return { upload: function () { return Promise.resolve({ data: { path: "x" }, error: null }); },
                                           getPublicUrl: function () { return { data: { publicUrl: "https://x/f.jpg" } }; } }; } }
  };
} };
`;

const patched = src + `
window.__rcp = { opState: opState, drawArticulosGrid: drawArticulosGrid, rcpCervEncolar: rcpCervEncolar,
  el: { body: opBody } };
`;

(async () => {
  /* ---------------- A) Recepción → Log/ Fabr ---------------- */
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  // con origen http, para que localStorage (la cola del Sí) funcione de verdad
  const doc = '<!doctype html><meta charset="utf-8"><body><script>' + FAKE_CLIENT + '<\/script><script type="module">' + patched + "<\/script></body>";
  await p.route("http://gv.test/**", (route) => route.fulfill({ status: 200, contentType: "text/html; charset=utf-8", body: doc }));
  await p.goto("http://gv.test/rcp.html");
  await p.waitForFunction(() => !!window.__rcp, null, { timeout: 10000 });
  const A = await p.evaluate(async () => {
    const R = window.__rcp, S = R.opState, out = {};
    window.alert = function () {};
    window.prompt = function () { return "vino roto"; };
    S.tipo = "tallerista"; S.tallNombre = "Log/ Fabr"; S.linea = "LK"; S.fecha = "2026-09-30";
    S.remito = "40077"; S.cargas = {}; S.artExtra = {}; S.altaNuevos = {};
    S.ocPorCod = {}; S.ocOk = false; S.ocAjena = {}; S.tallCod = "1"; S.tallCods = { LK: "1", CH: "2" };
    S.step = "articulos"; S.cerv = null; S.cervSi = {};
    S.articulos = [{ Cod_Art: "058", Desc: "" }, { Cod_Art: "071", Desc: "" }];
    R.drawArticulosGrid();
    await new Promise(function (r) { setTimeout(r, 150); });
    const rows = Array.from(document.querySelectorAll(".opCerv .opCervRow"));
    out.cods = rows.map(function (r) { return r.querySelector("b").textContent; });
    out.primero = document.querySelector("#rcpRoot .opCerv, .opCerv") === R.el.body.firstElementChild;
    // ✓ Llegó en el 058 (estaba en la lista) y en el 941E (no estaba)
    document.querySelector('.opCervRow[data-id="11"] button[data-a="si"]').click();
    document.querySelector('.opCervRow[data-id="12"] button[data-a="si"]').click();
    out.cargas1 = JSON.stringify(S.cargas);
    out.agregoArt = S.articulos.some(function (a) { return a.Cod_Art === "941E"; });
    out.marcaOk = !!document.querySelector('.opCervRow[data-id="11"] .opCervOk');
    // ↩ Deshacer el 941E
    document.querySelector('.opCervRow[data-id="12"] button[data-a="undo"]').click();
    out.cargas2 = JSON.stringify(S.cargas);
    // ✕ No llegó el 941E
    document.querySelector('.opCervRow[data-id="12"] button[data-a="no"]').click();
    await new Promise(function (r) { setTimeout(r, 80); });
    const den = window.__rpc.filter(function (x) { return x.fn === "gv_envio_cervantes_denegar"; });
    out.denego = den.length === 1 && den[0].args.p_id === 12 && den[0].args.p_motivo === "vino roto";
    out.salioDelAviso = !document.querySelector('.opCervRow[data-id="12"]');
    // el Sí se encola con el código (lo que hace opEnviar después de grabar)
    const cs = S.cervSi, ids = Object.keys(cs).filter(function (id) { return (Number(S.cargas[cs[id].cod]) || 0) > 0; });
    const cods = {}; ids.forEach(function (id) { cods[id] = cs[id].cod; });
    R.rcpCervEncolar(ids.map(Number), S.remito, cods, "legajo 104");
    await new Promise(function (r) { setTimeout(r, 80); });
    const conf = window.__rpc.filter(function (x) { return x.fn === "gv_envio_cervantes_confirmar"; });
    out.confirmo = conf.length === 1 && JSON.stringify(conf[0].args.p_ids) === "[11]" && conf[0].args.p_cods["11"] === "058" && conf[0].args.p_ref === "40077";
    out.colaVacia = (localStorage.getItem("rcp_cerv_conf_v1") || "[]") === "[]";
    return out;
  });
  await b.close();
  ok(JSON.stringify(A.cods) === JSON.stringify(["058", "941E"]), "A: el aviso trae sólo lo de LK — " + JSON.stringify(A.cods));
  ok(A.primero, "A: el aviso va arriba de los códigos");
  ok(A.cargas1 === '{"058":3,"941E":1}', "A: ✓ Llegó suma las cajas — " + A.cargas1);
  ok(A.agregoArt, "A: el código que no estaba en la lista se agrega");
  ok(A.marcaOk, "A: queda marcado «en la carga»");
  ok(A.cargas2 === '{"058":3,"941E":0}', "A: ↩ Deshacer saca las cajas — " + A.cargas2);
  ok(A.denego, "A: ✕ No llegó llama a gv_envio_cervantes_denegar con el motivo");
  ok(A.salioDelAviso, "A: lo denegado sale del aviso");
  ok(A.confirmo, "A: el Sí se encola con el código y el remito, sólo de lo cargado");
  ok(A.colaVacia, "A: la cola del Sí queda vacía cuando la base contesta");
  if (errs.length) fail.push("A pageerror: " + errs.join(" | "));

  /* ---------------- B) Recibir Insumos (index.html) ---------------- */
  const html = fs.readFileSync(path.join(root, "index.html"), "utf8");
  const i0 = html.indexOf("async function _insCervRpc(");
  const i1 = html.indexOf("/* Material GP2 (del bundle) del insumo");
  ok(i0 > 0 && i1 > i0, "B: están las funciones del aviso en index.html");
  const code = html.slice(i0, i1);
  const calls = [];
  const els = {};
  const ctx = {
    console, JSON, Number, String, Date, Math, Promise, setTimeout,
    SUPABASE_URL: "https://x", SUPABASE_KEY: "k",
    _insK: (c) => String(c == null ? "" : c).toUpperCase().trim(),
    _insNum: (n) => String(n), escapeHtml: (s) => String(s),
    legajoInput: { value: "104" },
    insRender: () => {}, _ins: null,
    insCrearTmp: (it) => { it.cod = "TMP-0042"; return Promise.resolve("TMP-0042"); },
    insUbicOk: (mode, g) => { calls.push({ fn: "insUbicOk", mode, g }); },
    alert: () => {},
    fetch: async (url, o) => {
      const fn = url.split("/rpc/")[1], args = JSON.parse(o.body || "{}");
      calls.push({ fn, args });
      const body = fn === "gv_envios_cervantes_pendientes" ? PEND
        : fn === "gv_envio_cervantes_denegar" ? { ok: true, revertido: true } : { ok: true };
      return { ok: true, status: 200, text: async () => JSON.stringify(body) };
    },
    document: {
      getElementById: (id) => els[id] || (els[id] = { id, innerHTML: "", style: {}, value: id.indexOf("insCervMot") === 0 ? "faltó" : "", textContent: "", disabled: false }),
      createElement: () => ({ style: {} }), body: { appendChild: () => {} }
    }
  };
  ctx.window = ctx;
  vm.createContext(ctx);
  try { vm.runInContext(code, ctx); } catch (e) { fail.push("B: no compila — " + e.message); }
  if (typeof ctx._insCervOpciones === "function") {
    await ctx._insCervOpciones();
    ok((ctx._insCervLista || []).length === 1 && ctx._insCervLista[0].id === 14, "B: el botón lista sólo insumos / SC / SP (no los terminados)");
    ok(/Cervantes te mandó 1 pieza/.test(els.insUbicCerv.innerHTML), "B: el botón dice cuántas piezas mandó Cervantes");
    // No en una, Sí en la otra (le agrego una segunda pieza para probar las dos)
    ctx._insCervLista.push({ id: 15, creado_en: "2026-09-30T18:08:00Z", grupo: "sc", cod_gp2: "A10", descripcion: "Cpo Una", cantidad: 100, unidad: "uni", cod_gv: "INS77", categoria_gv: "partes_crudo", unidad_gv: "Uni" });
    ctx.insCervAbrir();
    ctx.insCervMarcar(14, "si"); ctx.insCervMarcar(15, "no");
    await ctx.insCervContinuar();
    const den = calls.filter((c) => c.fn === "gv_envio_cervantes_denegar");
    ok(den.length === 1 && den[0].args.p_id === 15 && den[0].args.p_motivo === "faltó" && den[0].args.p_por === "legajo 104", "B: ✕ No llegó deniega con motivo y legajo — " + JSON.stringify(den));
    const sigue = calls.filter((c) => c.fn === "insUbicOk")[0];
    ok(sigue && sigue.mode === "RI" && sigue.g.modo === "CERV" && sigue.g.envios.length === 1 && sigue.g.envios[0].id === 14, "B: lo que llegó sigue a la recepción de siempre");
    // precarga: PC12 sin código → insumo nuevo TMP con categoría y unidad de acá; y uno con código existente
    const items = [{ cod: "INS77", nombre: "Cpo", qty: 0, unidad: "Kg" }];
    ctx._insCervPrecargar({ envios: [PEND[3], { id: 16, cantidad: 7, cod_gv: "INS77", unidad_gv: "Uni", cod_gp2: "A10" }] }, items);
    await new Promise((r) => setTimeout(r, 20));
    const nuevo = items.filter((x) => x.cod === "TMP-0042")[0];
    ok(!!nuevo && nuevo.qty === 5 && nuevo.cat === "partes_plasticas" && nuevo.unidad === "Uni" && JSON.stringify(nuevo._cervIds) === "[14]", "B: sin código entra como insumo nuevo (TMP) con su categoría y unidad — " + JSON.stringify(nuevo));
    ok(items[0].qty === 7 && items[0].unidad === "Uni" && JSON.stringify(items[0]._cervIds) === "[16]", "B: con código suma en ese insumo — " + JSON.stringify(items[0]));
    // confirmar: sólo lo grabado
    ctx.rcpCervEncolar = (ids, ref, cods, por) => calls.push({ fn: "encolar", ids, ref, cods, por });
    ctx._insCervConfirmar([nuevo], "R-9", "104");
    const enc = calls.filter((c) => c.fn === "encolar")[0];
    ok(enc && JSON.stringify(enc.ids) === "[14]" && enc.cods["14"] === "TMP-0042" && enc.ref === "R-9" && enc.por === "legajo 104", "B: al confirmar se cierra sólo el aviso de lo grabado, con su código — " + JSON.stringify(enc));
  }

  if (fail.length) { console.error("cerv-envio-aviso: FALLÓ →\n  " + fail.join("\n  ")); process.exit(1); }
  console.log("cerv-envio-aviso: OK — lo que manda Cervantes se contesta Sí / No en Recepción (Log/ Fabr) y en Recibir Insumos");
  process.exit(0);
})();

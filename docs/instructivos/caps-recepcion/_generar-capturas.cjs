/* Capturas REALES del módulo de recepción (recepcion.js) para el instructivo gráfico. */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { ({ chromium } = require("playwright")); }

const root = "/home/user/Gestion-Virgilio";
const OUT = __dirname;
const src = fs.readFileSync(path.join(root, "recepcion.js"), "utf8");

const FAKE = `
const TALLS = [
  { tipo:"tallerista", nombre:"Lucho",     cod_lk:"3806", cod_ch:"3715", cod_default:"3806", cod_factura:null },
  { tipo:"tallerista", nombre:"Garcia",    cod_lk:"3801", cod_ch:null,   cod_default:"3801", cod_factura:null },
  { tipo:"tallerista", nombre:"Pintos",    cod_lk:"3812", cod_ch:"3712", cod_default:"3812", cod_factura:null },
  { tipo:"tallerista", nombre:"Pedernera", cod_lk:"3820", cod_ch:null,   cod_default:"3820", cod_factura:null },
  { tipo:"tallerista", nombre:"Log/ Fabr", cod_lk:"3800", cod_ch:"3700", cod_default:"3800", cod_factura:null },
  { tipo:"tallerista", nombre:"Poly",      cod_lk:"3815", cod_ch:null,   cod_default:"3815", cod_factura:null },
  { tipo:"tallerista", nombre:"Rafael",    cod_lk:"3818", cod_ch:null,   cod_default:"3818", cod_factura:null },
  { tipo:"tallerista", nombre:"Martin",    cod_lk:"3822", cod_ch:null,   cod_default:"3822", cod_factura:null },
  { tipo:"prov_at",    nombre:"Tierra Nativa", cod_lk:null, cod_ch:null, cod_default:null, cod_factura:"9001" },
  { tipo:"prov_at",    nombre:"Basconia",      cod_lk:null, cod_ch:null, cod_default:null, cod_factura:"9002" }
];
const ARTS = ["505","506","510","518","550","586","587","609"].map(c => ({ Cod_Art:c }));
const DATA = { "vista_entidades_recepcion": TALLS, "Articulos Virgilio X Tallerista": ARTS };
function __q(table) {
  const o = {};
  ["select","gte","lte","eq","neq","in","not","or","ilike","order","limit","single","update","delete"]
    .forEach(function (m) { o[m] = function () { return o; }; });
  o.insert = function (rows) { return Promise.resolve({ data: rows, error: null }); };
  o.then = function (res, rej) { return Promise.resolve({ data: DATA[table] || [], error: null }).then(res, rej); };
  return o;
}
window.supabase = { createClient: function () {
  return {
    from: __q,
    storage: { from: function () { return { upload: function(){ return Promise.resolve({data:{},error:null}); },
      getPublicUrl: function (p) { return { data: { publicUrl: "http://x/"+p } }; } }; } },
    rpc: function (fn) {
      if (fn === "oc_vigentes_por_proveedor") return Promise.resolve({ data: [
        { cod:"505", fecha:"2026-10-07", ped:120, rec:0,  pend:120 },
        { cod:"506", fecha:"2026-10-07", ped:60,  rec:20, pend:40 },
        { cod:"518", fecha:"2026-10-07", ped:40,  rec:0,  pend:40 },
        { cod:"586", fecha:"2026-10-07", ped:25,  rec:0,  pend:25 },
        { cod:"609", fecha:"2026-10-07", ped:15,  rec:0,  pend:15 }
      ], error: null });
      return Promise.resolve({ data: [], error: null });
    },
    auth: {
      getSession: function () { return Promise.resolve({ data: { session: { fake: true } } }); },
      signInAnonymously: function () { return Promise.resolve({ data: { session: { fake: true } }, error: null }); }
    }
  };
} };
`;

const patched = src + `
window.__rcp = { opState: opState, renderTipoElegir: renderTipoElegir, renderLista: renderLista,
  seleccionarEntidad: seleccionarEntidad, renderLinea: renderLinea, renderTipoDoc: renderTipoDoc,
  renderDocFields: renderDocFields, renderArticulos: renderArticulos, drawArticulosGrid: drawArticulosGrid,
  openCajas: openCajas, closeCajas: closeCajas, renderResumen: renderResumen,
  cargarOCVigentes: cargarOCVigentes, listaPorTipo: listaPorTipo,
  el: { page: opPage, body: opBody, actions: opActions, cajas: opCajasModal, input: opCajasInput } };
`;

const sleep = (ms) => new Promise(r => setTimeout(r, ms));

(async () => {
  const b = await chromium.launch({ args: ["--lang=es-AR"] });
  const p = await b.newPage({ viewport: { width: 420, height: 880 }, deviceScaleFactor: 2.5, locale: "es-AR", timezoneId: "America/Argentina/Buenos_Aires" });
  p.on("pageerror", e => console.error("PAGEERROR:", e.message));
  p.on("console", m => { if (m.type() === "error") console.error("CONSOLE:", m.text()); });
  const html = '<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:#eef2f7;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}</style><body><script>' + FAKE + '<\/script><script type="module">' + patched + '<\/script></body>';
  await p.route("http://rcp.test/**", r => r.fulfill({ status: 200, contentType: "text/html; charset=utf-8", body: html }));
  await p.goto("http://rcp.test/");
  await p.waitForFunction(() => !!window.__rcp, null, { timeout: 15000 });

  async function shot(name, forzarAlto) {
    await sleep(260);
    let H = forzarAlto;
    if (!H) {
      H = await p.evaluate(() => {
        const body = document.getElementById("opBody");
        const inner = document.querySelector(".opPageInner");
        const act = document.getElementById("opActions");
        const bar = document.getElementById("opAnularBar");
        const topBody = body.getBoundingClientRect().top;
        let bot = topBody;
        [].forEach.call(body.children, ch => { const r = ch.getBoundingClientRect(); if (r.bottom > bot) bot = r.bottom; });
        const hAct = act && act.children.length ? act.getBoundingClientRect().height : 0;
        const hBar = bar && bar.children.length ? bar.getBoundingClientRect().height : 0;
        return Math.ceil(bot - 0 + hAct + hBar + 46);
      });
      H = Math.max(360, Math.min(880, H));
    }
    await p.setViewportSize({ width: 420, height: H });
    await sleep(220);
    await p.screenshot({ path: OUT + "/" + name + ".png" });
    await p.setViewportSize({ width: 420, height: 880 });
    await sleep(120);
    console.log("  ✓", name, H);
  }

  // 1 — ¿Qué vas a cargar?
  await p.evaluate(() => { window.openRecepcionOp("237", "2026-10-13"); });
  await sleep(500);
  await shot("01-tipo");

  // 2 — lista de talleristas
  await p.evaluate(() => window.__rcp.renderLista("tallerista"));
  await shot("02-lista");

  // 3 — fecha + línea
  await p.evaluate(() => {
    const R = window.__rcp;
    const e = R.listaPorTipo("tallerista").filter(x => x.Nombre === "Lucho")[0];
    R.seleccionarEntidad(e);
    R.opState.fecha = "2026-10-13";
    R.renderLinea();
  });
  await shot("03-linea");

  // 4 — ¿Qué documentación recibís?
  await p.evaluate(() => { const R = window.__rcp; R.opState.linea = "LK"; R.opState.tallCod = "3806"; R.renderTipoDoc(); });
  await shot("04-doc");

  // 5 — campos de documentación (remito cargado)
  await p.evaluate(() => {
    const R = window.__rcp;
    R.opState.tipoDoc = "remito"; R.opState.nroRemito = "40873"; R.opState.fechaRemito = "2026-10-13";
    R.renderDocFields();
  });
  // El input type=date de Chromium headless pinta MM/DD/AAAA; en el celular (es-AR) se ve DD/MM/AAAA.
  await p.evaluate(() => {
    document.querySelectorAll('#opBody input[type="date"]').forEach(function (i) {
      const t = document.createElement("input");
      t.type = "text"; t.value = i.value.split("-").reverse().join("/");
      t.setAttribute("style", i.getAttribute("style") || ""); t.readOnly = true;
      i.parentNode.replaceChild(t, i);
    });
  });
  await shot("05-remito");

  // 6 — grilla de códigos con OC
  await p.evaluate(async () => {
    const R = window.__rcp;
    R.opState.remito = "40873"; R.opState.articulos = null; R.opState.ocPorCod = null; R.opState.cargas = {};
    await R.renderArticulos();
  });
  await sleep(600);
  await p.evaluate(() => window.__rcp.drawArticulosGrid());
  await shot("06-codigos");

  // 7 — pop-up de cajas
  await p.evaluate(() => { window.__rcp.openCajas("505"); const i = window.__rcp.el.input; i.value = "40"; i.dispatchEvent(new Event("input")); });
  await shot("07-cajas", 640);

  // 8 — grilla con cargas
  await p.evaluate(() => {
    const R = window.__rcp;
    R.closeCajas(); R.opState.cargas = { "505": 40, "518": 12, "586": 6 }; R.drawArticulosGrid();
  });
  await shot("08-cargados");

  // 9 — resumen sin foto
  await p.evaluate(() => window.__rcp.renderResumen());
  await shot("09-resumen");

  // 10 — resumen con foto
  await p.evaluate(async () => {
    const R = window.__rcp;
    const c = document.createElement("canvas"); c.width = 640; c.height = 420;
    const x = c.getContext("2d");
    x.fillStyle = "#cbd5e1"; x.fillRect(0,0,640,420);
    x.fillStyle = "#b08968";
    for (let f = 0; f < 3; f++) for (let k = 0; k < 4; k++) {
      x.fillRect(40 + k*145, 120 + f*95, 130, 85);
      x.strokeStyle = "#8d6e55"; x.lineWidth = 3; x.strokeRect(40 + k*145, 120 + f*95, 130, 85);
    }
    x.fillStyle = "#475569"; x.font = "bold 26px sans-serif"; x.fillText("foto de la mercadería", 180, 60);
    const blob = await new Promise(r => c.toBlob(r, "image/jpeg", 0.8));
    R.opState.fotoFile = new File([blob], "foto.jpg", { type: "image/jpeg" });
    R.opState.fotoPreviewUrl = URL.createObjectURL(blob);
    R.renderResumen();
  });
  await shot("10-resumen-foto");

  // 11 — exceso sobre la OC: hay que avisar por WhatsApp antes de enviar
  await p.evaluate(() => {
    const R = window.__rcp;
    R.opState.cargas = { "505": 200, "518": 12, "586": 6 };
    R.renderResumen();
    const sec = document.getElementById("opExcWa");
    if (sec) sec.scrollIntoView({ block: "center" });
  });
  await shot("11-exceso");

  await b.close();
  console.log("listo");
})();

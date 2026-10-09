/* v29.22 (Luis, 09/10) — Insumos del operario:
   (a) «Recibir insumos» abre PRIMERO las categorías de insumos, SIN importados;
   (b) elegir una que no es plásticos no busca las OC de bolsas de GP2;
   (c) el modal de recepción abre en esa categoría y no trae importados;
   (d) «Envío a inyectores» muestra SÓLO las bolsas plásticas reales (plástico, con ubicación,
       sin TMP-), sin «‹ Atrás» ni buscador;
   (e) v29.25: en RECIBIR y en «Envío a otros», de plásticos sólo las bolsas reales (sin TMP- ni
       códigos viejos), sin «+ Agregar insumo» en plásticos ni la categoría en el alta. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 390, height: 844 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    window.alert = function () {};
    const CATS = [["plastico","🧪 Plásticos"],["fleje","🧵 Flejes"],["importados","🌎 Importados"],["partes_plasticas","🧩 Partes plásticas"],["cajas","📦 Cajas"],["parte_procesado","⚙ Procesado"],["partes_crudo","🔩 Crudo"]];
    window.insLoadMeta = async function () { INS_CATS = CATS.map(function (c) { return { k: c[0], lbl: c[1], unis: [], desc: "" }; }); };
    let gp2Llamado = 0; window._insGp2Opciones = async function () { gp2Llamado++; };
    window.insFetchCatalogo = async function () { return [
      { cod: "PP 2630", nombre: "pp", categoria: "plastico", ubicacion: "AF01" },
      { cod: "ABS", nombre: "abs", categoria: "plastico", ubicacion: "AF03" },
      { cod: "1445", nombre: "viejo", categoria: "plastico", ubicacion: "" },
      { cod: "TMP-0013", nombre: "tmp", categoria: "plastico", ubicacion: "" },
      { cod: "505C", nombre: "cuchilla", categoria: "importados", ubicacion: "R01AD" },
      { cod: "F10", nombre: "121 X 1,20", categoria: "fleje", ubicacion: "K04" }
    ]; };
    window.stockFetchSaldos = async function () { return {}; };
    window.insFetchSaldosXUni = async function () { return {}; };
    const out = {};
    insChooserGo("RI");
    await new Promise(function (res) { setTimeout(res, 50); });
    const btns = Array.from(document.querySelectorAll("#insChooserModal .ins-ri-cat")).map(function (x) { return x.textContent; });
    out.a = btns.length === 6 && !btns.some(function (t) { return /Importados/.test(t); });
    insRecibirCatGo("fleje");
    const ub = document.getElementById("insUbicModal");
    out.b = !!ub && ub.style.display === "flex" && gp2Llamado === 0 && window._insRiCat === "fleje";
    await showInsumoModal("RI", "104");
    out.c = _ins.cat === "fleje" && !_ins.items.some(function (x) { return x.cat === "importados"; }) && window._insRiCat === null;
    insUbicCancel();
    window._insGp2 = { modo: "EI", inyector: "Inyector X", mv: { materiales: [], inyectores: ["Inyector X"] } };
    await showInsumoModal("EI", "104");
    const cods = _ins.items.map(function (x) { return x.cod; }).sort();
    const html = document.getElementById("insBody").innerHTML;
    insBack();
    out.d = JSON.stringify(cods) === JSON.stringify(["ABS", "PP 2630"]) && _ins.soloBolsas === true && _ins.cat === "plastico" &&
      !/insBack\(\)/.test(html) && !/class="ins-search"/.test(html) && /Bolsas plásticas/.test(html);
    out.cods = cods;
    // (e) v29.25
    window._insRiCat = "plastico"; window._insGp2 = null;
    await showInsumoModal("RI", "104");
    const plaRI = _ins.items.filter(function (x) { return x.cat === "plastico"; }).map(function (x) { return x.cod; }).sort();
    const htmlRI = document.getElementById("insBody").innerHTML;
    insNuevoOpen("");
    const htmlAlta = document.getElementById("insBody").innerHTML;
    window._insGp2 = null;
    await showInsumoModal("EI", "104");
    const plaEI = _ins.items.filter(function (x) { return x.cat === "plastico"; }).map(function (x) { return x.cod; }).sort();
    const otrasEI = _ins.items.some(function (x) { return x.cod === "F10"; });
    out.e = JSON.stringify(plaRI) === JSON.stringify(["ABS", "PP 2630"]) && JSON.stringify(plaEI) === JSON.stringify(["ABS", "PP 2630"]) &&
      otrasEI && !/ins-itbtn add/.test(htmlRI) && !/insNuevoPick\('cat','plastico'\)/.test(htmlAlta) && /insNuevoPick\('cat','fleje'\)/.test(htmlAlta);
    out.plaRI = plaRI; out.plaEI = plaEI;
    return out;
  });
  const pass = r.a && r.b && r.c && r.d && r.e && errs.length === 0;
  console.log("ins-ri-cat-bolsas:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();

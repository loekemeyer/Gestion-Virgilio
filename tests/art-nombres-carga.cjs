/* Regresión v22.32 — EL PADRÓN DE NOMBRES CARGA DE VERDAD.
   Luis, 24/09: "¿Qué bajar primero?" mostraba 862 como "862" y 763 vacío, con el nombre en
   vista_nombres_articulos. Causa: loadArtNombres hacía `if (r.ok)` sobre lo que devuelve
   supaFetchAllSafe, que es un ARRAY de filas (no un Response): el mapa quedaba siempre vacío y
   artNombre() caía al texto del libro de stock en toda la app. Mismo pozo en loadArtMarcas y en
   dos lecturas de Articulos_Cajas. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const ROWS = { vista_nombres_articulos: [{ cod: "862", descripcion: "Corta Pizza Mgo Chef" }, { cod: "763", descripcion: "Bombilla Resorte Tradicional" }],
                   vista_marca_articulo: [{ cod: "862", marca: "CH" }] };
    window.supaFetchAll = async function (ep) { for (const k in ROWS) if (String(ep).indexOf(k) >= 0) return ROWS[k]; return []; };
    _artNombres = null; _artMarcas = null;
    await loadArtNombres(); await loadArtMarcas();
    return { n862: artNombre("862", "862"), n763: artNombre("0763", ""), marca: artMarca("862"), fb: artNombre("999", "x") };
  });
  await b.close();
  const f = [];
  // Candado estático: ninguna lectura con supaFetchAll(Safe) puede tratar su resultado como Response.
  const src = require("fs").readFileSync(path.join(__dirname, "..", "index.html"), "latin1").split("\n");
  src.forEach(function (l, i) {
    const m = /(?:const|let|var)\s+(\w+)\s*=\s*await\s+supaFetchAll(?:Safe)?\(/.exec(l);
    if (!m) return;
    const win = src.slice(i, i + 4).join("\n");
    if (new RegExp("\\b" + m[1] + "\\.(ok|json\\(|status)\\b").test(win)) f.push("línea " + (i + 1) + ": `" + m[1] + "` es un array de filas, no un Response");
  });
  if (r.n862 !== "Corta Pizza Mgo Chef") f.push("862 no toma el nombre del padrón: " + r.n862);
  if (r.n763 !== "Bombilla Resorte Tradicional") f.push("763 (con cero adelante) no resuelve: " + r.n763);
  if (r.marca !== "CH") f.push("la marca no carga: " + r.marca);
  if (r.fb !== "x") f.push("sin nombre en el padrón no cae al fallback");
  if (errs.length) f.push("errores: " + errs.join(" | "));
  if (f.length) { console.error("art-nombres-carga: FALLA\n  - " + f.join("\n  - ")); process.exit(1); }
  console.log("art-nombres-carga: OK — el padrón de nombres y marcas carga (array, no Response)");
})();

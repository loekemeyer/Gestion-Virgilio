/* Regresión v20.45 — EL DESTINO DEL EXPRESO Y EL AVISO DE MISIONES EN LA PROGRAMACIÓN.

   Luis, 2026-09-21: *"Tenemos que traer el dato de las dos paginas, tiene que viajar con los
   pedidos. Esta bueno que muestre la zona así para los expresos (expreso y provincia destino).
   Pero particularmente para los pedido de misiones necesito que la fila del día que tenga
   programado un pedido de misiones se ponga naranja y aparezca una medalla que diga (Hay pedido
   misiones). Lo mismo para tandas. Que las NPs de ese tipo de pedidos tambien se coloreen de
   naranja y tengan el badge "MISIONES"*.

   Corre el árbol de la Programación con filas de prueba y un mapa de destinos inyectado —sin
   red— y chequea sobre el HTML que sale:
   - la NP marcada lleva la clase `mis` y el badge con el nombre de la provincia;
   - la tanda que la contiene y el día que la contiene también (la marca SUBE, no se calcula
     aparte: las partes tienen que sumar el todo, igual que los m³ y los estados);
   - una NP sin alerta NO se pinta, y su tanda tampoco;
   - el destino del expreso ("Snaider · Misiones") se muestra sólo cuando HAY expreso;
   - la provincia NO está hardcodeada en el front: sale del flag `alerta` que manda el backend
     (`PPP_Web_Config.provincias_alerta`). Con otra provincia marcada tiene que andar igual.
   - el feed de LK pide `provincia` (sin eso el dato no viaja desde la página).
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
  const fallos = [];

  // ── guard estático: el dato tiene que salir de la página ──────────────────────────────
  const html = fs.readFileSync(path.join(root, "index.html"), "latin1");
  if (!/select=[a-z_,0-9]*localidad,provincia,zona_expreso/.test(html))
    fallos.push("el feed de LK no pide `provincia`: el destino no viaja desde la página");
  if (!/gv_np_destino\?select=np,provincia,expreso,alerta,destino_txt/.test(html))
    fallos.push("no se lee gv_np_destino");
  // la provincia no se decide en el front
  if (/["']Misiones["']/.test(html.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "")))
    fallos.push("aparece 'Misiones' hardcodeado fuera de los comentarios: tiene que salir de PPP_Web_Config.provincias_alerta");

  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    const out = {};
    // tres NP: una a Misiones por expreso, una a Santa Fe por expreso (no marcada) y una de
    // CABA sin expreso. Dos tandas, en dos días distintos.
    const filas = [
      { fecha: "2026-09-25", tanda: "E90A", np: "LK 0027", cod: "958", razon_social: "Albalandia S.R.L. (M)",
        localidad: "Soldati", barrio: "Soldati", zona: "Zona 1 - CABA Sur", zona_corta: "Zona 1",
        empresa: "LK", origen: "web", m3: 0.709, estado: "pendiente", estado_orden: 1, clave: "1357" },
      { fecha: "2026-09-25", tanda: "E90B", np: "LK 0028", cod: "2394", razon_social: "Clapera Alicia",
        localidad: "Soldati", barrio: "Soldati", zona: "Zona 1 - CABA Sur", zona_corta: "Zona 1",
        empresa: "LK", origen: "web", m3: 0.2, estado: "pendiente", estado_orden: 1, clave: "1358" },
      { fecha: "2026-09-26", tanda: "E91A", np: "LK 0029", cod: "3797", razon_social: "Oranhogar SRL",
        localidad: "Villa Urquiza", barrio: "Villa Urquiza", zona: "Zona 6 - GBA Norte", zona_corta: "Zona 6",
        empresa: "LK", origen: "web", m3: 0.3, estado: "pendiente", estado_orden: 1, clave: "1359" },
    ];
    const dest = new Map([
      ["LK 0027", { np: "LK 0027", provincia: "Misiones", expreso: "Snaider", alerta: true,  destino_txt: "Snaider · Misiones" }],
      ["LK 0028", { np: "LK 0028", provincia: "Santa Fe", expreso: "Avellaneda", alerta: false, destino_txt: "Avellaneda · Santa Fe" }],
      ["LK 0029", { np: "LK 0029", provincia: "CABA", expreso: null, alerta: false, destino_txt: "CABA" }],
    ]);
    // ⚠ `_pgaDest`, `_pgaOpenD` y `_pgaOpenT` se declaran con `let` en el script inline: NO
    // viven en `window`. Se asignan directo, que desde acá cae en el mismo binding.
    _pgaDest = dest;
    _pppSearch = "";
    _pgaOpenD = { "20260925": true, "20260926": true };
    _pgaOpenT = { "20260925|E90A": true, "20260925|E90B": true, "20260926|E91A": true };

    const arbol = _pgaArbol(filas);
    out.dias = arbol.map(function (d) {
      return { key: d.key, mis: d.mis, provs: [...d.misProv],
               tandas: d.tandasArr.map(function (t) { return { tanda: t.tanda, mis: t.mis }; }) };
    });
    const h = _pgaCuerpoHtml(arbol, {});
    out.html = h;

    // ¿qué filas quedaron marcadas?
    const trs = h.split("<tr ").slice(1);
    out.filasMis = trs.filter(function (x) { return / mis"/.test(x.split(">")[0]); }).length;
    out.npMis   = trs.filter(function (x) { return /pga-n[^"]* mis"/.test(x.split(">")[0]); }).length;
    out.tMis    = trs.filter(function (x) { return /pga-t [^"]*mis"/.test(x.split(">")[0]); }).length;
    out.dMis    = trs.filter(function (x) { return /pga-d[^"]* mis"/.test(x.split(">")[0]); }).length;

    // ── y ahora con OTRA provincia marcada: el front no puede tener Misiones adentro ──────
    dest.set("LK 0029", { np: "LK 0029", provincia: "Chubut", expreso: "Cruz Del Sur", alerta: true, destino_txt: "Cruz Del Sur · Chubut" });
    const h2 = _pgaCuerpoHtml(_pgaArbol(filas), {});
    out.chubut = /CHUBUT/.test(h2) && /Hay pedido Chubut/.test(h2);
    return out;
  });

  await b.close();
  if (errs.length) fallos.push("errores de página: " + errs.join(" | "));

  const d25 = (r.dias || []).find((x) => x.key === "20260925") || {};
  const d26 = (r.dias || []).find((x) => x.key === "20260926") || {};
  if (d25.mis !== 1) fallos.push("el día 25/09 tendría que contar 1 pedido marcado, cuenta " + d25.mis);
  if ((d25.provs || []).join() !== "Misiones") fallos.push("el día no guardó la provincia: " + JSON.stringify(d25.provs));
  if (d26.mis !== 0) fallos.push("el día 26/09 no tiene pedidos marcados y cuenta " + d26.mis);
  const t90a = (d25.tandas || []).find((x) => x.tanda === "E90A") || {};
  const t90b = (d25.tandas || []).find((x) => x.tanda === "E90B") || {};
  if (t90a.mis !== 1) fallos.push("la tanda E90A tendría que contar 1, cuenta " + t90a.mis);
  if (t90b.mis !== 0) fallos.push("la tanda E90B no lleva Misiones y cuenta " + t90b.mis);

  if (r.dMis !== 1) fallos.push("filas de DÍA en naranja: " + r.dMis + " (esperado 1)");
  if (r.tMis !== 1) fallos.push("filas de TANDA en naranja: " + r.tMis + " (esperado 1)");
  if (r.npMis !== 1) fallos.push("filas de NP en naranja: " + r.npMis + " (esperado 1)");

  const h = r.html || "";
  if (!/class="pga-mis"[^>]*>MISIONES</.test(h)) fallos.push("falta el badge MISIONES en la fila de la NP");
  if (!/Hay pedido Misiones/.test(h)) fallos.push("falta la medalla «Hay pedido Misiones» en el día y la tanda");
  if ((h.match(/Hay pedido Misiones/g) || []).length < 2) fallos.push("la medalla tiene que estar en el día Y en la tanda");
  if (!/Snaider · Misiones/.test(h)) fallos.push("falta el destino del expreso en la fila de la NP");
  if (!/Avellaneda · Santa Fe/.test(h)) fallos.push("el destino del expreso sólo se muestra para la provincia marcada; tiene que mostrarse siempre que haya expreso");
  if (/pga-dest[^<]*>🚚 CABA</.test(h)) fallos.push("un pedido SIN expreso no tiene que mostrar chip de destino");
  if (!r.chubut) fallos.push("con otra provincia marcada el front no reacciona: la provincia está hardcodeada");

  if (fallos.length) { console.error("ppp-misiones FALLA:\n - " + fallos.join("\n - ")); process.exit(1); }
  console.log("ppp-misiones OK — día/tanda/NP en naranja, badge y medalla por dato, destino del expreso a la vista.");
})();

/* v22.40 — un pedido RETIRA en la Programación no puede leerse como reparto.

   Caso real (Silvano Lucas Martin, LK 4282, LK 0096): la fila salía
   "Zona 6 · Retira 🚚 CABA" — la zona es la del cliente en el padrón (GBA Norte) y el 🚚 es el
   destino del expreso, así que parecía que salía en camión a Zona 6. Pero lo viene a buscar el
   cliente al depósito. La regla (v20.74): lo decide el PEDIDO — si es Retira, manda Retira.

   Este test corre el árbol de la Programación con una NP Retira y una de reparto, y chequea:
   - la fila Retira NO muestra la zona de reparto ("Zona 6") ni el 🚚 del expreso ("🚚 CABA");
   - la fila Retira SÍ muestra el chip "🏭 Retira";
   - una NP normal SÍ sigue mostrando su zona y su 🚚 destino (no se rompió lo de siempre);
   - aprDestinoChip devuelve "" para un Retira (A Programar tampoco le pone el 🚚).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const root = path.join(__dirname, "..");
  const fallos = [];
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    const out = {};
    const filas = [
      // RETIRA: zona del cliente = GBA Norte, pero lo retira del depósito (barrio "Retira")
      { fecha: "2026-09-25", tanda: "E64C", np: "LK 0096", cod: "4282", razon_social: "Silvano Lucas Martin",
        localidad: "Retira", barrio: "Retira", zona: "Zona 6 - GBA Norte", zona_corta: "Zona 6",
        empresa: "LK", origen: "web", m3: 0.03, estado: "pendiente", estado_orden: 1, clave: "1448" },
      // REPARTO normal: tiene que seguir mostrando su zona y su 🚚 destino
      { fecha: "2026-09-25", tanda: "E64D", np: "LK 0100", cod: "3797", razon_social: "Oranhogar SRL",
        localidad: "Villa Urquiza", barrio: "Villa Urquiza", zona: "Zona 6 - GBA Norte", zona_corta: "Zona 6",
        empresa: "LK", origen: "web", m3: 0.3, estado: "pendiente", estado_orden: 1, clave: "1500" },
    ];
    _pgaDest = new Map([
      ["LK 0096", { np: "LK 0096", provincia: "CABA", expreso: "Retira", alerta: false, destino_txt: "CABA" }],
      ["LK 0100", { np: "LK 0100", provincia: "CABA", expreso: "Snaider", alerta: false, destino_txt: "Snaider · CABA" }],
    ]);
    _pppSearch = "";
    _pgaOpenD = { "20260925": true };
    _pgaOpenT = { "20260925|E64C": true, "20260925|E64D": true };
    const h = _pgaCuerpoHtml(_pgaArbol(filas), {});
    // aislar la fila de cada NP
    const trs = h.split("<tr ").map(function (x) { return "<tr " + x; });
    out.retFila = trs.find(function (x) { return x.indexOf("LK 0096") >= 0; }) || "";
    out.repFila = trs.find(function (x) { return x.indexOf("LK 0100") >= 0; }) || "";
    // aprDestinoChip para un Retira (A Programar)
    _pgaDest = new Map([["LK 0096", { np: "LK 0096", provincia: "CABA", expreso: "Retira", alerta: false, destino_txt: "CABA" }]]);
    try { out.aprChipRet = aprDestinoChip({ np: "LK 0096", empresa: "lk", order_id: 1448, zona: "Retira" }); }
    catch (e) { out.aprChipRet = "ERR:" + e.message; }
    return out;
  });
  await b.close();
  if (errs.length) fallos.push("errores de página: " + errs.join(" | "));

  // --- fila RETIRA ---
  if (!/pga-ret[^>]*>🏭 Retira</.test(r.retFila)) fallos.push("la fila Retira no muestra el chip 🏭 Retira");
  if (/pga-loc[^>]*>[^<]*Zona 6/.test(r.retFila)) fallos.push("la fila Retira sigue mostrando la zona de reparto 'Zona 6'");
  if (/pga-dest[^>]*>🚚/.test(r.retFila)) fallos.push("la fila Retira sigue mostrando el 🚚 del expreso (no va en camión)");

  // --- fila REPARTO (no se rompió lo de siempre) ---
  if (!/pga-loc[^>]*>[^<]*Zona 6/.test(r.repFila)) fallos.push("la fila de reparto perdió su zona");
  if (!/pga-dest[^>]*>🚚 Snaider · CABA</.test(r.repFila)) fallos.push("la fila de reparto perdió su 🚚 destino");
  if (/pga-ret/.test(r.repFila)) fallos.push("la fila de reparto muestra el chip Retira por error");

  // --- A Programar ---
  if (r.aprChipRet !== "") fallos.push("aprDestinoChip debería ser '' para un Retira, dio: " + JSON.stringify(r.aprChipRet));

  if (fallos.length) { console.error("✗ ppp-retira-badge:\n  - " + fallos.join("\n  - ")); process.exit(1); }
  console.log("ppp-retira-badge: OK — Retira muestra 🏭 Retira, sin 'Zona 6' ni 🚚; el reparto intacto.");
})();

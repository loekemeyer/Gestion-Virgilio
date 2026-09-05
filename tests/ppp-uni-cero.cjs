/* Regresión (v12.70): la columna UNIDADES del detalle de una tanda se caía para
   TODOS los códigos que empiezan con cero.

   pppFetchDetalle normalizaba el código ANTES de mandarlo al servidor: _ocgNorm
   le saca los ceros de adelante ("031" → "31") y OC_Maximos los guarda CON el
   cero, así que el in.() no traía esas filas y la celda salía "—". Son 20 códigos
   activos (026, 027, 031, 034, 035E, 043, 052…); el 031 tiene uni_x_caja 24.

   Verifica que al servidor se le pidan los códigos CRUDOS (además del
   normalizado) y que las unidades se calculen igual para un código con cero y
   para uno sin cero. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    let uniUrl = "";
    const json = (o) => ({ ok: true, status: 200, json: async () => o });
    window.fetch = async (url) => {
      const u = String(url);
      if (u.includes("ppp_base_pedidos")) return json([
        { articulo: "031", cajas: 60 },   // con cero: el que fallaba
        { articulo: "502", cajas: 40 }    // sin cero: el que siempre anduvo
      ]);
      if (u.includes("OC_Maximos")) {
        uniUrl = u;
        // El servidor SOLO devuelve la fila si le pidieron el código tal cual está
        // guardado. Si el test recibiera "31" en vez de "031", no habría fila —
        // que es exactamente lo que pasaba.
        const rows = [{ cod: "502", uni_x_caja: 12 }];
        if (/[(,]031(,|\))/.test(u)) rows.push({ cod: "031", uni_x_caja: 24 });
        return json(rows);
      }
      return json([]);
    };
    const items = await pppFetchDetalle("98647");
    const html = _pppDetalleHtml(items, "98647");
    const by = {}; items.forEach(i => { by[i.articulo] = i._uni; });
    return {
      pidioCrudo: /[(,]031(,|\))/.test(uniUrl),
      uni031: by["031"], uni502: by["502"],
      html1440: html.includes(">1440<"),   // 60 × 24
      html480:  html.includes(">480<"),    // 40 × 12
      sinGuion: !html.includes(">—<")
    };
  });

  const ok = r.pidioCrudo && r.uni031 === 24 && r.uni502 === 12 && r.html1440 && r.html480 && r.sinGuion;
  console.log("ppp-uni-cero:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", (ok && !errs.length) ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit((ok && !errs.length) ? 0 : 1);
})();

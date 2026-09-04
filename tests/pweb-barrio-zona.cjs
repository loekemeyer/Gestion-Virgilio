/* Regresión (v12.72/73): de dónde sale la LOCALIDAD de un pedido web.

   Sale del PADRÓN de LK (`customer_delivery_addresses.localidad`), que es una
   columna propia — mismo criterio que la PPP de Producción, donde el barrio viene
   en su columna y la dirección es sólo el fallback. Partir el string de la
   dirección era una invención, y queda como ÚLTIMO RECURSO (Retira, etiquetas
   sueltas y Chef, cuya RPC todavía no trae la columna).

   El fallback igual tiene que cortar bien: por el ÚLTIMO guión, con o sin
   espacios alrededor.

   Antes se exigía espacio a los dos lados y el padrón real no lo respeta:
   "1737-Palermo", "2579- Constitucion", "Krausse5108-Tortuguita" quedaban sin
   cortar, la dirección entera se tomaba como barrio y la zona NUNCA resolvía. En
   pantalla eran 295 NP "sin zona".

   También verifica que un pedido web NO entre al panel de "revisar/corregir en el
   Excel": no sale de ningún Excel, y con 295 avisos el panel dejaba de servir para
   lo suyo, que es detectar errores de carga de la PPP de ISIS.

   Las direcciones son REALES (v_pedidos_web_np, 04/09). */
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

  const r = await p.evaluate(() => {
    window._pppZonaSupa = {
      palermo: "Zona 2 - CABA Centro", constitucion: "Zona 1 - CABA Sur",
      mataderos: "Zona 3 - CABA Oeste", martinez: "Zona 6 - GBA Norte",
      quilmes: "Zona 4 - GBA Sur", colegiales: "Zona 2 - CABA Centro"
    };
    const casos = {
      pegado:        pwebBarrioDe("Federico Lacroze 1737-Palermo"),
      espacioDerecha:pwebBarrioDe("Cochabamba 2579- Constitucion"),
      espacioAmbos:  pwebBarrioDe("Bragado 5742 - Mataderos"),
      sinEspacioNum: pwebBarrioDe("Av Otto Krausse5108-Tortuguita"),
      dosGuiones:    pwebBarrioDe("Av. Luro 6099-G. de Laferrere"),
      barras:        pwebBarrioDe("La Salle 2170/72/74- Flores"),
      sinGuion:      pwebBarrioDe("Rio Cuarto"),
      retira:        pwebBarrioDe("Retira en depósito"),
      vacio:         pwebBarrioDe("")
    };
    // La localidad del padrón MANDA sobre lo que diga la dirección.
    const padron = {
      // el padrón dice Colegiales aunque la dirección diga otra cosa
      mandaPadron:  pwebLocalidad({ localidad: "Colegiales", direccion: "Av Falsa 1 - Mataderos" }),
      // sin padrón, se cae al parseo
      fallback:     pwebLocalidad({ localidad: "",           direccion: "Federico Lacroze 1737-Palermo" }),
      fallbackNull: pwebLocalidad({ direccion: "Cochabamba 2579- Constitucion" })
    };
    const zonas = {
      dePadron:    pwebZonaSugerida({ localidad: "Quilmes", direccion: "Av Falsa 1 - Mataderos" }),
      deFallback:  pwebZonaSugerida({ direccion: "Federico Lacroze 1737-Palermo" }),
      interior:    pwebZonaSugerida({ localidad: "Cordoba" }),   // interior: sin zona, y está bien
      retira:      pwebZonaSugerida({ direccion: "Virgilio 2788 - Retira" })
    };
    // El panel de errores del Excel no tiene que ver los pedidos web.
    const info = _pppComputeErrors([
      { np: "LK 1343", _web: true,  localidad: "Cordoba", zona: "", programmed: false },
      { np: "98500",   _web: false, localidad: "Pueblo Ignoto", zona: "", programmed: false }
    ], new Set());
    return { casos, padron, zonas, sinZonaEnPanel: (info.sinZona || []).map(x => x.np) };
  });

  const c = r.casos, z = r.zonas;
  const ok = c.pegado === "Palermo" && c.espacioDerecha === "Constitucion"
    && c.espacioAmbos === "Mataderos" && c.sinEspacioNum === "Tortuguita"
    && c.dosGuiones === "G. de Laferrere" && c.barras === "Flores"
    && c.sinGuion === "Rio Cuarto" && c.retira === "Retira" && c.vacio === ""
    && r.padron.mandaPadron === "Colegiales" && r.padron.fallback === "Palermo"
    && r.padron.fallbackNull === "Constitucion"
    && z.dePadron === "Zona 4 - GBA Sur"        // gana el padrón (Quilmes), no la dirección (Mataderos)
    && z.deFallback === "Zona 2 - CABA Centro" && z.interior === "" && z.retira === "Retira"
    && r.sinZonaEnPanel.length === 1 && r.sinZonaEnPanel[0] === "98500";

  console.log("pweb-barrio-zona:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", (ok && !errs.length) ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit((ok && !errs.length) ? 0 : 1);
})();

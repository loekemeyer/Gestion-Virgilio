/* v13.89 — Hoja de ruta del camión: Google Maps + imprimible para el fletero.
   Dueño 07/09: "un botoncito que me abra Google Maps … poder imprimírselo al fletero con todos los
   pedidos que tiene … Dapelo pidió cuatro notas de pedido … que se unifique en uno solo, que aclare
   4 NP, pero que no aparezca todo el tiempo que hay que ir cuatro veces al mismo lugar".
   (a) una parada = una DIRECCIÓN: las 4 NP de Dapelo en Almagro son UNA parada que dice "4 NP";
   (b) el mismo cliente en OTRO barrio sigue siendo otra parada (Almagro / Colegiales / Villa Crespo
       son tres viajes de verdad: unificar sólo por cód se comería dos);
   (c) el link de Maps arranca en el depósito, va en orden de ENTREGA y no lleva las paradas sin
       ubicación (que igual se listan, marcadas);
   (d) la hoja se puede imprimir y el overlay abre con el nombre del camión.
   Todo con lo que ya está en memoria: sin red. Sale 1 si falla. */
const path = require("path");
const { chromium } = require("/opt/node22/lib/node_modules/playwright");
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    // ubicaciones de mentira, con la misma clave que usa PPP_Geo (dirección|barrio, en minúscula)
    const G = {};
    G[RT_DEPOT_KEY] = { lat: -34.6280, lng: -58.4110 };
    G[_rtDirKey("Guardia Vieja 4200", "Almagro")] = { lat: -34.5980, lng: -58.4200 };
    G[_rtDirKey("Conde 1100", "Colegiales")] = { lat: -34.5720, lng: -58.4570 };
    G[_rtDirKey("Serrano 500", "Villa Crespo")] = { lat: -34.5900, lng: -58.4400 };
    G[_rtDirKey("Brasil 1200", "Constitución")] = { lat: -34.6250, lng: -58.3880 };
    _pppGeo = G; _pppGeoCod = {};

    const ped = (np, cod, rs, dir, loc, m3, tanda) => ({ np: np, cod: cod, razon_social: rs, direccion: dir, localidad: loc, m3: m3, tanda: tanda, fecha_entrega: "11/09/2026" });
    const cam = {
      key: "n01", ruta: "so", tn: "E01", num: 1, zona: "Zona 2 - CABA Centro", tandas: ["E01A"], m3: 0,
      ped: [
        // Dapelo, 4 NP en la MISMA dirección de Almagro → una sola parada
        ped("98676", "1792", "Dapelo Claudio Marcelo", "Guardia Vieja 4200", "Almagro", 0.30, "E01A"),
        ped("98677", "1792", "Dapelo Claudio Marcelo", "Guardia Vieja 4200", "Almagro", 0.25, "E01A"),
        ped("98678", "1792", "Dapelo Claudio Marcelo", "Guardia Vieja 4200", "Almagro", 0.20, "E01A"),
        ped("98679", "1792", "Dapelo Claudio Marcelo", "Guardia Vieja 4200", "Almagro", 0.25, "E01A"),
        // el MISMO cód en otros dos barrios → dos paradas más
        ped("98669", "1792", "Dapelo Claudio Marcelo", "Conde 1100", "Colegiales", 0.40, "E01A"),
        ped("98674", "1792", "Dapelo Claudio Marcelo", "Serrano 500", "Villa Crespo", 0.35, "E01A"),
        // otro cliente ubicado + uno SIN ubicación
        ped("98680", "1587", "Otro Cliente SRL", "Brasil 1200", "Constitución", 0.50, "E01B"),
        ped("98681", "9999", "Sin Ubicar SA", "Calle Inventada 1", "Barrio Raro", 0.10, "E01B")
      ]
    };
    cam.m3 = cam.ped.reduce((a, x) => a + x.m3, 0);

    const oc = _pppOrdenCarga(cam);
    const paradas = _pppHojaParadas(oc.paradas);
    out.nParadas = paradas.length;
    out.nps = paradas.map((s) => s.nps.length);
    const almagro = paradas.find((s) => s.loc === "Almagro") || {};
    out.almagro = { nps: (almagro.nps || []).length, m3: Math.round((almagro.m3 || 0) * 1000) / 1000, lista: (almagro.nps || []).join(",") };
    out.barriosDapelo = paradas.filter((s) => s.cod === "1792").map((s) => s.loc).sort();
    out.sinUbic = paradas.filter((s) => !Number.isFinite(s.lat)).map((s) => s.cod);

    const H = { nombre: "Camión 1 · Zona 2 - CABA Centro", fecha: "11/09/2026", paradas: paradas, nps: cam.ped.length, m3: cam.m3 };
    const html = pppHojaHtml(H);
    out.html = html;
    out.dice4NP = /<b>4 NP<\/b>: 98676 · 98677 · 98678 · 98679/.test(html);
    out.maps = (html.match(/https:\/\/www\.google\.com\/maps\/dir\/[^"]+/g) || []);
    out.imprimir = /onclick="pppHojaImprimir\(\)"/.test(html);
    out.avisaSinUbic = /1 parada\(s\) sin ubicación/.test(html);
    out.totalNP = /<b>8<\/b> NP/.test(html);

    // el overlay abre con el nombre del camión
    _pppHoja["20260911|n01"] = H;
    pppHojaAbrir("20260911|n01");
    const o = document.getElementById("pppHrOverlay");
    out.abre = !!(o && o.classList.contains("show"));
    out.titulo = (document.getElementById("pppHrTitle") || {}).textContent || "";
    out.hayCssPrint = /@media print/.test(((document.getElementById("pppHrCss") || {}).textContent) || "");
    pppHojaCerrar();
    out.cierra = !o.classList.contains("show");
    out.crudo = /undefined|NaN/.test(html);

    // (e) el botón está de verdad en la pantalla del día, y NO en Retira
    const J = (data) => { const n = Array.isArray(data) ? data.length : 0; return Promise.resolve({ ok: true, status: 200,
      headers: { get: (h) => String(h).toLowerCase() === "content-range" ? ("0-" + Math.max(0, n - 1) + "/" + n) : null },
      json: () => Promise.resolve(data), text: () => Promise.resolve(JSON.stringify(data)) }); };
    const hab = _pppDiasHabiles(6).map((d) => d.date);
    const iso = (dt) => dt.getFullYear() + "-" + String(dt.getMonth() + 1).padStart(2, "0") + "-" + String(dt.getDate()).padStart(2, "0");
    const mk = (np, tanda, cod, rs, m3, barrio, dir, zona) => ({ np: np, tanda: tanda, tipo: "", fecha_recep: "2026-09-01", cod: cod, razon_social: rs, m3: m3, direccion: dir, barrio: barrio, fecha_entrega: iso(hab[0]), zona: zona });
    const filas = cam.ped.map((x) => mk(x.np, x.tanda, x.cod, x.razon_social, x.m3, x.localidad, x.direccion, "Zona 2 - CABA Centro"))
      .concat([mk("98690", "E02A", "1500", "Retira Uno", 0.7, "Retira", "", "Retira")]);
    window.fetch = (url) => {
      const u = String(url);
      if (u.indexOf("gv_ppp_programacion_diaria") >= 0) return J(filas);
      if (u.indexOf("PPP_Geo") >= 0) return J(Object.keys(G).map((k) => ({ dir_key: k, lat: G[k].lat, lng: G[k].lng })));
      return J([]);
    };
    window._pppEmitError = function () {};
    window.getActivityStatus = async () => ({ pickingStarted: new Set(), pickingDone: new Set(), armadoStarted: new Set(), armadoDone: new Set(), pickingEnCursoBy: new Map(), armadoEnCursoBy: new Map() });
    _pppGeo = null; _pppGeoCod = null;
    await pppLoadProgFromSupabase();
    await pppRefreshValor(); await pppRefreshGeo();
    _pppTab = "plan"; _pppPlanClasica = false;
    pppPlanAbrir(_pppDateKey(hab[0]));
    const pant = document.getElementById("pppPreview").innerHTML;
    out.botones = (pant.match(/pppHojaAbrir\(/g) || []).length;   // 1 (el camión) — Retira no lleva
    out.botonDice = /🗺️ Hoja de ruta<\/button><span class="pn-hr-t">5 paradas · 8 NP/.test(pant);
    out.tablaSigueXNp = (pant.match(/class="pn-ped/g) || []).length;   // una fila por NP, como antes
    return out;
  });
  await b.close();

  const fails = [];
  const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fails.push(m); };
  chk(r.nParadas === 5, "8 NP → 5 paradas (4 de Dapelo Almagro se unifican): " + r.nParadas);
  chk(r.almagro.nps === 4 && r.almagro.lista === "98676,98677,98678,98679", "la parada de Almagro junta las 4 NP (" + r.almagro.lista + ")");
  chk(Math.abs(r.almagro.m3 - 1.0) < 1e-6, "y suma los m³ de las 4 (" + r.almagro.m3 + ")");
  chk(JSON.stringify(r.barriosDapelo) === '["Almagro","Colegiales","Villa Crespo"]', "el mismo cód en otros barrios sigue siendo otra parada (" + r.barriosDapelo.join("/") + ")");
  chk(r.dice4NP, 'la hoja dice "4 NP" con la lista de las notas de pedido');
  chk(r.totalNP, "el encabezado dice las 8 NP del camión");
  chk(JSON.stringify(r.sinUbic) === '["9999"]', "la parada sin ubicación queda marcada, no se pierde");
  chk(r.avisaSinUbic, "y se avisa que no entra al link de Maps");
  chk(r.maps.length === 1, "un solo link de Maps para 4 paradas ubicadas: " + r.maps.length);
  chk(/origin=-34\.628000,-58\.411000/.test(r.maps[0] || ""), "el link arranca en el depósito");
  chk(/destination=-34\.628000,-58\.411000/.test(r.maps[0] || ""), "y vuelve al depósito");
  chk(((r.maps[0] || "").match(/%7C/g) || []).length === 3, "lleva las 4 paradas ubicadas como waypoints (3 separadores)");
  chk(r.imprimir, "tiene botón de imprimir");
  chk(r.hayCssPrint, "y una hoja de impresión (@media print)");
  chk(r.abre && /Camión 1/.test(r.titulo), "el overlay abre con el nombre del camión (" + r.titulo + ")");
  chk(r.cierra, "y cierra");
  chk(!r.crudo, "sin undefined/NaN en la hoja");
  chk(r.botones === 1, "el botón está en el camión de la pantalla del día, y NO en Retira: " + r.botones);
  chk(r.botonDice, "y dice cuántas paradas y cuántas NP (5 paradas · 8 NP)");
  chk(r.tablaSigueXNp === 9, "la tabla del camión sigue con UNA FILA POR NP (8 + 1 retira): " + r.tablaSigueXNp);
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));
  if (fails.length) { console.error("\nFALLARON " + fails.length + ":\n· " + fails.join("\n· ")); process.exit(1); }
  console.log("\nppp-hoja-ruta OK");
})();

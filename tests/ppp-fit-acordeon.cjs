/* v13.95 — Con un acordeón abierto, la PPP scrollea en vez de achicarse.
   Dueño 07/09, con captura del día 9 desplegado: "sólo para cuando hay algo tipo acordeón, ahí sí
   dejame el scroll, porque si no no puedo ver estas cosas". El zoom de `pppFitPantalla` (v13.69,
   "que entre entera en una pantalla") achicaba todo Y encima cortaba abajo justo la tabla recién
   abierta.
   (a) sin nada abierto sigue como siempre: achica para que entre y NO scrollea;
   (b) con un bloque abierto (_pppOpen): tamaño normal (zoom 1) y scroll;
   (c) lo mismo si hay una búsqueda, que abre sola las tandas que coinciden;
   (d) al cerrar el acordeón vuelve a entrar entera, sin scroll;
   (e) abrir/cerrar un bloque re-dispara el ajuste (pppToggleBlock llama a pppFitProgramar);
   (f) no cambia lo de antes: celular y A Programar siguen a tamaño normal con scroll.
   Sin red. Sale 1 si falla. */
const path = require("path");
const { chromium } = require("/opt/node22/lib/node_modules/playwright");
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    const out = {};
    // overlay de la PPP con un cuerpo MÁS ALTO de lo que entra → sin acordeón tiene que achicar
    let ov = document.getElementById("pppOverlay");
    if (!ov) { ov = document.createElement("div"); ov.id = "pppOverlay"; document.body.appendChild(ov); }
    ov.classList.add("show");
    ov.innerHTML = '<div class="planim-body"><div style="min-height:1150px;flex:0 0 auto"></div></div>';
    const body = ov.querySelector(".planim-body");
    const leer = () => ({ zoom: body.style.zoom, scroll: body.style.overflowY });

    _pppTab = "plan"; _pppSearch = ""; _pppOpen = new Set();
    pppFitPantalla();
    out.cerrado = leer();

    _pppOpen.add("pppb_D62A");
    pppFitPantalla();
    out.abierto = leer();

    _pppOpen = new Set(); _pppSearch = "chemelo";
    pppFitPantalla();
    out.buscando = leer();

    _pppSearch = "";
    pppFitPantalla();
    out.vuelve = leer();

    // (e) el toggle re-dispara el ajuste
    const d = document.createElement("div"); d.id = "pppb_TEST"; ov.querySelector(".planim-body").appendChild(d);
    let fits = 0; const _f = window.pppFitProgramar;
    window.pppFitProgramar = function () { fits++; return _f.apply(this, arguments); };
    pppToggleBlock("pppb_TEST");
    out.abrioYAjusto = { fits: fits, enSet: _pppOpen.has("pppb_TEST") };
    pppToggleBlock("pppb_TEST");
    out.cerroYAjusto = { fits: fits, enSet: _pppOpen.has("pppb_TEST") };
    window.pppFitProgramar = _f;

    // (f) A Programar sigue a tamaño normal con scroll, con acordeón o sin él
    _pppTab = "prog"; _pppOpen = new Set();
    pppFitPantalla();
    out.aProgramar = leer();
    _pppTab = "plan"; _pppOpen = new Set();
    return out;
  });

  // (f) celular
  await p.setViewportSize({ width: 400, height: 800 });
  const cel = await p.evaluate(() => {
    _pppTab = "plan"; _pppOpen = new Set(); pppFitPantalla();
    const body = document.querySelector("#pppOverlay .planim-body");
    return { zoom: body.style.zoom, scroll: body.style.overflowY };
  });
  await b.close();

  const fails = [];
  const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fails.push(m); };
  chk(Number(r.cerrado.zoom) < 1 && r.cerrado.scroll === "hidden", "sin acordeón: achica para que entre y no scrollea (zoom " + r.cerrado.zoom + ")");
  chk(r.abierto.zoom === "1" && r.abierto.scroll === "auto", "con un bloque abierto: tamaño normal y scroll (zoom " + r.abierto.zoom + ", " + r.abierto.scroll + ")");
  chk(r.buscando.zoom === "1" && r.buscando.scroll === "auto", "buscando (abre las tandas que coinciden): también scrollea");
  chk(Number(r.vuelve.zoom) < 1 && r.vuelve.scroll === "hidden", "al cerrar todo vuelve a entrar entera, sin scroll");
  chk(r.abrioYAjusto.fits === 1 && r.abrioYAjusto.enSet, "abrir un bloque re-dispara el ajuste");
  chk(r.cerroYAjusto.fits === 2 && !r.cerroYAjusto.enSet, "y cerrarlo también");
  chk(r.aProgramar.zoom === "1" && r.aProgramar.scroll === "auto", "A Programar sigue a tamaño normal con scroll (v13.83)");
  chk(cel.zoom === "1" && cel.scroll === "auto", "el celular sigue a tamaño normal con scroll (v13.81)");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));
  if (fails.length) { console.error("\nFALLARON " + fails.length + ":\n· " + fails.join("\n· ")); process.exit(1); }
  console.log("\nppp-fit-acordeon OK");
})();

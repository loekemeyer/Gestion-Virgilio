/* v18.12 (Luis, 2026-09-15) — PPP: la solapa "Modificar Pedidos", vacía.

   Pedido: *"vamos a crear una pestaña nueva en la PPP que se llame «Modificar Pedidos»"* y, al
   rato, *"creá la pestaña y módulo vacío, después te digo bien qué le ponemos"*.

   O sea que lo que hay que fijar es EL MARCO, no una funcionalidad:
     · la solapa existe, se llama así y está después de Programación;
     · tocarla cambia `_pppTab` y dibuja su pantalla, sin romper las otras;
     · NO pide datos a la red — el módulo está vacío, no tiene qué traer;
     · no toca `_pgaRows` ni ningún estado de las otras solapas;
     · queda exenta del zoom automático de `pppFitPantalla`, como Config. Cuarentena;
     · se puede volver a Programación y sigue andando.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    window.getTodayKey = () => "2026-09-15";
    _pppParsed = { prog: [{ np: "98630", tanda: "D72B", fecha_entrega: "2026-09-15", m3: 1.8,
                            cod: "1000", razon_social: "Jumbo", zona: "Zona 2", programmed: true }] };
    window._pppPlanAgrupar = function () { return { venc: [], byDay: new Map() }; };
    _pgaRows = []; _pgaTs = Date.now(); window.pgaNeed = function () {};
    document.getElementById("pppOverlay").classList.add("show");

    // ── (1) la solapa está, con ese nombre y en ese lugar ──────────────────
    pppPaintTabs();
    const tabs = [...document.querySelectorAll("#pppTabsBar .ppp-tab")].map((e) => e.textContent.trim());
    out.tabs = tabs;
    out.existe = tabs.some((t) => /Modificar Pedidos/.test(t));
    out.despuesDeProgramacion = tabs.findIndex((t) => /Modificar Pedidos/.test(t)) ===
                                tabs.findIndex((t) => /Programación/.test(t)) + 1;

    // ── (2) tocarla abre su pantalla ───────────────────────────────────────
    const antesRows = _pgaRows;
    /* El módulo está vacío DE VERDAD: dibujarlo no dispara ni un fetch. Se envuelve `fetch` justo
       alrededor del render — contar las llamadas de toda la página no sirve, porque la carga
       inicial y los refrescos de fondo siguen su curso y tapan lo que se quiere medir. */
    const _f = window.fetch; let nFetch = 0;
    window.fetch = function () { nFetch++; return _f.apply(this, arguments); };
    pppTab("modif");
    await new Promise((res) => setTimeout(res, 120));
    window.fetch = _f;
    out.fetchDelModulo = nFetch;
    out.tabActiva = _pppTab === "modif";
    const box = document.getElementById("pppPreview");
    out.html = box.innerHTML.slice(0, 200);
    out.dibuja = !!box.querySelector(".pmod-vacio");
    out.diceElNombre = /Modificar Pedidos/.test(box.textContent);
    out.diceQueEstaVacio = /M[óo]dulo vac[íi]o/i.test(box.textContent);
    // el botón de la solapa queda marcado como activo
    out.marcada = [...document.querySelectorAll("#pppTabsBar .ppp-tab")]
      .some((e) => /Modificar Pedidos/.test(e.textContent) && e.classList.contains("on"));
    // no toca el estado de las otras solapas
    out.noTocaRows = _pgaRows === antesRows;

    // ── (3) exenta del zoom automático ─────────────────────────────────────
    /* ⚠ el nodo tiene que ser el MISMO que mira `pppFitPantalla`: el suyo es
       `#pppOverlay .planim-body`, y en la página hay más de un `.planim-body`. Con el primero del
       documento se seteaba el zoom en uno y se leía el otro, y el chequeo daba rojo de mentira. */
    const body = document.querySelector("#pppOverlay .planim-body");
    out.hayBody = !!body;
    if (body) { body.style.zoom = "0.70"; pppFitPantalla(); out.zoom = body.style.zoom; }

    // ── (4) se vuelve a Programación y sigue andando ───────────────────────
    _pppPlanTabla = true; _pppPlanClasica = false;
    pppTab("plan");
    await new Promise((res) => setTimeout(res, 150));
    out.vuelve = _pppTab === "plan" && !document.getElementById("pppPreview").querySelector(".pmod-vacio");
    return out;
  });

  await b.close();

  const ok = [];
  const chk = (c, d) => ok.push([!!c, d]);
  chk(r.existe, "la solapa «✏️ Modificar Pedidos» está en la barra: " + JSON.stringify(r.tabs));
  chk(r.despuesDeProgramacion, "y va después de Programación, que es lo que se va a modificar");
  chk(r.tabActiva, "tocarla deja _pppTab en 'modif'");
  chk(r.marcada, "y el botón queda marcado como activo");
  chk(r.dibuja, "dibuja su propia pantalla (.pmod-vacio): " + JSON.stringify(r.html.slice(0, 90)));
  chk(r.diceElNombre && r.diceQueEstaVacio,
      "que dice el nombre y que está vacío — para que nadie la crea rota");
  chk(r.noTocaRows, "no pisa el estado de las otras solapas (_pgaRows intacto)");
  chk(r.zoom === "1", "queda exenta del zoom automático, como Config. Cuarentena: zoom=" + r.zoom);
  chk(r.vuelve, "se vuelve a Programación y sigue andando");
  chk(r.hayBody, "el cuerpo de la PPP existe — si no, el chequeo del zoom no mediría nada");
  chk(errs.length === 0, "sin errores de JS: " + JSON.stringify(errs));
  // el módulo está vacío DE VERDAD: desde que se entra a la solapa no sale ni una llamada. Si
  // algún día pide datos este chequeo avisa, y ahí se decide a conciencia si corresponde.
  chk(r.fetchDelModulo === 0,
      "dibujar el módulo no dispara ni un fetch: " + r.fetchDelModulo);

  let malas = 0;
  for (const [bien, d] of ok) { console.log((bien ? "  ok   " : "  FALLA") + " " + d); if (!bien) malas++; }
  console.log(malas ? "\n✗ " + malas + " de " + ok.length + " fallaron" : "\n✓ " + ok.length + " chequeos ok");
  process.exit(malas ? 1 : 0);
})();

/* v20.01 (Thomas, 2026-09-18) — LA TABLA DE PROGRAMACIÓN EN EL CELULAR.
   Pedido: *"la visual del cel se ve mal. Que desde el cel sólo diga 18/9 y después figure lo que
   está a la derecha tapado"*. La columna del día es la 1ª, es `sticky` y pedía `width:100%`, así
   que en un teléfono "Viernes 18/09" se llevaba todo el ancho y las otras siete columnas quedaban
   atrás de ella — y scrollear no servía, porque la columna pegada a la izquierda las tapaba igual.
   Lo que prueba este test:
     (1) a 390 px la fila del día dice SÓLO la fecha, "18/9" (sin el nombre del día ni el cero del mes);
     (2) el texto completo sigue en el HTML (`textContent` = "Viernes 18/09"): se esconde, no se recorta;
     (3) las 8 columnas entran en el ancho visible — la última termina dentro del contenedor;
     (4) en el escritorio no cambia nada: el día se sigue leyendo entero.
   Estado inyectado; no pega contra la red. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
const pintar = async (p) => p.evaluate(async () => {
  window.getTodayKey = () => "2026-09-18";
  _pppParsed = { prog: [{ np: "98630", tanda: "E39A", fecha_entrega: "2026-09-18", m3: 1.8,
                          cod: "1000", razon_social: "Jumbo", zona: "Zona 2", programmed: true }] };
  window._pppPlanAgrupar = function () { return { venc: [], byDay: new Map() }; };
  window.pppPaintTabs = function () {};
  window.pgaNeed = function () {};
  const mk = (f, t, np, rs, m3, est) => ({ fecha: f, tanda: t, np: np, np_num: 0, cod: "1000",
    razon_social: rs, localidad: "Barracas", zona: "Zona 2", zona_corta: "Zona 2", empresa: "LK",
    origen: "isis", m3: m3, estado: est, estado_orden: 1, barrio: "Flores", fecha_pedido: "2026-09-11" });
  // m³ grandes a propósito (uno de tres dígitos y un total de cuatro): son los que hacen
  // ancha la columna de los m³, que es la que después empuja a las demás fuera de la pantalla
  _pgaRows = [
    mk("2026-09-18", "E39A", "98630", "Jumbo", 112.34, "facturado"),
    mk("2026-09-22", "E41A", "98640", "Perez", 22.55, "pendiente"),
    mk("2026-09-23", "E42A", "98641", "Ricci", 11.25, "armado"),
    mk("2026-09-23", "E42B", "98642", "Osa", 13.75, "pendiente"),
    mk("2026-10-28", "E50A", "98660", "Andser", 19.95, "pendiente")
  ];
  _pgaTs = Date.now();
  // v20.10: con la columna SALIÓ llena («100 %»), que es el caso ancho — con el «—» de cuando
  // todavía no llegó En Salida la medición del ancho sería más chica de lo real.
  // (se usa `_pppLoadMs` —los CCN— y no `_pppEnSalida`, porque esa otra lista además ESCONDE de
  //  Programación lo que está en salida y acá lo que se mide es el ancho de la tabla llena)
  _pppLoadMs = new Map(_pgaRows.map((r) => [r.np, Date.now()]));
  _pppTab = "plan"; _pppPlanTabla = true; _pppPlanClasica = false; _pppPlanDay = null;
  document.getElementById("pppOverlay").classList.add("show");
  pppRenderProg(); await new Promise((s) => setTimeout(s, 250));
  const prev = document.getElementById("pppPreview");
  // ⚠ cada render REEMPLAZA el HTML: los nodos hay que volver a buscarlos después de abrir un día,
  //   si no se mide un nodo desconectado y todos los anchos dan 0.
  const medir = () => {
    const wrap = prev.querySelector(".pga-wrap"), tabla = prev.querySelector("table.pga");
    const ult = prev.querySelector("table.pga thead th:last-child");
    return {
      tabla: Math.round(tabla.getBoundingClientRect().width),
      wrap: Math.round(wrap.clientWidth),
      sobra: Math.round(wrap.getBoundingClientRect().right - ult.getBoundingClientRect().right),
      cols: prev.querySelectorAll("table.pga thead th").length
    };
  };
  const cerrado = medir();
  const fila = [...prev.querySelectorAll("tr.pga-d")][0];
  const visible = fila.children[0].innerText.replace(/\s+/g, " ").trim();
  const texto = fila.children[0].textContent.replace(/\s+/g, " ").trim();
  // v20.10 (Thomas: *"el desglose … tiene que figurar por tanda también"*) — con el DÍA abierto,
  // que es cuando se miran las tandas, las 9 columnas tienen que seguir entrando.
  pgaAbrirDia("20260923"); await new Promise((s) => setTimeout(s, 150));
  const tandaTr = prev.querySelector("tr.pga-t");
  const abierto = Object.assign(medir(), {
    pcts: tandaTr ? [...tandaTr.querySelectorAll(".pga-pct")].length : 0
  });
  pgaAbrirDia("20260923"); await new Promise((s) => setTimeout(s, 100));
  return {
    abierto: abierto, visible: visible, texto: texto,
    tabla: cerrado.tabla, wrap: cerrado.wrap, sobra: cerrado.sobra, cols: cerrado.cols
  };
});
(async () => {
  const b = await chromium.launch();
  const errs = [];
  const cel = await (async () => {
    const p = await b.newPage({ viewport: { width: 390, height: 820 } });
    p.on("pageerror", (e) => errs.push(e.message));
    await p.route("**/rest/v1/**", (r) => r.abort());
    await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
    const r = await pintar(p); await p.close(); return r;
  })();
  const esc = await (async () => {
    const p = await b.newPage({ viewport: { width: 1400, height: 900 } });
    p.on("pageerror", (e) => errs.push(e.message));
    await p.route("**/rest/v1/**", (r) => r.abort());
    await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
    const r = await pintar(p); await p.close(); return r;
  })();
  await b.close();

  let ok = true;
  const t = (c, m) => { console.log((c ? "  ✅ " : "  ❌ ") + m); if (!c) ok = false; };
  t(/(^|\s)18\/9(\s|$)/.test(cel.visible.replace("▸", "")),
    "(1) en el celular el día dice sólo la fecha «18/9» — «" + cel.visible + "»");
  t(!/Viernes/.test(cel.visible), "(1) sin el nombre del día");
  t(!/18\/09/.test(cel.visible), "(1) y sin el cero del mes");
  t(/Viernes 18\/09/.test(cel.texto), "(2) el texto completo sigue en el HTML (se esconde, no se recorta)");
  t(cel.cols === 9, "(3) las 9 columnas siguen estando (Salió incluida, v20.10) — " + cel.cols);
  t(cel.sobra >= 0, "(3) y entran en el ancho visible: la última termina dentro del marco (sobran " +
    cel.sobra + " px; tabla " + cel.tabla + " de " + cel.wrap + ")");
  t(cel.abierto.pcts === 5, "(5) con el día abierto, la fila de la tanda trae los 5 porcentajes — " + cel.abierto.pcts);
  t(cel.abierto.sobra >= 0, "(5) y las 9 columnas siguen entrando (sobran " + cel.abierto.sobra +
    " px; tabla " + cel.abierto.tabla + ")");
  t(/Viernes 18\/09/.test(esc.visible), "(6) en el escritorio el día se lee entero — «" + esc.visible + "»");
  t(errs.length === 0, "sin errores de JS" + (errs.length ? ": " + errs[0] : ""));
  console.log(ok ? "\nOK ppp-tabla-cel" : "\nFALLÓ ppp-tabla-cel");
  process.exit(ok ? 0 : 1);
})();

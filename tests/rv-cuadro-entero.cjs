/* v21.28 — Reporte diario Virgilio: el CUADRO tiene que entrar ENTERO, arrancar en HOY y
   dejar medir un LAPSO de horas.
   Luis, 22/09, con la captura del modal cortado: "tiene que mostrar todo el cuadro sinoptico
   y como se pide en el cuadro sinoptico" · "que siempre muestre el dia de hoy 1ro" ·
   "añadi para medir lapsos de horas por ejemplo desde la 1pm a 4:30 pm".
   (a) la tarjeta es la ANCHA (con la de 760 las 16 columnas quedaban cortadas);
   (b) el cuadro NO se corta: scrollWidth <= clientWidth, medido sobre el render real;
   (c) estan las 16 columnas y ninguna se perdio al compactar;
   (d) el selector de dia arranca en HOY;
   (e) hay Desde/Hasta y VIAJAN en el body del pedido;
   (f) el lapso que la edge aplico se muestra en el estado.
   Se mide RENDERIZANDO: un candado de texto no ve si la tabla entra. Sin red. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
const COLS = ["Operario","Prom. Picking M3 x Hs","Prom. Picking M3 x Día","Prom. Arm M3 x Hs",
  "Prom. Arm M3 x Día","Total Hs Día","Hs Prod","Picking","Armado","Carga de Camión",
  "Hs No Productivas","Recp de Merc","Guardado de Merc","Limpieza","Baño","Hs S/Reg"];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1500, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = { pedidos: [] };
    const fila = (n) => ({ nombre: n, pkH: "1,58", pkD: "3,18", arH: "0,36", arD: "0,31",
      totDia: "8:02", hsProd: "2:52", pick: "2:01", arm: "0:51", cc: "-", noProd: "5:10",
      rt: "0:12", mg: "0:20", limp: "-", pb: "0:08", sinReg: "0:58" });

    window.fetch = async (url, opt) => {
      out.pedidos.push({ url: String(url), body: JSON.parse((opt && opt.body) || "{}") });
      return { ok: true, status: 200, json: async () => ({
        solo_pdf: true, operarios: 3, titulo: "Logistica Virgilio - 22/09/2026 (13:00 a 16:30)",
        ventana: "13:00 a 16:30", pdfUrl: "", pendientes: null,
        bloques: [{ subtitulo: "(unico)", filas: [
          fila("Farias Juan Hilario"), fila("Juan Segundo Landaberry (entrevista)"),
          fila("Jhonny Moncayo") ] }] }) };
    };

    openReporteVirgilio();
    const card = document.querySelector(".stkpop-card");
    out.wide = !!(card && card.classList.contains("wide"));

    const iso = (d) => d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    out.hoyEsperado = iso(new Date());
    out.fechaDefault = (document.getElementById("rvFecha") || {}).value;
    out.hayDesde = !!document.getElementById("rvDesde");
    out.hayHasta = !!document.getElementById("rvHasta");

    // si los campos no existen todavia, el test tiene que REPORTAR la falta, no explotar:
    // un crash en CI no dice cual es el chequeo que se rompio.
    if (out.hayDesde) document.getElementById("rvDesde").value = "13:00";
    if (out.hayHasta) document.getElementById("rvHasta").value = "16:30";
    await rvGenerar();

    const wrap = document.querySelector("#rvVisor div[style*='overflow-x']");
    const tabla = wrap && wrap.querySelector("table");
    out.hayTabla = !!tabla;
    if (wrap) {
      out.scrollW = wrap.scrollWidth; out.clientW = wrap.clientWidth;
      out.entra = wrap.scrollWidth <= wrap.clientWidth + 1;
    }
    out.ths = [...(tabla ? tabla.querySelectorAll("thead th") : [])]
      .map((t) => t.textContent.replace(/\s+/g, " ").trim());
    out.estado = (document.getElementById("rvEstado") || {}).textContent || "";
    return out;
  });

  const fails = [];
  const ok = (c, m, d) => { console.log((c ? "  ok    · " : "  FALLA · ") + m + (d ? "  → " + d : "")); if (!c) fails.push(m); };

  console.log("== rv-cuadro-entero (v21.28: el cuadro entra entero, arranca en hoy, mide lapsos) ==");
  ok(r.wide, "(a) la tarjeta del pop-up es la ANCHA");
  ok(r.hayTabla, "(b) el cuadro se dibujo");
  ok(r.entra === true, "(b) el cuadro entra entero, sin corte horizontal",
     "scrollWidth=" + r.scrollW + " clientWidth=" + r.clientW);
  ok(r.ths.length === 16, "(c) estan las 16 columnas", "son " + r.ths.length);
  // el <br> del encabezado no aporta espacio al textContent ("Prom.PickingM3 x Hs"),
  // asi que se compara sin espacios: lo que importa es que la columna este, no como parte.
  const pelar = (t) => t.replace(/\s+/g, "");
  const faltan = COLS.filter((c) => !r.ths.some((t) => pelar(t) === pelar(c)));
  ok(faltan.length === 0, "(c) no se perdio ninguna columna al compactar", faltan.join(" | "));
  ok(r.fechaDefault === r.hoyEsperado, "(d) el selector arranca en HOY",
     r.fechaDefault + " vs " + r.hoyEsperado);
  ok(r.hayDesde && r.hayHasta, "(e) estan los campos Desde y Hasta");
  const b0 = (r.pedidos[0] || {}).body || {};
  ok(b0.desde_hora === "13:00" && b0.hasta_hora === "16:30",
     "(e) el lapso VIAJA en el pedido", JSON.stringify({ d: b0.desde_hora, h: b0.hasta_hora }));
  ok(/13:00 a 16:30/.test(r.estado), "(f) el estado dice el lapso aplicado", r.estado);
  ok(errs.length === 0, "sin errores de pagina", errs.join(" | "));

  await b.close();
  if (fails.length) { console.error("rv-cuadro-entero: FALLA (" + fails.length + ")"); process.exit(1); }
  console.log("rv-cuadro-entero: OK (10 chequeos)");
})();

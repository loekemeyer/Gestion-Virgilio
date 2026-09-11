/* Regresión v15.57 — la alerta "Tandas inconsistentes" del Resumen de la PPP tiene que decir
   QUÉ DÍA está programada la tanda y QUÉ ESTÁ MEZCLADO CON QUÉ. Dueño (11/09/2026), sobre
   "D68G (rutas mezcladas)": *"acá ese dato no me sirve, necesito más datos para que me sea
   útil: qué día se programó, qué está mezclado con qué"*.

   Caso real: D68G del 15/09 = 98694 Veronesi (La Boca, ruta Sur) + LK 0018 Bazar Mónica
   (Padua) y LK 0028 Laza (Ituzaingó), ruta Norte. Ciudadela (LK 0032) no cuenta como ruta
   aparte (regla del dueño) y no tiene que aparecer.

   Chequea:
   1) _pppComputeErrors deja en tandasMal quién cae en cada ruta (porRuta) y fecha (porFecha),
   2) el HTML trae la tanda, el día dd/mm, y cada ruta con sus NP · cliente · [barrio],
   3) con varias fechas, lista quién va en cada una.
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
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    const out = {};
    // zonas por barrio, sin depender del mapa cargado de Supabase
    window.pppZonaDeBarrio = function (b) {
      b = String(b || "").toLowerCase();
      if (b.indexOf("boca") >= 0) return "Zona 1 - CABA Sur";
      if (b.indexOf("padua") >= 0 || b.indexOf("ituzaing") >= 0 || b.indexOf("ciudadela") >= 0) return "Zona 5 - GBA Oeste";
      return "";
    };
    const mk = function (np, rs, loc, fe) { return { np: np, razon_social: rs, localidad: loc, zona: "", tanda: "D68G", fecha_entrega: fe, programmed: true, m3: 0.1, _err: [] }; };
    const peds = [
      mk("98694",   "Veronesi Alcira Elena",      "La Boca",              "15/09/2026"),
      mk("LK 0018", "Bazar Monica S. CAP I SECC", "San Antonio de Padua", "15/09/2026"),
      mk("LK 0028", "Laza Ariel Horacio",         "Ituzaingo",            "15/09/2026"),
      mk("LK 0032", "Gonzalez Pellegrini Dario",  "Ciudadela",            "15/09/2026")
    ];
    const e = _pppComputeErrors(peds);
    const t = (e.tandasMal || [])[0] || {};
    out.unaTanda = (e.tandasMal || []).length === 1 && t.tanda === "D68G";
    out.rutas = t.rutas; out.fechas = t.fechas;
    out.porRutaSo = !!(t.porRuta && t.porRuta.so) && t.porRuta.so.map(function (x) { return x.np; }).join(",");
    out.porRutaN  = !!(t.porRuta && t.porRuta.n)  && t.porRuta.n.map(function (x) { return x.np; }).join(",");
    const html = pppErroresHtml(e);
    out.html = html;
    out.tieneDia = html.indexOf("D68G") >= 0 && html.indexOf(" · 15/09") >= 0 && html.indexOf("15/09/2026") < 0;
    out.rutaSur = /Sur\/Centro\/Oeste<\/u>: .*98694.*Veronesi.*\[La Boca\]/.test(html);
    out.rutaNorte = /Norte<\/u>: .*LK 0018.*Bazar Monica.*\[San Antonio de Padua\].*LK 0028.*Laza.*\[Ituzaing/.test(html);
    out.sinCiudadela = html.indexOf("LK 0032") < 0;
    // varias fechas
    const peds2 = [
      mk("98700", "Cliente A", "La Boca", "15/09/2026"),
      mk("98701", "Cliente B", "La Boca", "16/09/2026")
    ];
    const html2 = pppErroresHtml(_pppComputeErrors(peds2));
    out.variasFechas = /varias fechas → <u>15\/09<\/u>: .*98700.*Cliente A.*<u>16\/09<\/u>: .*98701.*Cliente B/.test(html2);
    return out;
  });

  const pass = r.unaTanda && r.rutas === 2 && r.fechas === 1 &&
    r.porRutaSo === "98694" && r.porRutaN === "LK 0018,LK 0028" &&
    r.tieneDia && r.rutaSur && r.rutaNorte && r.sinCiudadela && r.variasFechas &&
    errs.length === 0;
  const { html, ...vis } = r;
  console.log("ppp-errores-detalle:", JSON.stringify(vis), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  if (!pass) console.log("HTML:", html);
  await b.close();
  process.exit(pass ? 0 : 1);
})();

/* Regresión v15.86 — LÍMITE DE JORNADA DEL CAMIÓN en la PPP.

   Thomas (11/09/2026): *"también hay que considerar que al tiempo de viaje entre paradas (máx 8 hs
   en un día) hay que considerar que hay tiempo parado para descargar cada pedido. Considerá por
   ahora sólo 15' por parada x cliente. Más que 8 hs por día no se puede programar"*. Y sobre los
   parámetros: *"lo lógico para un camión, definí vos"* → 28 km/h de marcha y recorrido = 1,35× la
   línea recta, los dos en `PPP_Web_Config` para recalibrarlos con las horas reales de la hoja de
   ruta sin tocar código.

   Caso real que lo disparó: el camión Norte del 16/09 con Luján adentro. Con estos parámetros da
   13 paradas / 207 km / 10,6 h; sacando Luján (que salió en kangoo aparte) baja a 8,5 h — o sea
   que sigue por encima del tope, y eso es justamente lo que el aviso tiene que mostrar.

   Chequea, sin red (con los defaults de `_pppJorCfg`):
   1) las horas = viaje (km óptimo × factor ÷ velocidad) + 15' por PARADA,
   2) una parada = una DIRECCIÓN: 3 NP del mismo cliente en el mismo lugar son UNA sola,
   3) un camión que se pasa entra en `_pppComputeErrors().jornada` y sale en el panel con el día,
      las horas, de qué se componen y qué parada lo estira,
   4) un camión corto no avisa,
   5) Retira nunca cuenta (no viaja).
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
    const DEP = { lat: -34.6158, lng: -58.5253 };          // Virgilio 2788
    // ubicaciones reales del camión Norte del 16/09
    const P = {
      "4024": { lat: -34.6397682, lng: -58.53103   },       // Ciudadela
      "2328": { lat: -34.649138,  lng: -58.6130446 },       // Morón
      "4045": { lat: -34.6690006, lng: -58.7010513 },       // San Antonio de Padua
      "4221": { lat: -34.6159374, lng: -58.7154287 },       // Ituzaingó
      "4114": { lat: -34.5635,    lng: -59.13658   },       // Luján (el que estira)
      "2543": { lat: -34.5788009, lng: -58.6380102 },       // Hurlingham
      "3927": { lat: -34.5397783, lng: -58.566037  },       // Villa Ballester
      "3861": { lat: -34.5814187, lng: -58.712349  },       // Bella Vista
      "4188": { lat: -34.5004611, lng: -58.5331229 },       // Martínez
      "2715": { lat: -34.5180976, lng: -58.4907891 },       // San Martín
      "4189": { lat: -34.588412,  lng: -58.537311  },       // Villa Lynch
      "4281": { lat: -34.4293467, lng: -58.8340505 },       // Pilar (Villa Rosa)
      "4198": { lat: -34.449868,  lng: -58.916581  }        // Pilar (Panamericana)
    };
    _pppGeo = { "__deposito_virgilio_2788__": DEP };
    _pppGeoCod = {}; Object.keys(P).forEach(function (c) { _pppGeoCod[c] = P[c]; });
    window.pppZonaDeBarrio = function (bo) { return /lugano|boca/i.test(String(bo)) ? "Zona 1 - CABA Sur" : "Zona 5 - GBA Oeste"; };

    const mk = function (np, cod, rs, loc, tanda, fe) {
      return { np: np, cod: cod, razon_social: rs, localidad: loc, direccion: "Calle " + cod, barrio: loc,
               zona: "", tanda: tanda, fecha_entrega: fe, programmed: true, m3: 0.2, _err: [] };
    };

    // --- (1) y (2): un camión con Luján + 3 NP del mismo cliente en el mismo lugar ---
    const camPed = [
      mk("1",  "4024", "G. Pellegrini", "Ciudadela",      "D69F", "16/09/2026"),
      mk("2",  "2328", "G-Seller",      "Moron",          "D69F", "16/09/2026"),
      mk("3",  "2328", "G-Seller",      "Moron",          "D69F", "16/09/2026"),   // misma dirección
      mk("4",  "2328", "G-Seller",      "Moron",          "D69F", "16/09/2026"),   // misma dirección
      mk("5",  "4045", "Bazar Monica",  "Padua",          "D69F", "16/09/2026"),
      mk("6",  "4221", "Laza",          "Ituzaingo",      "D69F", "16/09/2026"),
      mk("7",  "4114", "Extralimp",     "Lujan",          "D69F", "16/09/2026"),   // el que estira
      mk("8",  "2543", "Succarelli",    "Hurlingham",     "D69F", "16/09/2026"),
      mk("9",  "3927", "Arguello",      "Villa Ballester","D69F", "16/09/2026"),
      mk("10", "3861", "Martinelli",    "Bella Vista",    "D69F", "16/09/2026"),
      mk("11", "4188", "Orfali",        "Martinez",       "D69F", "16/09/2026"),
      mk("12", "2715", "Gifel",         "San Martin",     "D69F", "16/09/2026"),
      mk("13", "4189", "Valimar",       "Villa Lynch",    "D69F", "16/09/2026"),
      mk("14", "4281", "Biaggio",       "Pilar",          "D69F", "16/09/2026"),
      mk("15", "4198", "Benitez",       "Pilar",          "D69F", "16/09/2026")
    ];
    const j = _pppJornadaCam({ ped: camPed, ruta: "n" });
    out.paradas = j.paradas;                     // 13 direcciones, no 15 NP
    out.sinUbic = j.sinUbic;
    const cfg = _pppJorCfg;
    out.cfg = cfg.horasMax + "|" + cfg.minParada + "|" + cfg.kmH + "|" + cfg.factor;
    out.formulaOk = Math.abs(j.horas - (j.km / cfg.kmH + j.paradas * cfg.minParada / 60)) < 1e-9;
    out.descOk = Math.abs(j.hDesc - 13 * 15 / 60) < 1e-9;
    out.excede = j.excede;                        // con Luján se pasa de 8 h
    out.horas = Math.round(j.horas * 10) / 10;

    // sacar Luján (el que va en kangoo aparte) tiene que bajar el camión MUCHO — aunque con estos
    // parámetros el 16/09 siga por encima de 8 h: es el dato que hay que mirar, no un detalle.
    const sinLujan = camPed.filter(function (x) { return x.cod !== "4114"; });
    const j2 = _pppJornadaCam({ ped: sinLujan, ruta: "n" });
    out.sinLujanHoras = Math.round(j2.horas * 10) / 10;
    out.sinLujanBaja = (j.horas - j2.horas) > 1.5;

    // --- (3) el aviso del panel ---
    const e = _pppComputeErrors(camPed);
    out.enJornada = (e.jornada || []).length === 1 && e.jornada[0].fecha === "16/09/2026";
    const html = pppErroresHtml(e);
    out.html = html;
    out.avisaDia   = html.indexOf("Camión de más de 8 h") >= 0 && html.indexOf("<b>16/09</b>") >= 0;
    out.avisaHoras = /<b>\d+,\d h<\/b> \(viaje \d+,\d h \+ 13 paradas × 15′\)/.test(html);
    out.avisaLejos = /lo estira <b>Luj[áa]n<\/b> \(a \d+ km\)/.test(html);   // pppLocDisp le pone el tilde

    // --- (4) camión corto: no avisa ---
    const corto = [mk("8", "4024", "G. Pellegrini", "Ciudadela", "D69H", "17/09/2026")];
    const e2 = _pppComputeErrors(corto);
    out.cortoSinAviso = (e2.jornada || []).length === 0;

    // --- (5) Retira no cuenta ---
    const ret = [mk("9", "4114", "Extralimp", "Lujan", "", "18/09/2026")];
    ret[0].zona = "Retira";
    window.pppZonaDeBarrio = function () { return "Retira"; };
    const e3 = _pppComputeErrors(ret);
    out.retiraSinAviso = (e3.jornada || []).length === 0;
    return out;
  });

  const pass =
    r.paradas === 13 && r.sinUbic === 0 && r.cfg === "8|15|28|1.35" &&
    r.formulaOk && r.descOk && r.excede && r.horas > 8 &&
    r.sinLujanBaja && r.sinLujanHoras < r.horas &&
    r.enJornada && r.avisaDia && r.avisaHoras && r.avisaLejos &&
    r.cortoSinAviso && r.retiraSinAviso &&
    errs.length === 0;
  const { html, ...vis } = r;
  console.log("ppp-jornada-camion:", JSON.stringify(vis), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  if (!pass) console.log("HTML:", String(html).slice(0, 700));
  await b.close();
  process.exit(pass ? 0 : 1);
})();

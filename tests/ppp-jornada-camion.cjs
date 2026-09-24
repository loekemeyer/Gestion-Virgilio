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

   v16.65 — y el caso que la v15.86 NO veía: el tope es por VEHÍCULO y por DÍA. `_pppCamiones`
   hace un camión por número de tanda, así que ninguna tanda sola llegaba a 8 h (medido sobre la
   programación real del 14 al 18/09: la mayor daba 5,7 h) y el aviso no salía nunca — mientras
   el 16/09 tenía 6 tandas que suman 20,6 h de camión y, con los 2 fleteros que hay, son 10,3 h
   cada uno. Se chequea además:
   6) el día cuyas tandas repartidas entre `jornada_camiones` pasan el tope entra en
      `_pppComputeErrors().jornadaDia` y sale en el panel con las horas, las de más y la peor tanda,
   7) el mismo día con más camiones deja de avisar.

   v16.72 — VEHÍCULO PROPIO: E11A (Luján) salió en la kangoo, no en el camión del fletero. Con la
   tanda marcada en `_pppVehPropio` (lo que carga `pppRefreshVehPropio` desde `GV_Vehiculo_Propio`)
   el día la descuenta; si la marca no está (tabla inexistente, select fallido, vacío) nada cambia:
   8) con E11A marcada el aviso del 16/09 desaparece (entra en las 8 h) y, forzando el tope a 1 h para
      verlo, el día queda con 3 tandas y menos horas; con `null` o `{}` vuelve a las 4 de antes; una
      marca sobre una tanda que no está ese día no cambia nada.
   v22.44 — "no puede ser 313 km": el día se medía con una vuelta al depósito POR TANDA
   (`_pppCamiones`). Ahora es una por CAMIÓN REAL (`_pppCamionesJornada`, criterio del Resumen):
   9 tandas de una zona = 1 camión y los km son los de UN recorrido (6); el día se reparte entre
   los fleteros (7); la kangoo sigue sin contar (8).
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

    // --- (6) v22.44: una vuelta por CAMIÓN REAL, no por tanda ("no puede ser 313 km") ---
    // 9 tandas de la misma zona son UN camión: los km del día son los de UN recorrido.
    const nueve = [];
    ["4024", "2328", "4045", "4221", "2543", "3927", "3861", "4189", "2715"].forEach(function (c, i) {
      nueve.push(mk(String(200 + i), c, "Cli " + c, "Loc " + c, "E" + (60 + i) + "A", "30/09/2026"));
    });
    const hmOrig = _pppJorCfg.horasMax; _pppJorCfg.horasMax = 0.01;   // forzar el aviso para leerlo
    const d9 = (_pppComputeErrors(nueve).jornadaDia || [])[0] || {};
    _pppJorCfg.horasMax = hmOrig;
    const unaVuelta = _pppJornadaCam({ ped: nueve });
    out.nueveCam = d9.camiones;                                   // 1 camión
    out.nueveTandas = d9.tandas;                                  // 9 tandas
    out.nueveKmOk = Math.abs((d9.km || 0) - unaVuelta.km) < 1e-6; // UNA vuelta, no nueve
    let kmPorTanda = 0; nueve.forEach(function (x) { kmPorTanda += _pppJornadaCam({ ped: [x] }).km; });
    out.nueveNoInfla = kmPorTanda > 2.5 * unaVuelta.km;           // lo que sumaba antes

    // --- (7) el DÍA no entra repartido entre los fleteros: Oeste + Norte = 2 camiones ---
    window.pppZonaDeBarrio = function (bo) {
      return /lujan|pilar/i.test(String(bo)) ? "Zona 7 - GBA Norte Lejos"
           : /martinez|san martin|ballester|lynch/i.test(String(bo)) ? "Zona 6 - GBA Norte" : "Zona 5 - GBA Oeste";
    };
    const dia = camPed.map(function (x, i) { const y = Object.assign({}, x, { _err: [] }); y.tanda = i < 6 ? "D69A" : (x.cod === "4114" ? "E11A" : "E17A"); return y; });
    _pppJorCfg.horasMax = 0.01;
    const d0 = (_pppComputeErrors(dia).jornadaDia || [])[0] || {};
    out.diaCamiones = d0.camiones;                                // Oeste + Norte (Z6+Z7 juntas)
    out.diaFleteros = d0.fleteros;
    out.diaRepartoOk = Math.abs((d0.hCada || 0) * d0.fleteros - (d0.horas || 0)) < 1e-9;
    // el tope justo entre repartir en 2 y en 8 fleteros: avisa con 2, no con 8
    _pppJorCfg.horasMax = (d0.horas || 0) / 2 - 0.01;
    const eD = _pppComputeErrors(dia);
    out.diaAvisa = (eD.jornadaDia || []).length === 1;
    const htmlD = pppErroresHtml(eD);
    out.htmlD = htmlD;
    out.diaTexto = /🚚 <b>Día que no entra en la jornada \(1\)/.test(htmlD) &&
                   /<b>16\/09<\/b> · 2 camión\(es\), 3 tandas → <b>\d+,\d h<\/b> de camión/.test(htmlD) &&
                   /con 2 fletero\(s\) son <b>\d+,\d h<\/b> cada uno/.test(htmlD);
    const camOrig = _pppJorCfg.camiones; _pppJorCfg.camiones = 8;
    out.masCamionesSinAviso = (_pppComputeErrors(dia).jornadaDia || []).length === 0;
    _pppJorCfg.camiones = camOrig;

    // --- (8) v16.72: la tanda en vehículo propio no ocupa camión de fletero ---
    _pppJorCfg.horasMax = 0.01;
    _pppVehPropio = { E11A: "kangoo" };
    const dV = (_pppComputeErrors(dia).jornadaDia || [])[0] || {};
    out.vehTandas = dV.tandas;                                    // 2, no 3
    out.vehBaja = (dV.horas || 0) < (d0.horas || 0) - 1;          // la kangoo se lleva Luján
    _pppVehPropio = { E99Z: "kangoo" };
    out.vehOtraIgual = ((_pppComputeErrors(dia).jornadaDia || [])[0] || {}).tandas === 3;
    _pppVehPropio = {};
    out.vehVacioIgual = ((_pppComputeErrors(dia).jornadaDia || [])[0] || {}).tandas === 3;
    _pppVehPropio = null;
    out.vehNullIgual = ((_pppComputeErrors(dia).jornadaDia || [])[0] || {}).tandas === 3;
    out.vehFnExiste = typeof pppRefreshVehPropio === "function" && typeof _pppCamionesJornada === "function";
    _pppJorCfg.horasMax = hmOrig;

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
    r.nueveCam === 1 && r.nueveTandas === 9 && r.nueveKmOk && r.nueveNoInfla &&
    r.diaAvisa && r.diaCamiones === 2 && r.diaFleteros === 2 && r.diaRepartoOk && r.diaTexto && r.masCamionesSinAviso &&
    r.vehTandas === 2 && r.vehBaja && r.vehOtraIgual && r.vehVacioIgual && r.vehNullIgual && r.vehFnExiste &&
    errs.length === 0;
  const { html, htmlD, ...vis } = r;
  console.log("ppp-jornada-camion:", JSON.stringify(vis), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  if (!pass) console.log("HTML:", String(html).slice(0, 500), "\n--- día:", String(htmlD).slice(0, 500));
  await b.close();
  process.exit(pass ? 0 : 1);
})();

/* Regresión idea 3812 — ruteo de camiones de la Carga Camión (_rtOptimize / _rtSplitTrucks
   / _rtTourKm / _rtMapsUrls). Todo cálculo puro sobre coordenadas: no pega a Nominatim ni
   a Supabase.

   Cubre:
   - _rtOptimize: ≤2 paradas devuelve una COPIA sin reordenar (no muta la entrada) · con
     paradas colineales desordenadas encuentra el orden geográfico · nunca pierde ni duplica
     paradas · el tour optimizado nunca es MÁS largo que el orden de entrada (2-opt).
   - _rtSplitTrucks: corta contiguo al superar la capacidad · una parada que SOLA excede la
     capacidad viaja igual (en su propio camión, no se descarta) · una carga que da EXACTO
     la capacidad no abre camión de más (tolerancia 1e-9) · lista vacía → sin camiones ·
     ninguna parada se pierde en el reparto.
   - _rtMapsUrls: parte en tramos de ≤9 waypoints ENCADENADOS (el destino de un tramo es el
     origen del siguiente), arrancando y terminando en el depósito — el fix v10.23 de la
     ruta de 16 paradas que abría solo 9.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    const D = { lat: -34.60, lng: -58.45 };   // depósito
    const S = function (id, dlat, dlng, m3) { return { id: id, lat: D.lat + dlat, lng: D.lng + dlng, m3: m3 }; };
    const ids = function (arr) { return arr.map(function (x) { return x.id; }).join(","); };

    // ---- _rtOptimize: ≤2 paradas → copia intacta (no muta) ----
    const dos = [S("b", 0.20, 0), S("a", 0.05, 0)];
    const dosOut = _rtOptimize(D, dos);
    out.dosParadas_copia = ids(dosOut) === "b,a" && dosOut !== dos && ids(dos) === "b,a";

    // ---- colineales al norte, desordenadas → orden geográfico ----
    const col = [S("c", 0.30, 0), S("a", 0.10, 0), S("d", 0.40, 0), S("b", 0.20, 0)];
    const colOut = _rtOptimize(D, col);
    out.ordenGeografico = ids(colOut) === "a,b,c,d";
    out.noMuta = ids(col) === "c,a,d,b";

    // ---- no pierde ni duplica paradas (caso disperso) ----
    const disp = [S("p1", 0.10, 0.05), S("p2", -0.08, 0.12), S("p3", 0.22, -0.03),
                  S("p4", -0.15, -0.10), S("p5", 0.04, 0.20), S("p6", 0.18, 0.18)];
    const dispOut = _rtOptimize(D, disp);
    out.conservaParadas = dispOut.length === disp.length &&
      new Set(dispOut.map(function (x) { return x.id; })).size === disp.length;

    // ---- el tour optimizado nunca es peor que el orden de entrada ----
    out.noEmpeora = _rtTourKm(D, dispOut) <= _rtTourKm(D, disp) + 1e-9;
    // ---- _rtTourKm es un circuito CERRADO (vuelve al depósito) y positivo ----
    out.tourCerrado = _rtTourKm(D, [S("x", 0.10, 0)]) > 0 &&
      Math.abs(_rtTourKm(D, [S("x", 0.10, 0)]) - 2 * _rtHav(D, S("x", 0.10, 0))) < 1e-9;
    out.tourVacio = _rtTourKm(D, []) === 0;

    // ---- _rtSplitTrucks: corte contiguo por capacidad ----
    const carga = [S("a", 0, 0, 4), S("b", 0, 0, 3), S("c", 0, 0, 5), S("d", 0, 0, 2)];
    const t = _rtSplitTrucks(carga, 8);
    out.split_contiguo = t.length === 2 && ids(t[0]) === "a,b" && ids(t[1]) === "c,d";
    out.split_conservaTodo = t.reduce(function (n, k) { return n + k.length; }, 0) === carga.length;

    // ---- carga EXACTA a la capacidad: no abre camión de más ----
    const exacto = _rtSplitTrucks([S("a", 0, 0, 5), S("b", 0, 0, 5)], 10);
    out.split_exacto = exacto.length === 1 && ids(exacto[0]) === "a,b";

    // ---- una parada SOLA que excede la capacidad viaja igual (no se descarta) ----
    const gigante = _rtSplitTrucks([S("a", 0, 0, 2), S("gordo", 0, 0, 30), S("b", 0, 0, 1)], 10);
    out.split_gigante = gigante.length === 3 && ids(gigante[0]) === "a" &&
      ids(gigante[1]) === "gordo" && ids(gigante[2]) === "b";

    // ---- sin paradas → sin camiones ----
    out.split_vacio = _rtSplitTrucks([], 10).length === 0;

    // ---- _rtMapsUrls: tramos de ≤9 waypoints, encadenados desde/hasta el depósito ----
    const once = [];
    for (let i = 1; i <= 11; i++) once.push(S("s" + i, 0.01 * i, 0.01 * i, 1));
    const urls = _rtMapsUrls(D, once);
    const pt = function (q) { return q.lat.toFixed(6) + "," + q.lng.toFixed(6); };
    const par = urls.map(function (u) { const q = new URL(u).searchParams; return { o: q.get("origin"), d: q.get("destination"), wp: (q.get("waypoints") || "").split("|").filter(Boolean) }; });
    out.maps_varios = par.length === 2;
    out.maps_tope9 = par.every(function (x) { return x.wp.length <= 9; }) && par[0].wp.length === 9;
    out.maps_encadena = par[0].d === par[1].o;
    out.maps_depotAmbosExtremos = par[0].o === pt(D) && par[par.length - 1].d === pt(D);
    // toda parada aparece exactamente una vez (como waypoint o como empalme entre tramos)
    const vistos = [];
    par.forEach(function (x, i) { x.wp.forEach(function (w) { vistos.push(w); }); if (i < par.length - 1) vistos.push(x.d); });
    out.maps_todasLasParadas = vistos.length === once.length &&
      once.every(function (s) { return vistos.indexOf(pt(s)) >= 0; });

    return out;
  });
  const keys = Object.keys(r); const bad = keys.filter(function (k) { return r[k] !== true; });
  const pass = bad.length === 0 && errs.length === 0;
  console.log("rt-ruteo:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL " + bad.join(","));
  await b.close(); process.exit(pass ? 0 : 1);
})();

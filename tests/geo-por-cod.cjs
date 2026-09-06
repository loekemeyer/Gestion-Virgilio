/* v13.40 — la ubicación de un pedido se busca en este orden:
     1. GV_Geo_Cliente con la dirección EXACTA de ese cliente (cód + dirección)
     2. PPP_Geo por dirección (la de siempre, compartida con Producción)
     3. cualquier ubicación de ese cód — el paracaídas contra el cambio de tipeo en ISIS
   Antes existía sólo la 2: si ISIS escribía "Rivadavia 18059" un día y "Av Rivadavia 18059" otro,
   la clave era nueva y el pedido caía a "sin ubicación", que en el orden de carga lo manda al
   final del reparto. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1200, height: 800 } });
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    // PPP_Geo: sólo conoce el depósito y UNA dirección
    _pppGeo = {
      "__deposito_virgilio_2788__": { lat: -34.65, lng: -58.5 },
      "moreno 1248|balvanera": { lat: -34.61, lng: -58.39 }
    };
    // GV_Geo_Cliente: exacta del cliente 151, y "la mejor" de 151 y de 1792
    _pppGeoCod = {
      "151 rivadavia 18059|moron": { lat: -34.65, lng: -58.62, usos: 3, ts: "b" },
      "151": { lat: -34.65, lng: -58.62, usos: 3, ts: "b" },
      "1792": { lat: -34.60, lng: -58.44, usos: 5, ts: "c" }
    };
    const P = (cod, dir, barrio) => ({ cod, direccion: dir, barrio: barrio });

    // 1 · dirección exacta del cliente en GV_Geo_Cliente
    const a = _pppGeoDe(P("151", "Rivadavia  18059", "Moron"));
    out.exacta = a && a.lat === -34.65 && a.lng === -58.62;
    // 2 · sin fila por cód, cae en PPP_Geo por dirección
    const c = _pppGeoDe(P("260", "Moreno  1248", "Balvanera"));
    out.porDireccion = c && c.lat === -34.61 && c.lng === -58.39;
    // 3 · ISIS le cambió el tipeo ("Av Rivadavia 18059"): la clave por dirección ya no está,
    //     pero la del cód sí → sigue ubicado
    const d = _pppGeoDe(P("151", "Av Rivadavia 18059", "Moron"));
    out.tipeoCambiado = d && d.lat === -34.65 && d.lng === -58.62;
    // 3b · cliente con varias direcciones: sin la exacta usa la que más se usó
    const e = _pppGeoDe(P("1792", "Av. F. Lacroze  2481", "Colegiales"));
    out.mejorDelCliente = e && e.lat === -34.60 && e.lng === -58.44;
    // sin nada: sin ubicación (va al final del reparto, como siempre)
    out.sinNada = _pppGeoDe(P("9999", "Calle Inventada 1", "Nowhere")) === null;
    // un pedido sin cód no puede "heredar" la ubicación de otro
    out.sinCod = _pppGeoDe(P("", "Otra Calle 5", "Flores")) === null;

    // y el orden de carga usa todo eso: los 3 ubicados ordenan, el 4º va al final
    const cam = { ped: [P("151", "Av Rivadavia 18059", "Moron"), P("260", "Moreno  1248", "Balvanera"),
                        P("1792", "Av. F. Lacroze  2481", "Colegiales"), P("9999", "Calle Inventada 1", "Nowhere")] };
    const oc = _pppOrdenCarga(cam);
    out.sinUbic = oc.sinUbic;
    out.ultimaParada = oc.paradas[oc.paradas.length - 1].cod;
    return out;
  });

  await b.close();
  let bad = 0;
  const chk = (ok, name) => { console.log((ok ? "  ok   " : "  FALLA") + " · " + name); if (!ok) bad++; };
  chk(r.exacta === true, "1 · dirección exacta del cliente (GV_Geo_Cliente)");
  chk(r.porDireccion === true, "2 · sin fila por cód → PPP_Geo por dirección");
  chk(r.tipeoCambiado === true, "3 · ISIS cambió el tipeo de la dirección → la ubicación del cód lo salva");
  chk(r.mejorDelCliente === true, "3b · cliente con varias direcciones → la que más se usó");
  chk(r.sinNada === true, "sin ubicación en ningún lado → null");
  chk(r.sinCod === true, "un pedido sin cód no hereda la ubicación de otro");
  chk(r.sinUbic === 1 && r.ultimaParada === "9999", "el orden de carga deja al sin ubicación al final del reparto");
  chk(errs.length === 0, "sin errores de página");
  if (bad) console.log("  detalle:", JSON.stringify(r), errs);
  console.log(bad ? ("geo-por-cod: " + bad + " FALLA(S)") : "geo-por-cod: OK");
  process.exit(bad ? 1 : 0);
})();

/* v13.38 — 📍 Mapa de zonas: (a) las direcciones a ubicar salen de ISIS **y** de la programación
   web (antes sólo ISIS, y por eso todo lo de la página quedaba "sin ubicación" para siempre);
   (b) una dirección de expreso se limpia antes de preguntarle a Nominatim: el nombre del expreso
   adelante y el domicilio final del cliente entre paréntesis (otra provincia) hacían que no
   encontrara nada o cayera lejos. La clave de PPP_Geo sigue siendo la dirección original. */
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
    // (b) limpieza de la dirección SÓLO para la consulta
    out.limpia = [
      _zgDirQuery("Exp. Arnes — AUSTRALIA 2959, Barracas (Rivadavia 3663- Mar Del Plata)"),
      _zgDirQuery("Exp. Arias (Comodoro) — Av. Pinedo 50, Barracas (Belgrano 926- C.Rivadavia)"),
      _zgDirQuery("Exp. Bin — PERGAMINO 3750, Soldati (Tucuman 1442- Corrientes)")
    ].join(" ; ");
    out.intacta = [_zgDirQuery("Av. Monroe 2325- Belgrano"), _zgDirQuery("Bragado 5742 - Mataderos"), _zgDirQuery("Av Rivadavia  17640")].join(" ; ");
    out.vacia = _zgDirQuery("") === "" && _zgDirQuery(null) === "";

    // (a) el mapa pide las dos programaciones y no repite una dirección que está en las dos
    const pedidas = [];
    window.fetch = (url) => {
      const u = String(url); pedidas.push(u);
      const J = (d) => Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(d) });
      if (u.indexOf("gv_ppp_programacion_diaria") >= 0) return J([
        { np: "98603", razon_social: "Sauer Ignacio Jose", direccion: "San Luis  1461", barrio: "Rafael Calzada", zona: "Zona 4 - GBA Sur" },
        { np: "98604", razon_social: "Otro", direccion: "San Luis  1461", barrio: "Rafael Calzada", zona: "Zona 4 - GBA Sur" },
        { np: "98605", razon_social: "Sin dirección", direccion: "", barrio: "Flores", zona: "Zona 3 - CABA Oeste" }
      ]);
      if (u.indexOf("PPP_Web_Programacion") >= 0) return J([
        { np: "1344", razon_social: "Torres Y Liva S.A Cif", direccion: "Exp. Arnes — AUSTRALIA 2959, Barracas (Rivadavia 3663- Mar Del Plata)", barrio: "Barracas", zona: "Zona 1 - CABA Sur" },
        { np: "1345", razon_social: "Chen Li Yu", direccion: "Av. Monroe 2325- Belgrano", barrio: "Belgrano", zona: "Zona 2 - CABA Centro" }
      ]);
      return J([]);
    };
    const addrs = await _zgFetchAddrs();
    out.pidioIsis = pedidas.some((u) => u.indexOf("gv_ppp_programacion_diaria") >= 0);
    out.pidioWeb = pedidas.some((u) => u.indexOf("PPP_Web_Programacion") >= 0);
    out.dirs = addrs.map((a) => a.rs + "|" + a.key).join(" ; ");
    return out;
  });

  await b.close();
  let bad = 0;
  const chk = (ok, name) => { console.log((ok ? "  ok   " : "  FALLA") + " · " + name); if (!ok) bad++; };
  chk(r.limpia === "AUSTRALIA 2959, Barracas ; Av. Pinedo 50, Barracas ; PERGAMINO 3750, Soldati", "expreso: se va el nombre del expreso y el domicilio final entre paréntesis");
  chk(r.intacta === "Av. Monroe 2325- Belgrano ; Bragado 5742 - Mataderos ; Av Rivadavia  17640", "una dirección normal no se toca");
  chk(r.vacia === true, "dirección vacía sigue vacía (no rompe)");
  chk(r.pidioIsis === true && r.pidioWeb === true, "v13.38: pide ISIS y la programación web");
  chk(r.dirs === "Sauer Ignacio Jose|san luis 1461|rafael calzada ; Torres Y Liva S.A Cif|exp. arnes — australia 2959, barracas (rivadavia 3663- mar del plata)|barracas ; Chen Li Yu|av. monroe 2325- belgrano|belgrano",
    "una dirección por clave (sin repetir), sin las vacías, y la clave es la dirección ORIGINAL");
  chk(errs.length === 0, "sin errores de página");
  if (bad) console.log("  detalle:", JSON.stringify(r), errs);
  console.log(bad ? ("zg-geo-web-expreso: " + bad + " FALLA(S)") : "zg-geo-web-expreso: OK");
  process.exit(bad ? 1 : 0);
})();

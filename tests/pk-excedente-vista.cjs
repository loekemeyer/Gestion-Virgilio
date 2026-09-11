/* Regresión v14.93 — pkFetchExcedente NO suma movimientos (PostgREST corta en 1000 filas y
   el excedente tiene 5.500+): las CAJAS salen de vista_saldos_stock y de Movimientos_Stock
   sólo las UBICACIONES (delta>0 con ubicación). Caso real 2026-09-10: 502 tenía 26 cajas
   "fantasma" en el front (ventana de 1000) y 0 real → el picking mandaba al excedente.

   Chequea:
   - Artículo con saldo 0 en la vista pero entradas positivas en movimientos → NO aparece.
   - Artículo con saldo > 0 → cajas = las de la vista (no la suma de movimientos), ubics de
     las entradas, recientes primero, sin repetir.
   - Artículo con saldo > 0 y sin entrada con ubicación → ubics [].
   - Las dos consultas piden sólo los códigos de la tanda; la de movimientos filtra delta>0 y
     ubicación no nula.
   - Si la vista falla (HTTP 500) → {} (degradación: todo de góndola).
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
    const out = {}; const urls = [];
    let vistaFalla = false;
    window.fetch = async function (url) {
      urls.push(String(url));
      const J = (rows, status) => ({ ok: (status || 200) < 400, status: status || 200, json: async () => rows, headers: { get: () => null } });
      if (String(url).indexOf("vista_saldos_stock") >= 0) {
        if (vistaFalla) return J([], 500);
        return J([{ cod_art: "502", excedente: 0 }, { cod_art: "066", excedente: 137 }, { cod_art: "315", excedente: 4 }]);
      }
      if (String(url).indexOf("Movimientos_Stock") >= 0) {
        return J([
          { cod_art: "502", ubicacion: "P11", ts: "2026-08-21" },   // saldo real 0 → no debe salir
          { cod_art: "066", ubicacion: "P3", ts: "2026-08-30" },
          { cod_art: "066", ubicacion: "P3", ts: "2026-08-10" },    // repetida
          { cod_art: "066", ubicacion: "AD2", ts: "2026-07-01" }
        ]);
      }
      return J([]);
    };
    const m = await pkFetchExcedente(["502", "066", "315", "546"]);
    out.sinFantasma502 = !m["502"];
    out.cajasDeVista066 = !!m["066"] && m["066"].cajas === 137;
    // v15.81 — las ubicaciones salen NORMALIZADAS (P3 → P03, AD2 → AD02), que es el
    // formato canónico de GV_Lugar. Antes pasaban crudas y "P3" y "P03" contaban como
    // dos lugares distintos siendo el mismo — el operario veía la lista repetida.
    out.ubics066 = !!m["066"] && JSON.stringify(m["066"].ubics) === JSON.stringify(["P03", "AD02"]);
    out.ubicsVacias315 = !!m["315"] && m["315"].cajas === 4 && m["315"].ubics.length === 0;
    out.noPedido546 = !m["546"];
    const uv = urls.find(u => u.indexOf("vista_saldos_stock") >= 0) || "";
    const um = urls.find(u => u.indexOf("Movimientos_Stock") >= 0) || "";
    out.vistaFiltraCods = uv.indexOf("cod_art=in.(502,066,315,546)") >= 0 && uv.indexOf("select=cod_art,excedente") >= 0;
    out.movsSoloEntradasConUbic = um.indexOf("deposito=eq.excedente") >= 0 && um.indexOf("delta=gt.0") >= 0 && um.indexOf("ubicacion=not.is.null") >= 0;
    vistaFalla = true;
    const m2 = await pkFetchExcedente(["502", "066"]);
    out.vistaFalla_vacio = JSON.stringify(m2) === "{}";
    return out;
  });
  const pass = Object.keys(r).every(k => r[k] === true) && !errs.length;
  console.log("pk-excedente-vista:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join(" | ") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();

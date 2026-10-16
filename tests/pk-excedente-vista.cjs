/* Regresión v14.93 — pkFetchExcedente NO suma movimientos (PostgREST corta en 1000 filas y
   el excedente tiene 5.500+): las CAJAS salen de vista_saldos_stock y de Movimientos_Stock
   sólo las UBICACIONES (delta>0 con ubicación). Caso real 2026-09-10: 502 tenía 26 cajas
   "fantasma" en el front (ventana de 1000) y 0 real → el picking mandaba al excedente.

   Chequea:
   - Artículo con saldo 0 en la vista pero entradas positivas en movimientos → NO aparece.
   - Artículo con saldo > 0 → cajas = las de la vista (no la suma de movimientos), ubics de
     gv_excedente_posicion (v31.59: neto por posición HOY, en orden de recorrido), sin repetir.
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
        // v16.16 — la vista devuelve `clave` (la que distingue 809E LK de 809E CH) además de
        // `cod_art`. El 315 va SIN `clave` a propósito: prueba el fallback a `cod_art` por si
        // se rueda atrás la vista y la columna desaparece.
        return J([{ clave: "502", cod_art: "502", excedente: 0 }, { clave: "066", cod_art: "066", excedente: 137 }, { cod_art: "315", excedente: 4 }]);
      }
      // v31.59 — las posiciones salen de gv_excedente_posicion (neto de cada posición HOY, en
      // orden de recorrido), no de las entradas históricas de Movimientos_Stock.
      if (String(url).indexOf("gv_excedente_posicion") >= 0) {
        return J([
          { clave: "502", sector: "P11", orden: 728, cajas: 3 },   // saldo real 0 en la vista → no debe salir
          { clave: "066", sector: "P3", orden: 720, cajas: 80 },
          { clave: "066", sector: "P03", orden: 720, cajas: 1 },   // misma posición con otra grafía
          { clave: "066", sector: "AD2", orden: 730, cajas: 56 }
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
    const um = urls.find(u => u.indexOf("gv_excedente_posicion") >= 0) || "";
    // v16.16 — filtra y selecciona por `clave`, no por `cod_art`: es la columna que sigue
    // separando los duales cuando `cod_art` quede pelado (docs/PLAN-SACAR-SUFIJO-EMPRESA.md).
    out.vistaFiltraCods = uv.indexOf("clave=in.(502,066,315,546)") >= 0 && uv.indexOf("select=clave,cod_art,excedente") >= 0
      && uv.indexOf("cod_art=in.(") < 0;
    out.posicionesNetasEnOrden = um.indexOf("clave=in.(502,066,315,546)") >= 0 && um.indexOf("sector=not.is.null") >= 0 && um.indexOf("order=orden.asc") >= 0;
    out.noLeeEntradasViejas = !urls.some(u => u.indexOf("Movimientos_Stock") >= 0 && u.indexOf("deposito=eq.excedente") >= 0);
    // v31.80 — P3 y P03 son la MISMA posición: sus cajas se suman (80 + 1), no gana la primera.
    out.cajasPorUbic = !!m["066"] && m["066"].porUbic && m["066"].porUbic["P03"] === 81 && m["066"].porUbic["AD02"] === 56;
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

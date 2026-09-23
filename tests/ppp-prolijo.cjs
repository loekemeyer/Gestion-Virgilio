/* v14.10 — dos arreglos de prolijidad en Programación, mirando la pantalla real del 07/09.
   (1) COLUMNA FANTASMA. La tabla de cada camión tiene 7 columnas fijas y la última es "Carga" (el
       orden de carga). En los camiones que NO tienen orden de carga —súper, retira, o menos de 2
       paradas ubicadas— esa columna quedaba VACÍA ocupando 150 px al final de cada fila: el
       encabezado terminaba en "Picking · Armado" y sobraba una columna muda. Ahora esos camiones
       usan una grilla de 6 columnas.
   (2) LISTA DE TANDAS DESBORDADA. El viernes 11 hay un camión con 11 tandas: el encabezado escupía
       "Tandas D67A · D67B · … · D67K", se iba a dos renglones y desalineaba los m³ y el valor.
       Ahora se muestran las primeras (4 adentro del día, 3 en la tarjeta de la grilla) y "+N";
       la lista completa queda en el globito.
   Sin red. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  // v15.40: sin este fallback el test muere en CI (el runner instala playwright con npm,
  // no tiene /opt/node22) y, como run.sh corta en el primero que falla, todo lo que venía
  // después NUNCA se corrió en GitHub. Mismo patrón que ya tenían los demás tests.
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1500, height: 950 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    try { localStorage.clear(); } catch (_e) {}
    const J = (d) => Promise.resolve({ ok: true, status: 200,
      headers: { get: (h) => String(h).toLowerCase() === "content-range" ? ("0-" + Math.max(0, d.length - 1) + "/" + d.length) : null },
      json: () => Promise.resolve(d), text: () => Promise.resolve(JSON.stringify(d)) });
    const hab = _pppDiasHabiles(6).map((d) => d.date);
    const iso = (dt) => dt.getFullYear() + "-" + String(dt.getMonth() + 1).padStart(2, "0") + "-" + String(dt.getDate()).padStart(2, "0");
    const mk = (np, tanda, cod, rs, m3, barrio, dir, dt, zona) => ({ np: np, tanda: tanda, tipo: "", fecha_recep: "2026-09-01", cod: cod, razon_social: rs, m3: m3, direccion: dir, barrio: barrio, fecha_entrega: iso(dt), zona: zona });
    // día 1: un camión con 11 tandas (como el viernes 11 real) + un SÚPER (sin orden de carga)
    const LET = "ABCDEFGHIJK".split("");
    const rows = LET.map((L, i) => mk("990" + (10 + i), "D67" + L, "20" + (10 + i), "Cliente " + L, 0.2, "Soldati", "Calle " + i, hab[0], "Zona 1 - CABA Sur"));
    rows.push(mk("99050", "D62A", "771", "S.A.Imp Y Exp De La Patagonia", 3.0, "Campo de Mayo", "Ruta 8", hab[0], "Super"));
    window.fetch = (u) => {
      const s = String(u);
      if (s.indexOf("gv_ppp_programacion_diaria") >= 0) return J(rows);
      if (s.indexOf("PPP_Geo") >= 0) return J([]);   // sin ubicaciones → ningún camión tiene orden de carga
      return J([]);
    };
    window._pppEmitError = function () {};
    window.getActivityStatus = async () => ({ pickingStarted: new Set(), pickingDone: new Set(), armadoStarted: new Set(), armadoDone: new Set(), pickingEnCursoBy: new Map(), armadoEnCursoBy: new Map() });
    await pppLoadProgFromSupabase();
    await pppRefreshControlado(); await pppRefreshArmado(); await pppRefreshEnSalida(); await pppRefreshValor(); await pppRefreshGeo();

    // ---- la vista de Programación ----
    // v21.38 (Luis: "Tablero de 6 días, eliminá esa visual") — la grilla de tarjetas ya no se
    // dibuja, así que sus tres chequeos (3 tandas + "+8", el globito, el súper entero) se fueron
    // con ella. Lo que sí sigue vivo es el recorte de la lista ADENTRO del día, que es el mismo
    // criterio y está abajo.
    _pppTab = "plan"; _pppPlanDay = null; _pppPlanTabla = false; pppRenderProg();
    const g = document.getElementById("pppPreview").innerHTML;
    out.sinGrilla = !/pn-days/.test(g) && !/pn-card/.test(g);

    // ---- ADENTRO del día ----
    pppPlanAbrir(_pppDateKey(hab[0]));
    const h = document.getElementById("pppPreview").innerHTML;
    out.diaCorto = /Tandas D67A · D67B · D67C · D67D <b class="pn-mas">\+7 más<\/b>/.test(h);
    out.diaTitle = /title="D67A · D67B · D67C · D67D · D67E · D67F · D67G · D67H · D67I · D67J · D67K"/.test(h);
    // (1) sin orden de carga (no hay PPP_Geo) → thead y filas SIN la última columna
    out.theads = (h.match(/class="pn-thead pn-sin-ult"/g) || []).length;
    out.theadsConUlt = (h.match(/class="pn-thead"/g) || []).length;
    out.filasSinUlt = (h.match(/class="pn-ped pn-sin-ult/g) || []).length;
    out.filas = (h.match(/class="pn-ped/g) || []).length;
    out.sinColumnaMuda = !/Picking · Armado<\/span><span><\/span>/.test(h);
    // la grilla de 6 columnas existe en el CSS
    out.css = [...document.styleSheets].some((ss) => { try { return [...ss.cssRules].some((r) => /pn-sin-ult/.test(r.cssText)); } catch (_e) { return false; } });
    return out;
  });
  await b.close();

  const fails = [];
  const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fails.push(m); };
  chk(r.sinGrilla, "v21.38: la grilla de 6 días no se dibuja; queda la tabla día → tanda → NP");
  chk(r.diaCorto, "adentro del día muestra 4 y '+7 más'");
  chk(r.diaTitle, "y también deja la lista entera en el globito");
  chk(r.theads === 2 && r.theadsConUlt === 0, "los dos camiones sin orden de carga usan la tabla de 6 columnas (" + r.theads + ")");
  chk(r.filas === 12 && r.filasSinUlt === 12, "y todas sus filas también (" + r.filasSinUlt + "/" + r.filas + ")");
  chk(r.sinColumnaMuda, "no queda una columna muda después de 'Picking · Armado'");
  chk(r.css, "el CSS de la grilla de 6 columnas está");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));
  if (fails.length) { console.error("\nFALLARON " + fails.length + ":\n· " + fails.join("\n· ")); process.exit(1); }
  console.log("\nppp-prolijo OK");
})();

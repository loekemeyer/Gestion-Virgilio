/* v21.37 — UN SOLO CRITERIO DE "ATRASADO" EN LAS TRES PANTALLAS QUE LO MUESTRAN.

   Luis, 22/09, con las dos capturas: "en Programación dice que no hay pedidos atrasados,
   pero en Resumen dice 18/9". Eran dos criterios distintos corriendo a la vez:

     · el submódulo de Pedidos atrasados (v18.78) pregunta `gv_ppp_atrasados`, que mira el
       CCN Y EL FSS POSTERIOR y normaliza la NP -> decía 0;
     · el cartel de Resumen y la banda del Tablero de 6 días contaban por su cuenta TODO
       pedido con fecha_entrega anterior a hoy, saliera o no -> decían 6.

   El test corre la pantalla de verdad con un pedido de fecha vencida que YA SALIÓ (el
   backend no lo marca) y otro que NO salió, y mira que las tres coincidan.
   ⚠ No alcanza con un candado de texto: lo que importa es qué dibuja cada solapa.
   Sin red. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    try { localStorage.clear(); } catch (_e) {}
    const J = (data) => { const n = Array.isArray(data) ? data.length : 0; return Promise.resolve({ ok: true, status: 200,
      headers: { get: (h) => String(h).toLowerCase() === "content-range" ? ("0-" + Math.max(0, n - 1) + "/" + n) : null },
      json: () => Promise.resolve(data), text: () => Promise.resolve(JSON.stringify(data)) }); };
    const hab = _pppDiasHabiles(6).map((d) => d.date);
    const iso = (dt) => dt.getFullYear() + "-" + String(dt.getMonth() + 1).padStart(2, "0") + "-" + String(dt.getDate()).padStart(2, "0");
    const ayer = new Date(hab[0].getTime()); ayer.setDate(ayer.getDate() - 3);
    const mk = (np, tanda, cod, rs, m3, dt) => ({ np: np, tanda: tanda, tipo: "", fecha_recep: "2026-08-20", cod: cod,
      razon_social: rs, m3: m3, direccion: "Alberdi 6000", barrio: "Soldati", fecha_entrega: iso(dt), zona: "Zona 1 - CABA Sur" });
    const rows = [
      mk("98901", "E95A", "1001", "Salió Y Tiene Remito", 0.30, ayer),   // fecha vencida, PERO ya salió
      mk("98902", "E96A", "1002", "Parado De Verdad", 0.40, ayer),       // fecha vencida y sin salida
      mk("98903", "E97A", "1003", "Al Día", 1.10, hab[0])
    ];
    let atrasados = [];   // lo que contesta el backend en cada corrida
    window.fetch = (url) => {
      const u = String(url);
      if (u.indexOf("gv_ppp_atrasados") >= 0) return J(atrasados);
      if (u.indexOf("gv_ppp_programacion_diaria") >= 0) return J(rows);
      return J([]);
    };
    window._pppEmitError = function () {};
    window.getActivityStatus = async () => ({ pickingStarted: new Set(["E95A", "E96A"]), pickingDone: new Set(["E95A", "E96A"]),
      armadoStarted: new Set(["E95A"]), armadoDone: new Set(["E95A"]), pickingEnCursoBy: new Map(), armadoEnCursoBy: new Map() });
    await pppLoadProgFromSupabase();
    await pppRefreshControlado(); await pppRefreshArmado(); await pppRefreshEnSalida(); await pppRefreshValor();

    const pinta = async () => {
      _patrRows = null; _patrTs = 0; _patrErr = "";
      patrNeed(true);
      await new Promise((ok) => setTimeout(ok, 120));
      // v21.38 — la grilla de 6 dias (y con ella su banda ⏰) se saco. La unica vista de
      //   Programacion es el arbol, con el submodulo de Pedidos atrasados arriba.
      const o = {};
      _pppTab = "plan"; _pppPlanDay = null; _pppPlanTabla = true; pppRenderProg();
      const arbol = document.getElementById("pppPreview").innerHTML;
      o.grilla = /pn-venc-band/.test(arbol);                       // tiene que ser false SIEMPRE
      // ⚠ sólo el caso vacío: el detalle del submódulo cuelga de `pgaNeed()`, que acá no trae
      //   filas, y ya lo cubre `ppp-atrasados-modulo.cjs`. Lo que se prueba acá es Resumen.
      o.vacio = /Sin pedidos atrasados/.test(arbol);
      _pppTab = "resumen"; _pppVencInline = false; pppRenderProg();
      const res = document.getElementById("pppPreview").innerHTML;
      o.cartel = /pedido\(s\) con fecha de entrega vencida/.test(res);
      o.cartelN = (/⏰ <b>(\d+)<\/b> pedido\(s\) con fecha de entrega vencida/.exec(res) || [])[1] || "0";
      return o;
    };

    // (1) el backend dice que NO hay atrasados: las tres pantallas tienen que callarse
    atrasados = [];
    out.vacio = await pinta();

    // (2) el backend marca UNO: las tres tienen que decir 1, y el mismo
    atrasados = [rows[1]];
    out.uno = await pinta();

    // (3) el backend caído -> ante la duda se avisa, con el criterio viejo (los 2 vencidos)
    window.fetch = (url) => {
      const u = String(url);
      if (u.indexOf("gv_ppp_atrasados") >= 0) return Promise.reject(new Error("boom"));
      if (u.indexOf("gv_ppp_programacion_diaria") >= 0) return J(rows);
      return J([]);
    };
    out.caido = await pinta();
    return out;
  });
  await b.close();

  const fails = [];
  const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fails.push(m); };

  chk(!r.vacio.cartel, "backend sin atrasados → Resumen NO saca el cartel de fecha vencida (era el bug: decía " + r.vacio.cartelN + ")");
  chk(r.vacio.vacio, "…y el submódulo de Programación dice «Sin pedidos atrasados»");

  chk(r.uno.cartel && r.uno.cartelN === "1", "backend con 1 atrasado → Resumen dice 1: " + r.uno.cartelN);

  chk(r.caido.cartel && r.caido.cartelN === "2", "backend caído → ante la duda se avisa, con el criterio viejo (2): " + r.caido.cartelN);
  chk(!r.vacio.grilla && !r.uno.grilla && !r.caido.grilla, "v21.38: la grilla de 6 días no se dibuja nunca");

  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));
  if (fails.length) { console.error("\nFALLARON " + fails.length + ":\n· " + fails.join("\n· ")); process.exit(1); }
  console.log("\nppp-atrasados-un-criterio OK");
})();

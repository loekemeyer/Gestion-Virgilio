/* v13.94 — Los atrasados se ven SIN dar vueltas.
   Dueño 07/09: "hoy para ver los pedidos atrasados tengo que entrar a Resumen para que me aparezca
   el botón que me lleve de nuevo a Programación, una locura". La v13.33 había sacado la tarjeta de
   Atrasados de Programación ("es un dato de gerencia") pero la LISTA se quedó ahí: el cartel de
   Resumen sólo servía para rebotar de solapa.
   (a) en Programación hay una banda chiquita con el conteo, partido en "sin salir → reprogramar" y
       "salieron · falta el remito", y abre la lista en la misma solapa;
   (b) esa banda NO es la tarjeta grande de la v13.33 (nada de .pn-alert) y no aparece si no hay
       atrasados;
   (c) el cartel de Resumen abre la lista ADENTRO de Resumen (no llama a pppTab) y el botón pasa a
       decir "Cerrar la lista";
   (d) la lista abierta en Resumen dice "Cerrar la lista", no "Volver a los 6 días" (ahí no hay
       grilla a la que volver), y cerrándola desaparece;
   (e) los KPI de Programación siguen contando sólo lo que tiene fecha por delante (v13.33).
   Sin red. Sale 1 si falla. */
const path = require("path");
const { chromium } = require("/opt/node22/lib/node_modules/playwright");
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
    const mk = (np, tanda, cod, rs, m3, barrio, dir, dt, zona) => ({ np: np, tanda: tanda, tipo: "", fecha_recep: "2026-08-20", cod: cod, razon_social: rs, m3: m3, direccion: dir, barrio: barrio, fecha_entrega: iso(dt), zona: zona });
    // 3 vencidos: E90A armada (salió, falta remito) · E91A sin armar ×2 (no salieron) + 2 al día
    const rows = [
      mk("98801", "E90A", "1001", "Salió Uno SRL", 0.30, "Barracas", "Montes de Oca 1000", ayer, "Zona 1 - CABA Sur"),
      mk("98802", "E91A", "1002", "No Salió Uno", 0.40, "Soldati", "Alberdi 6000", ayer, "Zona 1 - CABA Sur"),
      mk("98803", "E91A", "1003", "No Salió Dos", 0.20, "Soldati", "Escalada 1200", ayer, "Zona 1 - CABA Sur"),
      mk("98804", "E92A", "1004", "Al Día Uno", 1.10, "Pompeya", "Sáenz 1100", hab[0], "Zona 1 - CABA Sur"),
      mk("98805", "E92A", "1005", "Al Día Dos", 0.90, "Lugano", "Cafayate 4000", hab[0], "Zona 1 - CABA Sur")
    ];
    window.fetch = (url) => {
      const u = String(url);
      if (u.indexOf("gv_ppp_programacion_diaria") >= 0) return J(rows);
      return J([]);
    };
    window._pppEmitError = function () {};
    // E90A armada (TAP) → "salió, falta remito". E91A ni empezada → "no salió".
    window.getActivityStatus = async () => ({ pickingStarted: new Set(["E90A"]), pickingDone: new Set(["E90A"]), armadoStarted: new Set(["E90A"]), armadoDone: new Set(["E90A"]), pickingEnCursoBy: new Map(), armadoEnCursoBy: new Map() });
    await pppLoadProgFromSupabase();
    await pppRefreshControlado(); await pppRefreshArmado(); await pppRefreshEnSalida(); await pppRefreshValor();

    // (a)+(b)+(e) la grilla de Programación
    _pppTab = "plan"; _pppPlanDay = null; _pppPlanClasica = false; pppRenderProg();
    let h = document.getElementById("pppPreview").innerHTML;
    out.banda = /class="pn-venc-band rep"[^>]*onclick="pppPlanAbrir\('venc'\)"/.test(h);
    out.bandaDice = /<b>⏰ 3 atrasados<\/b>/.test(h) && /2 sin salir → reprogramar/.test(h) && /1 salieron · falta el remito/.test(h);
    out.sinTarjetaGrande = !/pn-alert/.test(h);
    out.kpiSoloFuturo = /<div class="l">Pedidos<\/div><div class="v">2<\/div>/.test(h);   // v13.33: los 3 vencidos no cuentan

    // abre la lista en la MISMA solapa
    pppPlanAbrir("venc");
    h = document.getElementById("pppPreview").innerHTML;
    out.listaEnPlan = /Atrasados — la fecha de entrega ya pasó/.test(h) && _pppTab === "plan";
    out.volverALaGrilla = /onclick="pppPlanVolver\(\)"/.test(h);
    pppPlanVolver();

    // (c)+(d) el cartel de Resumen
    _pppTab = "resumen"; pppRenderProg();
    h = document.getElementById("pppPreview").innerHTML;
    out.cartel = /3<\/b> pedido\(s\) con fecha de entrega vencida/.test(h);
    // el cartel en sí no debe mandar a otra solapa (la barra de solapas obviamente sí la tiene)
    const _cartel = (/<div class="ppp-res-note[^"]*">[\s\S]*?<\/div>/.exec(h) || [""])[0];
    out.noSalta = _cartel.indexOf("pppTab(") < 0 && /vencida/.test(_cartel);
    out.abreInline = /onclick="pppVencInline\(true\)"/.test(h) && !/Atrasados — la fecha de entrega ya pasó/.test(h);

    pppVencInline(true);
    h = document.getElementById("pppPreview").innerHTML;
    out.tab = _pppTab;   // sigue en resumen
    out.listaEnResumen = /Atrasados — la fecha de entrega ya pasó/.test(h);
    out.cerrarNoVolver = /onclick="pppVencInline\(false\)"/.test(h) && !/Volver a los 6 días/.test(h);
    out.dosCierres = (h.match(/pppVencInline\(false\)/g) || []).length;   // el del cartel y el de la barra
    out.reprog = /NO salió/.test(h) || /reprogramar/.test(h);

    pppVencInline(false);
    h = document.getElementById("pppPreview").innerHTML;
    out.cierra = !/Atrasados — la fecha de entrega ya pasó/.test(h);

    // (b) sin atrasados no hay banda
    _pppParsed.prog = _pppParsed.prog.filter((x) => x.tanda !== "E90A" && x.tanda !== "E91A");
    _pppTab = "plan"; _pppPlanDay = null; pppRenderProg();
    out.sinAtrasados = !/pn-venc-band/.test(document.getElementById("pppPreview").innerHTML);
    return out;
  });
  await b.close();

  const fails = [];
  const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fails.push(m); };
  chk(r.banda, "Programación tiene la banda de atrasados y abre la lista ahí mismo");
  chk(r.bandaDice, "y dice cuántos son, partidos en sin salir / falta el remito");
  chk(r.sinTarjetaGrande, "sin la tarjeta grande que se sacó en la v13.33");
  chk(r.kpiSoloFuturo, "el KPI de Pedidos sigue contando sólo lo que tiene fecha por delante (2)");
  chk(r.listaEnPlan, "la lista abre en la misma solapa Programación");
  chk(r.volverALaGrilla, "y ahí el botón vuelve a la grilla de 6 días");
  chk(r.cartel, "Resumen sigue con su cartel de vencidos");
  chk(r.noSalta, "y el cartel ya NO manda a la solapa Programación");
  chk(r.abreInline, "el botón despliega la lista, cerrada por defecto");
  chk(r.tab === "resumen" && r.listaEnResumen, "la lista se dibuja ADENTRO de Resumen (solapa: " + r.tab + ")");
  chk(r.cerrarNoVolver, "ahí dice Cerrar la lista, no 'Volver a los 6 días' (no hay grilla atrás)");
  chk(r.dosCierres === 2, "se cierra desde el cartel y desde la barra de la lista: " + r.dosCierres);
  chk(r.reprog, "y la lista marca los que no salieron");
  chk(r.cierra, "cerrarla la saca de la pantalla");
  chk(r.sinAtrasados, "sin atrasados no se dibuja ninguna banda");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));
  if (fails.length) { console.error("\nFALLARON " + fails.length + ":\n· " + fails.join("\n· ")); process.exit(1); }
  console.log("\nppp-atrasados OK");
})();

/* Regresión v13.03 — PROGRAMACIÓN NUEVA: tablero de 6 días hábiles (mockup v2) + orden de carga LIFO (idea 5920).
   Fixture: 2 vencidas, 5 pedidos el 1er día hábil (2 zonas), 2 el 2º (una Retira), 1 el 4º, 1 el 5º, 1 más adelante.
   PPP_Geo con el depósito y 4 direcciones del camión 1 → recorrido Mataderos → Lugano → Pompeya → Barracas
   (nearest-neighbor + 2-opt) → carga 1º Barracas … 4º Mataderos. E01A armada (TAP), E01B en picking (EP). */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1500, height: 900 } });
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
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
    const mk = (np, tanda, cod, rs, m3, barrio, dir, dt, zona) => ({ np, tanda, tipo: "", fecha_recep: "2026-09-01", cod, razon_social: rs, m3, direccion: dir, barrio, fecha_entrega: iso(dt), zona });
    const rows = [
      mk("98665", "D50E", "1001", "Vencida Uno", 0.04, "Mataderos", "Alberdi 6000", ayer, "Zona 3 - CABA Oeste"),
      mk("98474", "D46E", "1002", "Vencida Dos", 0.04, "Mataderos", "Escalada 1200", ayer, "Zona 3 - CABA Oeste"),
      mk("98701", "E01A", "1007", "Distribuidora Cuyana S.A.", 3.7, "Mataderos", "Alberdi 6000", hab[0], "Zona 1 - CABA Sur"),
      mk("98702", "E01A", "1008", "Astorga Ng S.A.", 0.8, "Barracas", "Montes de Oca 1000", hab[0], "Zona 1 - CABA Sur"),
      mk("98703", "E01B", "1009", "Bazar Luna", 0.9, "Pompeya", "Sáenz 1100", hab[0], "Zona 1 - CABA Sur"),
      mk("98704", "E01B", "1010", "Ferretería El Tornillo", 0.6, "Lugano", "Cafayate 4000", hab[0], "Zona 1 - CABA Sur"),
      mk("98705", "E02A", "1011", "Casa Pérez", 1.0, "San Isidro", "Centenario 500", hab[0], "Zona 6 - GBA Norte"),
      mk("98706", "E03A", "1012", "Cristalería Norte", 4.8, "Flores", "Rivadavia 7000", hab[1], "Zona 3 - CABA Oeste"),
      mk("98707", "E03A", "1013", "Bazar Mitre", 0.7, "Retira", "", hab[1], "Retira"),
      mk("98708", "E04A", "1014", "Coto Lanús", 1.9, "Lanús", "Yrigoyen 5000", hab[3], "Zona 4 - GBA Sur"),
      mk("98709", "E05A", "1015", "Ferretería Oeste", 6.0, "Morón", "Rivadavia 18000", hab[4], "Zona 5 - GBA Oeste"),
      mk("98710", "E06A", "1016", "Más Adelante SRL", 0.5, "Quilmes", "Mitre 300", new Date(hab[5].getTime() + 7 * 86400000), "Zona 4 - GBA Sur")
    ];
    window.fetch = (url) => {
      const u = String(url);
      if (u.indexOf("gv_ppp_programacion_diaria") >= 0) return J(rows);
      if (u.indexOf("gv_ppp_np_valor") >= 0) return J(rows.map((x) => ({ np: x.np, valor_lista: Math.round(x.m3 * 1000000), lineas_sin_precio: 0 })));
      if (u.indexOf("PPP_Geo") >= 0) return J([
        { dir_key: "__deposito_virgilio_2788__", lat: -34.65, lng: -58.5 },
        { dir_key: "alberdi 6000|mataderos", lat: -34.655, lng: -58.5 }, { dir_key: "montes de oca 1000|barracas", lat: -34.64, lng: -58.37 },
        { dir_key: "sáenz 1100|pompeya", lat: -34.65, lng: -58.41 }, { dir_key: "cafayate 4000|lugano", lat: -34.68, lng: -58.47 }
      ]);
      return J([]);
    };
    window._pppEmitError = function () {};
    window.getActivityStatus = async () => ({ pickingStarted: new Set(["E01A", "E01B"]), pickingDone: new Set(["E01A"]), armadoStarted: new Set(["E01A"]), armadoDone: new Set(["E01A"]), pickingEnCursoBy: new Map(), armadoEnCursoBy: new Map() });
    await pppLoadProgFromSupabase();
    await pppRefreshControlado(); await pppRefreshMetaEntSet(); await pppRefreshDelivered(); await pppRefreshEnSalida();
    await pppRefreshArmado(); await pppRefreshValor(); await pppRefreshGeo();
    _pppTab = "plan"; _pppPlanDay = null; _pppPlanClasica = false; pppRenderProg();
    let html = document.getElementById("pppPreview").innerHTML;
    const kpi = (l) => { const m = new RegExp('<div class="l">' + l + '</div><div class="v">([^<]*)</div>').exec(html); return m ? m[1] : null; };
    out.kpiPed = kpi("Pedidos"); out.kpiCam = kpi("Camiones"); out.kpiVol = kpi("Volumen"); out.kpiVal = kpi("Valor"); out.kpiAt = kpi("Atrasados");
    out.dias = (html.match(/class="pn-day(?: |")/g) || []).length;
    out.vacios = (html.match(/pn-day empty/g) || []).length;
    out.alerta = /pn-alert/.test(html) && /Pedidos atrasados/.test(html) && !/pn-alert warn/.test(html);
    out.hoyBadge = /class="hoy">HOY/.test(html) === (hab[0].getTime() === _pppKeyDate(_pppHoyKey()).getTime());
    out.dia1 = /Camión 1 · Zona 1 - CABA Sur/.test(html) && /Camión 2 · Zona 6 - GBA Norte/.test(html) && /\$ 6\.000\.000/.test(html);   // 3,7+0,8+0,9+0,6 m³ × 1 M
    out.retira = /Retira en fábrica/.test(html);
    out.masAdelante = /Más adelante:/.test(html) && /1 ped · 0,5 m³/.test(html);
    out.over = /al 100 % \(6,0 \/ 6,0 m³\)/.test(html) === false && !/pn-warn/.test(html);   // 6,0 = tope justo, sin aviso
    out.barra = /2 armados/.test(html) && /2 en curso/.test(html) && /1 sin empezar/.test(html);
    // adentro del día 1
    pppPlanAbrir(_pppDateKey(hab[0]));
    html = document.getElementById("pppPreview").innerHTML;
    out.volver = /Volver a los 6 días/.test(html);
    out.head = /class="d2">\d+ de [a-z]+</.test(html) && /VALOR ESTIMADO|Valor estimado/i.test(html) && /\$ 7\.000\.000/.test(html);
    out.orden = /1º Barracas/.test(html) && /4º Mataderos/.test(html) && /Recorrido: Mataderos → Lugano → Pompeya → Barracas/.test(html);
    const fila = (np) => { const i = html.indexOf(np + " · "); return i < 0 ? "" : html.slice(i, i + 900); };
    out.cargarAhora = /CARGAR AHORA/.test(fila("98702")) && /class="n go">1º/.test(fila("98702"));
    out.esperaTurno = /4º/.test(fila("98701")) && /espera su turno/.test(fila("98701"));
    out.faltaArmar = /2º/.test(fila("98703")) && /falta armar/.test(fila("98703")) && /En picking/.test(fila("98703"));
    out.sinOrdenNorte = /Camión 2 · Zona 6 - GBA Norte/.test(html) && /1º<\/span><span class="t">se carga primero/.test(html);
    out.bloques = /Tanda E01A/.test(html) && /Tanda E01B/.test(html) && /Tanda E02A/.test(html) && /ppp-tanda-h/.test(html);
    // vencidas
    pppPlanAbrir("venc");
    html = document.getElementById("pppPreview").innerHTML;
    out.venc = /Atrasados/.test(html) && /Vencida Uno/.test(html) && /Vencida Dos/.test(html) && !/Astorga/.test(html);
    // vista clásica y vuelta
    pppPlanClasica(true);
    html = document.getElementById("pppPreview").innerHTML;
    out.clasica = /ppp-sec-done/.test(html) && /Tablero de 6 días/.test(html) && !/pn-days/.test(html);
    pppPlanClasica(false); pppPlanVolver();
    out.vuelve = /pn-days/.test(document.getElementById("pppPreview").innerHTML);
    // día 2: Retira no cuenta como camión ni tiene orden de carga
    pppPlanAbrir(_pppDateKey(hab[1]));
    html = document.getElementById("pppPreview").innerHTML;
    out.dia2 = /class="l">Camiones<\/div><div class="v">1</.test(html) && /Retira en fábrica/.test(html) && !/Orden de carga/.test(html);
    return out;
  });

  const checks = [
    ["KPI pedidos 9 (6 días, sin vencidas ni más adelante)",  r.kpiPed === "9"],
    ["KPI camiones 5 (uno por zona y día; Retira no cuenta)", r.kpiCam === "5"],
    ["KPI volumen 20,4 m³",                                   r.kpiVol === "20,4 m³"],
    ["KPI valor $ 20.400.000",                                r.kpiVal === "$ 20.400.000"],
    ["KPI atrasados 2",                                       r.kpiAt === "2"],
    ["6 tarjetas de día, 2 vacías",                           r.dias === 6 && r.vacios === 2],
    ["cartel rojo de atrasados (sin el naranja: no hay sin controlar)", r.alerta === true],
    ["HOY sólo si hoy es hábil",                              r.hoyBadge === true],
    ["día 1: dos camiones por zona con $",                    r.dia1 === true],
    ["día 2: Retira en fábrica aparte",                       r.retira === true],
    ["más adelante: chip con el pedido fuera de los 6 días",  r.masAdelante === true],
    ["barra de estado del día 1",                             r.barra === true],
    ["adentro: botón volver",                                 r.volver === true],
    ["adentro: cabecera con fecha y $ del día",               r.head === true],
    ["orden de carga = recorrido al revés (1º Barracas)",     r.orden === true],
    ["1º armado → CARGAR AHORA",                              r.cargarAhora === true],
    ["4º armado → espera su turno",                           r.esperaTurno === true],
    ["2º en picking → falta armar",                           r.faltaArmar === true],
    ["camión de 1 pedido: 1º se carga primero",               r.sinOrdenNorte === true],
    ["las tandas del día siguen abajo con sus bloques",       r.bloques === true],
    ["vista de atrasados",                                    r.venc === true],
    ["vista clásica y vuelta al tablero",                     r.clasica === true && r.vuelve === true],
    ["día 2: Retira sin orden de carga ni camión",            r.dia2 === true],
    ["sin errores de página",                                 errs.length === 0]
  ];
  let bad = 0;
  for (const [name, ok] of checks) { console.log((ok ? "  ok   " : "  FALLA") + " · " + name); if (!ok) bad++; }
  if (bad) console.log("  detalle:", JSON.stringify(r));
  if (errs.length) console.log("  pageerror: " + errs.join(" | "));
  console.log(bad ? "ppp-plan-nueva: " + bad + " FALLA(S)" : "ppp-plan-nueva: OK (" + checks.length + " chequeos)");
  await b.close();
  process.exit(bad ? 1 : 0);
})();

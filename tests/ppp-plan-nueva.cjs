/* Regresión v13.03 — vista de UN DÍA de Programación + orden de carga LIFO (idea 5920).
   ⚠ El tablero de 6 días que media este test se ELIMINO en la v21.38 (Luis): ver la nota de abajo.
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
    const urlsSupers = [];        // para mirar QUÉ columnas pide el padrón de súper (problema 203)
    window.fetch = (url) => {
      const u = String(url);
      if (u.indexOf("gv_ppp_programacion_diaria") >= 0) return J(rows);
      // v13.53: una tanda WEB viene con fecha_entrega ISO ("2026-09-11") desde PPP_Web_Programacion y tiene
      // que caer en su día del tablero (antes caía en "después" y no se veía en ningún día).
      if (u.indexOf("PPP_Web_Programacion") >= 0) return J([
        { empresa: "lk", order_id: 1360, np_idx: 1, np: 1360, cod_cliente: "4321", razon_social: "Web Nueva SRL", direccion: "Pergamino 3751", barrio: "Soldati",
          zona: "Zona 1 - CABA Sur", tanda: "E09A", fecha_entrega: iso(hab[2]), fecha_recep: "2026-09-05", m3: 0.3, m3_parcial: false, lineas: 3, cajas: 5 }
      ]);
      if (u.indexOf("gv_ppp_np_valor") >= 0) return J(rows.map((x) => ({ np: x.np, valor_lista: Math.round(x.m3 * 1000000), lineas_sin_precio: 0 })));
      // ⚠ El padrón de súper: desde la v17.74 sale de la BASE (`gv_supers`), no del localStorage.
      // Sin este stub la lista queda vacía y el camión de Coto sale como "Cód 801" — el test medía
      // el nombre lindo y pasó a rojo cuando el padrón se mudó, sin que el tablero cambiara.
      if (u.indexOf("gv_supers") >= 0) { urlsSupers.push(u); return J([
        { empresa: "lk",   cod: "801", nombre: "Coto", super_key: "coto", cuit: "", nota: "Coto C.I.C.S.A." },
        { empresa: "chef", cod: "801", nombre: "Coto", super_key: "coto", cuit: "", nota: "Coto C.I.C.S.A." },
        { empresa: "lk",   cod: "802", nombre: "Carrefour", super_key: "carrefour", cuit: "", nota: "Inc Sociedad Anonima" }
      ]); }
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
    // El padrón de súper se siembra en la caché ANTES de dibujar: `pppSupersNeed()` lo trae por red
    // y resuelve después del render, así que con sólo stubear el fetch el primer dibujo sale con la
    // lista vacía y el camión de Coto queda como "Cód 801".
    // El padrón está por (empresa, cód), y la empresa del pedido sale de su NP cuando no la trae:
    // las NP cortas de esta fixture ("8", "9") resuelven a chef, así que Coto va bajo las dos —
    // un mismo súper puede estar en los dos padrones, y así el test no depende de ese detalle.
    _pppSupers = [
      { empresa: "lk",   cod: "801", nombre: "Coto", super_key: "coto", cuit: "", nota: "" },
      { empresa: "chef", cod: "801", nombre: "Coto", super_key: "coto", cuit: "", nota: "" },
      { empresa: "lk",   cod: "802", nombre: "Carrefour", super_key: "carrefour", cuit: "",
        nota: "Inc Sociedad Anonima" }
    ];
    _pppSupersTs = Date.now();     // para que no salga a pedirla de nuevo

    // ⚠ `_pppPlanTabla = false` a mano: desde la v17.66 la vista por DEFECTO de Programación es la
    // tabla día→tanda→NP, así que sin esta línea `pppRenderProg()` dibuja la tabla y este test —que
    // mide el tablero de 6 días— no encuentra nada. El tablero sigue existiendo (botón "Tablero de
    // 6 días" → `pppPlanTabla(false)`); lo que quedó viejo era el test.
    _pppTab = "plan"; _pppPlanDay = null; _pppPlanTabla = false; pppRenderProg();
    let html = document.getElementById("pppPreview").innerHTML;
    const kpi = (l) => { const m = new RegExp('<div class="l">' + l + '</div><div class="v">([^<]*)</div>').exec(html); return m ? m[1] : null; };
    out.kpiPed = kpi("Pedidos"); out.kpiCam = kpi("Camiones"); out.kpiVol = kpi("Volumen"); out.kpiVal = (function () { const m = /<div class="l">Valor<\/div><div class="v"><span class="full">([^<]*)<\/span><span class="short">([^<]*)<\/span>/.exec(html); return m ? m[1] + "|" + m[2] : null; })();   // v13.25: largo + corto (celular)
    out.kpiAt = kpi("Atrasados");   // v13.33: ya no existe en Programación → null
    out.kpiPedSub = (function () { const m = /<div class="l">Pedidos<\/div><div class="v">[^<]*<\/div><div class="s">([^<]*)<\/div>/.exec(html); return m ? m[1] : null; })();
    out.dias = (html.match(/class="pn-day(?: |")/g) || []).length;
    out.vacios = (html.match(/pn-day empty/g) || []).length;
    // v14.06 — la v13.33 había sacado los atrasados de Programación ("es un dato de gerencia") y el
    // dueño lo revirtió el 07/09: *"hoy para ver los pedidos atrasados tengo que entrar a control para
    // que me aparezca el botón que me lleve de nuevo a programación, una locura"*. Ahora la banda vive
    // acá y abre la lista en la misma solapa. Lo que sigue sin volver son los carteles grandes de la
    // v13.05/v13.25 (`pn-alert`, `pn-flags`) y la tarjeta-KPI de Atrasados.
    out.alerta = !/pn-alert/.test(html) && !/pn-flags/.test(html);
    // v14.11: la banda de atrasados y el botón de "cargados sin controlar" van en UNA fila (.pn-avisos)
    out.bandaVenc = /pn-venc-band/.test(html) && /pppPlanAbrir\('venc'\)/.test(html) && /2 atrasados/.test(html) && /pn-avisos/.test(html);
    out.hoyBadge = /class="hoy">HOY/.test(html) === (hab[0].getTime() === _pppKeyDate(_pppHoyKey()).getTime());
    out.dia1 = /Camión 1 · Zona 1 - CABA Sur/.test(html) && /Camión 2 · Zona 6 - GBA Norte/.test(html) && /\$ 6\.000\.000/.test(html);   // 3,7+0,8+0,9+0,6 m³ × 1 M
    out.retira = /Retira en fábrica/.test(html);
    out.masAdelante = /Más adelante:/.test(html) && /1 ped · 0,5 m³/.test(html);
    out.over = /al 100 % \(6,0 \/ 6,0 m³\)/.test(html) === false && !/pn-warn/.test(html);   // 6,0 = tope justo, sin aviso
    // v17.02 (pedido del dueño: "hacela más visible, poneles un porcentaje visible"): la leyenda
    // "2 armados · 2 en curso · 1 sin empezar" pasó a ser barra gruesa + los tres PORCENTAJES con
    // la cuenta de pedidos al lado. Sin backend (acá el REST está abortado) usa ese conteo.
    out.barra = /pn-bar big/.test(html) && /armado <em>\(2\)<\/em>/.test(html) &&
                /en curso <em>\(2\)<\/em>/.test(html) && /sin empezar <em>\(1\)<\/em>/.test(html);
    // adentro del día 1
    pppPlanAbrir(_pppDateKey(hab[0]));
    html = document.getElementById("pppPreview").innerHTML;
    out.volver = /Volver a los 6 días/.test(html);
    out.head = /class="d2">\d+ de [a-z]+</.test(html) && /VALOR ESTIMADO|Valor estimado/i.test(html) && /\$ 7\.000\.000/.test(html);
    // v13.36: el chip lleva el CÓD del cliente (1008 = Astorga, Barracas; 1007 = Cuyana, Mataderos);
    // el cliente y la localidad quedan en el title y ya no hay línea "Recorrido: …".
    out.orden = /title="Astorga Ng S\.A\. · Barracas · NP 98702">1º cód 1008</.test(html) && /4º cód 1007</.test(html) &&
      !/Recorrido:/.test(html) && !/1º Barracas/.test(html) && /Se carga primero el último que se entrega<\/div>/.test(html);
    const fila = (np) => { const i = html.indexOf(np + " · "); return i < 0 ? "" : html.slice(i, i + 900); };
    out.cargarAhora = /CARGAR AHORA/.test(fila("98702")) && /class="n go">1º/.test(fila("98702"));
    out.esperaTurno = /4º/.test(fila("98701")) && /espera su turno/.test(fila("98701"));
    out.faltaArmar = /2º/.test(fila("98703")) && /falta armar/.test(fila("98703")) && /En picking/.test(fila("98703"));
    // v13.13: con 1 pedido (o sin ubicaciones) no hay orden de carga ni "se carga primero"
    const _norte = html.slice(html.indexOf("Camión 2 · Zona 6 - GBA Norte"));
    out.sinOrdenNorte = /Camión 2 · Zona 6 - GBA Norte/.test(html) && !/Orden de carga/.test(_norte) && !/se carga primero/.test(_norte);
    out.bloques = /Tanda E01A/.test(html) && /Tanda E01B/.test(html) && /Tanda E02A/.test(html) && /ppp-tanda-h/.test(html);
    // vencidas
    pppPlanAbrir("venc");
    html = document.getElementById("pppPreview").innerHTML;
    // v13.46: las dos vencidas del fixture (D50E, D46E) nunca se armaron → alerta "NO salieron, reprogramar";
    // sin orden de carga en esta vista; la columna dice qué hacer.
    out.venc = /Atrasados/.test(html) && /Vencida Uno/.test(html) && /Vencida Dos/.test(html) && !/Astorga/.test(html) &&
      /pn-reprog/.test(html) && /⚠ 2 pedidos NO salieron — hay que reprogramarlos/.test(html) && (html.match(/NO SALIÓ/g) || []).length === 2 &&
      !/Orden de carga/.test(html) && /<span>Qué hacer<\/span>/.test(html) &&
      // v15.92 — el cartel "N pedidos con la tanda ARMADA y nadie registró la Carga Camión"
      // ahora sale SÓLO si N > 0 (antes se imprimía igual con 0, que era ruido). Las 2 vencidas
      // del fixture nunca se armaron → N = 0 → el cartel NO tiene que estar.
      !/pn-note/.test(html);
    // v20.24: la vista clásica se borró; queda la vuelta al tablero
    pppPlanVolver();
    html = document.getElementById("pppPreview").innerHTML;
    out.vuelve = /pn-days/.test(html);
    // v13.17: "Ver hoja 2 →" pagina de a 6 hábiles; "Más Adelante SRL" (hábil 11) cae en la hoja 2 y deja de ser chip
    out.hoja1Btn = /Ver hoja 2 →/.test(html) && !/← Hoja/.test(html);
    pppPlanHoja(1);
    html = document.getElementById("pppPreview").innerHTML;
    out.hoja2 = (html.match(/class="pn-day(?: |")/g) || []).length === 6 && (html.match(/pn-day empty/g) || []).length === 5 &&
      /Hoja 2 · /.test(html) && /← Hoja 1/.test(html) && /Ver hoja 3 →/.test(html) && !/Más adelante:/.test(html) && kpi("Pedidos") === "11" && /1 en la hoja 2 · 10 después/.test(html);
    pppPlanHoja(0);
    html = document.getElementById("pppPreview").innerHTML;
    out.hoja1Vuelve = /Próximos 6 días hábiles/.test(html) && /Más adelante:/.test(html) && kpi("Pedidos") === "11";
    // v13.33: los atrasados se miran desde Resumen
    // v14.29: la barra de solapas se pinta APARTE, en #pppTabsBar (fuera de #pppPreview y del zoom),
    // así que el contador de la solapa se lee de ahí, no del preview.
    pppPaintTabs();
    out.tabPlanN = />🗓️ Programación \(11\)</.test((document.getElementById("pppTabsBar") || {}).innerHTML || "");
    _pppTab = "resumen"; pppRenderProg();
    html = document.getElementById("pppPreview").innerHTML;
    out.resumenVenc = /pedido\(s\) con fecha de entrega vencida/.test(html);
    _pppTab = "plan"; pppRenderProg();
    // día 2: Retira no cuenta como camión ni tiene orden de carga
    pppPlanAbrir(_pppDateKey(hab[1]));
    html = document.getElementById("pppPreview").innerHTML;
    out.dia2 = /class="l">Camiones<\/div><div class="v">1</.test(html) && /Retira en fábrica/.test(html) && !/Orden de carga/.test(html);
    // v13.53: la tanda web (fecha ISO) está en el día 3 con su etiqueta LK 1360
    pppPlanVolver(); pppPlanAbrir(_pppDateKey(hab[2]));
    html = document.getElementById("pppPreview").innerHTML;
    out.webDia3 = /Tanda E09A/.test(html) && /LK 1360/.test(html) && /Web Nueva SRL/.test(html);
    pppPlanVolver();
    // v13.07 (idea 7317): camión = número de tanda; una tanda que mezcla zonas vecinas se etiqueta "Zona 1 + Zona 2".
    const cams = _pppCamiones([
      { np: "1", tanda: "E01A", m3: 0.3, zona: "Zona 1 - CABA Sur", barrio: "Barracas" },
      { np: "2", tanda: "E01A", m3: 0.2, zona: "Zona 2 - CABA Centro", barrio: "Constitucion" },
      { np: "3", tanda: "E01B", m3: 0.4, zona: "Zona 3 - CABA Oeste", barrio: "Flores" },
      { np: "4", tanda: "E02A", m3: 0.5, zona: "Zona 6 - GBA Norte", barrio: "Munro" },
      { np: "5", tanda: "", m3: 0.1, zona: "Zona 4 - GBA Sur", barrio: "Lanús" },
      { np: "6", tanda: "E01C", m3: 0.1, zona: "Retira", barrio: "Retira" },
      { np: "7", tanda: "F01A", m3: 0.2, zona: "Zona 1 - CABA Sur", barrio: "Boedo" },   // v13.16: Chef, misma NN que LK → otro camión
      { np: "8", tanda: "D59A", m3: 8.9, zona: "", tipo: "KRIKOS", barrio: "", cod: "801" },   // v13.35: cód en la lista de súper → va su nombre
      { np: "9", tanda: "D61A", m3: 3.0, zona: "", tipo: "KRIKOS", barrio: "", razon_social: "Inc Sociedad Anonima" },   // v13.37: sin cód, se reconoce por la razón social vieja → Carrefour
      { np: "10", tanda: "D63A", m3: 1.0, zona: "", tipo: "KRIKOS", barrio: "" }         // v13.35: sin nombre ni cód → "Súper" como antes
    ]);
    out.porTanda = cams.map((c) => _pppCamionNombre(c) + "|" + c.tandas.join("+") + "|" + c.ped.length).join(" ; ");

    // v17.97 (problema 203): el padrón que la app PIDE tiene que traer `nota`, si no el fallback
    // por razón social de arriba es letra muerta. Se mide contra la lista que queda en memoria
    // después de una lectura real (no la sembrada a mano).
    _pppSupers = null; _pppSupersTs = 0; _pppSupersBusy = false;
    try { localStorage.removeItem(PPP_SUPER_KEY); } catch (_e) {}
    pppSupersNeed(true);
    await new Promise((res) => setTimeout(res, 200));
    out.urlSupers = urlsSupers[0] || null;
    out.notaViaja = (pppLoadSupers().find((s) => s.cod === "802") || {}).nota === "Inc Sociedad Anonima";
    return out;
  });

  // ⚠ v21.49 — la v21.38 saco el TABLERO DE 6 DIAS (Luis: "elimina esa visual") y actualizo
  // cuatro tests, pero no este: sus 18 chequeos del tablero (los KPI, las tarjetas de dia, las
  // hojas 1 y 2, la banda de atrasados y la vuelta al tablero) median algo que ya no se dibuja,
  // asi que CI quedo en rojo desde entonces. Se van con el tablero; el que sigue vivo es el
  // orden de carga LIFO y la vista de UN DIA, que es lo que mide de aca en adelante.
  // Lo que se saco y donde quedo cubierto: la banda de atrasados y el cartel de Resumen, en
  // ppp-atrasados y ppp-atrasados-un-criterio (v21.37); la vista de vencidos, en ppp-crn-auto.
  const checks = [
    ["v13.53: la tanda web con fecha ISO se ve en su día (Tanda E09A · LK 1360)", r.webDia3 === true],
    ["sin los carteles grandes de la v13.05/v13.25 (pn-alert / pn-flags)", r.alerta === true],
    ["adentro: cabecera con fecha y $ del día",               r.head === true],
    ["v13.36: orden de carga por CÓD de cliente (1º cód 1008), sin línea de recorrido", r.orden === true],
    ["1º armado → CARGAR AHORA",                              r.cargarAhora === true],
    ["4º armado → espera su turno",                           r.esperaTurno === true],
    ["2º en picking → falta armar",                           r.faltaArmar === true],
    ["camión de 1 pedido: sin orden de carga (v13.13)",       r.sinOrdenNorte === true],
    ["las tandas del día siguen abajo con sus bloques",       r.bloques === true],
    ["día 2: Retira sin orden de carga ni camión",            r.dia2 === true],
    ["v13.07/v13.35: camión = n° de tanda, zonas mezcladas, y el súper con el NOMBRE del cliente",
     r.porTanda === "Camión 1 · Zona 1 + Zona 2 + Zona 3|E01A+E01B|3 ; Camión 2 · Zona 1 - CABA Sur|F01A|1 ; Sin tanda · Zona 4 - GBA Sur||1 ; Camión 3 · Zona 6 - GBA Norte|E02A|1 ; Camión 4 · Coto|D59A|1 ; Camión 5 · Carrefour|D61A|1 ; Camión 6 · Súper|D63A|1 ; Retira en fábrica|E01C|1"],
    ["problema 203: el padrón de súper pide `nota` (si no, el fallback por razón social es letra muerta)",
     typeof r.urlSupers === "string" && /[?&]select=[^&]*\bnota\b/.test(r.urlSupers)],
    ["problema 203: y `nota` llega a la lista en memoria, no se pierde en el .map()", r.notaViaja === true],
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

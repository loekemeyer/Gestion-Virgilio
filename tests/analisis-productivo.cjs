/* v29.83 — ANÁLISIS PRODUCTIVO POR TANDA (Luis, 13/10/2026). Corre la pantalla de verdad
   (analisis.js dentro de index.html) con las RPC mockeadas y mide:
     (a) el botón está en el panel del supervisor y abre la pantalla;
     (b) la lista: una tarjeta por tanda, con el rendimiento en color y el chip de avisos duros;
     (c) el detalle: veredicto en una línea, avisos ordenados por severidad, el rendimiento de
         picking y armado, y la tabla código por código con «frente a la góndola» y «veces lo normal»;
     (d) una lectura ROTA se dice, no se dibuja como «sin tandas» (regla de la v18, §lectura rota);
     (e) el botón del módulo de operarios aparece SÓLO si gv_analisis_acceso_ok devuelve true, y
         cuando aparece manda el legajo;
     (f) el overlay no hereda el button{width:100%} global del index;
     (g) el SISTEMA DE DISEÑO «GV-UI» (regla del CLAUDE.md), que esta pantalla sostiene:
         el dato principal es el texto más grande de la pantalla · el veredicto es UNA línea ·
         nada de lo explicativo se dibuja abierto (va en <details>) · sin emojis decorativos;
     (j) v30.20 (Luis, 13/10): abre en el DÍA DE LA FECHA (p_dias 1) y el botón «Días anteriores»
         pide 30+1 días y saca las tandas de hoy (el «hoy» es el `hasta` del servidor).
         v30.21: la barra tiene SÓLO esos dos botones de período («Hoy» / «Días anteriores»).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

const LISTA = {
  desde: "2026-09-30", hasta: "2026-10-13",
  tandas: [
    { tanda: "F77A", dia: "2026-10-13", m3: 0.667, alerta: 0, n_falto: 0, n_paso: 0,
      pick: { legajo: "277", nombre: "Jhonny Cartaya", ts: "2026-10-13T10:13:21-03:00", indice: 1.186, grado: 2, nivel: "Baja", esperado_min: 17.8, real_min: 15, lineas: 7, cajas: 97 },
      arm: null },
    { tanda: "F13C", dia: "2026-10-06", m3: 1.2, alerta: 2, n_falto: 1, n_paso: 1,
      pick: { legajo: "104", nombre: "J. Colombia", ts: "2026-10-06T11:40:00-03:00", indice: 0.62, grado: 7, nivel: "Alta", esperado_min: 40, real_min: 64, lineas: 12, cajas: 55 },
      arm: { legajo: "8", nombre: "Farias Juan Hilario", ts: "2026-10-06T15:00:00-03:00", indice: 1.05, grado: 4, nivel: "Media", esperado_min: 50, real_min: 47.6, nps: 3 } }
  ]
};
const DET = {
  tanda: "F13C",
  cabecera: { tanda: "F13C", nps: ["LK 0101", "LK 0102"], clientes: ["Bazar Monica SRL"], m3: 1.2, zona: "Zona 2 - CABA Centro", fecha_entrega: "2026-10-08" },
  picking: { legajo: "104", nombre: "J. Colombia", ep: "2026-10-06T10:30:00-03:00", tp: "2026-10-06T11:40:00-03:00",
    lineas: 12, cajas: 55, paradas: 8, esc: 3, n_mx: 1, n_f: 0, grado: 7, nivel: "Alta", dificultad: 0.37,
    multiplicador: 1.2, esperado_min: 40, est_ini_min: 42, bruto_min: 70, pausa_min: 4, huecos_min: 6,
    cola_min: 4, cola_tipo: "sig", real_min: 64, indice: 0.62, m3_h: 1.13, cajas_h: 51.6, lineas_h: 11.3,
    seg_linea: 320, prom_grado: 0.98, prom_operario: 1.1 },
  armado: { legajo: "8", nombre: "Farias Juan Hilario", ap: "2026-10-06T14:10:00-03:00", tap: "2026-10-06T15:00:00-03:00",
    nps: 3, lineas: 12, cajas: 55, super: false, grado: 4, nivel: "Media", esperado_min: 50, est_ini_min: 48,
    bruto_min: 50, pausa_min: 0, cola_min: 0, real_min: 47.6, indice: 1.05, m3_h: 1.51, cajas_h: 69.3, prom_grado: 1.0 },
  lineas: [
    { orden: 1, cod: "865E", ck: "865E", desc: "Rallador Plano", ts: "2026-10-06T10:35:00-03:00", pedidas: 6, cajas: 6,
      seg: 30, seg_caja: 5, base_n: 40, base_seg: 28, med_seg: 33, med_seg_caja: 8, esp_seg: 50.4, ratio: 0.6,
      seg_vista: 1.2, visitas: 1, confirmaciones: 1, sector: "L57", es_exc: false, accion: "ok", falto_armado: 1 },
    { orden: 2, cod: "437E CH", ck: "437E", desc: "Colador 16cm", ts: "2026-10-06T10:50:00-03:00", pedidas: 2, cajas: 2,
      seg: 900, seg_caja: 450, base_n: 64, base_seg: 28.4, med_seg: 33.7, med_seg_caja: 18.1, esp_seg: 35.9, ratio: 25,
      seg_vista: 880, visitas: 2, confirmaciones: 2, sector: "L07 · L08", es_exc: false, accion: "ok", falto_armado: 0 }
  ],
  avisos: [
    { tipo: "falto_en_armado", sev: "alta", peso: 95, texto: "El picking dio por completo 1 codigo(s) que el armado despues declaro faltante: 865E (faltaron 1 cj)" },
    { tipo: "paso_relampago", sev: "alta", peso: 90, texto: "Hay 1 codigo(s) confirmados a menos de 2 segundos de que la pantalla los mostro: 865E (1.2 s, 6 cj)" },
    { tipo: "ritmo_bajo", sev: "media", peso: 70, texto: "El picking tardo 161 % de lo esperado para su dificultad (alta, grado 7)." },
    { tipo: "huecos", sev: "media", peso: 45, texto: "El picking tiene 6 min en huecos de mas de 5 minutos sin confirmar nada." }
  ],
  conteo: [], registro_por_paso: true, nota_paso: null
};

(async () => {
  const b = await chromium.launch();
  const p = await (await b.newContext({ viewport: { width: 1280, height: 900 }, serviceWorkers: "block" })).newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async ({ LISTA, DET }) => {
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    for (let i = 0; i < 60 && typeof window.openAnalisisProductivo !== "function"; i++) await espera(100);
    const out = { pedidos: [] };
    if (typeof window.openAnalisisProductivo !== "function") { out.sinModulo = true; return out; }
    let modo = "ok", acceso = true, badgeRoto = false;
    window.sb = { rpc: async (n, a) => {
      out.pedidos.push(n + ":" + JSON.stringify(a || {}));
      if (n === "gv_analisis_acceso_ok") return { data: acceso, error: null };
      if (modo === "roto") return { data: null, error: { message: "canceling statement due to statement timeout" } };
      if (n === "gv_analisis_lista") return { data: LISTA, error: null };
      if (n === "gv_analisis_tanda") return { data: DET, error: null };
      if (n === "gv_analisis_marcas") return { data: {}, error: null };
      if (n === "gv_analisis_badge") return badgeRoto ? { data: null, error: { message: "timeout" } }
                                                     : { data: { pendientes: 3, con_aviso: 5, anomalas: 1 }, error: null };
      if (n === "gv_analisis_marcar") return { data: { ok: true }, error: null };
      return { data: null, error: { message: "?" } };
    } };

    // (i) el badge del botón: cuenta las tandas con avisos sin revisar
    await window.anLoadBadge("8"); await espera(60);
    const bd = document.getElementById("anBadge");
    out.badge = bd && bd.style.display !== "none" ? bd.textContent : "";
    out.badgeTitle = bd ? bd.title : "";
    badgeRoto = true; await window.anLoadBadge("8"); await espera(60);
    out.badgeTrasRoto = bd && bd.style.display !== "none" ? bd.textContent : "";
    badgeRoto = false;

    // (a) botón del panel
    const btn = [...document.querySelectorAll(".sup-action-btn")].find((x) => /openAnalisisProductivo/.test(x.getAttribute("onclick") || ""));
    out.botonPanel = !!btn && /An[áa]lisis Productivo/.test(btn.textContent);

    window.openAnalisisProductivo(); await espera(120);
    out.abierto = (document.getElementById("anOv") || {}).style ? document.getElementById("anOv").style.display : "";
    // (j) abre en el día
    out.pideHoy = out.pedidos.filter((x) => /^gv_analisis_lista:/.test(x)).pop() || "";
    const modos = () => [...document.querySelectorAll("#anOv .an-bar [onclick^='anModo'], #anOv .an-bar [onclick^='anDias']")]
      .map((x) => x.textContent.trim() + (x.classList.contains("on") ? "*" : ""));
    out.modosHoy = modos().join("|");

    // (b) lista
    const t = [...document.querySelectorAll("#anOv .an-t")];
    out.tarjetas = t.length;
    out.primera = t[0] ? t[0].querySelector(".cod").textContent : "";
    out.alerta = t[1] ? (t[1].querySelector(".gv-badge") || {}).textContent || "" : "";
    out.sinAlerta = t[0] ? !t[0].querySelector(".gv-badge") : false;
    out.lineasTarjeta = t[1] ? [...t[1].querySelectorAll(".l")].map((x) => x.textContent.trim()) : [];
    out.rotulos = t[1] ? [...t[1].querySelectorAll(".l .q")].map((x) => x.textContent.trim()) : [];
    out.rojoBajo = t[1] ? /rgb\(185, 28, 28\)/.test(window.getComputedStyle(t[1].querySelector(".l .r")).color) : false;

    // (c) detalle
    t[1].click(); await espera(120);
    out.avisos = [...document.querySelectorAll("#anOv .gv-item")].map((x) => x.className.replace("gv-item ", "") + "|" + x.textContent.slice(0, 22));
    out.avisoTexto = (document.querySelector("#anOv .gv-item span:last-child") || {}).textContent || "";
    out.cards = [...document.querySelectorAll("#anOv .an-kpi div span")].map((x) => x.textContent.trim());
    out.secciones = [...document.querySelectorAll("#anOv summary")].map((x) => x.textContent.trim().slice(0, 28));
    out.cols = [...document.querySelectorAll("#anOv th")].map((x) => x.innerHTML.replace(/<br>/g, " ").replace(/\s+/g, " ").trim());
    const filas = [...document.querySelectorAll("#anOv tbody tr")];
    out.filas = filas.length;
    out.malas = filas.filter((f) => f.classList.contains("mala")).map((f) => f.cells[1].textContent);
    out.f1 = filas[0] ? [...filas[0].cells].map((c) => c.textContent.trim()) : [];
    out.primeraFila = filas[0] ? filas[0].cells[1].textContent.trim() : "";
    out.difFila = filas[0] ? filas[0].cells[7].textContent.trim() : "";
    out.volver = !!document.querySelector("#anOv .an-top button[onclick='anVolver()']");
    out.concl = (document.querySelector("#anOv .gv-state .v") || {}).textContent || "";
    out.mkBotones = document.querySelectorAll("#anOv .an-mk-b").length;

    // (g) SISTEMA DE DISEÑO «GV-UI» — lo que esta pantalla tiene que sostener
    const vis = (e) => e.offsetParent !== null || e === document.body;
    const px = (e) => parseFloat(window.getComputedStyle(e).fontSize) || 0;
    const hero = document.querySelector("#anOv .an-hero .big");
    out.heroTxt = hero ? hero.textContent.trim() : "";
    out.heroPx = hero ? px(hero) : 0;
    // 1) el dato principal es el texto MÁS GRANDE que se ve
    out.mayor = 0; out.mayorQ = "";
    [...document.querySelectorAll("#anOv *")].forEach((e) => {
      if (!vis(e) || !e.textContent.trim() || e.children.length) return;
      const f = px(e);
      if (f > out.mayor) { out.mayor = f; out.mayorQ = e.className + ":" + e.textContent.trim().slice(0, 14); }
    });
    // 2) el veredicto es UNA línea corta
    out.veredictoLargo = out.concl.length;
    // 3) nada explicativo abierto: ningún texto suelto largo fuera de <details>
    out.sueltoLargo = [...document.querySelectorAll("#anOv .an-body *")]
      .filter((e) => vis(e) && !e.children.length && !e.closest("details") && e.textContent.trim().length > 150)
      .map((e) => e.textContent.trim().slice(0, 40));
    // 4) el glosario existe y arranca PLEGADO
    const gl = [...document.querySelectorAll("#anOv details")].find((d) => /Cómo se leen/.test(d.textContent));
    out.glosario = !!gl && !gl.open;
    // 5) sin emojis decorativos (regla «MENOS EMOJIS»): sólo los del dato
    out.emojis = (document.querySelector("#anOv .an-body").textContent.match(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/gu) || []).join("");

    window.prompt = () => "no contó";
    await window.anMarcar("anomala"); await espera(60);
    out.marcado = out.pedidos.filter((x) => /gv_analisis_marcar/.test(x))[0] || "";
    out.chipTrasMarcar = /ANÓMALA/.test((document.querySelector("#anOv .gv-state") || {}).textContent || "");

    // (h) los filtros de la lista
    window.anVolver(); await espera(60);
    out.filtroTodas = document.querySelectorAll("#anOv .an-t").length;
    window.anFiltro("avisos"); await espera(40);
    out.filtroAvisos = document.querySelectorAll("#anOv .an-t").length;
    window.anFiltro("marcadas"); await espera(40);
    out.filtroMarcadas = document.querySelectorAll("#anOv .an-t").length;
    window.anFiltro("todas"); await espera(40);
    // (j) días anteriores
    document.getElementById("anBtnAnt").click(); await espera(80);
    out.pideAnt = out.pedidos.filter((x) => /^gv_analisis_lista:/.test(x)).pop() || "";
    out.antTandas = [...document.querySelectorAll("#anOv .an-t .cod")].map((x) => x.textContent);
    out.modosAnt = modos().join("|");
    document.getElementById("anBtnHoy").click(); await espera(80);
    out.volvioHoy = modos().join("|") === "Hoy*|Días anteriores" && /"p_dias":1\b/.test(out.pedidos.filter((x) => /^gv_analisis_lista:/.test(x)).pop() || "");
    // (k) carrera: pedir «hoy» y cambiar a «ant» sin esperar la respuesta. El token descarta la
    // respuesta vieja; antes el `if (cargando) return` dejaba «hoy» pintado bajo modo «ant» (falso vacío).
    window._anCargar(); window.anModo("ant"); await espera(140);
    out.raceModo = modos().join("|");
    out.racePide = out.pedidos.filter((x) => /^gv_analisis_lista:/.test(x)).pop() || "";
    out.raceCods = [...document.querySelectorAll("#anOv .an-t .cod")].map((x) => x.textContent).join(",");
    window.anModo("hoy"); await espera(80);
    _an.tanda = "F13C"; _an.det = DET; _anRender(); await espera(40);

    // (f) el botón Cerrar no hereda el width:100% global
    const cer = [...document.querySelectorAll("#anOv .an-top button")].pop();
    out.btnAncho = cer ? window.getComputedStyle(cer).width : "";

    // (d) lectura rota
    window.anVolver(); modo = "roto"; window._anCargar(); await espera(120);
    out.rota = (document.querySelector("#anOv .gv-err") || {}).textContent || "";
    out.rotaNoVacio = !/No hay tandas/.test(document.querySelector("#anOv .an-body").textContent);
    modo = "ok";
    window.anCerrar();

    // (e) el botón del operario
    const bop = document.getElementById("btnAnalisisOp");
    out.opExiste = !!bop;
    acceso = false; await window.anMostrarBotonOperario("277"); await espera(80);
    out.opOculto277 = bop ? bop.style.display === "none" : false;
    acceso = true; await window.anMostrarBotonOperario("8"); await espera(80);
    out.opVisible8 = bop ? bop.style.display !== "none" : false;
    out.opLegajo = bop ? bop.getAttribute("data-legajo") : "";
    return out;
  }, { LISTA, DET });

  await b.close();
  const fallos = [];
  const ok = (c, m) => { if (!c) fallos.push(m); };
  if (r.sinModulo) { console.error("ANÁLISIS PRODUCTIVO — FALLA:\n  analisis.js no se cargó: openAnalisisProductivo no existe."); process.exit(1); }
  ok(r.badge === "3", "(i) el badge dice «" + r.badge + "» (esperaba 3)");
  ok(/sin revisar/.test(r.badgeTitle), "(i) el badge no explica qué cuenta: " + r.badgeTitle);
  ok(r.badgeTrasRoto === "3", "(i) una lectura rota APAGÓ el badge (quedó «" + r.badgeTrasRoto + "»)");
  ok(r.botonPanel, "(a) falta el botón «Análisis Productivo» en el panel del supervisor");
  ok(r.abierto === "flex", "(a) la pantalla no se abrió");
  ok(/"p_dias":1\b/.test(r.pideHoy), "(j) no abre en el día: pidió " + r.pideHoy);
  ok(r.modosHoy === "Hoy*|Días anteriores", "(j) la barra de período es «" + r.modosHoy + "» (esperaba sólo Hoy* | Días anteriores)");
  ok(/"p_dias":31\b/.test(r.pideAnt), "(j) «Días anteriores» pidió " + r.pideAnt + " (esperaba 30 + hoy = 31)");
  ok(r.antTandas.join() === "F13C", "(j) en días anteriores quedan " + r.antTandas.join() + " (esperaba sólo F13C, sin la de hoy)");
  ok(r.modosAnt === "Hoy|Días anteriores*", "(j) en días anteriores la barra es «" + r.modosAnt + "»");
  ok(r.volvioHoy, "(j) «Hoy» no vuelve a la vista del día");
  ok(/"p_dias":31\b/.test(r.racePide), "(k) cambiar a «Días anteriores» durante una carga no disparó su lectura: " + r.racePide);
  ok(r.raceModo === "Hoy|Días anteriores*", "(k) tras la carrera la barra quedó «" + r.raceModo + "» (esperaba ant activo)");
  ok(r.raceCods === "F13C", "(k) la carrera dejó la lista en «" + r.raceCods + "» (esperaba sólo F13C: ni falso vacío ni datos de hoy)");
  ok(r.tarjetas === 2, "(b) tarjetas: " + r.tarjetas + " (esperaba 2)");
  ok(r.primera === "F77A", "(b) la primera tanda es " + r.primera);
  ok(r.alerta.indexOf("2") >= 0, "(b) F13C tendría que mostrar ⚠ 2, muestra «" + r.alerta + "»");
  ok(r.sinAlerta, "(b) F77A no tiene avisos y le puso el ⚠");
  ok(/Jhonny|Colombia/.test(r.lineasTarjeta.join(" ")), "(b) la tarjeta no nombra al operario");
  ok(r.rotulos.join("|").toUpperCase() === "PICK|ARM", "(b) la tarjeta no trae las dos fases rotuladas: " + JSON.stringify(r.rotulos));
  ok(r.avisos.length === 4 && /^alta/.test(r.avisos[0]), "(c) avisos: " + JSON.stringify(r.avisos));
  ok(/códigos?/.test(r.avisoTexto) && !/\(s\)/.test(r.avisoTexto),
     "(c) el aviso sale sin acentuar o con el «(s)» crudo de la base: «" + r.avisoTexto + "»");
  ok(r.secciones.length === 4 && /Picking/.test(r.secciones[0]) && /Armado/.test(r.secciones[1]) &&
     /C.digo por c.digo/.test(r.secciones[2]) && /C.mo se leen/.test(r.secciones[3]),
     "(c) las secciones plegadas: " + JSON.stringify(r.secciones));
  ok(/2 hallazgos fuertes/.test(r.concl), "(h) el veredicto no dice qué hacer: «" + r.concl + "»");
  ok(r.mkBotones === 2, "(h) la barra de marcar tendría que tener 2 botones sin marca, tiene " + r.mkBotones);
  ok(/anomala/.test(r.marcado) && /F13C/.test(r.marcado), "(h) 🚩 no llamó bien a gv_analisis_marcar: " + r.marcado);
  ok(r.chipTrasMarcar, "(h) después de marcar no quedó el cartel de anómala");
  ok(r.filtroMarcadas === 1 && r.filtroAvisos === 1 && r.filtroTodas === 2,
     "(h) los filtros: marcadas=" + r.filtroMarcadas + " avisos=" + r.filtroAvisos + " todas=" + r.filtroTodas);
  ok(r.cards.join(" ").indexOf("rendimiento") >= 0 && r.cards.join(" ").indexOf("dificultad") >= 0,
     "(c) faltan las tarjetas de rendimiento y dificultad: " + JSON.stringify(r.cards));
  ok(r.cols.join("|").indexOf("Frente a la góndola") >= 0, "(c) falta la columna «Frente a la góndola»: " + JSON.stringify(r.cols));
  ok(["Esperado", "Real", "Dif"].every(function (c) { return r.cols.indexOf(c) >= 0; }),
     "(c) faltan las columnas Esperado/Real/Dif del ítem por ítem: " + JSON.stringify(r.cols));
  ok(/−|-/.test(r.difFila) && r.difFila !== "—", "(c) la columna Dif no muestra la diferencia con signo: «" + r.difFila + "»");
  ok(/^(437E|865E)/.test(r.primeraFila), "(c) la tabla no ordenó por la diferencia más grande arriba: " + r.primeraFila);
  ok(r.filas === 2, "(c) filas de la tabla: " + r.filas);
  ok(r.malas.length === 2, "(c) las dos líneas raras tendrían que ir marcadas, van " + r.malas.length);
  ok(/timeout/.test(r.rota) && r.rotaNoVacio, "(d) una lectura rota no se dijo: «" + r.rota + "»");
  ok(r.opExiste, "(e) falta el botón #btnAnalisisOp en la botonera");
  ok(r.opOculto277, "(e) el botón se mostró para un legajo sin acceso");
  ok(r.opVisible8 && r.opLegajo === "8", "(e) el botón no se mostró para el legajo habilitado");
  ok(r.pedidos.some((x) => /gv_analisis_tanda.*F13C/.test(x)), "(c) no pidió el detalle de la tanda");
  ok(r.btnAncho && parseFloat(r.btnAncho) < 300, "(f) el botón Cerrar salió de " + r.btnAncho + " (hereda el width:100% global)");
  // (g) el sistema de diseño
  ok(r.heroPx >= 34, "(g) el dato principal está chico: " + r.heroPx + "px (mínimo 34)");
  ok(r.mayor <= r.heroPx, "(g) hay un texto MÁS GRANDE que el dato principal (" + r.mayor + "px en «" + r.mayorQ +
     "» contra " + r.heroPx + "px del rendimiento)");
  ok(r.veredictoLargo > 0 && r.veredictoLargo <= 64, "(g) el veredicto no entra en una línea: " + r.veredictoLargo + " caracteres");
  ok(!r.sueltoLargo.length, "(g) hay texto explicativo largo SIN plegar: " + JSON.stringify(r.sueltoLargo));
  ok(r.glosario, "(g) falta el glosario «Cómo se leen estos números», o arranca abierto");
  ok(!r.emojis, "(g) emojis decorativos en el detalle: " + r.emojis);
  if (errs.length) fallos.push("errores de página: " + errs.join(" · "));

  if (fallos.length) { console.error("ANÁLISIS PRODUCTIVO — FALLA:\n  " + fallos.join("\n  ")); process.exit(1); }
  console.log("analisis-productivo OK — lista, detalle, avisos, lectura rota, botón del operario y el sistema GV-UI.");
})();

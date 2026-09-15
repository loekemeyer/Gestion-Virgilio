/* Regresión v13.62 — "En Salida" tiene que mostrar la FECHA EN QUE SE CARGÓ EL CAMIÓN
   y el ESTADO de cada nota de pedido (pedido del dueño, 2026-09-06), y tiene que listar
   también las NP facturadas SIN evento CCN (98665 / 98502 / 98569), que antes se perdían.
   Además: la Recepción de Remitos embebida (tildar Controlado, ↩ s/salida) sólo aparece
   para supervisores; el módulo RR de arriba no se toca.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado (/opt/node22/lib/node_modules/playwright)."); process.exit(2); }
}

(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    const SRC = document.documentElement.innerHTML;
    // Dos filas como las que devuelve gv_ppp_en_salida v13.60: una cargada al camión y
    // una facturada sin registro de carga (el caso que motivó el cambio).
    const filas = [
      { np: "98602", empresa: "lk", es_web: false, tanda: "D53F", cod_cliente: "3915",
        razon_social: "Haidezer Sa", m3: 0.224, fecha_entrega: "2026-09-03", zona: "Zona 1 - CABA Sur",
        barrio: "Barracas", fecha_carga: "2026-09-03", cargado_at: "2026-09-03T17:20:00-03:00",
        facturada: true, armada: true, armado_at: "2026-09-03T11:00:00-03:00",
        cargada: true, control_previo: true, facturada_el: "2026-09-02",
        estado: "cargada", dias_sin_controlar: 3, camionero: "Guillermo" },
      { np: "98665", empresa: "lk", es_web: false, tanda: "D50E", cod_cliente: "2193",
        razon_social: "Merajver Marcelo Fabian", m3: 0.042, fecha_entrega: "2026-09-02", zona: "Zona 1 - CABA Sur",
        barrio: "Pompeya", fecha_carga: null, cargado_at: null,
        facturada: true, armada: true, armado_at: "2026-09-02T10:00:00-03:00",
        cargada: false, control_previo: false, facturada_el: "2026-09-01",
        // v18.09: sin camionero — es lo normal en un RETIRA y en las cargas anteriores a la v11.47
        estado: "facturada_sin_cargar", dias_sin_controlar: 4, camionero: null, zona: "Retira" },
      // v18.09: MISMO día que la 98602, y sin fletero — así el desglose del día tiene las dos
      // cosas y se puede ver que el "sin fletero" va al final. Con las dos filas de arriba solas
      // no servía: caen en días distintos y cada resumen tenía un solo tipo.
      { np: "98603", empresa: "lk", es_web: false, tanda: "D53F", cod_cliente: "3915",
        razon_social: "Haidezer Sa", m3: 0.1, fecha_entrega: "2026-09-03", zona: "Retira en fábrica",
        barrio: "Barracas", fecha_carga: "2026-09-03", cargado_at: "2026-09-03T18:00:00-03:00",
        facturada: true, armada: true, armado_at: "2026-09-03T11:00:00-03:00",
        cargada: true, control_previo: true, facturada_el: "2026-09-02",
        estado: "cargada", dias_sin_controlar: 3, camionero: null }
    ];
    // OJO: estas son `let` en el <script> (binding global declarativo), NO propiedades
    // de window. Hay que asignarlas SIN `window.` o el módulo sigue viendo su null.
    _pppEnSalida = new Map(filas.map((f) => [String(f.np), f]));
    _pppDelivered = [];
    _pppMetaEntSet = new Set();
    _pppSearch = "";
    _pppEsSel = new Set();

    // ── 1) Como OPERARIO (no supervisor): datos sí, acciones no ──────────────
    window.__isSupervisor = false;
    const hOp = _pppEnViajeHtml();

    // ── 2) Como SUPERVISOR: aparece la Recepción de Remitos embebida ─────────
    window.__isSupervisor = true;
    const hSup = _pppEnViajeHtml();

    // ── 3) Tildar una y ver que el botón de confirmar la cuenta ──────────────
    _pppEsSel = new Set(["98602"]);
    const hSel = _pppEnViajeHtml();

    return {
      // lo que pidió el dueño: fecha de carga y estado, visibles
      fechaCarga:      hOp.indexOf("03/09") >= 0,
      sinCargaVisible: hOp.indexOf("sin carga") >= 0,
      chipCargado:     hOp.indexOf("Cargado al camión") >= 0,
      chipSinRegistro: hOp.indexOf("Sin registro de carga") >= 0,
      chipArmada:      hOp.indexOf("Armada") >= 0,   // el texto largo sigue existiendo (en la no-sana)
      // ── v18.09 (Luis: "pintá el camionero en En Salida") ──────────────────
      // el dato ya viajaba en el evento de Carga Camión desde la v11.47 y no se mostraba
      camColumna:      /<th[^>]*>Camionero<\/th>/.test(hOp),
      camPintado:      /<td class="cam">Guillermo<\/td>/.test(hOp),
      camVacioRaya:    /<td class="cam"><span class="ppp-es-sincam"[^>]*>—<\/span><\/td>/.test(hOp),
      // y un retira dice POR QUÉ está vacío, en vez de dejar una raya muda
      camRetiraExplica: /Retira en f\u00e1brica: lo pasa a buscar el cliente/.test(hOp),
      // el desglose del día: quién tiene los remitos que faltan
      camResumen:      /🚛 <b>Guillermo<\/b> 1/.test(hOp),
      // los sin fletero van al FINAL y con nombre: un "— 1" entre los camioneros no se entiende
      camResumenSin:   /<b>Guillermo<\/b> 1[\s\S]{0,90}sin fletero 1/.test(hOp) &&
                       !/🚛 <span class="ppp-es-sincam">/.test(hOp),
      // el select tiene que PEDIR la columna, si no la fila llega sin el dato
      // anclado a gv_ppp_en_salida: hay varios `select=` en el archivo y un regex suelto podría
      // matchear cualquiera y dar verde de mentira
      camEnSelect:     /gv_ppp_en_salida"[\s\S]{0,80}?select=[^"']*\bcamionero\b/.test(SRC),

      // ── v18.10 (Luis: "se ve muy chiquito todo y mucho espacio en blanco") ──
      // Una NP SANA (cargada + armada + facturada) colapsa los dos chips que dicen lo esperado
      // en íconos: medido, la columna Estado se llevaba 479 px de 1254 repitiéndolos en todas
      // las filas. El texto entero queda en el `title`.
      sanaIconos:      /<span class="ppp-es-ico" title="Armada — Pasó por armado[^"]*">🧰<\/span>/.test(hOp) &&
                       /<span class="ppp-es-ico" title="Facturada">🧾<\/span>/.test(hOp),
      // ⚠ y en una NP que NO está sana vuelve el texto completo — el aviso de la v16.01 ("armado
      // no quiere decir que salió") no se perdió, se muestra cuando hace falta leerlo
      noSanaTextoLargo: /<span class="ppp-es-chip" title="Pasó por armado[^"]*">🧰 Armada \(no es que salió\)<\/span>/.test(hOp),
      // los encabezados de acción: la palabra entera forzaba 114 y 69 px para un tilde y un botón
      thAccionCortos:  /<th class="c" title="Tildá los remitos que ya volvieron">✓<\/th>/.test(hSup) &&
                       /<th class="c" title="El cliente no recibió[^"]*">↩<\/th>/.test(hSup) &&
                       hSup.indexOf(">Controlado</th>") < 0,
      // v18.07: son días HÁBILES (gv_dias_habiles en el backend); el chip lo dice y el title explica
      // que no cuenta sábados, domingos ni feriados.
      chipDias:        hOp.indexOf("4 días hábiles sin controlar") >= 0 &&
                       /no cuenta sábados, domingos ni feriados/.test(hOp),
      // la NP sin CCN tiene que estar listada
      traeLaSinCCN:    hOp.indexOf("98665") >= 0,
      traeLaCargada:   hOp.indexOf("98602") >= 0,
      /* gate: el operario NO ve las acciones de control. ⚠ v18.10: esto miraba el texto
         "Controlado</th>", que dejó de existir al acortar el encabezado a "✓" — el chequeo del
         supervisor se puso rojo y el del operario pasaba SOLO. Ahora los dos cuentan las columnas
         de acción y miran el handler, que es lo que de verdad define el gate. */
      opSinControl:    hOp.indexOf("pppEsToggle") < 0 && hOp.indexOf("pppEsSinSalida") < 0 &&
                       (hOp.match(/<th class="c" title=/g) || []).length === 0,
      // supervisor SÍ las ve: DOS por tabla — el fixture tiene dos días, o sea dos tablas, así
      // que un `=== 2` a secas fallaba contando 4
      supConControl:   hSup.indexOf("pppEsToggle") >= 0 &&
                       (hSup.match(/<th class="c" title=/g) || []).length ===
                       2 * (hSup.match(/<table class="ppp-es-table">/g) || []).length,
      supConSinSalida: hSup.indexOf("pppEsSinSalida") >= 0,
      supConAyuda:     hSup.indexOf("Recepción de Remitos") >= 0,
      // el botón de confirmar arranca deshabilitado y cuenta lo tildado
      botonVacioOff:   hSup.indexOf("disabled ") >= 0 && hSup.indexOf("Marcar 0 controlada(s)") >= 0,
      botonCuenta:     hSel.indexOf("Marcar 1 controlada(s)") >= 0 && hSel.indexOf("ppp-es-row on") >= 0,
      // los emisores que reusa son los MISMOS del módulo RR de arriba
      reusaCRN:        typeof window.crSendDetail === "function",
      reusaFSS:        typeof window.crSendSinSalida === "function",
      // el módulo RR de arriba sigue intacto
      rrIntacto:       typeof window.showControlRemitos === "function" && typeof window.crFinish === "function",
      // el tamaño se mide sobre la tabla DIBUJADA, no sobre el CSS: era 12,5 px
      fontMasGrande:   (function () {
        const d = document.createElement("div"); d.innerHTML = hSup;
        document.body.appendChild(d);
        const t = d.querySelector("table.ppp-es-table");
        const px = t ? parseFloat(getComputedStyle(t).fontSize) : 0;
        d.remove();
        return px >= 15;
      })()
    };
  });

  await b.close();
  const fails = Object.keys(r).filter((k) => !r[k]);
  const ok = fails.length === 0 && errs.length === 0;
  console.log("ppp-ensalida-estado:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join(" | ") : "none", ok ? "· ✓ OK" : "· ✗ FALLA: " + fails.join(", "));
  process.exit(ok ? 0 : 1);
})();

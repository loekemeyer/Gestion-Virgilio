/* Regresión v7.16/v7.45 — CHEQUEO DE GÓNDOLA en la PPP (semáforo auto + modal).

   Verifica el núcleo puro `pppChkCompute` (pedido × saldos → filas del chequeo):
     · alcanza en góndola                       → ✅ ok
     · no alcanza pero hay en otro depósito     → 🔁 bajar
     · no está en ningún lado                   → 🚨 falta
     · equivalencia 029→437E + empresa por NP   → mira el saldo de "437E CH", NO el de LK
     · código pelado sin sufijo en planimetría  → suma la FAMILIA LK/CH (criterio SSG v7.04)
     · picking hecho y todavía NO descontado    → se resta (excedente primero, luego góndola)
     · orden: primero lo que falta

   El SEMÁFORO automático (v7.45): `_pppChkStatusFor` colapsa las filas a un estado
   (ok / warn=faltan algunos / bad=no hay ninguno) y `_pppChkIcon` lo pinta con el
   glifo + clase correctos y el título con resumen + hora del último chequeo.

   Y el flujo completo `pppChequeoNp` con la red mockeada: abre el modal, resume el
   estado y NO toca el stock. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

// NP 44548 = Chef (empieza con 4 / < 90000) → los códigos partidos van a la variante CH.
const LINEAS = [
  { pedido: "44548", articulo: "097",   cajas: 7 },    // 193 en góndola → OK
  { pedido: "44548", articulo: "758",   cajas: 20 },   // 6 en góndola + 30 en racks → BAJAR (faltan 14)
  { pedido: "44548", articulo: "439EL", cajas: 6 },    // no hay en ningún depósito → FALTA
  { pedido: "44548", articulo: "029",   cajas: 5 },    // equiv → 437E → empresa CH: sólo 3 → FALTA (no los 100 de LK)
  { pedido: "44548", articulo: "840",   cajas: 10 },   // 12 góndola + 5 excedente, con 8 pickeadas sin descontar
  { pedido: "44548", articulo: "888E",  cajas: 3 }     // pelado sin sufijo en planimetría → familia LK(2)+CH(1) = 3 → OK
];
const SALDOS = [
  { cod_art: "097",     descripcion: "Afila Cuchillo", terminado: 193, excedente: 0, racks: 0,  racks_ch: 0, a_guardar: 0, para_envasar: 0 },
  { cod_art: "758",     descripcion: "Bombilla Plana", terminado: 6,   excedente: 0, racks: 30, racks_ch: 0, a_guardar: 0, para_envasar: 0 },
  { cod_art: "437E CH", descripcion: "Colador CH",     terminado: 3,   excedente: 0, racks: 0,  racks_ch: 0, a_guardar: 0, para_envasar: 0 },
  { cod_art: "437E LK", descripcion: "Colador LK",     terminado: 100, excedente: 0, racks: 0,  racks_ch: 0, a_guardar: 0, para_envasar: 0 },
  { cod_art: "840",     descripcion: "Rallador",       terminado: 12,  excedente: 5, racks: 0,  racks_ch: 0, a_guardar: 0, para_envasar: 0 },
  { cod_art: "888E LK", descripcion: "Partido LK",     terminado: 2,   excedente: 0, racks: 0,  racks_ch: 0, a_guardar: 0, para_envasar: 0 },
  { cod_art: "888E CH", descripcion: "Partido CH",     terminado: 1,   excedente: 0, racks: 0,  racks_ch: 0, a_guardar: 0, para_envasar: 0 }
];
// 8 cajas de 840 pickeadas en una tanda que el cron todavía no escribió al stock.
const PEND = { "840": 8 };

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async (fx) => {
    const out = {};
    // Planimetría: "437E CH" existe (→ pkCodEmpresa parte por empresa), "888E CH" NO (→ familia).
    window.GONDOLA = { "097": ["A01", 1], "758": ["B02", 2], "437E CH": ["F09", 3], "888E": ["C03", 4] };
    window._codeEquiv = { "29": { real: "437E", nota: "Colador 16cm importado" } };

    const filas = pppChkCompute(fx.LINEAS, fx.SALDOS, fx.PEND);
    const by = {}; filas.forEach(function (f) { by[String(f.codRaw).toUpperCase()] = f; });
    out.codigos = filas.map(function (f) { return f.codRaw + ":" + f.estado; });

    out.ok097     = !!by["097"]  && by["097"].estado === "ok"    && by["097"].gond === 193 && by["097"].sector === "A01";
    out.bajar758  = !!by["758"]  && by["758"].estado === "bajar" && by["758"].falta === 14 && by["758"].racks === 30;
    out.falta439  = !!by["439EL"] && by["439EL"].estado === "falta" && by["439EL"].otros === 0;
    // equivalencia + empresa: usa "437E CH" (3), NO la familia (103) ni LK (100)
    out.equivEmp  = !!by["437E CH"] && by["437E CH"].gond === 3 && by["437E CH"].estado === "falta" && by["437E CH"].ped === "029";
    // pendiente de descontar: excedente primero (5) y el resto de góndola (12-3=9) → faltan 1
    out.pend840   = !!by["840"] && by["840"].gond === 9 && by["840"].exc === 0 && by["840"].falta === 1 && by["840"].estado === "falta";
    // pelado sin sufijo en planimetría → familia LK+CH = 3 → alcanza justo
    out.fam888    = !!by["888E"] && by["888E"].gond === 3 && by["888E"].estado === "ok";
    // los problemas van primero
    out.ordenado  = filas.length > 0 && filas[0].estado !== "ok" && filas[filas.length - 1].estado === "ok";

    // --- flujo completo, con la red mockeada ---
    window.supaFetchAllSafe = async function (endpoint, query) {
      if (/vista_saldos_stock/.test(endpoint)) return fx.SALDOS.slice();
      if (/Registros_Produccion_Virgilio/.test(endpoint)) return [{ texto: "D99Z|840|8|8" }];   // PKC sin descontar
      if (/Movimientos_Stock/.test(endpoint)) return [{ ref: "D17A" }];                          // otra tanda ya descontada
      return [];
    };
    window.fetch = function (url) {
      const rows = /PPP_Base_Pedidos/.test(String(url)) ? fx.LINEAS.slice() : [];
      return Promise.resolve({ ok: true, json: function () { return Promise.resolve(rows); } });
    };
    window.loadArtNombres = async function () { return {}; };
    window.loadCodCanon = async function () { return {}; };
    window.getActivityStatus = async function () { return { pickingDone: new Set(), pickingEnCursoBy: new Map() }; };
    let movio = 0; window.stockMove = function () { movio++; };

    await pppChequeoNp("44548", "Pedido 44548 · D'Onofrio S.A.", "D77A");
    const ov = document.getElementById("pppChkOv");
    const txt = ov ? (ov.innerText || "") : "";
    out.abrio      = !!ov && ov.classList.contains("show");
    // 4 de 6 sin cubrir en góndola (439EL + 437E CH + 840 sin nada, 758 bajable de racks)
    out.resume     = /Faltan 4 de 6 art/.test(txt) && /3<\/b> no est/.test(ov.innerHTML) && /1<\/b> se puede/.test(ov.innerHTML);
    out.txt        = txt.slice(0, 220);
    out.detalla    = /439EL/.test(txt) && /758/.test(txt);
    out.avisaPend  = /D99Z/.test(txt);                         // avisó el picking sin impactar
    out.horaLeida  = /Stock le/.test(txt);
    out.sinTocarStock = movio === 0;

    // el ícono sale en la fila (onclick re-chequea; sobrevive un apóstrofo en la razón social)
    const html = _pppRowTr({ np: "44548", tanda: "D77A", cod: "2686", razon_social: "D'Onofrio S.A.", fecha: "03/08/2026", m3: 1.19, localidad: "Moreno" });
    out.botonFila = /pppChequeoNp\(/.test(html) && html.indexOf("D\\&#39;Onofrio") >= 0 && /ppp-chk-ico/.test(html);

    // --- semáforo automático (v7.45) ---
    _pickBaseCache = new Map([
      ["44548", fx.LINEAS.map(function (l) { return { art: l.articulo, cajas: l.cajas }; })],
      ["90001", [{ art: "097", cajas: 2 }]],                       // 193 en góndola → todo OK
      ["90002", [{ art: "999", cajas: 3 }, { art: "998", cajas: 2 }]]   // nada en ningún lado → bad
    ]);
    _pickBaseCacheTs = Date.now();
    _pppChkSet(fx.SALDOS, { porArt: fx.PEND, tandas: ["D99Z"] });
    out.baseSet = (_pickBaseCache instanceof Map) && !!_pppChkData;

    const stW = _pppChkStatusFor(["44548"]);
    out.semWarn = stW.ready && stW.estado === "warn" && stW.total === 6 && stW.faltan === 4;
    const stOk = _pppChkStatusFor(["90001"]);
    out.semOk = stOk.ready && stOk.estado === "ok" && stOk.faltan === 0 && stOk.total === 1;
    const stBad = _pppChkStatusFor(["90002"]);
    out.semBad = stBad.ready && stBad.estado === "bad" && stBad.faltan === stBad.total && stBad.total === 2;

    const icoW = _pppChkIcon(["44548"], "Pedido 44548", "D77A", false);
    out.icoWarn = /ppp-chk-ico warn/.test(icoW) && icoW.indexOf(">!<") >= 0 && /Faltan 4 de 6/.test(icoW) && /chequeado/.test(icoW);
    const icoOk = _pppChkIcon(["90001"], "x", "", true);
    out.icoOk = /ppp-chk-ico ok big/.test(icoOk) && icoOk.indexOf(">✓<") >= 0;   // ✓
    const icoBad = _pppChkIcon(["90002"], "x", "", false);
    out.icoBad = /ppp-chk-ico bad/.test(icoBad) && icoBad.indexOf(">✕<") >= 0;    // ✕

    // sin datos cargados → estado de espera (gris ⋯)
    _pppChkData = null;
    const icoWait = _pppChkIcon(["44548"], "x", "", false);
    out.icoWait = /ppp-chk-ico wait/.test(icoWait) && icoWait.indexOf(">⋯<") >= 0;   // ⋯
    return out;
  }, { LINEAS: LINEAS, SALDOS: SALDOS, PEND: PEND });

  const claves = ["ok097", "bajar758", "falta439", "equivEmp", "pend840", "fam888", "ordenado",
                  "abrio", "resume", "detalla", "avisaPend", "horaLeida", "sinTocarStock", "botonFila",
                  "baseSet", "semWarn", "semOk", "semBad", "icoWarn", "icoOk", "icoBad", "icoWait"];
  const fallan = claves.filter((k) => !r[k]);
  const pass = fallan.length === 0 && errs.length === 0;
  console.log("ppp-chk-gondola:", JSON.stringify(r), fallan.length ? "· fallan: " + fallan.join(",") : "",
    "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();

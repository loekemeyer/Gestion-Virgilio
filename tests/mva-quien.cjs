/* Regresión v6.66: en el detalle de movimientos por artículo, el chip 👤 con las
   SIGLAS + LEGAJO del que hizo cada movimiento (en `recepcion`, del que recibió).
   - Si el movimiento trae `legajo` (guardado/picking/ajuste, y recepciones nuevas
     desde la idea 7725) → chip GRIS, exacto.
   - Si es `recepcion` SIN legajo (las viejas) → se deduce por la sesión de RT que
     contiene el ts → chip ÁMBAR con "~".
   - Si no se puede saber (no hay sesión que lo contenga) → sin chip.
   - Sesiones superpuestas: gana la que arrancó más tarde.
   Un error acá le pone el nombre equivocado a quien recibió la mercadería. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const T = (s) => new Date(s).getTime();
    _empleadosNombres = new Map([["104", "Ariel Gomez"], ["237", "Pedro Suarez"], ["122", "Luis Paz"]]);
    // Sesiones de RT: 104 abarca 15:14–16:07 y 237 se le superpone 15:23–15:43.
    _stkRtSes = [
      { leg: "104", ini: T("2026-07-06T15:14:00Z"), fin: T("2026-07-06T16:07:00Z") },
      { leg: "237", ini: T("2026-07-06T15:23:00Z"), fin: T("2026-07-06T15:43:00Z") },
      { leg: "122", ini: T("2026-07-08T09:00:00Z"), fin: Infinity }   // sesión todavía abierta
    ];
    const chip = (mv) => _stkQuienChip(mv);

    // A) movimiento con legajo propio → exacto (gris, sin "~"), con siglas del nombre.
    const a = chip({ tipo: "guardado", legajo: "237", ts: "2026-07-08T17:01:00Z" });
    const exacto = a.indexOf("PS") > 0 && a.indexOf("· 237") > 0 && a.indexOf("aprox") < 0 && a.indexOf("~") < 0;

    // B) recepción SIN legajo dentro de una sola sesión → deducido (ámbar + "~").
    const bq = chip({ tipo: "recepcion", legajo: null, ts: "2026-07-06T15:57:00Z" });
    const deducido = bq.indexOf("aprox") > 0 && bq.indexOf("AG") > 0 && bq.indexOf("· 104") > 0 && bq.indexOf("~") > 0;

    // C) sesiones superpuestas → gana la que arrancó más tarde (237, no 104).
    const c = chip({ tipo: "recepcion", legajo: null, ts: "2026-07-06T15:30:00Z" });
    const superpuesta = c.indexOf("· 237") > 0 && c.indexOf("· 104") < 0;

    // D) recepción fuera de toda sesión → sin chip.
    const sinDato = chip({ tipo: "recepcion", legajo: null, ts: "2026-07-06T09:00:00Z" }) === "";

    // E) sesión abierta (sin cierre) → cubre lo posterior.
    const abierta = chip({ tipo: "recepcion", legajo: null, ts: "2026-07-08T18:30:00Z" }).indexOf("· 122") > 0;

    // F) un movimiento que NO es recepción y no trae legajo no se le adjudica a nadie.
    const noInventa = chip({ tipo: "picking", legajo: null, ts: "2026-07-06T15:57:00Z" }) === "";

    // G) el chip sale en la fila de la tabla (que _stkMovsBlock lo use, no sólo que exista).
    _stk = { movs: [{ cod_art: "824", deposito: "a_guardar", delta: 14, tipo: "recepcion", ref: "0245", legajo: null, ts: "2026-07-06T15:57:00Z" }], cutoff: null };
    _stkPop = { kind: "movsArt", cod: "824", codN: _stkNormCod("824"), dep: "a_guardar", titulo: "A guardar", desde: "", hasta: "", npByTanda: {} };
    const enTabla = _stkMovsBlock().indexOf("mva-qui") > 0;

    return { exacto, deducido, superpuesta, sinDato, abierta, noInventa, enTabla };
  });
  const pass = Object.keys(r).every((k) => r[k] === true) && errs.length === 0;
  console.log("mva-quien:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();

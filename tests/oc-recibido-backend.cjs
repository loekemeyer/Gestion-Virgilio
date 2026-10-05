/* v24.00 (Luis, 29/09/2026) — dos cosas del modulo de OCs, medidas corriendo las funciones.

   A) EL RECIBIDO SALE DEL BACKEND. El visualizador recalculaba el recibido en el front
      (ocBuildRecep) comparando los nombres CRUDOS de proveedor, asi que una OC a
      "Pettofrezza" contra una entrega a nombre de "Rafael" no matcheaba y mostraba 0.
      El backend (gv_oc_recompute_recibido -> Ordenes_Compra.cantidad_recibida) SI resuelve
      los alias (gv_norm_prov_keys: pettofrezza -> rafael) y GV_OC_Fabrica_Para.
      Caso real: OC 1589 del 23/09, 501, 1153 pedidas, 300 recibidas el 24 -> la pantalla
      decia 0. Eran 12 OC del 23/09 asi.
      El front queda de RESPALDO (se toma el mayor): una entrega recien cargada que el
      recompute todavia no proceso tiene que seguir viendose.

   B) EL SELECTOR "A esa fecha" NO SE CORTA. El input datetime-local tenia width fijo de
      158px con font 11; el widget nativo de Chrome (dd/mm/aaaa --:-- + calendario) necesita
      ~170px y en pantallas chicas salia cortado contra su propio borde. Y los tres controles
      sueltos se partian al medio con el scroll horizontal de la barra de filtros.

   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const out = {};
    // ---------- A) ocRecEff ----------
    // el caso 501: el front no encontro nada (alias), el backend dice 300.
    _oc = { rows: [], recepByRow: {} };
    out.backendGana = ocRecEff({ id: 1, cantidad_recibida: 300 }) === 300;
    // el front sigue valiendo cuando el backend todavia no proceso la entrega.
    _oc = { rows: [], recepByRow: { 2: 50 } };
    out.frontDeRespaldo = ocRecEff({ id: 2, cantidad_recibida: 0 }) === 50;
    // con los dos cargados manda el mayor (nunca se pierde lo recibido).
    _oc = { rows: [], recepByRow: { 3: 10 } };
    out.tomaElMayor = ocRecEff({ id: 3, cantidad_recibida: 300 }) === 300;
    out.sinDatoEsCero = (function () { _oc = { rows: [], recepByRow: {} };
      return ocRecEff({ id: 9, cantidad_recibida: null }) === 0; })();

    // ---------- A2) _ocgRecibMap: OC vigente por codigo ----------
    _oc = { rows: [
      // la vigente del 501 (23/09) y una anterior ANULADA que no tiene que ganar
      { id: 10, codigo: "501", fecha: "2026-09-23", proveedor: "Pettofrezza", cantidad: 1153, cantidad_recibida: 300, estado: "pendiente" },
      { id: 11, codigo: "501", fecha: "2026-09-02", proveedor: "Pettofrezza", cantidad: 164, cantidad_recibida: 164, estado: "anulada" },
      // el 506 sale el mismo dia a DOS talleristas: la pregunta es por el codigo -> se suman
      { id: 12, codigo: "506", fecha: "2026-09-23", proveedor: "Martin C", cantidad: 456, cantidad_recibida: 194, estado: "pendiente" },
      { id: 13, codigo: "506", fecha: "2026-09-23", proveedor: "Carlos E", cantidad: 455, cantidad_recibida: 193, estado: "pendiente" },
      // una cerrada sola: no es vigente -> ese codigo no tiene que aparecer
      { id: 14, codigo: "777", fecha: "2026-09-23", proveedor: "Garcia", cantidad: 10, cantidad_recibida: 10, estado: "cerrada" }
    ], recepByRow: {} };
    const m = _ocgRecibMap();
    out.vigenteNoEsLaAnulada = !!m["501"] && m["501"].ped === 1153 && m["501"].rec === 300;
    out.sumaLosDosDelMismoDia = !!m["506"] && m["506"].ped === 911 && m["506"].rec === 387;
    out.cerradaNoEsVigente = !m["777"];

    // ---------- A3) la columna en la vista previa del generador ----------
    const mk = (cod, desc, prov, falta) => ({ cod: cod, desc: desc, prov: prov, falta: falta,
      max: 1689, maxTot: 1689, demanda: 219, demandaTot: 219, stock: 945, stockTot: 945,
      fuente: "proy", indice: 1.5, proy: 1126, uni: 6, ncaja: 22, prop: 100, sinProv: false, cap: null });
    const it501 = mk("501", "Abrelatas A Manija", "Pettofrezza", 963);
    const itNueva = mk("888", "Codigo sin OC previa", "Garcia", 40);
    const itemsAll = [it501, itNueva];
    _oc.view = "gen"; _oc.genMode = "art"; _oc.genFiltro = "";
    _oc.gen = { fecha: "2026-09-29", items: itemsAll, itemsAll: itemsAll };
    const html = ocBodyGenArt();
    out.muestraLoRecibido = html.indexOf(">300</b><span style=\"color:#94a3b8\">/1153<") >= 0;
    out.tooltipDiceLaOC = html.indexOf("pedidas 1153, recibidas 300, faltan 853") >= 0;
    out.sinOCpreviaMuestraGuion = html.indexOf("No hay una OC vigente de este código") >= 0;
    out.sigueElNeto = html.indexOf(">963</td>") >= 0;        // "A pedir" no cambia
    out.encabezadoRecib = html.indexOf(">Recib.</th>") >= 0;
    // candado invertido: la columna es informativa, no toca lo que se va a ORDENAR
    const g = ocgGroups();
    let totalAPedir = 0;
    Object.keys(g).forEach(k => g[k].items.forEach(i => { totalAPedir += i.falta; }));
    out.noCambiaLoQueSeManda = totalAPedir === 1003;          // 963 + 40

    // por tallerista, la misma columna
    _oc.genMode = "tall";
    const htmlT = ocBodyGenTall();
    out.tallTambienMuestra = htmlT.indexOf(">Recib.</th>") >= 0 && htmlT.indexOf("/1153<") >= 0;

    // ---------- B) el selector "A esa fecha" ----------
    _stk = { asOf: null, asOfPicking: true, asOfInput: "2026-09-22T23:00" };
    const c = stkAsOfControl();
    out.inputSinAnchoFijo = c.indexOf("width:158px") < 0 && c.indexOf("min-width:172px") >= 0;
    out.inputLegible = c.indexOf("font-size:11px") < 0;
    // el grupo viaja junto: abre con un <span> contenedor y cierra con </span>
    out.grupoEnvuelto = /^<span style="flex:0 0 auto;display:inline-flex;/.test(c) && /<\/span>$/.test(c);
    // y sigue trayendo los tres controles
    // v26.72 — los rótulos van en dos renglones (Luis)
    out.tresControles = c.indexOf("Ver<br>stock:") >= 0 && c.indexOf("En<br>vivo") >= 0
      && c.indexOf('id="stkAsOfInp"') >= 0 && c.indexOf("A esa<br>fecha") >= 0;
    return out;
  });
  const malas = Object.keys(r).filter(k => r[k] !== true);
  const pass = !malas.length && errs.length === 0;
  console.log("oc-recibido-backend:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL -> " + malas.join(", "));
  await b.close(); process.exit(pass ? 0 : 1);
})();

/* ============================================================================
   HOT SALE — rentabilidad ponderada (v25.91, pedido de Thomas 01/10/2026)
   ----------------------------------------------------------------------------
   Los súper piden un APORTE de hot sale (un % sobre el precio) dos o tres veces
   al año. Thomas quiere saber qué rentabilidad le queda en el período completo
   (la oferta más las semanas normales que la rodean), contando que en hot sale
   se vende más. Es su planilla (Semana · Vta · Recibo · Costo · Markup, con
   recibo $ y costo $ sumados y (recibo − costo) ÷ costo), hecha pantalla.

   DATOS QUE PIDE (los de arriba de su planilla): HotSale % · Semanas HotSale ·
   Rent c/AP (nacionales) · Rent Pta Pta (importados, sin hot sale) · Semanas a
   Ponderar · cuánto más se vende en hot sale (× lo normal).
   Los dos % de rentabilidad los tiene él ("en función de mi markup sé cuál es mi
   costo: 100 % punta a punta = recibo 1.000, me cuesta 500"): acá no se calculan.

   CÓMO SE CALCULA (markup sobre costo; el costo unitario se cancela, por eso no se pide)
     rent. en hot sale = (1 + rent) × (1 − aporte) − 1
     ponderada        = (N × rent + H × k × rentHS) ÷ (N + H × k)
                        N = semanas normales, H = de hot sale, k = cuánto más se vende
   Verificado contra su planilla: 100 % / 20 % / 4 sem / 2 HS / ×2 → 73,33 %;
   su ítem real (recibo 922, costo 986 → −6,49 %) / 20 % / 12 sem / 2 HS / ×2 → −11,83 %
   (él redondea −12 %). La rentabilidad puede ser NEGATIVA: se admite.

   ⚠ POR QUÉ VIVE EN SU PROPIO ARCHIVO: regla v23.98 (cobranzas.js). Se carga con
   ?v= atado a APP_VERSION — está en SIGUEN_APP_VERSION de scripts/bump-version.cjs
   y tests/version-tokens.cjs. No lee ni escribe la base: los parámetros quedan en
   localStorage del navegador (gv_hotsale_params_v1). Candado: tests/hotsale-rent.cjs.
   ============================================================================ */

var _HS_KEY = "gv_hotsale_params_v1";
var _HS_IDS = ["MI", "MN", "A", "H", "P", "K"];
/* los valores de la planilla de Thomas del 01/10 */
var _HS_DEF = { MI: 75, MN: 10, A: 20, H: 2, P: 12, K: 2 };
var _HS_ROT = {
  MI: "Rent Pta Pta (importados)", MN: "Rent c/AP (nacionales)", A: "HotSale %",
  H: "Semanas HotSale", P: "Semanas a Ponderar", K: "cuánto más vendo en hot sale"
};

/* m: rentabilidad base (tanto por uno) · a: aporte hot sale (tanto por uno) ·
   P: semanas a ponderar · H: semanas de hot sale · k: cuánto más se vende (× lo normal) */
function hsCalc(m, a, P, H, k) {
  var mHS = (1 + m) * (1 - a) - 1;
  var N = P - H;
  var peso = N + H * k;                      /* unidades relativas: cada semana normal = 1 */
  var pond = peso > 0 ? (N * m + H * k * mHS) / peso : NaN;
  return { mHS: mHS, pond: pond, N: N };
}

function _hsNum(v, dec) {
  var n = Number(v);
  if (!isFinite(n)) return "—";
  return n.toLocaleString("es-AR", { minimumFractionDigits: dec, maximumFractionDigits: dec });
}
function _hsPct(x) { return isFinite(x) ? _hsNum(x * 100, 2) + " %" : "—"; }
function _hsPctS(x) { return isFinite(x) ? _hsNum(x * 100, 0).replace(/,00$/, "") + " %" : "—"; }
function _hsS(v) { var n = Number(v); return isFinite(n) ? n.toLocaleString("es-AR", { maximumFractionDigits: 2 }) : "—"; }

function _hsCss() {
  if (document.getElementById("hsCss")) return;
  var st = document.createElement("style");
  st.id = "hsCss";
  st.textContent = [
    "#hsOv{position:fixed;inset:0;z-index:9600;background:#f1f5f9;display:none;flex-direction:column;font-family:system-ui,Segoe UI,Arial,sans-serif;color:#0f172a;}",
    "#hsOv *{box-sizing:border-box;}",
    /* el index tiene un button{width:100%;padding:16px;font-size:22px;margin-top:14px} global:
       se neutraliza por contenedor (mismo pozo que cobranzas.js e Importados v23.93) */
    "#hsOv button{width:auto;margin-top:0;padding:6px 13px;font-size:13px;line-height:1.25;}",
    "#hsOv input{width:100%;margin-top:0;font:inherit;font-size:16px;font-weight:700;text-align:center;padding:7px 8px;border:1px solid #cbd5e1;border-radius:8px;background:#fff;color:#0f172a;}",
    "#hsOv input:focus{outline:none;border-color:#b91c1c;box-shadow:0 0 0 3px rgba(185,28,28,.14);}",
    ".hs-top{display:flex;align-items:center;gap:14px;padding:10px 16px;background:linear-gradient(90deg,#b91c1c,#7f1d1d);color:#fff;flex:0 0 auto;flex-wrap:wrap;}",
    ".hs-top b{font-size:17px;letter-spacing:.2px;}",
    ".hs-top span{font-size:12.5px;opacity:.9;flex:1 1 320px;min-width:0;}",
    ".hs-x{order:2;margin-left:auto;background:#fff;color:#7f1d1d;border:none;border-radius:8px;padding:7px 16px;font-weight:800;cursor:pointer;}",
    ".hs-body{flex:1;min-height:0;overflow:auto;padding:16px;}",
    ".hs-wrap{max-width:760px;margin:0 auto;display:grid;gap:14px;}",
    ".hs-form{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px 14px;align-items:end;background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:12px 14px;box-shadow:0 1px 2px rgba(15,23,42,.06);}",
    "@media(max-width:560px){.hs-form{grid-template-columns:repeat(2,minmax(0,1fr));}}",
    ".hs-form label{display:grid;gap:3px;font-size:12px;color:#475569;min-width:0;line-height:1.25;font-weight:600;}",
    ".hs-form label.rent{color:#7f1d1d;}",
    ".hs-form label.rent input{border-color:#b91c1c;}",
    ".hs-bar{display:flex;gap:10px;align-items:center;justify-content:space-between;flex-wrap:wrap;font-size:12.5px;color:#64748b;min-height:1.2em;}",
    ".hs-bar .err{color:#b91c1c;font-weight:700;}",
    ".hs-bar button{background:#fff;border:1px solid #cbd5e1;border-radius:8px;color:#0f172a;font-weight:700;cursor:pointer;}",
    ".hs-wrapt{overflow-x:auto;}",
    ".hs-t{border-collapse:collapse;margin:0 auto;font-variant-numeric:tabular-nums;background:#fff;border:1px solid #e2e8f0;border-radius:12px;}",
    ".hs-t th,.hs-t td{padding:7px 14px;text-align:center;border-bottom:1px solid #e2e8f0;white-space:nowrap;}",
    ".hs-t th{font-size:14px;font-weight:800;line-height:1.2;}",
    ".hs-t th small{display:block;font-weight:600;color:#64748b;font-size:11.5px;}",
    ".hs-t td.c{white-space:normal;max-width:26ch;font-size:13.5px;font-weight:600;color:#334155;}",
    ".hs-t td.c small{display:block;color:#64748b;font-size:11px;font-weight:500;}",
    ".hs-t td.v{font-size:16px;font-weight:700;}",
    ".hs-t tr.hs td{background:#fef2f2;}",
    ".hs-t tr.key td{border-bottom:none;}",
    ".hs-t tr.key td.v{font-size:26px;font-weight:900;color:#b91c1c;}",
    ".hs-t tr.key td.v.neg{color:#7f1d1d;}",
    /* celular: la tabla tiene que entrar entera en 390 px (medido: 385 px con el relleno de escritorio) */
    "@media(max-width:560px){.hs-t th,.hs-t td{padding:6px 7px;}.hs-t td.c{max-width:17ch;font-size:12.5px;}.hs-t td.v{font-size:14px;}.hs-t tr.key td.v{font-size:21px;}.hs-t th{font-size:13px;}}",
    ".hs-det{font-size:13px;color:#475569;max-width:70ch;}",
    "#hsSemDet{max-width:none;}",
    ".hs-det summary{cursor:pointer;color:#0f172a;font-weight:700;}",
    ".hs-det p{margin:6px 0;}",
    ".hs-sem{display:grid;grid-template-columns:repeat(auto-fit,max-content);gap:14px;justify-content:center;margin-top:8px;}",
    ".hs-sem table{border-collapse:collapse;font-variant-numeric:tabular-nums;background:#fff;}",
    ".hs-sem caption{font-weight:800;padding:0 0 4px;}",
    ".hs-sem th,.hs-sem td{padding:3px 10px;text-align:center;border-bottom:1px solid #e2e8f0;white-space:nowrap;font-size:12.5px;}",
    ".hs-sem tr.hs td{background:#fef2f2;}",
    ".hs-sem tr.tot td{font-weight:800;border-top:2px solid #cbd5e1;border-bottom:none;}"
  ].join("\n");
  document.head.appendChild(st);
}

function openHotSale() {
  try { if (typeof requireSupervisor === "function" && !requireSupervisor()) return; } catch (_e) {}
  _hsCss();
  var ov = document.getElementById("hsOv");
  if (!ov) { ov = document.createElement("div"); ov.id = "hsOv"; document.body.appendChild(ov); }
  ov.style.display = "flex";
  ov.innerHTML =
    '<div class="hs-top">' +
      '<b>🏷️ Hot Sale — rentabilidad ponderada</b>' +
      '<span>Cargás las dos rentabilidades que tenés hoy y lo que pide el súper; sale el % que queda en el período, por separado para importados y nacionales.</span>' +
      '<button class="hs-x" onclick="hsClose()">Cerrar</button>' +
    '</div>' +
    '<div class="hs-body"><div class="hs-wrap">' +
      '<form class="hs-form" id="hsForm" autocomplete="off" onsubmit="return false">' +
        '<label class="rent">Rent Pta Pta — importados, sin hot sale (%)<input id="hsMI" type="number" step="1"></label>' +
        '<label class="rent">Rent c/AP — nacionales (%)<input id="hsMN" type="number" step="1"></label>' +
        '<label>HotSale % (aporte sobre el precio)<input id="hsA" type="number" min="0" max="100" step="0.5"></label>' +
        '<label>Semanas HotSale<input id="hsH" type="number" min="0" step="1"></label>' +
        '<label>Semanas a Ponderar<input id="hsP" type="number" min="1" max="104" step="1"></label>' +
        '<label>Cuánto más vendo en hot sale (× lo normal)<input id="hsK" type="number" min="0" step="0.1"></label>' +
      '</form>' +
      '<div class="hs-bar"><span id="hsMsg"></span><button type="button" onclick="hsReset()">Volver a la planilla de ejemplo</button></div>' +
      '<div class="hs-wrapt"><table class="hs-t" id="hsT"></table></div>' +
      '<details class="hs-det" id="hsSemDet"><summary>Semana por semana (como la planilla)</summary><div class="hs-sem" id="hsSem"></div></details>' +
      '<details class="hs-det"><summary>Cómo se calcula</summary>' +
        '<p><b>Rentabilidad en hot sale</b> = (1 + rent.) × (1 − HotSale %) − 1. Con 100 % y 20 %: 2 × 0,8 − 1 = 60 %. Vale también en negativo: recibo 922 con costo 986 (−6,49 %) queda en −25,19 %.</p>' +
        '<p><b>Ponderada</b> = promedio de las rentabilidades pesado por lo que se vende cada semana: una semana normal pesa 1 y una de hot sale pesa lo que se vende de más (× 2 = pesa doble). Con 4 semanas, 2 de hot sale y venta doble: (2 × 100 % + 4 × 60 %) ÷ 6 = 73,33 %. Es la misma cuenta que la planilla, (recibo − costo) ÷ costo: el costo unitario se cancela y por eso no se pide.</p>' +
      '</details>' +
    '</div></div>';
  _hsLoad();
  ov.querySelector("#hsForm").addEventListener("input", hsRender);
  hsRender();
}
function hsClose() { var ov = document.getElementById("hsOv"); if (ov) ov.style.display = "none"; }
function hsReset() { _HS_IDS.forEach(function (id) { document.getElementById("hs" + id).value = _HS_DEF[id]; }); hsRender(); }

function _hsLoad() {
  var o = null;
  try { o = JSON.parse(localStorage.getItem(_HS_KEY) || "null"); } catch (_e) { o = null; }
  _HS_IDS.forEach(function (id) { document.getElementById("hs" + id).value = (o && isFinite(o[id])) ? o[id] : _HS_DEF[id]; });
}
function _hsRead() { var o = {}; _HS_IDS.forEach(function (id) { o[id] = parseFloat(document.getElementById("hs" + id).value); }); return o; }

function _hsSemanas(o, m, titulo) {
  var r = hsCalc(m, o.A / 100, o.P, o.H, o.K);
  var h = '<table><caption>' + titulo + '</caption><thead><tr><th>Semana</th><th>Vta (× normal)</th><th>Rent.</th></tr></thead><tbody>';
  for (var w = 1; w <= o.P; w++) {
    var hs = w > r.N;
    h += '<tr' + (hs ? ' class="hs"' : '') + '><td>' + w + (hs ? ' · hot sale' : '') + '</td><td>' + _hsS(hs ? o.K : 1) + '</td><td>' + _hsPct(hs ? r.mHS : m) + '</td></tr>';
  }
  h += '<tr class="tot"><td>Ponderada</td><td>' + _hsS(r.N + o.H * o.K) + '</td><td>' + _hsPct(r.pond) + '</td></tr></tbody></table>';
  return h;
}

function hsRender() {
  var o = _hsRead(), bad = [];
  _HS_IDS.forEach(function (id) { if (!isFinite(o[id]) || (o[id] < 0 && id !== "MI" && id !== "MN")) bad.push(_HS_ROT[id]); });
  if (isFinite(o.H) && isFinite(o.P) && o.H > o.P) bad.push("Semanas HotSale > Semanas a Ponderar");
  if (isFinite(o.P) && o.P < 1) bad.push("Semanas a Ponderar (mínimo 1)");
  if (isFinite(o.P) && o.P > 104) bad.push("Semanas a Ponderar (máximo 104, dos años)");
  var msg = document.getElementById("hsMsg"), t = document.getElementById("hsT"), sem = document.getElementById("hsSem");
  if (bad.length) {
    msg.innerHTML = '<span class="err">Revisá: ' + bad.join(", ") + ".</span>";
    t.innerHTML = ""; sem.innerHTML = "";
    return;
  }
  msg.textContent = "Los datos quedan guardados en este navegador.";
  var a = o.A / 100;
  var I = hsCalc(o.MI / 100, a, o.P, o.H, o.K), N = hsCalc(o.MN / 100, a, o.P, o.H, o.K);
  var h = '<thead><tr><th></th><th>Importados<small>Rent Pta Pta</small></th><th>Nacionales<small>Rent c/AP</small></th></tr></thead><tbody>';
  h += '<tr><td class="c">Rent. hoy, sin hot sale</td><td class="v">' + _hsPct(o.MI / 100) + '</td><td class="v">' + _hsPct(o.MN / 100) + '</td></tr>';
  h += '<tr class="hs"><td class="c">En hot sale, con ' + _hsS(o.A) + ' % de aporte<small>' + _hsS(o.H) + ' sem · venta × ' + _hsS(o.K) + '</small></td><td class="v">' + _hsPct(I.mHS) + '</td><td class="v">' + _hsPct(N.mHS) + '</td></tr>';
  h += '<tr class="key"><td class="c">Rent. ponderada en ' + _hsS(o.P) + ' semanas<small>' + _hsS(I.N) + ' normales + ' + _hsS(o.H) + ' de hot sale</small></td>' +
       '<td class="v' + (I.pond < 0 ? ' neg' : '') + '" id="hsPondImp">' + _hsPct(I.pond) + '</td><td class="v' + (N.pond < 0 ? ' neg' : '') + '" id="hsPondNac">' + _hsPct(N.pond) + '</td></tr>';
  h += '</tbody>';
  t.innerHTML = h;
  sem.innerHTML = _hsSemanas(o, o.MI / 100, "Importados") + _hsSemanas(o, o.MN / 100, "Nacionales");
  try { localStorage.setItem(_HS_KEY, JSON.stringify(o)); } catch (_e) {}
}

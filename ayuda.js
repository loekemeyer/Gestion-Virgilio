/* v29.17 (Luis, 09/10/2026) — ❓ AYUDA: chat del operario con un asistente que SÓLO explica
   cómo se usa la app, a partir de ayuda/manual-operario.md. Lo contesta la Edge Function
   gv-ayuda, que no tiene herramientas ni acceso a datos: acá sólo viaja la pregunta y el
   historial corto de esta charla (en memoria, no se guarda en el celular). */
var _ayuda = { hist: [], enviando: false };
var AYUDA_FN_URL = (typeof SUPABASE_URL !== "undefined" ? SUPABASE_URL : "") + "/functions/v1/gv-ayuda";

function _ayudaEsc(s) {
  return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
    return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
  });
}
function _ayudaFmt(s) {
  return _ayudaEsc(s).replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>").replace(/\n/g, "<br>");
}
function _ayudaCss() {
  if (document.getElementById("ayudaCss")) return;
  var s = document.createElement("style"); s.id = "ayudaCss";
  s.textContent = "#ayudaModal{display:none;position:fixed;inset:0;z-index:1400;background:rgba(2,6,23,.78);padding:10px;}" +
    "#ayudaModal.show{display:flex;align-items:center;justify-content:center;}" +
    ".ay-card{background:#f8fafc;width:100%;max-width:480px;height:min(640px,94vh);border-radius:16px;display:flex;flex-direction:column;overflow:hidden;box-shadow:0 24px 70px rgba(0,0,0,.5);}" +
    ".ay-head{display:flex;align-items:center;justify-content:space-between;padding:12px 14px;background:#1e3a8a;color:#fff;}" +
    ".ay-tit{font-size:17px;font-weight:800;}" +
    "#ayudaModal button{width:auto;margin:0;}" +
    ".ay-x{background:rgba(255,255,255,.2);color:#fff;border:0;border-radius:8px;padding:6px 12px;font-weight:800;font-size:14px;cursor:pointer;}" +
    ".ay-log{flex:1;overflow:auto;padding:12px;display:flex;flex-direction:column;gap:8px;}" +
    ".ay-m{max-width:88%;padding:9px 11px;border-radius:12px;font-size:14.5px;line-height:1.4;}" +
    ".ay-u{align-self:flex-end;background:#1e6bd6;color:#fff;}" +
    ".ay-a{align-self:flex-start;background:#fff;border:1px solid #e2e8f0;color:#0f172a;}" +
    ".ay-err{align-self:center;color:#b91c1c;font-size:13px;}" +
    ".ay-in{display:flex;gap:6px;padding:10px;border-top:1px solid #e2e8f0;background:#fff;}" +
    ".ay-in textarea{flex:1;resize:none;height:46px;font-size:15px;padding:8px;border:1px solid #cbd5e1;border-radius:10px;box-sizing:border-box;}" +
    ".ay-send{background:#1e6bd6;color:#fff;border:0;border-radius:10px;padding:0 14px;font-weight:800;font-size:15px;cursor:pointer;}" +
    ".ay-send:disabled{opacity:.5;}";
  document.head.appendChild(s);
}
function ayudaAbrir() {
  _ayudaCss();
  var ov = document.getElementById("ayudaModal");
  if (!ov) {
    ov = document.createElement("div"); ov.id = "ayudaModal";
    ov.innerHTML = '<div class="ay-card"><div class="ay-head"><span class="ay-tit">❓ Ayuda — ¿cómo se usa?</span>' +
      '<button class="ay-x" onclick="ayudaCerrar()">Cerrar</button></div>' +
      '<div class="ay-log" id="ayudaLog"></div>' +
      '<div class="ay-in"><textarea id="ayudaTxt" maxlength="500" placeholder="Escribí tu duda sobre la app…"></textarea>' +
      '<button class="ay-send" id="ayudaSend" onclick="ayudaEnviar()">Enviar</button></div></div>';
    document.body.appendChild(ov);
    ov.addEventListener("click", function (e) { if (e.target === ov) ayudaCerrar(); });
    document.getElementById("ayudaTxt").addEventListener("keydown", function (e) {
      if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); ayudaEnviar(); }
    });
  }
  if (!_ayuda.hist.length) _ayudaPintar();
  ov.classList.add("show");
  try { document.getElementById("ayudaTxt").focus(); } catch (_e) {}
}
function ayudaCerrar() { var ov = document.getElementById("ayudaModal"); if (ov) ov.classList.remove("show"); }
function _ayudaPintar(err) {
  var log = document.getElementById("ayudaLog"); if (!log) return;
  var h = '<div class="ay-m ay-a">Hola. Preguntame cómo se usa cualquier módulo de la app (picking, armado, guardado, racks, insumos…). Sólo sé lo que dice el manual: no veo stock ni pedidos.</div>';
  h += _ayuda.hist.map(function (m) {
    return '<div class="ay-m ' + (m.rol === "user" ? "ay-u" : "ay-a") + '">' + _ayudaFmt(m.texto) + "</div>";
  }).join("");
  if (_ayuda.enviando) h += '<div class="ay-m ay-a">…</div>';
  if (err) h += '<div class="ay-err">' + _ayudaEsc(err) + "</div>";
  log.innerHTML = h;
  log.scrollTop = log.scrollHeight;
}
async function _ayudaHdr() {
  var key = typeof SUPABASE_KEY !== "undefined" ? SUPABASE_KEY : "";
  var h = { "Content-Type": "application/json", apikey: key, Authorization: "Bearer " + key };
  try {
    if (window.sb && window.sb.auth) {
      var r = await window.sb.auth.getSession();
      var tok = r && r.data && r.data.session && r.data.session.access_token;
      if (tok) h.Authorization = "Bearer " + tok;
    }
  } catch (_e) {}
  return h;
}
async function ayudaEnviar() {
  if (_ayuda.enviando) return;
  var ta = document.getElementById("ayudaTxt");
  var q = String(ta && ta.value || "").trim().slice(0, 500);
  if (q.length < 2) return;
  var hist = _ayuda.hist.slice(-6);
  _ayuda.hist.push({ rol: "user", texto: q });
  ta.value = "";
  _ayuda.enviando = true;
  var btn = document.getElementById("ayudaSend"); if (btn) btn.disabled = true;
  _ayudaPintar();
  var err = "";
  try {
    var ac = new AbortController();
    var t = setTimeout(function () { ac.abort(); }, 45000);
    var r = await fetch(AYUDA_FN_URL, { method: "POST", headers: await _ayudaHdr(), signal: ac.signal,
      body: JSON.stringify({ pregunta: q, historial: hist }) });
    clearTimeout(t);
    var j = await r.json().catch(function () { return {}; });
    if (j && j.respuesta) _ayuda.hist.push({ rol: "asistente", texto: String(j.respuesta) });
    else err = (j && j.error) || "No pude conseguir respuesta. Probá de nuevo.";
  } catch (_e) {
    err = "Sin conexión con el asistente. Probá de nuevo o mirá «¿Cómo se usa?».";
  }
  _ayuda.enviando = false;
  if (btn) btn.disabled = false;
  _ayudaPintar(err);
}

/* =========================================================================================
   v29.18 (Luis, 09/10/2026) — ⚙️ Configuración → 🤖 Asistente IA operarios.
   Se pega la API key de cada proveedor y se elige el modelo y cuál responde primero.
   La clave va DIRECTO al Vault de Supabase (gv_ayuda_config_guardar, sólo supervisor) y NUNCA
   vuelve al navegador: acá sólo se ve «tiene clave · termina en XXXX». La lee la Edge Function
   gv-ayuda con service_role (gv_ayuda_proveedores_server). Los demás quedan de respaldo, en orden.
   ========================================================================================= */
var _aycfg = { filas: null, msg: "", err: "", prueba: "" };
var AYCFG_INFO = {
  gemini: { nom: "Google Gemini", url: "https://aistudio.google.com/apikey", ej: "gemini-2.5-flash" },
  groq: { nom: "Groq", url: "https://console.groq.com/keys", ej: "openai/gpt-oss-120b" },
  openrouter: { nom: "OpenRouter", url: "https://openrouter.ai/keys", ej: "meta-llama/llama-3.3-70b-instruct:free" }
};
async function _aycfgHdr() {
  if (typeof gvWriteHdr === "function") { try { return await gvWriteHdr(); } catch (_e) {} }
  return await _ayudaHdr();
}
async function _aycfgRpc(fn, body) {
  var r = await fetch(SUPABASE_URL + "/rest/v1/rpc/" + fn, { method: "POST", headers: Object.assign({ "Content-Type": "application/json" }, await _aycfgHdr()), body: JSON.stringify(body || {}) });
  var t = await r.text(); var j = null; try { j = JSON.parse(t); } catch (_e) {}
  if (!r.ok) throw new Error((j && (j.message || j.hint)) || ("HTTP " + r.status));
  return j;
}
function _aycfgCss() {
  _ayudaCss();
  if (document.getElementById("aycfgCss")) return;
  var s = document.createElement("style"); s.id = "aycfgCss";
  s.textContent = "#aycfgModal{display:none;position:fixed;inset:0;z-index:1400;background:rgba(2,6,23,.78);padding:10px;}" +
    "#aycfgModal.show{display:flex;align-items:center;justify-content:center;}" +
    "#aycfgModal button{width:auto;margin:0;padding:6px 12px;font-size:13.5px;border-radius:8px;border:0;font-weight:800;cursor:pointer;}" +
    "#aycfgModal input{box-sizing:border-box;font-size:14px;padding:6px 8px;border:1px solid #cbd5e1;border-radius:8px;margin:0;}" +
    ".acf-card{background:#f8fafc;width:100%;max-width:640px;max-height:94vh;overflow:auto;border-radius:16px;box-shadow:0 24px 70px rgba(0,0,0,.5);}" +
    ".acf-head{display:flex;align-items:center;justify-content:space-between;padding:12px 14px;background:#1e3a8a;color:#fff;position:sticky;top:0;}" +
    ".acf-tit{font-size:17px;font-weight:800;}" +
    ".acf-body{padding:12px 14px;display:flex;flex-direction:column;gap:10px;}" +
    ".acf-p{background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:10px 12px;display:grid;grid-template-columns:1fr auto;gap:6px 10px;align-items:center;}" +
    ".acf-p.prin{border:2px solid #1e6bd6;}" +
    ".acf-n{font-weight:800;font-size:15px;}" +
    ".acf-st{font-size:12.5px;color:#475569;}" +
    ".acf-st b{color:#15803d;}" +
    ".acf-row{grid-column:1/-1;display:flex;gap:6px;flex-wrap:wrap;align-items:center;}" +
    ".acf-row input[type=password]{flex:1;min-width:180px;}" +
    ".acf-row input.mod{flex:1;min-width:180px;}" +
    ".acf-ok{background:#1e6bd6;color:#fff;}" +
    ".acf-sec{background:#e2e8f0;color:#0f172a;}" +
    ".acf-del{background:#fee2e2;color:#b91c1c;}" +
    ".acf-msg{font-size:13px;color:#15803d;font-weight:700;}" +
    ".acf-err{font-size:13px;color:#b91c1c;font-weight:700;}" +
    ".acf-x{background:rgba(255,255,255,.2)!important;color:#fff;}" +
    ".acf-pr{white-space:pre-wrap;font-size:13.5px;background:#fff;border:1px solid #e2e8f0;border-radius:10px;padding:8px;}";
  document.head.appendChild(s);
}
async function openAyudaConfig() {
  if (typeof requireSupervisor === "function" && !requireSupervisor()) return;
  _aycfgCss();
  var ov = document.getElementById("aycfgModal");
  if (!ov) {
    ov = document.createElement("div"); ov.id = "aycfgModal";
    ov.addEventListener("click", function (e) { if (e.target === ov) closeAyudaConfig(); });
    document.body.appendChild(ov);
  }
  _aycfg.msg = ""; _aycfg.err = ""; _aycfg.prueba = "";
  ov.classList.add("show");
  await _aycfgCargar();
}
function closeAyudaConfig() { var ov = document.getElementById("aycfgModal"); if (ov) ov.classList.remove("show"); }
async function _aycfgCargar() {
  try { _aycfg.filas = await _aycfgRpc("gv_ayuda_config_leer"); _aycfg.err = ""; }
  catch (e) { _aycfg.filas = null; _aycfg.err = "No se pudo leer la configuración: " + (e && e.message || e); }
  _aycfgPintar();
}
function _aycfgPintar() {
  var ov = document.getElementById("aycfgModal"); if (!ov) return;
  var h = '<div class="acf-card"><div class="acf-head"><span class="acf-tit">🤖 Asistente IA operarios</span>' +
    '<button class="acf-x" onclick="closeAyudaConfig()">✕</button></div><div class="acf-body">';
  if (_aycfg.filas) {
    var prin = (_aycfg.filas.filter(function (f) { return f.activo && f.tiene_clave; })[0] || {}).proveedor;
    _aycfg.filas.forEach(function (f) {
      var inf = AYCFG_INFO[f.proveedor] || { nom: f.proveedor, url: "#", ej: "" };
      var p = f.proveedor;
      h += '<div class="acf-p' + (p === prin ? " prin" : "") + '">' +
        '<div><div class="acf-n">' + _ayudaEsc(inf.nom) + (p === prin ? " · responde primero" : "") + '</div>' +
        '<div class="acf-st">' + (f.tiene_clave ? "<b>Clave cargada</b> · termina en " + _ayudaEsc(f.clave_fin || "????") : "Sin clave") +
        ' · <a href="' + inf.url + '" target="_blank" rel="noopener">conseguir clave gratis</a></div></div>' +
        '<label class="acf-st"><input type="checkbox" id="acfAct_' + p + '"' + (f.activo ? " checked" : "") + '> activo</label>' +
        '<div class="acf-row"><input type="password" id="acfKey_' + p + '" autocomplete="off" placeholder="' + (f.tiene_clave ? "Pegar una clave nueva para reemplazarla" : "Pegar la API key") + '"></div>' +
        '<div class="acf-row"><span class="acf-st">Modelo</span><input class="mod" id="acfMod_' + p + '" value="' + _ayudaEsc(f.modelo || "") + '" placeholder="' + _ayudaEsc(inf.ej) + '">' +
        '<button class="acf-ok" onclick="aycfgGuardar(\'' + p + '\',false)">Guardar</button>' +
        (p !== prin ? '<button class="acf-sec" onclick="aycfgGuardar(\'' + p + '\',true)">Usar este primero</button>' : "") +
        (f.tiene_clave ? '<button class="acf-del" onclick="aycfgBorrar(\'' + p + '\')">Quitar clave</button>' : "") +
        "</div></div>";
    });
    if (!prin) h += '<div class="acf-err">Sin ninguna clave activa el asistente contesta copiando la parte del manual que coincide.</div>';
  }
  if (_aycfg.msg) h += '<div class="acf-msg">' + _ayudaEsc(_aycfg.msg) + "</div>";
  if (_aycfg.err) h += '<div class="acf-err">' + _ayudaEsc(_aycfg.err) + "</div>";
  h += '<div class="acf-row"><input class="mod" id="acfPrueba" maxlength="500" placeholder="Pregunta de prueba (ej: ¿cómo bajo de racks?)">' +
    '<button class="acf-ok" onclick="aycfgProbar()">Probar</button></div>';
  if (_aycfg.prueba) h += '<div class="acf-pr">' + _ayudaEsc(_aycfg.prueba) + "</div>";
  h += "</div></div>";
  ov.innerHTML = h;
}
async function aycfgGuardar(p, principal) {
  var k = document.getElementById("acfKey_" + p), m = document.getElementById("acfMod_" + p), a = document.getElementById("acfAct_" + p);
  var body = { p_proveedor: p, p_api_key: k ? k.value.trim() : null, p_modelo: m ? m.value.trim() : null,
    p_activo: a ? a.checked : null, p_principal: !!principal };
  if (k) k.value = "";
  try { await _aycfgRpc("gv_ayuda_config_guardar", body); _aycfg.msg = "✓ Guardado (" + (AYCFG_INFO[p] || { nom: p }).nom + ")."; _aycfg.err = ""; }
  catch (e) { _aycfg.msg = ""; _aycfg.err = "No se guardó: " + (e && e.message || e); }
  await _aycfgCargar();
}
async function aycfgBorrar(p) {
  if (!confirm("¿Quitar la clave de " + ((AYCFG_INFO[p] || { nom: p }).nom) + "?")) return;
  try { await _aycfgRpc("gv_ayuda_config_guardar", { p_proveedor: p, p_borrar_clave: true }); _aycfg.msg = "✓ Clave quitada."; _aycfg.err = ""; }
  catch (e) { _aycfg.msg = ""; _aycfg.err = "No se quitó: " + (e && e.message || e); }
  await _aycfgCargar();
}
async function aycfgProbar() {
  var i = document.getElementById("acfPrueba"); var q = i ? i.value.trim() : "";
  if (q.length < 2) q = "¿cómo bajo de racks?";
  _aycfg.prueba = "Preguntando… (la configuración nueva tarda hasta 1 minuto en tomarse)"; _aycfgPintar();
  try {
    var r = await fetch(AYUDA_FN_URL, { method: "POST", headers: await _ayudaHdr(), body: JSON.stringify({ pregunta: q, historial: [] }) });
    var j = await r.json().catch(function () { return {}; });
    _aycfg.prueba = r.ok ? "Respondió: " + (j.fuente || "?") + "\n\n" + (j.respuesta || "") : "Error: " + (j.error || ("HTTP " + r.status));
  } catch (e) { _aycfg.prueba = "Sin conexión con el asistente: " + (e && e.message || e); }
  _aycfgPintar();
  var i2 = document.getElementById("acfPrueba"); if (i2) i2.value = q;
}

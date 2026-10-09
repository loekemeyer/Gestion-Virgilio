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

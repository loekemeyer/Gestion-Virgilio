/* monitor/alerta-inactivo.js — v25.79 (Luis, 2026-10-01)
 *
 * ALARMA DE OPERARIO INACTIVO en los monitores (TV de pared, «Vista TV» y «Mon. Admin»).
 *
 *   celular del operario: a los 5 min de tiempo muerto → rpc gv_alerta_inactivo_abrir
 *                         al registrar la próxima tarea → rpc gv_alerta_inactivo_cerrar
 *   este archivo:          lee gv_alertas_inactivo_vivas() cada 4 s y, por cada alerta nueva,
 *                          muestra un cartel centrado del 70 % de la pantalla con alarma sonora.
 *                          Se va a los 15 s o apenas el operario registra algo (cerrada = true).
 *
 * Vive APARTE de tv.html a propósito: tv.html tiene techo de 100 KB (tests/mon-tv.cjs) y
 * admin.html se genera desde tv.html, así que con un <script> los dos lo cargan.
 *
 * ⚠ SONIDO: los navegadores no dejan sonar audio sin que alguien haya tocado la pantalla una vez.
 *   Si el kiosko no se abre con --autoplay-policy=no-user-gesture-required, la primera alarma sale
 *   muda y el cartel lo dice; cualquier toque o tecla habilita el sonido desde ahí.
 */
(function () {
  "use strict";
  var URL_ = window.VIR_SUPABASE_URL, KEY = window.VIR_SUPABASE_KEY;
  if (!URL_ || !KEY) return;
  /* v25.90 (Luis, 01/10): sólo en el monitor del DEPÓSITO. Dentro de un iframe (📺 Vista TV del admin) no corre. */
  try { if (window.self !== window.top) return; } catch (_e) { return; }
  var DURA_MS = 15000, CADA_MS = 4000;
  var vistas = {};          // id → ms en que se mostró por primera vez
  var abiertas = {};        // id → alerta viva en pantalla
  var ctx = null, sirena = null;

  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
  function nombreCorto(n) {
    var p = String(n || "").trim().split(/\s+/);
    return p.length > 2 ? p[0] + " " + p[1] : String(n || "").trim();
  }

  function css() {
    if (document.getElementById("aiCss")) return;
    var s = document.createElement("style"); s.id = "aiCss";
    s.textContent =
      "#aiOv{position:fixed;inset:0;z-index:99999;display:none;align-items:center;justify-content:center;background:rgba(0,0,0,.55);}" +
      "#aiOv.on{display:flex;}" +
      "#aiBox{width:70vw;height:70vh;box-sizing:border-box;border:1.2vmin solid #fff;border-radius:3vmin;display:flex;flex-direction:column;" +
      "align-items:center;justify-content:center;text-align:center;color:#fff;padding:3vmin;animation:aiTit 0.6s steps(1) infinite;" +
      "box-shadow:0 0 6vmin 2vmin rgba(255,0,0,.8);font-family:system-ui,Segoe UI,Arial,sans-serif;}" +
      "@keyframes aiTit{0%{background:#dc2626;}50%{background:#7f1d1d;}}" +
      "#aiBox .ai-ic{font-size:14vmin;line-height:1;animation:aiLat 0.6s ease-in-out infinite;}" +
      "@keyframes aiLat{50%{transform:scale(1.18);}}" +
      "#aiBox .ai-tx{font-size:7.5vmin;font-weight:900;line-height:1.15;margin-top:2vmin;text-shadow:0 .5vmin 0 rgba(0,0,0,.35);}" +
      "#aiBox .ai-tx b{display:block;font-size:10vmin;text-transform:uppercase;}" +
      "#aiBox .ai-mudo{font-size:2.6vmin;font-weight:700;margin-top:3vmin;opacity:.9;}";
    document.head.appendChild(s);
  }
  function caja() {
    css();
    var ov = document.getElementById("aiOv");
    if (!ov) {
      ov = document.createElement("div"); ov.id = "aiOv";
      ov.innerHTML = '<div id="aiBox"></div>';
      document.body.appendChild(ov);
    }
    return ov;
  }

  /* ── sonido: sirena de dos tonos con Web Audio (sin archivos) ── */
  function audio() {
    try {
      if (!ctx) { var AC = window.AudioContext || window.webkitAudioContext; if (!AC) return null; ctx = new AC(); }
      if (ctx.state === "suspended") ctx.resume();
      return ctx;
    } catch (_e) { return null; }
  }
  ["pointerdown", "keydown", "touchstart"].forEach(function (ev) {
    window.addEventListener(ev, function () { audio(); }, { passive: true });
  });
  function sonar() {
    if (sirena) return;
    var c = audio(); if (!c) return;
    try {
      var o = c.createOscillator(), g = c.createGain();
      o.type = "square"; g.gain.value = 0.25;
      o.connect(g); g.connect(c.destination); o.start();
      var alto = false;
      var t = setInterval(function () { alto = !alto; try { o.frequency.setValueAtTime(alto ? 1250 : 820, c.currentTime); } catch (_e) {} }, 350);
      sirena = { o: o, t: t };
    } catch (_e) {}
  }
  function callar() {
    if (!sirena) return;
    try { clearInterval(sirena.t); sirena.o.stop(); } catch (_e) {}
    sirena = null;
  }
  function suena() { return !!(ctx && ctx.state === "running"); }

  function pintar() {
    var ahora = Date.now(), vivas = [];
    Object.keys(abiertas).forEach(function (id) {
      if (ahora - vistas[id] >= DURA_MS) delete abiertas[id]; else vivas.push(abiertas[id]);
    });
    var ov = caja();
    if (!vivas.length) { ov.classList.remove("on"); callar(); return; }
    var nombres = vivas.map(function (a) { return "<b>" + esc(nombreCorto(a.nombre)) + "</b>"; }).join("");
    document.getElementById("aiBox").innerHTML =
      '<div class="ai-ic">⏰</div><div class="ai-tx">' + nombres +
      (vivas.length > 1 ? "llevan" : "lleva") + " más de 5 minutos inactivo" + (vivas.length > 1 ? "s" : "") + "</div>" +
      (suena() ? "" : '<div class="ai-mudo">🔇 Sin sonido: tocá la pantalla una vez para habilitar la alarma</div>');
    ov.classList.add("on");
    sonar();
  }

  function leer() {
    /* un iframe escondido (la otra pestaña del monitor) no suena ni muestra: mide 0 */
    if (!window.innerWidth || !window.innerHeight) return;
    fetch(URL_ + "/rest/v1/rpc/gv_alertas_inactivo_vivas", {
      method: "POST", cache: "no-store",
      headers: { apikey: KEY, Authorization: "Bearer " + KEY, "Content-Type": "application/json" }, body: "{}"
    }).then(function (r) { return r.ok ? r.json() : null; }).then(function (rows) {
      if (!Array.isArray(rows)) return;
      var ahora = Date.now();
      rows.forEach(function (a) {
        var id = String(a.id);
        if (a.cerrada) { delete abiertas[id]; return; }            // registró una tarea → se va solo
        if (!vistas[id]) { vistas[id] = ahora; abiertas[id] = a; }  // nueva: 15 s desde que se ve
      });
      pintar();
    }).catch(function () {});
  }

  window.gvAlertaInactivo = { leer: leer, pintar: pintar, _abiertas: abiertas, _vistas: vistas };
  function arrancar() { leer(); setInterval(leer, CADA_MS); setInterval(pintar, 1000); }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", arrancar); else arrancar();
})();

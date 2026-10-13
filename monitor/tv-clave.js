/* monitor/tv-clave.js — v29.84 (Elías, 13/10/2026): de dónde saca una pantalla el CÓDIGO DE INGRESO.
   [Elías: «1 hay que cambiar» · «no es anon, tiene que ser al enviar con el token que se obtiene de la pantalla»]

   Lo usan la TV de pared (monitor/tv.html), el Mon. Admin (admin.html, generado de tv.html) y el header
   del monitor de index.html. Una sola cuenta, en este archivo.

   Orden:
     1. Con sesión de SUPERVISOR (la pantalla está adentro de Gestión): gv_tv_clave_actual con su token.
     2. Sin sesión (la TV de la pared): la pantalla guarda un SECRETO propio (localStorage gv_tv_secreto) y
        pide el código con él (gv_tv_clave_actual_tv). La primera vez la TV no está vinculada: pide un código
        de 6 dígitos (gv_tv_vincular_pedir) que un supervisor aprueba en ⚙️ Configuración → «📺 Vincular TV».
     3. Mientras la TV no esté vinculada y la base todavía lo permita (parte A de sql/gv_tv_seguridad_v2974.sql),
        cae a gv_tv_clave_actual con la clave pública, para no dejar la pared sin código. Cuando se aplica la
        parte B esa llamada deja de contestar y queda sólo el código de vinculación.

   Devuelve una promesa con { clave, cambia_en_s, fuente: "sesion"|"tv"|"anon", vincular?: "123456",
   revocada?: true } o null si no pudo leer nada (la pantalla deja el número de antes). */
(function (w) {
  "use strict";
  var SEC_KEY = "gv_tv_secreto";

  function secreto() {
    try {
      var s = w.localStorage.getItem(SEC_KEY);
      if (s && s.length >= 32) return s;
      var a = new Uint8Array(32);
      w.crypto.getRandomValues(a);
      s = Array.prototype.map.call(a, function (b) { return ("0" + b.toString(16)).slice(-2); }).join("");
      w.localStorage.setItem(SEC_KEY, s);
      return s;
    } catch (_e) { return null; }
  }

  function rpc(url, key, fn, body, token) {
    return w.fetch(url + "/rest/v1/rpc/" + fn, {
      method: "POST", cache: "no-store",
      headers: { apikey: key, Authorization: "Bearer " + (token || key), "Content-Type": "application/json" },
      body: JSON.stringify(body || {})
    }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; });
  }

  function conClave(j, fuente) {
    if (!j || !j.clave) return null;
    return { clave: String(j.clave), cambia_en_s: Number(j.cambia_en_s) || 60, fuente: fuente };
  }

  w.gvTvClaveLeer = function (url, key, getToken) {
    function anon() { return rpc(url, key, "gv_tv_clave_actual", {}).then(function (j) { return conClave(j, "anon"); }); }
    var tokP;
    try { tokP = Promise.resolve(getToken ? getToken() : null); } catch (_e) { tokP = Promise.resolve(null); }
    return tokP.catch(function () { return null; }).then(function (tok) {
      if (!tok) return null;
      return rpc(url, key, "gv_tv_clave_actual", {}, tok).then(function (j) { return conClave(j, "sesion"); });
    }).then(function (r) {
      if (r) return r;
      var s = secreto();
      if (!s) return anon();
      return rpc(url, key, "gv_tv_clave_actual_tv", { p_secreto: s }).then(function (t) {
        if (t && t.ok && t.clave) return conClave(t, "tv");
        if (t && t.estado === "revocada") {
          return anon().then(function (a) { if (a) { a.revocada = true; return a; } return { revocada: true }; });
        }
        var pedir = (t && t.estado === "pendiente" && t.codigo)
          ? Promise.resolve({ codigo: t.codigo })
          : rpc(url, key, "gv_tv_vincular_pedir",
              { p_secreto: s, p_navegador: String((w.navigator && w.navigator.userAgent) || "").slice(0, 200) });
        return pedir.then(function (p) {
          var cod = (p && p.codigo) || null;
          return anon().then(function (a) {
            if (a) { a.vincular = cod; return a; }
            return cod ? { vincular: cod } : null;
          });
        });
      });
    }).catch(function () { return null; });
  };
})(window);

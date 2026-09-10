/* ============================================================
   INTERRUPTOR DEL LOGIN — una sola linea prende y apaga todo.

     false = SUELTO (hoy). No pide login: se entra directo al menu.
     true  = con login de Google + whitelist, como estaba.

   APAGADO el 2026-08-29 por pedido del usuario: "la pagina ya esta
   privada y va a costar que accedan, por ahora prefiero que este suelto".
   Es momentaneo. Para volver a prenderlo: poner true aca y bumpear el ?v=
   de auth-guard.js en los HTML (si no, las tablets siguen con el cacheado).

   OJO, lo que este interruptor NO cambia: el login siempre fue una tranquera
   de PANTALLA, no una barrera de datos. La clave anon viaja en el HTML de
   cada pagina, asi que quien tenga la URL siempre pudo llamar a las RPCs.
   Lo que de verdad protege la base es la RLS + que toda escritura pase por
   RPCs SECURITY DEFINER que validan. Eso sigue igual, prendido o apagado.
   ============================================================ */
var GP2_AUTH_ON = false;
window.GP2_AUTH_ON = GP2_AUTH_ON;

(function() {
  // 0) Login apagado -> no se controla nada, se entra suelto.
  if (!GP2_AUTH_ON) return;

  // 1) Sin login (sessionStorage) -> mandar a login.
  if (sessionStorage.getItem('gp_auth') !== 'ok') {
    redirigirLogin();
    return;
  }

  // 2) JWT expirado o ausente -> forzar relogin.
  // Supabase v2 guarda la sesion en localStorage bajo "sb-<projectref>-auth-token".
  // El access_token (JWT) tiene "exp" (unix seconds) en el payload base64.
  if (jwtExpiradoOAusente()) {
    sessionStorage.clear();
    redirigirLogin('logout=1');
    return;
  }

  // 3) Si el role es "envios", restringir las paginas accesibles.
  var role = sessionStorage.getItem('gp_role') || 'admin';
  if (role === 'envios') {
    var path = decodeURIComponent(window.location.pathname).toLowerCase();
    var permitidos = [
      'envios-only.html',
      // Tall
      'talleristas/envios/enviostall.html',
      'talleristas/recepcion/recepcion cervantes.html',
      'talleristas/recepcion/devolucion cervantes.html',
      // Prov Serv
      'prov serv/envios/enviosps.html',
      'prov serv/entregas/entregaps.html',
      // Recepción Insumos
      'stockflejes/recepcion.html',
      // Relevamiento (insumos - logística): el GP2 nativo, el viejo se borro el 2026-09-04
      'relevamiento/relevamiento_gp2.html',
      // Avanzado (solo pantalla grande, gated por CSS en envios-only.html)
      'produccion/monitor.html',
      'produccion/maestro.html',
      // Calculadoras
      'calculadora.html',
      'calculadora-basica.html',
      'calcular-cajones.html',
      'login.html'
    ];
    var ok = permitidos.some(function(p){ return path.indexOf(p) !== -1; });
    if (!ok) {
      var script2 = document.querySelector('script[src*="auth-guard"]');
      var src2 = script2.getAttribute('src');
      window.location.replace(src2.replace('auth-guard.js', 'envios-only.html'));
    }
  }

  // ---- helpers ----

  function redirigirLogin(qs) {
    var script = document.querySelector('script[src*="auth-guard"]');
    var src = script.getAttribute('src');
    var dst = src.replace('auth-guard.js', 'login.html');
    if (qs) dst += (dst.indexOf('?') === -1 ? '?' : '&') + qs;
    window.location.replace(dst);
  }

  function jwtExpiradoOAusente() {
    try {
      // Buscar la key sb-*-auth-token (sin hardcodear el projectref por robustez).
      var rawKey = null;
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        if (k && k.indexOf('sb-') === 0 && k.indexOf('-auth-token') !== -1) {
          rawKey = k;
          break;
        }
      }
      if (!rawKey) return true; // no hay sesion guardada -> expirado
      var raw = localStorage.getItem(rawKey);
      if (!raw) return true;
      var session = JSON.parse(raw);
      var token = session && session.access_token;
      if (!token) return true;
      var parts = token.split('.');
      if (parts.length < 2) return true;
      // Decodificar payload base64url
      var b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      // Pad para que length sea multiplo de 4
      while (b64.length % 4) b64 += '=';
      var payload = JSON.parse(atob(b64));
      var ahora = Math.floor(Date.now() / 1000);
      // Margen 30s para evitar carreras justo en el borde.
      return !payload.exp || payload.exp < (ahora + 30);
    } catch (e) {
      // Cualquier error decoding -> mejor forzar relogin que dejar pasar.
      console.warn('[auth-guard] error decoding JWT:', e);
      return true;
    }
  }
})();

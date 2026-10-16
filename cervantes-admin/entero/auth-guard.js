(function() {
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

  // 2c) Problema 824 (Elías, 15/10/2026): el ROL lo dice la BASE, no sessionStorage. Antes bastaba con una
  //     sesión de Google de CUALQUIER gmail (el alta es libre) y escribir gp_auth=ok a mano en la consola: sin
  //     gp_role el guard asumía 'admin'. Ahora la pantalla queda oculta hasta que la base (gp_mi_rol, que lee el
  //     mail del JWT verificado) confirma el rol: sin rol -> afuera; rol distinto al guardado -> se corrige.
  //     Si la base no contesta (red caída), la pantalla sigue como antes: cada RPC vuelve a chequear la whitelist.
  verificarRolEnBase();

  // 3) Si el role es "envios", restringir las paginas accesibles.
  var role = sessionStorage.getItem('gp_role') || 'envios';   // 824: sin rol, lo mínimo (antes 'admin')
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
      // Relevamiento (insumos - logística)
      'relevamiento/relevamiento.html',
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
  // ---- 824: el rol, desde la base ----
  function verificarRolEnBase() {
    var oculto = document.createElement('style');
    oculto.id = 'gp-rol-oculto';
    oculto.textContent = 'html{visibility:hidden!important}';
    (document.head || document.documentElement).appendChild(oculto);
    var mostrar = function () { var e = document.getElementById('gp-rol-oculto'); if (e) e.parentNode.removeChild(e); };
    var tope = setTimeout(mostrar, 8000);   // sin respuesta en 8 s: se muestra (la base igual re-chequea cada RPC)
    var listo = document.readyState === 'loading'
      ? new Promise(function (ok) { document.addEventListener('DOMContentLoaded', ok); }) : Promise.resolve();
    listo.then(pedirRol).then(function (r) {
      clearTimeout(tope);
      if (r.estado === 'sin_rol') { sessionStorage.clear(); purgarSesion(); redirigirLogin('logout=1'); return; }
      if (r.estado === 'vencido') { redirigirLogin(); return; }
      if (r.estado === 'ok' && r.rol !== sessionStorage.getItem('gp_role')) {
        sessionStorage.setItem('gp_role', r.rol); window.location.reload(); return;
      }
      mostrar();
    }, function () { clearTimeout(tope); mostrar(); });
  }

  function pedirRol() {
      var tok = tokenGuardado();
      if (!tok) return Promise.resolve({ estado: 'vencido' });
      return fetch('https://hrxfctzncixxqmpfhskv.supabase.co/rest/v1/rpc/gp_mi_rol', {
        method: 'POST',
        headers: { apikey: 'sb_publishable_BqpAgZH6ty-9wft10_YMhw_0rcIPuWT', Authorization: 'Bearer ' + tok, 'Content-Type': 'application/json' },
        body: '{}'
      }).then(function (res) {
        if (res.status === 401) return { estado: 'vencido' };
        if (!res.ok) return { estado: 'red' };
        return res.json().then(function (rol) { return rol ? { estado: 'ok', rol: rol } : { estado: 'sin_rol' }; });
      });
  }

  function tokenGuardado() {
    try {
      var ses = JSON.parse(localStorage.getItem('sb-hrxfctzncixxqmpfhskv-auth-token') || 'null');
      ses = ses && (ses.currentSession || ses);
      return ses && ses.access_token || null;
    } catch (e) { return null; }
  }

  function purgarSesion() {
    try {
      for (var i = localStorage.length - 1; i >= 0; i--) {
        var k = localStorage.key(i);
        if (k && k.indexOf('sb-hrxfctzncixxqmpfhskv') === 0) localStorage.removeItem(k);
      }
    } catch (e) {}
  }

})();

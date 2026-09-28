// /functions/v1/Impo_Comex_web/<function>   (deploy: Impo_Comex_web, verify_jwt = true)
//
// Puerta de la version WEB de IMPO COMEX (la que se abre desde Gestion Virgilio, boton
// "🛃 IMPO COMEX" en Pedidos Importacion). Fuente: Gestion Virgilio, supabase/impo-comex-web/index.ts
//
// Por que una puerta y no tocar las 12 functions: el portable sigue andando igual, con su
// x-impo-comex-token, y las functions no cambian. La web no conoce el token: manda la sesion
// de Google del supervisor (el JWT de Gestion Virgilio, mismo proyecto y mismo origin) y esta
// puerta:
//   1. acepta solo pedidos desde Gestion Virgilio (GitHub Pages y Vercel; CORS);
//   2. pregunta a la base si ese JWT es de un supervisor (public.es_supervisor_virgilio(): mail
//      en los 3 fijos o en Supervisores_Virgilio). Un usuario anonimo no tiene mail -> no pasa;
//   3. reenvia el pedido a Impo_Comex_<function> agregando el token del servidor y el mail del
//      supervisor (x-impo-comex-usuario), y devuelve la respuesta tal cual.
// El token nunca sale del servidor.

// Gestion Virgilio se publica en GitHub Pages y en Vercel.
const ORIGENES = new Set(['https://loekemeyer.github.io', 'https://gestion-virgilio.vercel.app']);

// Los datos personales de la DDJJ (controlante) NO van en este codigo: viven en la tabla cerrada
// impo_comex.ddjj_controlante y se leen con public.gv_impo_comex_ddjj_controlante(), que solo los
// devuelve a un supervisor. Asi este fuente puede vivir en el repo publico de Gestion Virgilio.

// Las que usa la pantalla (client/src/api.js). respaldos y ncm-inal-check quedan afuera.
const PERMITIDAS = new Set([
  'analyze-docs', 'autorizacion-envases', 'compare-historical', 'editar', 'export-excel',
  'inal-certificados', 'ncm-detect', 'verify-cajas', 'verify-lakout', 'verify-marks',
  'verify-multi-doc',
]);

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;

function envCI(nombre: string): string | null {
  const exacto = Deno.env.get(nombre);
  if (exacto && exacto.trim()) return exacto.trim();
  const buscado = nombre.toLowerCase();
  for (const [k, v] of Object.entries(Deno.env.toObject())) {
    if (k.toLowerCase() === buscado && v && v.trim()) return v.trim();
  }
  return null;
}

function cors(origin: string | null): Record<string, string> {
  const h: Record<string, string> = {
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Expose-Headers': 'content-disposition',
    'Vary': 'Origin',
  };
  if (origin && ORIGENES.has(origin)) h['Access-Control-Allow-Origin'] = origin;
  return h;
}

function json(body: unknown, status: number, origin: string | null) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...cors(origin), 'Content-Type': 'application/json' },
  });
}

// Mail del supervisor, o null si el JWT no es de un supervisor.
// La clave publica la manda el navegador (sb_publishable_): se usa esa, con la del entorno de
// respaldo. Con la del entorno sola, la consulta daba 401 y todo supervisor salia rechazado.
// El mail sale del JWT, que ya valido la plataforma (verify_jwt) y que es_supervisor_virgilio()
// acaba de aceptar. NO se pregunta a /auth/v1/user: si la sesion de Google se renovo o se cerro
// en otra pestana, contesta 403 session_not_found con un token todavia valido (paso el 28/09).
function mailDelJwt(auth: string): string | null {
  try {
    const p = auth.replace(/^Bearer\s+/, '').split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    const j = JSON.parse(atob(p + '='.repeat((4 - p.length % 4) % 4)));
    return typeof j.email === 'string' && j.email ? j.email : null;
  } catch { return null; }
}

async function supervisor(auth: string, apikey: string): Promise<string | null> {
  const rs = await fetch(`${SUPABASE_URL}/rest/v1/rpc/es_supervisor_virgilio`, {
    method: 'POST', body: '{}', headers: { apikey, Authorization: auth, 'Content-Type': 'application/json' },
  });
  if (!rs.ok) { console.error(`[web] supervisor rpc=${rs.status} ${(await rs.text()).slice(0, 200)}`); return null; }
  const es = await rs.json();
  if (es !== true) { console.error(`[web] es_supervisor_virgilio=${JSON.stringify(es)}`); return null; }
  return mailDelJwt(auth);
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get('origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (!origin || !ORIGENES.has(origin)) return json({ error: 'Origen no permitido.', codigo: 'origen' }, 403, origin);

  const url = new URL(req.url);
  const m = url.pathname.match(/\/Impo_Comex_web\/([a-z-]+)\/?$/);
  const fn = m ? m[1] : '';
  if (fn !== 'datos-ddjj' && !PERMITIDAS.has(fn)) return json({ error: `Function desconocida: ${fn || '(vacia)'}`, codigo: 'function' }, 404, origin);

  const auth = req.headers.get('authorization') || '';
  if (!/^Bearer\s+\S+/.test(auth)) return json({ error: 'Iniciá sesión en Gestión Virgilio.', codigo: 'sin_sesion' }, 401, origin);
  let mail: string | null = null;
  try { mail = await supervisor(auth, req.headers.get('apikey') || ANON); } catch (e) { console.error('[web] supervisor', e); }
  if (!mail) return json({ error: 'Sólo los supervisores de Gestión Virgilio pueden usar IMPO COMEX.', codigo: 'no_supervisor' }, 403, origin);

  if (fn === 'datos-ddjj') {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/gv_impo_comex_ddjj_controlante`, {
      method: 'POST', body: '{}',
      headers: { apikey: req.headers.get('apikey') || ANON, Authorization: auth, 'Content-Type': 'application/json' },
    });
    const c = r.ok ? await r.json() : null;
    if (!c) return json({ error: 'No se pudieron leer los datos de la DDJJ.', codigo: 'ddjj' }, 502, origin);
    return json({ controlante: c }, 200, origin);
  }

  const token = envCI('Impo_Comex_APP_TOKEN');
  if (!token) return json({ error: 'Servidor sin configurar.', codigo: 'sin_token_servidor' }, 500, origin);

  const headers: Record<string, string> = {
    apikey: req.headers.get('apikey') || ANON, 'x-impo-comex-token': token, 'x-impo-comex-usuario': mail,
  };
  const ct = req.headers.get('content-type');
  if (ct) headers['content-type'] = ct;

  const destino = `${SUPABASE_URL}/functions/v1/Impo_Comex_${fn}${url.search}`;
  const res = await fetch(destino, {
    method: req.method,
    headers,
    body: req.method === 'GET' || req.method === 'HEAD' ? undefined : req.body,
    // @ts-ignore: necesario para reenviar el body como stream
    duplex: 'half',
  });

  const out = new Headers(cors(origin));
  for (const k of ['content-type', 'content-disposition']) {
    const v = res.headers.get(k);
    if (v) out.set(k, v);
  }
  console.log(`[web] ${mail} ${req.method} ${fn} -> ${res.status}`);
  return new Response(res.body, { status: res.status, headers: out });
});

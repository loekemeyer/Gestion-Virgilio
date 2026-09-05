// ══════════════════════════════════════════════════════════════════════════
// gv-ppp-web-tandas-diarias — arma las tandas del día al comenzar el día
// Proyecto VIRGILIO (hrxfctzncixxqmpfhskv) · verify_jwt = true
// ══════════════════════════════════════════════════════════════════════════
// Lo que pidió el dueño: *"para el comienzo de cada día (lunes a viernes no
// feriado) tiene que elegir las tandas a armar a ese día"*.
//
// La lógica de armado NO está acá: vive en `ppp_web_armar_tandas` (Postgres),
// probada contra 120 días de tandas reales. Esta función es el DISPARADOR y el
// puente hacia LK/Chef, que es lo único que la base no puede hacer sola.
//
// Hace, en orden:
//   1. ¿es día hábil en Argentina? → si no, loguea 'salteada' y corta
//   2. lee LK (`gv_pedidos_web_np_lk`) y Chef (`gv_pedidos_web_np_chef`), que
//      devuelven EXACTAMENTE las mismas columnas — CRUDAS, sin filtrar
//   2b. `gv_pedidos_web_excluidos` — saca lo que NO es de Gestión: lo anterior a
//      `gestion_desde` y lo que Producción/ISIS ya conoce (regla del dueño,
//      2026-09-04). Si esta llamada falla, no se programa nada: falla cerrado.
//   3. `gv_ppp_web_np_asignar`  — registra la NP de cada bloque (= nº de pedido de la página)
//   4. `ppp_web_resync`         — pone al día lo YA programado que cambió
//   5. `gv_ppp_web_zona_lote`   — resuelve la zona de cada NP
//   6. `ppp_web_armar_tandas`   — arma las tandas del día, hasta el cupo de m³
//   7. `PPP_Web_Base`           — la foto de artículos, o el picking sale vacío
//   8. `GV_Tandas_Auto_Log`     — deja constancia, incluso de no haber hecho nada
//
// LK va PRIMERO y Chef después, no en paralelo: si un cliente de LK entró hoy y
// el mismo (por CUIT) también tiene pedido en Chef, el de Chef entra forzado ese
// mismo día. Es la regla del dueño *"clientes que son de la misma razón social y
// piden LK y CH hay que mandarlos el mismo día"*.
//
// ⚠⚠ NO TOCA PRODUCCIÓN VIRGILIO. Escribe en `PPP_Web_Programacion`,
//    `PPP_Web_Base` y `GV_Tandas_Auto_Log`, todas nuestras. De lo compartido
//    sólo se lee (`Zonas_Barrios`, `planify.feriados`) y ni un INSERT toca
//    `PPP_Programacion_Diaria`.
//
// Es IDEMPOTENTE de punta a punta: correrla dos veces el mismo día no duplica ni
// mueve nada ya programado (`ppp_web_armar_tandas` sólo mira lo que no tiene
// tanda). Se puede disparar a mano sin miedo.
// ══════════════════════════════════════════════════════════════════════════

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const VIRGILIO_URL = Deno.env.get("SUPABASE_URL")!;
const VIRGILIO_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Proyecto de LK. Los datos que necesita el armado no son publicos (razon
// social, direccion, detalle de pedidos), asi que la anon key no alcanza y asi
// tiene que seguir.
//
// `GV_LK_SERVICE_KEY` acepta CUALQUIERA de las dos credenciales, sin recompilar:
//   · una secret key `sb_secret_...` del panel de LK — se crea en dos clicks
//     pero BYPASEA la RLS, asi que abre todo LK. Se prefiere sobre la
//     `service_role` legacy porque se revoca sola: borrar esa llave no toca
//     nada mas, mientras que revocar la legacy obliga a rotar el JWT Secret,
//     que invalida la anon key y todas las sesiones abiertas del sitio; o
//   · el token del rol `gv_reader` — solo puede ejecutar las tres funciones
//     `gv_*` de abajo y no lee NI UNA tabla, pero hay que firmarlo aparte
//     (`tools/gv-token-lk.js`).
// Por eso todo va por RPC y no por lectura directa de vistas: `gv_reader` no
// tiene SELECT sobre nada, a proposito. Cambiar de una credencial a la otra es
// cambiar el valor del secreto, sin tocar codigo.
//
// Las dos credenciales viajan distinto y por eso `authLk()` decide sola:
//   · `sb_secret_...` (llave del sistema nuevo) va en los DOS headers, apikey y
//     Authorization. Es lo que espera el gateway para ese formato.
//   · un JWT (`ey...`, como el de `gv_reader`) va en Authorization, y el apikey
//     lleva la anon key de LK, que es publica y ya esta en el front. Ahi quien
//     decide los permisos es el rol del JWT.
const LK_URL = Deno.env.get("GV_LK_URL") ?? "https://kwkclwhmoygunqmlegrg.supabase.co";
const LK_KEY = Deno.env.get("GV_LK_SERVICE_KEY") ?? "";
const LK_ANON = Deno.env.get("GV_LK_ANON") ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt3a2Nsd2htb3lndW5xbWxlZ3JnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk1MjA2NzUsImV4cCI6MjA4NTA5NjY3NX0.soqPY5hfA3RkAJ9jmIms8UtEGUc4WpZztpEbmDijOgU";

const TZ = "America/Argentina/Buenos_Aires";

/** El día de HOY en Argentina. Sin esto, un cron a las 03:01 UTC caería en el
 *  día siguiente para el UTC y en el correcto para nosotros sólo por suerte. */
function hoyArgentina(): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit",
  }).format(new Date());
}

async function vg(path: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(VIRGILIO_URL + path, {
    ...init,
    headers: {
      apikey: VIRGILIO_KEY,
      Authorization: "Bearer " + VIRGILIO_KEY,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });
}

async function vgRpc<T>(fn: string, body: unknown): Promise<T> {
  const r = await vg("/rest/v1/rpc/" + fn, { method: "POST", body: JSON.stringify(body) });
  if (!r.ok) throw new Error(`${fn}: HTTP ${r.status} ${(await r.text()).slice(0, 300)}`);
  return await r.json() as T;
}

function authLk(): { apikey: string; Authorization: string } {
  // Una llave del sistema nuevo no es un JWT: el gateway la quiere en apikey.
  const esLlaveNueva = LK_KEY.startsWith("sb_secret_") || LK_KEY.startsWith("sb_publishable_");
  return {
    apikey: esLlaveNueva ? LK_KEY : LK_ANON,
    Authorization: "Bearer " + LK_KEY,
  };
}

async function lk(path: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(LK_URL + path, {
    ...init,
    headers: {
      ...authLk(),
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });
}

type Fila = Record<string, unknown>;

/** Los pedidos de Loekemeyer. Va por RPC y no leyendo `v_pedidos_web_np`
 *  directo: la vista es `security_invoker`, asi que un rol acotado chocaria con
 *  la RLS de las tablas de abajo y no veria nada. Envuelta en una funcion
 *  SECURITY DEFINER el permiso pasa a ser el GRANT, que es lo que se audita. */
async function traerLk(desde: string): Promise<Fila[]> {
  const r = await lk("/rest/v1/rpc/gv_pedidos_web_np_lk",
    { method: "POST", body: JSON.stringify({ p_desde: desde }) });
  if (!r.ok) throw new Error(`LK gv_pedidos_web_np_lk: HTTP ${r.status} ${(await r.text()).slice(0, 300)}`);
  return await r.json();
}

/** Chef vive en otro proyecto y se lee por FDW desde LK, por eso va por RPC
 *  aparte: unirlo a la vista de LK haria pagar ese costo en cada lectura.
 *
 *  ⚠ Va contra `gv_pedidos_web_np_chef`, NO contra `get_pedidos_web_np_chef` que
 *  usa el front. Dos motivos: la original chequea `auth.uid()` contra
 *  `public.admins` —con la service key eso es NULL y siempre falla— y ademas NO
 *  devuelve el punto de entrega, sin el cual la zona de Chef no resuelve (31 de
 *  38 sin zona antes de arreglarlo, 0 despues). */
async function traerChef(dias: number): Promise<Fila[]> {
  const r = await lk("/rest/v1/rpc/gv_pedidos_web_np_chef",
    { method: "POST", body: JSON.stringify({ p_dias: dias }) });
  if (!r.ok) throw new Error(`Chef RPC: HTTP ${r.status} ${(await r.text()).slice(0, 300)}`);
  return await r.json();
}

/** PENDIENTE PARA GESTIÓN = pedido de la página con fecha >= gestion_desde que
 *  Producción/ISIS no conozca. La regla vive en Virgilio (`gv_pedidos_web_excluidos`,
 *  sql/gv_pedidos_web_excluidos.sql); acá sólo se le pasa (empresa, order_id, cod,
 *  fecha_recep) de cada pedido y se sacan los que devuelve, con el motivo contado
 *  para el log. Los feeds de LK son CRUDOS a propósito: si esta llamada falla, la
 *  empresa entera falla y no se programa nada — antes que duplicar un pedido que
 *  Producción ya tiene, no tomar ninguno (2026-09-04, regla del dueño). */
async function soloPendientes(
  emp: "lk" | "chef", filas: Fila[],
): Promise<{ filas: Fila[]; excluidos: Record<string, number>; pedidos_crudos: number }> {
  const porPedido = new Map<string, Fila>();
  for (const n of filas) { const k = String(n.order_id); if (!porPedido.has(k)) porPedido.set(k, n); }
  if (!porPedido.size) return { filas, excluidos: {}, pedidos_crudos: 0 };
  const p_pedidos = [...porPedido.values()].map((n) => ({
    empresa: emp, order_id: n.order_id, cod: n.cod ?? "", fecha_recep: n.fecha_recep ?? null,
    enviado_a_compras: !!n.enviado_a_compras,
  }));
  const ex = await vgRpc<{ empresa: string; order_id: number; motivo: string }[]>(
    "gv_pedidos_web_excluidos", { p_pedidos });
  const fuera = new Set(ex.map((x) => String(x.order_id)));
  const excluidos: Record<string, number> = {};
  for (const x of ex) excluidos[x.motivo] = (excluidos[x.motivo] ?? 0) + 1;
  return {
    filas: filas.filter((n) => !fuera.has(String(n.order_id))),
    excluidos, pedidos_crudos: porPedido.size,
  };
}

/** Espejo de `pwebDireccion()`: si hay expreso, adónde va el camión de verdad. */
function direccionDe(n: Fila): string {
  const exp = String(n.nombre_expreso ?? "").trim();
  const dexp = String(n.direccion_expreso ?? "").trim();
  const dir = String(n.direccion ?? "").trim();
  if (exp || dexp) return `Exp. ${exp}${dexp ? " — " + dexp : ""} (${dir})`;
  return dir;
}

/** Espejo de `pwebLocalidad()`: zona_expreso → localidad → parseo de la dirección.
 *  El parseo final lo hace el backend (`gv_ppp_web_barrio_de`), así que acá sólo
 *  se elige la fuente; si las dos primeras están vacías se manda la dirección
 *  cruda y la resuelve `gv_ppp_web_zona`. */
function barrioCrudo(n: Fila): { barrio: string; usaDireccion: boolean } {
  const ze = String(n.zona_expreso ?? "").trim();
  if (ze) return { barrio: ze, usaDireccion: false };
  const loc = String(n.localidad ?? "").trim();
  if (loc) return { barrio: loc, usaDireccion: false };
  return { barrio: String(n.direccion ?? "").trim(), usaDireccion: true };
}

/** Resuelve las zonas de todas las filas en UNA sola consulta. Llamar a
 *  `gv_ppp_web_zona` fila por fila serían cientos de round trips. */
async function resolverZonas(entradas: { ze: string; loc: string; dir: string }[]): Promise<string[]> {
  if (!entradas.length) return [];
  const res = await vgRpc<{ r_idx: number; r_zona: string | null }[]>(
    "gv_ppp_web_zona_lote", { p_filas: entradas });
  const out: string[] = new Array(entradas.length).fill("");
  for (const x of res) out[x.r_idx] = x.r_zona ?? "";
  return out;
}

/** Los códigos de Chef que corresponden a estos códigos de LK, por CUIT.
 *  `gv_clientes_lk_ch` es una vista de LK que aparea los dos padrones (357
 *  clientes al 2026-09-04). Por CUIT y no por nombre: los padrones escriben
 *  distinto la misma razón social ("Torres Y Liva S.A Cif" contra "Torres Y Liva"). */
async function codsChefDe(codsLk: string[]): Promise<string[]> {
  if (!codsLk.length) return [];
  const r = await lk("/rest/v1/rpc/gv_cods_chef_de_lk",
    { method: "POST", body: JSON.stringify({ p_cods_lk: codsLk }) });
  if (!r.ok) return [];                   // sin mapeo se sigue igual, no se rompe el armado
  const out = new Set<string>();
  for (const x of await r.json() as { cod_ch: string }[]) out.add(String(x.cod_ch));
  return [...out];
}

/** La etiqueta que ve el operario: "LK 1350" / "LK 1350-2" (bloque 2) / "CH 0217".
 *  El número ES el número de pedido de la página (dueño, 2026-09-05); 4 dígitos.
 *
 *  ⚠ ES UNA COPIA. La fuente de verdad es `gv_ppp_web_np_label(empresa, np)` en
 *  Supabase; acá se duplica para no pagar un round trip por cada línea de la
 *  foto de artículos. Si cambia el formato, se cambia PRIMERO en el backend.
 *
 *  Pasado 9999 la etiqueta crece ("LK 10000") en vez de recortarse: recortar
 *  repetiría un número ya usado. */
function npLabel(empresa: string, num: number, idx = 1): string {
  const emp = String(empresa).toLowerCase() === "chef" || String(empresa).toUpperCase() === "CH" ? "CH" : "LK";
  const n = String(num);
  return emp + " " + (n.length >= 4 ? n : n.padStart(4, "0")) + (idx > 1 ? "-" + idx : "");
}

/** Umbral del armado intradía (idea 7317): `intradia_umbral_m3`, si no el tope de
 *  mezcla `tanda_m3_max_mezcla`, si no 0,80. */
async function umbralIntradia(): Promise<number> {
  const r = await vg("/rest/v1/PPP_Web_Config?select=clave,valor&clave=in.(intradia_umbral_m3,tanda_m3_max_mezcla)");
  const rows = r.ok ? await r.json() as { clave: string; valor: number | null }[] : [];
  const de = (k: string) => { const x = rows.find((y) => y.clave === k); return x && x.valor != null ? Number(x.valor) : NaN; };
  const u = de("intradia_umbral_m3");
  if (!isNaN(u) && u > 0) return u;
  const t = de("tanda_m3_max_mezcla");
  return (!isNaN(t) && t > 0) ? t : 0.8;
}

/** Lo PENDIENTE del armado automático: filas de la empresa que todavía no tienen tanda
 *  y cuya zona es automática (`gv_ppp_web_zona_automatica`: hoy 1 y 2; Súper, Retira y
 *  el resto nunca). Es lo que se compara contra el umbral intradía. Sólo lee. */
async function pendienteAutomatico(emp: "lk" | "chef", filas: Fila[]): Promise<{ m3: number; np: number; zonas: Record<string, number> }> {
  if (!filas.length) return { m3: 0, np: 0, zonas: {} };
  const rProg = await vg(`/rest/v1/PPP_Web_Programacion?select=order_id,np_idx` +
    `&empresa=eq.${emp}&tanda=not.is.null&limit=20000`);
  const progRows = rProg.ok ? await rProg.json() as { order_id: number; np_idx: number }[] : [];
  const conTanda = new Set(progRows.map((x) => `${x.order_id}|${x.np_idx}`));
  const pend = filas.filter((n) => !conTanda.has(`${n.order_id}|${n.np_idx}`));
  if (!pend.length) return { m3: 0, np: 0, zonas: {} };
  const zonas = await resolverZonas(pend.map((n) => {
    const b = barrioCrudo(n);
    return b.usaDireccion ? { ze: "", loc: "", dir: b.barrio } : { ze: b.barrio, loc: "", dir: "" };
  }));
  const auto = new Map<string, boolean>();
  for (const z of new Set(zonas.filter(Boolean))) {
    try { auto.set(z, await vgRpc<boolean>("gv_ppp_web_zona_automatica", { p_zona: z })); }
    catch (_e) { auto.set(z, false); }
  }
  let m3 = 0, np = 0;
  const porZona: Record<string, number> = {};
  pend.forEach((n, i) => {
    const z = zonas[i] || "";
    if (!auto.get(z)) return;
    m3 += Number(n.m3) || 0; np++;
    porZona[z] = (porZona[z] ?? 0) + (Number(n.m3) || 0);
  });
  return { m3: Math.round(m3 * 1000) / 1000, np, zonas: porZona };
}

async function procesarEmpresa(
  emp: "lk" | "chef", filas: Fila[], fecha: string, forzarCods: string[] = [],
) {
  if (!filas.length) {
    return { np_leidas: 0, np_programadas: 0, tandas: [] as unknown[], codsHoy: [] as string[] };
  }

  // ── 1. numerar ──────────────────────────────────────────────────────────
  // Va por `gv_ppp_web_np_asignar` y NO por `ppp_web_np_asignar`, que es la
  // puerta del front y arranca con `if auth.uid() is null then raise`. Acá no
  // hay nadie logueado: `vg()` entra con la service key y `auth.uid()` da NULL,
  // así que la original tira "Se necesita sesión" y el job muere sin numerar
  // nada (pasó de verdad el 2026-09-04, log id 2). La lógica de numeración es
  // LA MISMA —la original delega en esta— sólo cambia el candado: GRANT a
  // `service_role` en vez de sesión.
  //
  // ⚠ Hasta que Gestión reemplace a Producción esto CORTA a propósito:
  //   `PPP_Web_Config.numeracion_activa = 0`. Hoy la NP la manda ISIS a la hoja
  //   de cálculos y la usa Producción; Gestión numera recién el día del cambio.
  const pares = filas.map((n) => ({ order_id: n.order_id, np_idx: n.np_idx }));
  const nums = await vgRpc<{ r_order_id: number; r_np_idx: number; r_np: number }[]>(
    "gv_ppp_web_np_asignar", { p_empresa: emp, p_pares: pares });
  const numDe = new Map<string, number>();
  for (const x of nums) numDe.set(`${x.r_order_id}|${x.r_np_idx}`, x.r_np);

  // ── 2. resync: lo YA programado que cambió durante la noche ─────────────
  const filasResync = filas.map((n) => ({
    order_id: n.order_id, np_idx: n.np_idx,
    m3: n.m3, m3_parcial: !!n.m3_parcial, lineas: n.lineas, cajas: n.cajas,
    cod: n.cod ?? null, razon_social: n.razon_social ?? null,
    direccion: direccionDe(n) || null, barrio: barrioCrudo(n).barrio || null,
  }));
  await vgRpc("ppp_web_resync", { p_empresa: emp, p_filas: filasResync });

  // ── 3. zona ─────────────────────────────────────────────────────────────
  const zonas = await resolverZonas(filas.map((n) => {
    const b = barrioCrudo(n);
    return b.usaDireccion
      ? { ze: "", loc: "", dir: b.barrio }
      : { ze: b.barrio, loc: "", dir: "" };
  }));

  // ── 4. armar las tandas ─────────────────────────────────────────────────
  const filasTanda = filas.map((n, i) => ({
    order_id: n.order_id, np_idx: n.np_idx,
    np: numDe.get(`${n.order_id}|${n.np_idx}`) ?? null,
    zona: zonas[i] || "",
    cod: n.cod ?? null, razon_social: n.razon_social ?? null,
    direccion: direccionDe(n) || null, barrio: barrioCrudo(n).barrio || null,
    // La antigüedad es con lo que se ordena la cola cuando no entra todo.
    fecha_recep: n.fecha_recep ?? null,
    m3: n.m3, m3_parcial: !!n.m3_parcial, lineas: n.lineas, cajas: n.cajas,
  }));
  const tandas = await vgRpc<{ r_tanda: string; r_zona: string; r_np_count: number; r_m3: number; r_clientes: number }[]>(
    "ppp_web_armar_tandas",
    { p_empresa: emp, p_fecha: fecha, p_filas: filasTanda, p_forzar_cods: forzarCods });

  // ── 5. la foto de artículos ─────────────────────────────────────────────
  // Sin esto el operario abre la tanda y no ve un solo artículo. El front las
  // escribe juntas (`pwebGuardarProg`) y `ppp_web_armar_tandas` no la toca, así
  // que le toca a esta función. Se suma por código —el carrito puede repetir un
  // artículo y el picking cuenta cajas por código, no renglones— y se ordena,
  // para que dos corridas den el mismo orden de líneas.
  const rProg = await vg(`/rest/v1/PPP_Web_Programacion?select=order_id,np_idx` +
    `&empresa=eq.${emp}&tanda=not.is.null&limit=20000`);
  const progRows = rProg.ok ? await rProg.json() as { order_id: number; np_idx: number }[] : [];
  const programadas = new Set(progRows.map((x) => `${x.order_id}|${x.np_idx}`));

  const lineas: Fila[] = [];
  for (const n of filas) {
    const k = `${n.order_id}|${n.np_idx}`;
    if (!programadas.has(k)) continue;              // sin tanda no hay nada que pickear
    const num = numDe.get(k);
    if (!num) continue;
    const porArt: Record<string, number> = {};
    for (const it of (n.items as { art: string; cajas: number }[] ?? [])) {
      const a = String(it.art ?? "").trim();
      if (!a) continue;
      porArt[a] = (porArt[a] ?? 0) + (Number(it.cajas) || 0);
    }
    for (const a of Object.keys(porArt).sort()) {
      lineas.push({
        empresa: emp, order_id: n.order_id, np_idx: n.np_idx,
        np_label: npLabel(emp, num, Number(n.np_idx) || 1), articulo: a, cajas: porArt[a],
      });
    }
  }
  if (lineas.length) {
    const rb = await vg("/rest/v1/PPP_Web_Base?on_conflict=empresa,order_id,np_idx,articulo", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify(lineas),
    });
    if (!rb.ok) {
      throw new Error(`PPP_Web_Base: HTTP ${rb.status} ${(await rb.text()).slice(0, 300)} ` +
        `— la tanda quedó programada pero el operario la vería vacía.`);
    }
  }

  // Los clientes que entraron HOY, para encadenar Chef con LK.
  const rHoy = await vg(`/rest/v1/PPP_Web_Programacion?select=cod_cliente` +
    `&empresa=eq.${emp}&fecha_entrega=eq.${fecha}&tanda=not.is.null&limit=20000`);
  const codsHoy = rHoy.ok
    ? [...new Set((await rHoy.json() as { cod_cliente: string }[])
        .map((x) => String(x.cod_cliente)).filter(Boolean))]
    : [];

  return { np_leidas: filas.length, np_programadas: programadas.size, tandas, codsHoy };
}

Deno.serve(async (req: Request) => {
  const t0 = Date.now();
  const url = new URL(req.url);

  // Los flags valen tanto en la query (`?dry=1`) como en el body
  // (`{"dry":true}`). Antes eran SÓLO query, y mandar `{"dry":true}` en el body
  // no daba error: se ignoraba en silencio y la corrida salía POR EL CAMINO
  // REAL creyendo uno que era una prueba (pasó el 2026-09-04). Un flag de
  // seguridad que se ignora sin avisar es peor que no tenerlo.
  let cuerpo: Record<string, unknown> = {};
  try { cuerpo = await req.json() as Record<string, unknown>; } catch (_e) { /* body vacío: el cron manda {} */ }
  const flag = (k: string) =>
    url.searchParams.get(k) === "1" || cuerpo[k] === true || cuerpo[k] === "1";

  // `forzar` corre aunque sea sábado o feriado. Para probar a mano.
  const forzar = flag("forzar");
  // `dry` hace todo menos escribir: no numera, no resync, no arma. Sólo mide.
  const dry = flag("dry");
  // `esperar` devuelve el resultado en vez de contestar al toque (ver abajo).
  const esperar = flag("esperar");
  // `intradia` (idea 7317, 2026-09-05): corrida DURANTE el día, cada 15 min. Sólo arma si
  // lo pendiente sin tanda de las zonas automáticas (1 y 2; Súper nunca) suma
  // ≥ `intradia_umbral_m3` (0,80), y lo arma para la fecha que elige
  // `gv_ppp_web_proximo_dia_entrega` (hoy si es antes de las 12:00 y hay cupo; si no,
  // el próximo hábil con cupo). Lo que no llega al umbral lo arma igual el job de las 00:01.
  const intradia = flag("intradia");
  const fechaExplicita = url.searchParams.get("fecha") ??
    (typeof cuerpo.fecha === "string" ? cuerpo.fecha : null);
  let fecha = fechaExplicita ?? hoyArgentina();

  const log = async (estado: string, motivo: string | null, extra: Record<string, unknown>) => {
    try {
      await vg("/rest/v1/GV_Tandas_Auto_Log", {
        method: "POST",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify([{
          fecha_objetivo: fecha, estado, motivo,
          ms: Date.now() - t0, ...extra,
        }]),
      });
    } catch (_e) { /* el log no puede tumbar la corrida */ }
  };

  const trabajo = async (): Promise<{ status: number; body: Record<string, unknown> }> => {
    try {
      // ── intradía: la fecha la elige el backend ────────────────────────
      if (intradia && !fechaExplicita) {
        fecha = await vgRpc<string>("gv_ppp_web_proximo_dia_entrega", {});
      }
      // ── día hábil ─────────────────────────────────────────────────────
      const habil = await vgRpc<boolean>("gv_es_dia_habil", { p_fecha: fecha });
      if (!habil && !forzar) {
        const motivo = "No es día hábil (fin de semana o feriado)";
        if (!dry) await log("salteada", motivo, {});
        return { status: 200, body: { ok: true, fecha, salteada: true, motivo } };
      }

      if (!LK_KEY) throw new Error("Falta el secreto GV_LK_SERVICE_KEY (secret key de LK, o token de gv_reader).");

      const rCfg = await vg("/rest/v1/PPP_Web_Config?select=valor&clave=eq.ventana_dias");
      const cfg = rCfg.ok ? await rCfg.json() as { valor: number }[] : [];
      const ventana = Number(cfg[0]?.valor) || 30;
      const desde = new Date(Date.now() - ventana * 86400000).toISOString().slice(0, 10);

      // Modo prueba: lee las dos fuentes y resuelve zonas, sin escribir nada.
      if (dry) {
        const out: Record<string, unknown> = {};
        let m3Auto = 0, npAuto = 0;
        for (const emp of ["lk", "chef"] as const) {
          try {
            const crudas = emp === "lk" ? await traerLk(desde) : await traerChef(ventana);
            const { filas, excluidos, pedidos_crudos } = await soloPendientes(emp, crudas);
            const zonas = await resolverZonas(filas.map((n) => {
              const b = barrioCrudo(n);
              return b.usaDireccion ? { ze: "", loc: "", dir: b.barrio } : { ze: b.barrio, loc: "", dir: "" };
            }));
            const porZona: Record<string, number> = {};
            zonas.forEach((z) => { const k = z || "(sin zona)"; porZona[k] = (porZona[k] ?? 0) + 1; });
            const pend = await pendienteAutomatico(emp, filas);
            m3Auto += pend.m3; npAuto += pend.np;
            out[emp] = {
              np_crudas: crudas.length, pedidos_crudos, excluidos,
              np_leidas: filas.length,
              con_fecha_pactada: filas.filter((n) => n.fecha_entrega_pactada).length,
              por_zona: porZona,
              pendiente_automatico: pend,
            };
          } catch (e) {
            out[emp] = { error: e instanceof Error ? e.message : String(e) };
          }
        }
        const umbral = await umbralIntradia();
        return { status: 200, body: { ok: true, dry: true, intradia, fecha, ventana, umbral_m3: umbral, m3_pendiente_automatico: m3Auto, np_pendiente_automatico: npAuto, armaria: m3Auto >= umbral, detalle: out } };
      }

      // Las dos empresas por separado: si Chef falla, LK igual queda armado.
      // LK va primero porque de ahí salen los clientes a forzar en Chef.
      const out: Record<string, unknown> = {};
      let leidas = 0, programadas = 0, nTandas = 0;
      const errores: string[] = [];
      let forzarChef: string[] = [];

      // ── intradía: ¿se llegó al umbral? ─────────────────────────────────
      // Se leen las dos fuentes UNA vez (se reutilizan abajo) y se suma lo pendiente
      // sin tanda de las zonas automáticas. Por debajo del umbral no se escribe nada
      // salvo el log; a las 00:01 el job normal arma lo que quedó chico.
      let filasLk: Fila[] | null = null, filasChef: Fila[] | null = null;
      let exLk: Record<string, number> = {}, exChef: Record<string, number> = {};
      if (intradia) {
        const umbral = await umbralIntradia();
        let m3Auto = 0, npAuto = 0;
        const det: Record<string, unknown> = {};
        try {
          const s = await soloPendientes("lk", await traerLk(desde)); filasLk = s.filas; exLk = s.excluidos;
          const p = await pendienteAutomatico("lk", filasLk); m3Auto += p.m3; npAuto += p.np; det.lk = p;
        } catch (e) { det.lk = { error: e instanceof Error ? e.message : String(e) }; }
        try {
          const s = await soloPendientes("chef", await traerChef(ventana)); filasChef = s.filas; exChef = s.excluidos;
          const p = await pendienteAutomatico("chef", filasChef); m3Auto += p.m3; npAuto += p.np; det.chef = p;
        } catch (e) { det.chef = { error: e instanceof Error ? e.message : String(e) }; }
        if (m3Auto < umbral) {
          const motivo = `intradía: pendiente automático ${m3Auto.toFixed(3)} m³ (${npAuto} NP) < umbral ${umbral} m³`;
          await log("intradia_sin_umbral", motivo, { np_leidas: (filasLk?.length ?? 0) + (filasChef?.length ?? 0), detalle: { m3_pendiente_automatico: m3Auto, np_pendiente_automatico: npAuto, umbral_m3: umbral, ...det } });
          return { status: 200, body: { ok: true, intradia: true, fecha, armo: false, motivo, m3_pendiente_automatico: m3Auto, umbral_m3: umbral } };
        }
        out.intradia = { m3_pendiente_automatico: m3Auto, np_pendiente_automatico: npAuto, umbral_m3: umbral, ...det };
      }

      try {
        const { filas, excluidos } = filasLk
          ? { filas: filasLk, excluidos: exLk }
          : await soloPendientes("lk", await traerLk(desde));
        const r = await procesarEmpresa("lk", filas, fecha);
        leidas += r.np_leidas; programadas += r.np_programadas; nTandas += r.tandas.length;
        out.lk = { np_leidas: r.np_leidas, excluidos, tandas_nuevas: r.tandas };
        // Misma razón social pidiendo a las dos empresas → el mismo día.
        forzarChef = await codsChefDe(r.codsHoy);
        if (forzarChef.length) out.forzados_en_chef = forzarChef;
      } catch (e) {
        const msg = `lk: ${e instanceof Error ? e.message : String(e)}`;
        errores.push(msg); out.lk = { error: msg };
      }

      try {
        const { filas, excluidos } = filasChef
          ? { filas: filasChef, excluidos: exChef }
          : await soloPendientes("chef", await traerChef(ventana));
        const r = await procesarEmpresa("chef", filas, fecha, forzarChef);
        leidas += r.np_leidas; programadas += r.np_programadas; nTandas += r.tandas.length;
        out.chef = { np_leidas: r.np_leidas, excluidos, tandas_nuevas: r.tandas };
      } catch (e) {
        const msg = `chef: ${e instanceof Error ? e.message : String(e)}`;
        errores.push(msg); out.chef = { error: msg };
      }

      const estado = errores.length === 2 ? "error" : (intradia ? "intradia_ok" : "ok");
      await log(estado, errores.length ? errores.join(" | ") : null, {
        np_leidas: leidas, np_programadas: programadas, tandas: nTandas, detalle: out,
      });
      return {
        status: estado === "error" ? 500 : 200,
        body: { ok: estado !== "error", intradia, fecha, tandas: nTandas, detalle: out },
      };
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      await log("error", msg, {});
      return { status: 500, body: { ok: false, fecha, error: msg } };
    }
  };

  // ⚠ El cron NO espera el resultado, y no es un detalle: `pg_net` corta a los
  //   5 segundos (probado el 2026-09-04 — le pasamos timeout_milliseconds y lo
  //   ignoró igual), y la corrida real pasa de eso porque leer Chef va por FDW.
  //   Si esperáramos, el cron registraría un timeout en cada corrida y encima el
  //   trabajo podría quedar cortado a la mitad, con escrituras parciales.
  //   Entonces: se contesta al instante y el trabajo sigue con `waitUntil`. El
  //   resultado se mira en `GV_Tandas_Auto_Log`, que para eso está.
  //   Con `?dry=1` o `?esperar=1` sí se espera, que es como se prueba a mano.
  if (dry || esperar) {
    const r = await trabajo();
    return Response.json(r.body, { status: r.status });
  }
  EdgeRuntime.waitUntil(trabajo());
  return Response.json({ ok: true, encolada: true, fecha });
});

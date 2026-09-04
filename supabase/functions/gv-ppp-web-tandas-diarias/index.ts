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
//   2. lee LK (`gv_pedidos_web_np_lk`) y Chef (`gv_pedidos_web_np_chef`)
//   3. `ppp_web_np_asignar`     — numera lo que no tiene número
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
//   · el token del rol `gv_reader` (recomendado) — solo puede ejecutar las tres
//     funciones `gv_*` de abajo y no lee NI UNA tabla; o
//   · la service key de LK, que abre todo.
// Por eso todo va por RPC y no por lectura directa de vistas: `gv_reader` no
// tiene SELECT sobre nada, a proposito.
//
// El header `apikey` va SIEMPRE con la anon key de LK (es publica, esta en el
// front) porque el gateway la exige; quien decide los permisos es el JWT del
// Authorization.
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

async function lk(path: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(LK_URL + path, {
    ...init,
    headers: {
      apikey: LK_ANON,
      Authorization: "Bearer " + LK_KEY,
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

/** Chef vive en otro proyecto y se lee por FDW desde LK (~3,3 s), por eso va por
 *  RPC aparte: unirlo a la vista de LK haría pagar ese costo en cada lectura.
 *
 *  ⚠ Va contra `gv_pedidos_web_np_chef`, NO contra `get_pedidos_web_np_chef` que
 *  usa el front. El original chequea `auth.uid()` contra `public.admins`, y acá
 *  corremos con la service key: `auth.uid()` es NULL, así que ese chequeo siempre
 *  falla. El gemelo `gv_` no tiene ese chequeo — su gate es el GRANT, que sólo
 *  alcanza a `service_role` y a `gv_reader`. */
async function traerChef(dias: number): Promise<Fila[]> {
  const r = await lk("/rest/v1/rpc/gv_pedidos_web_np_chef",
    { method: "POST", body: JSON.stringify({ p_dias: dias }) });
  if (!r.ok) throw new Error(`Chef RPC: HTTP ${r.status} ${(await r.text()).slice(0, 300)}`);
  return await r.json();
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

/** La etiqueta que ve el operario: "LK 1343". */
function npLabel(empresa: string, num: number): string {
  return (String(empresa).toLowerCase() === "chef" || String(empresa).toUpperCase() === "CH" ? "CH" : "LK") +
    " " + num;
}

async function procesarEmpresa(
  emp: "lk" | "chef", filas: Fila[], fecha: string, forzarCods: string[] = [],
) {
  if (!filas.length) {
    return { np_leidas: 0, np_programadas: 0, tandas: [] as unknown[], codsHoy: [] as string[] };
  }

  // ── 1. numerar ──────────────────────────────────────────────────────────
  const pares = filas.map((n) => ({ order_id: n.order_id, np_idx: n.np_idx }));
  const nums = await vgRpc<{ r_order_id: number; r_np_idx: number; r_np: number }[]>(
    "ppp_web_np_asignar", { p_empresa: emp, p_pares: pares });
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
        np_label: npLabel(emp, num), articulo: a, cajas: porArt[a],
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
  // `?forzar=1` corre aunque sea sábado o feriado. Para probar a mano.
  const forzar = url.searchParams.get("forzar") === "1";
  // `?dry=1` hace todo menos escribir: no numera, no resync, no arma. Sólo mide.
  const dry = url.searchParams.get("dry") === "1";
  const fecha = url.searchParams.get("fecha") ?? hoyArgentina();

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

  try {
    // ── día hábil ─────────────────────────────────────────────────────────
    const habil = await vgRpc<boolean>("gv_es_dia_habil", { p_fecha: fecha });
    if (!habil && !forzar) {
      const motivo = "No es día hábil (fin de semana o feriado)";
      if (!dry) await log("salteada", motivo, {});
      return Response.json({ ok: true, fecha, salteada: true, motivo });
    }

    if (!LK_KEY) throw new Error("Falta el secreto GV_LK_SERVICE_KEY (token de gv_reader, o service_role de LK).");

    const rCfg = await vg("/rest/v1/PPP_Web_Config?select=valor&clave=eq.ventana_dias");
    const cfg = rCfg.ok ? await rCfg.json() as { valor: number }[] : [];
    const ventana = Number(cfg[0]?.valor) || 30;
    const desde = new Date(Date.now() - ventana * 86400000).toISOString().slice(0, 10);

    // Modo prueba: lee las dos fuentes y resuelve zonas, sin escribir nada.
    if (dry) {
      const out: Record<string, unknown> = {};
      for (const emp of ["lk", "chef"] as const) {
        try {
          const filas = emp === "lk" ? await traerLk(desde) : await traerChef(ventana);
          const zonas = await resolverZonas(filas.map((n) => {
            const b = barrioCrudo(n);
            return b.usaDireccion ? { ze: "", loc: "", dir: b.barrio } : { ze: b.barrio, loc: "", dir: "" };
          }));
          const porZona: Record<string, number> = {};
          zonas.forEach((z) => { const k = z || "(sin zona)"; porZona[k] = (porZona[k] ?? 0) + 1; });
          out[emp] = { np_leidas: filas.length, por_zona: porZona };
        } catch (e) {
          out[emp] = { error: e instanceof Error ? e.message : String(e) };
        }
      }
      return Response.json({ ok: true, dry: true, fecha, ventana, detalle: out });
    }

    // Las dos empresas por separado: si Chef falla, LK igual queda armado.
    // LK va primero porque de ahí salen los clientes a forzar en Chef.
    const out: Record<string, unknown> = {};
    let leidas = 0, programadas = 0, nTandas = 0;
    const errores: string[] = [];
    let forzarChef: string[] = [];

    try {
      const filas = await traerLk(desde);
      const r = await procesarEmpresa("lk", filas, fecha);
      leidas += r.np_leidas; programadas += r.np_programadas; nTandas += r.tandas.length;
      out.lk = { np_leidas: r.np_leidas, tandas_nuevas: r.tandas };
      // Misma razón social pidiendo a las dos empresas → el mismo día.
      forzarChef = await codsChefDe(r.codsHoy);
      if (forzarChef.length) out.forzados_en_chef = forzarChef;
    } catch (e) {
      const msg = `lk: ${e instanceof Error ? e.message : String(e)}`;
      errores.push(msg); out.lk = { error: msg };
    }

    try {
      const filas = await traerChef(ventana);
      const r = await procesarEmpresa("chef", filas, fecha, forzarChef);
      leidas += r.np_leidas; programadas += r.np_programadas; nTandas += r.tandas.length;
      out.chef = { np_leidas: r.np_leidas, tandas_nuevas: r.tandas };
    } catch (e) {
      const msg = `chef: ${e instanceof Error ? e.message : String(e)}`;
      errores.push(msg); out.chef = { error: msg };
    }

    const estado = errores.length === 2 ? "error" : "ok";
    await log(estado, errores.length ? errores.join(" | ") : null, {
      np_leidas: leidas, np_programadas: programadas, tandas: nTandas, detalle: out,
    });
    return Response.json({ ok: estado === "ok", fecha, tandas: nTandas, detalle: out },
      { status: estado === "ok" ? 200 : 500 });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await log("error", msg, {});
    return Response.json({ ok: false, fecha, error: msg }, { status: 500 });
  }
});

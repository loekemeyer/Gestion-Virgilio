// ══════════════════════════════════════════════════════════════════════════
// gv-geocodificar — ubica en el mapa las direcciones programadas que faltan
// Proyecto VIRGILIO (hrxfctzncixxqmpfhskv) · verify_jwt = true
// ══════════════════════════════════════════════════════════════════════════
// Lo que pidió el dueño (2026-09-06): *"todo tenés que tener todas las
// ubicaciones"*. Hasta hoy la única forma de geocodificar era que un supervisor
// abriera 📍 Mapa de zonas y tocara "Geocodificar faltantes": la última corrida
// era del 21/08 y quedaban 43 de 54 direcciones sin ubicar. Sin ubicación, el
// orden de carga del camión manda ese pedido al final y el reparto se arma mal.
//
// Hace, en orden:
//   1. lee `gv_geo_faltantes` (ISIS + web, sin las que ya están por (cód,dir)
//      ni por dirección; Retira no cuenta)
//   2. por cada una le pregunta a Nominatim/OpenStreetMap, UNA POR SEGUNDO —
//      es el límite de la política de uso gratuita y no se negocia
//   3. escribe la ubicación en `GV_Geo_Cliente` (cód + dirección: nuestra) y
//      AGREGA la fila a `PPP_Geo` si no está
//   4. deja constancia en `GV_Geo_Log`, incluso cuando no hubo nada que hacer
//
// ⚠⚠ `PPP_Geo` es COMPARTIDA con Producción Virgilio (la usa su index.html).
//    Acá sólo se le AGREGAN filas (`Prefer: resolution=ignore-duplicates`):
//    ni un update ni un delete sobre lo que ya existe.
//
// Es idempotente: lo que ya tiene ubicación no vuelve a pedirse, así que
// correrla dos veces seguidas no gasta ni una llamada de más.
//
// El tope de `MAX_POR_CORRIDA` existe para no pasarse del tiempo de ejecución de
// la Edge Function: con 1 llamada por segundo, 40 son ~45 s. Lo que sobra queda
// para la corrida siguiente del cron (cada 6 h), y el propio log lo dice.
// ══════════════════════════════════════════════════════════════════════════

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const MAX_POR_CORRIDA = 40;
const ESPERA_MS = 1100;          // 1 por segundo + margen (política de Nominatim)
// Nominatim EXIGE un User-Agent que identifique a la aplicación. Sin esto
// devuelve 403 y la función parece "no encontrar nada".
const UA = "GestionVirgilio/1.0 (deposito Loekemeyer; contacto por el repo loekemeyer/Gestion-Virgilio)";

type Falt = {
  fuente: string; cod: string; razon_social: string | null;
  direccion: string; barrio: string | null; zona: string | null;
  dir_key: string;
  // v13.41: `dir_query` y `barrio_geo` vienen YA corregidos por `GV_Geo_Correccion` (la vista los
  // resuelve). Acá no se sabe nada de correcciones: se pregunta lo que la vista entrega.
  dir_query: string; barrio_geo: string | null; corregida?: boolean;
};

const H = { apikey: KEY, Authorization: "Bearer " + KEY, "Content-Type": "application/json" };

async function rest(path: string, init?: RequestInit) {
  const r = await fetch(URL_ + "/rest/v1/" + path, { ...init, headers: { ...H, ...((init?.headers as object) || {}) } });
  if (!r.ok) throw new Error(path.split("?")[0] + " → HTTP " + r.status + " " + (await r.text()).slice(0, 300));
  const t = await r.text();
  return t ? JSON.parse(t) : null;
}

type Coord = { lat: number; lng: number; comp: unknown };

/* ISIS escribe los barrios abreviados o mal, y con eso Nominatim no encuentra nada.
   Sólo los que aparecieron de verdad en la programación; el resto va tal cual. */
const BARRIOS: Record<string, string> = {
  "p.patricios": "Parque Patricios", "p. patricios": "Parque Patricios",
  "soldati": "Villa Soldati", "tortuguita": "Tortuguitas", "moron": "Morón",
  "lujan": "Luján", "g. de laferrere": "Gregorio de Laferrere", "pompeya": "Nueva Pompeya",
};
function barrioOk(b: string | null) {
  const k = String(b || "").trim().toLowerCase();
  return BARRIOS[k] || String(b || "").trim();
}

/* Sin acentos, minúsculas, un espacio: para comparar "Morón" con "moron" o "Luján" con "lujan". */
function plano(s: unknown) {
  return String(s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/\s+/g, " ").trim();
}
/* v13.42 — ¿el resultado cae DONDE se pidió? Sin esto, "J. M. Pérez, Luján" devolvió una calle
   de Laferrere a 45 km, y un pedido ubicado MAL es peor que sin ubicar. La primera versión
   comparaba nombres (¿algún componente de la respuesta dice "Luján"?) y también falló: en
   Laferrere hay un barrio "Villa Luján". Así que ahora es GEOGRÁFICO: se ubica el barrio pedido
   una vez por corrida (cache) y el resultado tiene que estar a menos de RADIO_KM de ese centro.
   Si el barrio no se puede ubicar, no hay contra qué verificar y el intento se descarta:
   falla cerrado. */
const RADIO_KM = 20;   // un partido grande del GBA (Luján, Pilar, La Matanza) cabe en 20 km de radio
const _centros = new Map<string, { lat: number; lng: number } | null>();
function kmEntre(a: { lat: number; lng: number }, b: { lat: number; lng: number }) {
  const R = 6371, dLat = (b.lat - a.lat) * Math.PI / 180, dLng = (b.lng - a.lng) * Math.PI / 180;
  const s = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * Math.PI / 180) * Math.cos(b.lat * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(s)));
}
async function centroBarrio(barrio: string) {
  const k = plano(barrio);
  if (_centros.has(k)) return _centros.get(k)!;
  await new Promise((r) => setTimeout(r, ESPERA_MS));   // es una llamada más a Nominatim: 1 por segundo
  // Búsqueda ESTRUCTURADA (city + state), no libre: "Luján, Argentina" a secas puede ser Luján de
  // Cuyo (Mendoza), un río o un barrio que se llame así. Con city= sólo devuelve la localidad.
  // Un barrio de CABA (Flores, Parque Patricios) también sale por city=: Nominatim lo resuelve
  // como suburb de Buenos Aires.
  const res = await nominatim("format=jsonv2&limit=1&countrycodes=ar&viewbox=-58.80,-34.40,-58.05,-34.85&city=" + encodeURIComponent(barrio) + "&state=" + encodeURIComponent("Buenos Aires") + "&country=Argentina");
  const c = res.c ? { lat: res.c.lat, lng: res.c.lng } : null;
  _centros.set(k, c);
  return c;
}

async function nominatim(qs: string, barrioExigido?: string) {
  const r = await fetch("https://nominatim.openstreetmap.org/search?" + qs,
    { headers: { Accept: "application/json", "User-Agent": UA } });
  if (!r.ok) return { c: null as null | Coord, err: "HTTP " + r.status };
  const j = await r.json();
  if (!j || !j.length || !j[0].lat) return { c: null, err: "sin resultado" };
  const lat = +j[0].lat, lng = +j[0].lon;
  if (!isFinite(lat) || !isFinite(lng)) return { c: null, err: "coordenada inválida" };
  if (barrioExigido) {
    const centro = await centroBarrio(barrioExigido);
    if (!centro) return { c: null, err: "no se pudo ubicar el barrio " + barrioExigido + " para verificar" };
    const km = kmEntre(centro, { lat, lng });
    if (km > RADIO_KM) return { c: null, err: "cayó a " + Math.round(km) + " km de " + barrioExigido };
  }
  return { c: { lat, lng, comp: j[0].address || null }, err: "" };
}

/* Nominatim con addressdetails (para guardar partido/barrio oficiales) y viewbox sesgado al AMBA,
   sin forzarlo: un cliente de Luján o de Campo de Mayo también tiene que caer bien.
   Va en cascada, porque con UNA sola forma de preguntar quedaban 19 de 64 sin ubicar:
     1. dirección + barrio + Buenos Aires   (lo normal)
     2. lo mismo con el barrio corregido    ("P.Patricios" → "Parque Patricios")
     3. dirección + Argentina, sin Buenos Aires ni viewbox — un pedido de Chef entrega en
        Río Cuarto (Córdoba) y el ", Buenos Aires" lo mandaba a ningún lado
     4. búsqueda estructurada street/city, que tolera mejor una calle mal escrita
     5. (v13.42) la CALLE sin el número, sólo si tiene barrio — "Trole 163" existe (el dueño lo
        mostró en Google Maps) pero OpenStreetMap no tiene esa altura cargada. Una calle de dos
        cuadras ordena el reparto igual de bien; queda marcada `precision = 'calle'` para
        poder revisarla. Sin barrio no se intenta: "Rivadavia" solo es cualquier lado.
   Cada intento cuesta 1 segundo (política de Nominatim), y sólo se hacen si el anterior falló. */
async function geocodificar(dir: string, barrio: string | null) {
  const AMBA = "&viewbox=-58.80,-34.40,-58.05,-34.85";
  const base = "format=jsonv2&addressdetails=1&limit=1&countrycodes=ar";
  const bOk = barrioOk(barrio);
  // `exigir`: el resultado tiene que caer a ≤ RADIO_KM del barrio pedido o se descarta. Va en TODOS
  // los intentos (v13.43): el dueño aclaró que una dirección de otra provincia nunca es punto de
  // entrega —se entrega al expreso en Buenos Aires—, así que un resultado lejos del barrio es
  // siempre un error, no importa cómo se preguntó. Sin barrio no hay contra qué verificar.
  const intentos: { qs: string; precision: string; exigir: boolean }[] = [
    { qs: base + AMBA + "&q=" + encodeURIComponent(dir + (barrio ? ", " + barrio : "") + ", Buenos Aires, Argentina"), precision: "exacta", exigir: !!bOk },
  ];
  if (bOk && bOk !== String(barrio || "").trim()) {
    intentos.push({ qs: base + AMBA + "&q=" + encodeURIComponent(dir + ", " + bOk + ", Buenos Aires, Argentina"), precision: "exacta", exigir: true });
  }
  intentos.push({ qs: base + "&q=" + encodeURIComponent(dir + (bOk ? ", " + bOk : "") + ", Argentina"), precision: "exacta", exigir: !!bOk });
  intentos.push({ qs: base + AMBA + "&street=" + encodeURIComponent(dir) + (bOk ? "&city=" + encodeURIComponent(bOk) : "") + "&country=Argentina", precision: "exacta", exigir: !!bOk });
  // 5 · la calle sola. Se saca el número del final ("Trole 163" → "Trole", "Av. La Salle 1923" →
  //     "Av. La Salle"); si la dirección no termina en número, no hay nada que sacar y no se intenta.
  const calle = dir.replace(/\s+\d[\d\/\-\s]*[a-zA-Z]?\s*$/, "").trim();
  if (bOk && calle && calle !== dir) {
    intentos.push({ qs: base + AMBA + "&street=" + encodeURIComponent(calle) + "&city=" + encodeURIComponent(bOk) + "&country=Argentina", precision: "calle", exigir: true });
  }

  let err = "sin resultado";
  for (let i = 0; i < intentos.length; i++) {
    if (i) await new Promise((r) => setTimeout(r, ESPERA_MS));
    const res = await nominatim(intentos[i].qs, intentos[i].exigir ? bOk : undefined);
    if (res.c) return { c: res.c, err: "", intento: i + 1, precision: intentos[i].precision };
    err = res.err;
  }
  return { c: null as null | Coord, err, intento: intentos.length, precision: "" };
}

async function log(estado: string, pedidas: number, ubicadas: number, fallaron: number, motivo: string, detalle: unknown) {
  try {
    await rest('GV_Geo_Log', {
      method: "POST", headers: { Prefer: "return=minimal" },
      body: JSON.stringify({ estado, pedidas, ubicadas, fallaron, motivo: motivo || null, detalle }),
    });
  } catch (_e) { /* el log no puede tumbar la corrida */ }
}

Deno.serve(async (req) => {
  const t0 = Date.now();
  try {
    const body = await req.json().catch(() => ({}));
    const tope = Math.min(Math.max(Number(body?.max) || MAX_POR_CORRIDA, 1), 200);

    const falt: Falt[] = await rest("gv_geo_faltantes?select=*&limit=500");
    if (!falt.length) {
      await log("sin_faltantes", 0, 0, 0, "", null);
      return Response.json({ ok: true, estado: "sin_faltantes", faltaban: 0 });
    }

    const lote = falt.slice(0, tope);
    let ubicadas = 0, aproximadas = 0; const errores: { cod: string; dir: string; err: string }[] = [];
    const porCalle: { cod: string; dir: string }[] = [];

    for (let i = 0; i < lote.length; i++) {
      const f = lote[i];
      const { c, err, precision } = await geocodificar(f.dir_query, f.barrio_geo || f.barrio);
      if (c) {
        if (precision === "calle") { aproximadas++; porCalle.push({ cod: f.cod, dir: f.direccion }); }
        // Nuestra tabla: la fuente canónica de Gestión.
        await rest('GV_Geo_Cliente?on_conflict=cod,dir_key', {
          method: "POST", headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
          body: JSON.stringify({
            cod: f.cod || "", dir_key: f.dir_key, razon_social: f.razon_social,
            direccion: f.direccion, barrio: f.barrio, lat: c.lat, lng: c.lng, comp: c.comp,
            fuente: "nominatim", precision: precision || "exacta", actualizado_at: new Date().toISOString(),
          }),
        }).catch((e) => errores.push({ cod: f.cod, dir: f.direccion, err: "GV_Geo_Cliente: " + e.message }));
        // Compartida con Producción: SÓLO agregar. Si la clave ya está, no se toca.
        await rest("PPP_Geo", {
          method: "POST", headers: { Prefer: "resolution=ignore-duplicates,return=minimal" },
          body: JSON.stringify({ dir_key: f.dir_key, direccion: f.direccion, barrio: f.barrio, lat: c.lat, lng: c.lng, comp: c.comp }),
        }).catch((e) => errores.push({ cod: f.cod, dir: f.direccion, err: "PPP_Geo: " + e.message }));
        ubicadas++;
      } else {
        errores.push({ cod: f.cod, dir: f.dir_query, err });
      }
      if (i < lote.length - 1) await new Promise((r) => setTimeout(r, ESPERA_MS));
    }

    const quedan = falt.length - ubicadas;
    const motivo = [quedan > 0 ? quedan + " sin ubicar todavía" : "", aproximadas ? aproximadas + " por la calle (sin altura en OSM)" : ""].filter(Boolean).join(" · ");
    await log("ok", lote.length, ubicadas, errores.length, motivo,
      (errores.length || porCalle.length) ? { errores: errores.slice(0, 40), por_calle: porCalle.slice(0, 40) } : null);
    return Response.json({ ok: true, estado: "ok", faltaban: falt.length, pedidas: lote.length, ubicadas, aproximadas, fallaron: errores.length, quedan, errores: errores.slice(0, 40), por_calle: porCalle, ms: Date.now() - t0 });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await log("error", 0, 0, 0, msg, null);
    return Response.json({ ok: false, error: msg }, { status: 500 });
  }
});

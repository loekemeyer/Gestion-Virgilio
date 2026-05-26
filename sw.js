/* =========================================================
   sw.js — Service Worker para Producción Virgilio
   Procesa la cola de envíos en background usando Background Sync API,
   incluso cuando la pestaña/app está cerrada.

   ⚠ IMPORTANTE: SUPABASE_URL y SUPABASE_KEY están duplicados acá y en
   index.html. Si rotás la publishable key, hay que actualizar AMBOS.
   ========================================================= */
const SW_VERSION = "v1.42-vir";

/* Cache del HTML para servir offline (último deploy bueno) cuando no hay red. */
const HTML_CACHE = "html-" + SW_VERSION;

const SUPABASE_URL = "https://hrxfctzncixxqmpfhskv.supabase.co";
const SUPABASE_KEY = "sb_publishable_BqpAgZH6ty-9wft10_YMhw_0rcIPuWT";
const SUPABASE_TABLE_ENDPOINT =
  SUPABASE_URL + "/rest/v1/Registros_Produccion_Virgilio";
const AUDIT_ENDPOINT =
  SUPABASE_URL + "/rest/v1/Auditoria_Produccion_Virgilio";

const IDB_NAME    = "registro-prod-virgilio";
const IDB_VERSION = 1;
const IDB_STORE   = "queue";

const SEND_TIMEOUT_MS = 12000;

/* ============== IndexedDB ============== */
let _dbPromise = null;
function idbOpen() {
  if (_dbPromise) return _dbPromise;
  _dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(IDB_NAME, IDB_VERSION);
    req.onupgradeneeded = (e) => {
      const db = e.target.result;
      if (!db.objectStoreNames.contains(IDB_STORE)) {
        db.createObjectStore(IDB_STORE, { keyPath: "id" });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror   = () => reject(req.error);
  });
  return _dbPromise;
}
function idbGetAll() {
  return idbOpen().then(db => new Promise((res, rej) => {
    const tx = db.transaction(IDB_STORE, "readonly");
    const r = tx.objectStore(IDB_STORE).getAll();
    r.onsuccess = () => res(r.result || []);
    r.onerror   = () => rej(r.error);
  }));
}
function idbDelete(id) {
  return idbOpen().then(db => new Promise((res, rej) => {
    const tx = db.transaction(IDB_STORE, "readwrite");
    const r = tx.objectStore(IDB_STORE).delete(id);
    r.onsuccess = () => res();
    r.onerror   = () => rej(r.error);
  }));
}
function idbPut(item) {
  return idbOpen().then(db => new Promise((res, rej) => {
    const tx = db.transaction(IDB_STORE, "readwrite");
    const r = tx.objectStore(IDB_STORE).put(item);
    r.onsuccess = () => res();
    r.onerror   = () => rej(r.error);
  }));
}

/* ============== Auditoría remota (best-effort) ============== */
function logErrorToAudit(payload, attempts, r) {
  try {
    const body = {
      client_id:   payload.id || null,
      legajo:      payload.legajo || null,
      opcion:      payload.opcion || null,
      descripcion: payload.descripcion || null,
      texto:       payload.texto || null,
      ts_cliente:  payload.ts ? new Date(payload.ts).toISOString() : null,
      ts_inicio:   payload.ts_inicio_iso || null,
      intentos:    attempts || 1,
      motivo:      r.networkFail ? "network" : `server_${r.status || "?"}`,
      user_agent:  (self.navigator && self.navigator.userAgent) || "sw"
    };
    fetch(AUDIT_ENDPOINT, {
      method: "POST",
      headers: {
        "apikey":        SUPABASE_KEY,
        "Authorization": "Bearer " + SUPABASE_KEY,
        "Content-Type":  "application/json",
        "Prefer":        "return=minimal"
      },
      body: JSON.stringify(body)
    }).catch(() => {});
  } catch { /* fire and forget */ }
}

/* ============== Envío a Supabase ============== */
async function trySendOneReport(payload) {
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), SEND_TIMEOUT_MS);
    // Espejo de la lógica del index.html: para FJ usamos upsert
    // (merge-duplicates + ?on_conflict=client_id) para que un segundo
    // Terminar Día actualice la fila en lugar de generar 409 y dejar
    // los datos desactualizados. El resto va con INSERT normal.
    const isFJ   = (payload.opcion === "FJ");
    const url    = isFJ
      ? SUPABASE_TABLE_ENDPOINT + "?on_conflict=client_id"
      : SUPABASE_TABLE_ENDPOINT;
    const prefer = isFJ
      ? "resolution=merge-duplicates,return=minimal"
      : "return=minimal";
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "apikey":        SUPABASE_KEY,
        "Authorization": "Bearer " + SUPABASE_KEY,
        "Content-Type":  "application/json",
        "Prefer":        prefer
      },
      body: JSON.stringify({
        client_id:   payload.id,
        legajo:      payload.legajo,
        opcion:      payload.opcion,
        descripcion: payload.descripcion,
        texto:       payload.texto,
        ts_cliente:  new Date(payload.ts).toISOString(),
        ts_inicio:   payload.ts_inicio_iso || null
      }),
      signal: ctrl.signal
    });
    clearTimeout(t);
    if (!res) return { ok: false, networkFail: true };
    if (res.ok || res.status === 409) return { ok: true, status: res.status };
    return { ok: false, networkFail: false, status: res.status };
  } catch (e) {
    return { ok: false, networkFail: true };
  }
}

/* ============== Aviso a la página ============== */
async function notifyClientsItemSent(item, createdAt) {
  try {
    const clients = await self.clients.matchAll({ includeUncontrolled: true });
    for (const c of clients) {
      try {
        c.postMessage({
          type:      "ITEM_SENT",
          id:        item.id,
          legajo:    item.legajo,
          fecha:     item.fecha,
          createdAt: createdAt || null
        });
      } catch {}
    }
  } catch {}
}

/* ============== Flush en background ============== */
async function flushQueueInSW() {
  let items;
  try { items = await idbGetAll(); } catch { return; }
  if (!items.length) return;

  let hadNetworkFail = false;
  for (const item of items) {
    const r = await trySendOneReport(item.payload);
    if (r.ok) {
      try { await idbDelete(item.id); } catch {}
      // Aviso a cualquier página abierta para que limpie LS y actualice UI.
      notifyClientsItemSent(item, r.created_at);
    } else {
      // Anotar intento en IDB y auditar (intento 1 y cada 5).
      const newAttempts = (item.attempts || 0) + 1;
      item.attempts = newAttempts;
      item.lastTry  = Date.now();
      item.lastErr  = r.networkFail ? "network" : `server_${r.status || "?"}`;
      try { await idbPut(item); } catch {}
      if (newAttempts === 1 || newAttempts % 5 === 0) {
        logErrorToAudit(item.payload, newAttempts, r);
      }
      if (r.networkFail) {
        hadNetworkFail = true;
        break;
      }
      // Rechazo del server: seguir con los demás. Quedan en IDB y la
      // página los va a mostrar como ⚠ falló cuando reconcile corra.
    }
  }
  // Throw -> el browser planifica reintento del sync con backoff.
  if (hadNetworkFail) throw new Error("network_down");
}

/* ============== Event handlers ============== */
self.addEventListener("install", () => {
  // Saltear waiting: la nueva versión del SW toma control de inmediato.
  self.skipWaiting();
});
self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    // Borrar caches de HTML de versiones anteriores.
    const keys = await caches.keys();
    await Promise.all(
      keys.filter(k => k !== HTML_CACHE).map(k => caches.delete(k))
    );
    await self.clients.claim();
  })());
});
self.addEventListener("sync", (event) => {
  if (event.tag === "flush-queue") {
    event.waitUntil(flushQueueInSW());
  }
});
/* También expongo un message handler por si la página quiere disparar un flush
   manual desde foreground sin esperar al Background Sync. */
self.addEventListener("message", (event) => {
  if (event.data && event.data.type === "FLUSH_NOW") {
    event.waitUntil(flushQueueInSW().catch(() => {}));
  }
});

/* Fetch handler: SOLO maneja navegaciones same-origin (el HTML) en modo
   network-first, salteando el cache HTTP caprichoso de smart TVs / WebViews
   viejos. Todo lo demás (incluidas las llamadas a Supabase, que son
   cross-origin) pasa de largo sin interceptar, preservando el Background Sync. */
self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.mode !== "navigate") return;                          // solo el HTML
  if (new URL(req.url).origin !== self.location.origin) return; // no tocar cross-origin
  event.respondWith((async () => {
    try {
      // cache:"no-store" => ignora el cache HTTP del navegador y va a la red.
      // Pedimos por URL (no el Request en modo "navigate") para evitar el
      // pitfall de construir un Request navigate con init.
      const fresh = await fetch(req.url, { cache: "no-store" });
      if (fresh && fresh.ok) {
        (await caches.open(HTML_CACHE)).put(req, fresh.clone());
      }
      return fresh;
    } catch (e) {
      // Offline: devolver el último HTML guardado.
      return (await caches.match(req)) ||
             (await caches.match("./")) ||
             Promise.reject(e);
    }
  })());
});

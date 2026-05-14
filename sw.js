/* =========================================================
   sw.js — Service Worker para Producción Virgilio
   Procesa la cola de envíos en background usando Background Sync API,
   incluso cuando la pestaña/app está cerrada.

   ⚠ IMPORTANTE: SUPABASE_URL y SUPABASE_KEY están duplicados acá y en
   index.html. Si rotás la publishable key, hay que actualizar AMBOS.
   ========================================================= */
const SW_VERSION = "v1.0-vir";

const SUPABASE_URL = "https://hrxfctzncixxqmpfhskv.supabase.co";
const SUPABASE_KEY = "sb_publishable_BqpAgZH6ty-9wft10_YMhw_0rcIPuWT";
const SUPABASE_TABLE_ENDPOINT =
  SUPABASE_URL + "/rest/v1/Registros_Produccion_Virgilio";

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

/* ============== Envío a Supabase ============== */
async function trySendOneReport(payload) {
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), SEND_TIMEOUT_MS);
    const res = await fetch(SUPABASE_TABLE_ENDPOINT, {
      method: "POST",
      headers: {
        "apikey":        SUPABASE_KEY,
        "Authorization": "Bearer " + SUPABASE_KEY,
        "Content-Type":  "application/json",
        "Prefer":        "return=minimal"
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
    } else if (r.networkFail) {
      // Red caída: cortar, pedirle al browser que reintente otro sync.
      hadNetworkFail = true;
      break;
    }
    // Rechazo del server (4xx/5xx): seguir con los demás. Quedan en IDB y la
    // página los va a mostrar como ⚠ falló cuando reconcile corra.
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
  event.waitUntil(self.clients.claim());
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

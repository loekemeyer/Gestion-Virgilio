/* Regresión v20.52 — EL ENVOLTORIO DE `fetch` QUE TAPA EL TOPE DE 1.000 FILAS.

   Luis, 2026-09-21: *"quiero que esto quede cubierto sin el cambio global al proyecto"*.

   PostgREST corta en 1.000 filas (`db-max-rows`) y contesta 200 sin avisar. Subir ese tope es
   configuración del PROYECTO —lo ven también Producción Virgilio y los admin de Cervantes— así
   que en vez de eso `supabase-config.js` envuelve `fetch` una sola vez: si una respuesta de
   `/rest/v1/` llega justo con 1.000 filas, pide las que faltan con `offset` y devuelve todo junto.

   Prueba con red simulada (sin tocar Supabase):
   - una lectura de 2.137 filas sin `limit` → devuelve las 2.137, en 3 pedidos;
   - lo mismo con `limit=20000` (el techo que el autor CREYÓ pedir) → completa;
   - con `limit=1000` → NO completa: el que llamó pidió ese tope (y es como pagina `gvRestTodo`,
     así que esto también prueba que no hay recursión);
   - con `limit=300` → ni se mira;
   - una respuesta corta (999 filas) → un solo pedido, sin leer el body;
   - una respuesta que NO es de `/rest/v1/` → intacta;
   - un POST a `rpc/` → también se completa (offset anda igual en rpc: medido 21/09);
   - si la página siguiente falla, devuelve lo que juntó en vez de romper;
   - `offset` no se duplica en la URL.
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const src = fs.readFileSync(path.join(__dirname, "..", "supabase-config.js"), "utf8");
const fallos = [];

function nuevoMundo(total, opts) {
  const o = opts || {};
  const pedidos = [];
  const g = {};
  g.self = g;
  g.Headers = class Headers {
    constructor(h) { this.m = new Map(); if (h && h.m) for (const [k, v] of h.m) this.m.set(k, v); }
    get(k) { return this.m.has(String(k).toLowerCase()) ? this.m.get(String(k).toLowerCase()) : null; }
    set(k, v) { this.m.set(String(k).toLowerCase(), String(v)); }
  };
  g.Response = class Response {
    constructor(body, init) {
      this._b = body;
      const i = init || {};
      this.status = i.status != null ? i.status : 200;
      this.statusText = i.statusText || "";
      this.ok = this.status >= 200 && this.status < 300;
      this.headers = i.headers instanceof g.Headers ? i.headers : new g.Headers(i.headers);
    }
    text() { return Promise.resolve(this._b); }
    json() { return Promise.resolve(JSON.parse(this._b)); }
  };
  g.fetch = function (url, init) {
    const u = String(url);
    pedidos.push({ url: u, method: (init && init.method) || "GET" });
    if (o.rompeDesde != null && pedidos.length > o.rompeDesde) return Promise.reject(new Error("red"));
    const off = Number((/[?&]offset=(\d+)/.exec(u) || [])[1] || 0);
    const limUrl = Number((/[?&]limit=(\d+)/.exec(u) || [])[1] || 0);
    const cap = Math.min(1000, limUrl || 1000);
    const n = Math.max(0, Math.min(cap, total - off));
    const filas = Array.from({ length: n }, (_, i) => ({ i: off + i }));
    const h = new g.Headers();
    if (!o.sinRango) h.set("content-range", n ? off + "-" + (off + n - 1) + "/*" : "*/*");
    return Promise.resolve(new g.Response(JSON.stringify(filas), { status: 200, headers: h }));
  };
  vm.createContext(g);
  vm.runInContext(src, g);
  return { g, pedidos };
}

(async () => {
  // 1) sin limit → completa
  {
    const { g, pedidos } = nuevoMundo(2137);
    const r = await g.fetch("https://x.supabase.co/rest/v1/vista_x?select=a");
    const filas = await r.json();
    if (filas.length !== 2137) fallos.push("sin limit: devolvio " + filas.length + " de 2137");
    if (pedidos.length !== 3) fallos.push("sin limit: " + pedidos.length + " pedidos (esperado 3)");
    if (filas[2136].i !== 2136) fallos.push("sin limit: la ultima fila no es la 2136");
    if (r.headers.get("x-gv-completado") !== "2137") fallos.push("sin limit: no marca x-gv-completado");
    if (pedidos.filter((p) => (p.url.match(/offset=/g) || []).length > 1).length)
      fallos.push("sin limit: offset duplicado en la URL");
  }
  // 2) limit=20000 (el techo que el autor creyo pedir) → completa
  {
    const { g, pedidos } = nuevoMundo(2137);
    const filas = await (await g.fetch("https://x.supabase.co/rest/v1/vista_x?select=a&limit=20000")).json();
    if (filas.length !== 2137) fallos.push("limit=20000: devolvio " + filas.length);
    if (pedidos.length !== 3) fallos.push("limit=20000: " + pedidos.length + " pedidos");
  }
  // 3) limit=1000 → NO completa (asi pagina gvRestTodo: tambien prueba que no recursa)
  {
    const { g, pedidos } = nuevoMundo(2137);
    const filas = await (await g.fetch("https://x.supabase.co/rest/v1/vista_x?select=a&limit=1000")).json();
    if (filas.length !== 1000) fallos.push("limit=1000: completo cuando no debia (" + filas.length + ")");
    if (pedidos.length !== 1) fallos.push("limit=1000: hizo " + pedidos.length + " pedidos, tiene que ser 1");
  }
  // 4) limit=300 → ni se mira
  {
    const { g, pedidos } = nuevoMundo(2137);
    const filas = await (await g.fetch("https://x.supabase.co/rest/v1/vista_x?select=a&limit=300")).json();
    if (filas.length !== 300 || pedidos.length !== 1) fallos.push("limit=300: se metio donde no debia");
  }
  // 5) respuesta corta → un solo pedido
  {
    const { g, pedidos } = nuevoMundo(999);
    const filas = await (await g.fetch("https://x.supabase.co/rest/v1/vista_x?select=a")).json();
    if (filas.length !== 999 || pedidos.length !== 1) fallos.push("999 filas: " + filas.length + " en " + pedidos.length + " pedidos");
  }
  // 6) justo 1000 y no hay mas → dos pedidos, 1000 filas
  {
    const { g, pedidos } = nuevoMundo(1000);
    const filas = await (await g.fetch("https://x.supabase.co/rest/v1/vista_x?select=a")).json();
    if (filas.length !== 1000) fallos.push("exactamente 1000: devolvio " + filas.length);
    if (pedidos.length !== 2) fallos.push("exactamente 1000: " + pedidos.length + " pedidos (esperado 2)");
  }
  // 7) no es /rest/v1/ → intacta
  {
    const { g, pedidos } = nuevoMundo(2137);
    const filas = await (await g.fetch("https://otra.cosa/api/x")).json();
    if (pedidos.length !== 1) fallos.push("fuera de /rest/v1/: se metio igual");
    if (filas.length !== 1000) fallos.push("fuera de /rest/v1/: toco el body");
  }
  // 8) POST a rpc → tambien completa, y conserva el metodo en las paginas siguientes
  {
    const { g, pedidos } = nuevoMundo(2137);
    const filas = await (await g.fetch("https://x.supabase.co/rest/v1/rpc/f",
      { method: "POST", body: "{}" })).json();
    if (filas.length !== 2137) fallos.push("rpc POST: devolvio " + filas.length);
    if (!pedidos.every((p) => p.method === "POST")) fallos.push("rpc POST: las paginas siguientes no van por POST");
  }
  // 9) sin Content-Range → no toca nada
  {
    const { g, pedidos } = nuevoMundo(2137, { sinRango: true });
    const filas = await (await g.fetch("https://x.supabase.co/rest/v1/vista_x?select=a")).json();
    if (pedidos.length !== 1 || filas.length !== 1000) fallos.push("sin Content-Range: no puede completar a ciegas");
  }
  // 10) si la pagina siguiente falla, devuelve lo que junto
  {
    const { g } = nuevoMundo(2137, { rompeDesde: 2 });
    const filas = await (await g.fetch("https://x.supabase.co/rest/v1/vista_x?select=a")).json();
    if (filas.length !== 2000) fallos.push("red caida a mitad: devolvio " + filas.length + " (esperado 2000)");
  }

  if (fallos.length) { console.error("rest-tope-wrapper FALLA:\n - " + fallos.join("\n - ")); process.exit(1); }
  console.log("rest-tope-wrapper OK — completa cuando el limit era un deseo, no toca cuando era una decision.");
})();

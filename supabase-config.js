/* =========================================================================
   CONFIG COMPARTIDA SUPABASE — proyecto Virgilio ("Control Partes Talleristas",
   hrxfctzncixxqmpfhskv). Idea normalizar-datos (TOP-10, v11.101).

   ÚNICO lugar del repo donde vive la URL + publishable key de Virgilio.
   Rotar la key = editar SOLO este archivo (+ bump APP_VERSION/SW_VERSION y los
   ?v= de este script para invalidar cache).

   Consumidores (los 6 que antes tenían la key hardcodeada):
   - index.html        → <script src="supabase-config.js?v=...">
   - recepcion.js      → módulo, lee los globals (index.html ya cargó esto antes)
   - sw.js             → importScripts("supabase-config.js")
   - fichada.html      → carga esto antes de fichada-config.js
   - fichadas-monitor.html / productividad.html → <script src>

   ⚠ La key de LK (kwkclwhmoygunqmlegrg) es OTRA y sigue en index.html
   (SUPABASE_LK_KEY) + admin/admin.js — no la mezcla acá.
   ========================================================================= */
(function (g) {
  g.VIR_SUPABASE_URL = "https://hrxfctzncixxqmpfhskv.supabase.co";
  g.VIR_SUPABASE_KEY = "sb_publishable_BqpAgZH6ty-9wft10_YMhw_0rcIPuWT";
})(typeof self !== "undefined" ? self : globalThis);

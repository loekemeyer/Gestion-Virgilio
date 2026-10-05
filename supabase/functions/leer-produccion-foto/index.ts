import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// leer-produccion-foto — RETIRADA (v27.10, 2026-10-05).
// Era el OCR (gpt-4o) del botón «Cargar foto» de Maestro Producción. No se usaba
// (0 lecturas desde el 15/09) y el dueño pidió sacarlo: el botón ya no existe.
// Queda como tapón (igual que leer-factura) para que nada vuelva a gastar en una API de IA.

Deno.serve(() =>
  new Response(JSON.stringify({ error: "El OCR de planillas se retiró el 05/10/2026: cargá las filas a mano." }), {
    status: 410,
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  })
);

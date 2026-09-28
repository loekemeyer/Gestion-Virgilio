import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// send-rendimiento-matrices — DADA DE BAJA el 2026-09-28 (v23.41, seguridad; dueño: "b)").
// Mandaba por WhatsApp un texto "Rendimiento Matrices" a 2 números fijos, sin ningún
// control: cualquiera con la URL disparaba mensajes desde el número de la empresa y un
// barrido completo de db_n8n_espejo. Nada la llamaba (código de los 3 repos, cron).
// El reporte vigente es el PDF de `reporte-diario-rendimiento` (cron 2, 18:00, con token).
// El código anterior está en ORIGINAL_v46.ts.txt (esta misma carpeta).

Deno.serve(() =>
  new Response(
    JSON.stringify({ error: "send-rendimiento-matrices fue dada de baja. El reporte diario es reporte-diario-rendimiento." }),
    { status: 410, headers: { "Content-Type": "application/json" } },
  )
);

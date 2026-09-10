/* =========================================================
   supabase-config.js — la URL y la clave anon de GP2, en UN solo lugar.

   ROTAR LA CLAVE = EDITAR SOLO ESTE ARCHIVO (y bumpear su ?v= en los HTML).
   Antes la clave estaba escrita a mano en 112 archivos: rotarla significaba
   tocarlos todos y rezar que no se escapara ninguno. Mismo criterio que usa
   Produccion Virgilio, que ya lo tenia resuelto asi.

   NO es un secreto: la clave anon viaja igual en el HTML de cada pagina, y
   siempre fue asi. Lo que protege la base es la RLS (anon solo lee) mas que
   toda escritura pase por RPCs SECURITY DEFINER que validan. Esto no cambia
   la seguridad — cambia que haya UN lugar donde tocarla.

   Se expone con los cuatro nombres que ya usaban las pantallas, para no tener
   que reescribir el codigo de cada una:
     SUPABASE_URL / SB_URL          -> la URL del proyecto
     SUPABASE_KEY / SUPABASE_ANON_KEY / SB_ANON -> la clave anon

   Van en self a proposito: en una pagina self===window, asi el codigo las ve como
   variables sueltas (SUPABASE_URL) sin declararlas — que es como ya estaban
   escritas — y ademas el archivo sirve dentro de un service worker (importScripts).
   ========================================================= */
self.SUPABASE_URL = "https://hrxfctzncixxqmpfhskv.supabase.co";
self.SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhyeGZjdHpuY2l4eHFtcGZoc2t2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI3MjQyNjEsImV4cCI6MjA4ODMwMDI2MX0.4L6wguch8UZGhC2VpzrWcCjJGUV-IkYsl9JoCWrOLUs";

// Alias: los mismos valores con los otros nombres que ya existian en el codigo.
self.SUPABASE_ANON_KEY = self.SUPABASE_KEY;
self.SB_URL            = self.SUPABASE_URL;
self.SB_ANON           = self.SUPABASE_KEY;

/* El cliente GP2, UNA sola vez (2026-09-05): schema GP2 y sin sesion persistida. Antes cada
   pantalla escribia su propio createClient (40 copias, cinco formas distintas). Se resuelve
   al llamarlo, asi no importa si el CDN de supabase-js se cargo antes o despues de este
   archivo. En un service worker no hay cliente (no hay window.supabase). */
self.GP2_SB = function (opts) {
  return self.supabase.createClient(self.SUPABASE_URL, self.SUPABASE_KEY,
    opts || { db: { schema: "GP2" }, auth: { persistSession: false } });
};

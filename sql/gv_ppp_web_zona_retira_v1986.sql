-- v19.86 — RETIRA: que un pedido que se retira FIGURE como retira en la programación.
--
-- Thomas, 2026-09-18: *"Los pedidos que se retiran tienen que figurar como que se retiran en la
-- programación (sean ISIS o web)"*.
--
-- Lo de ISIS ya andaba: la zona viaja en la programación (`GV_PPP_Programacion_Diaria.zona`) y el
-- barrio "Retira" está en el diccionario `Zonas_Barrios` → zona `Retira`. Medido el 18/09: 0 NP de
-- ISIS con dirección de retiro y otra zona.
--
-- Lo web NO. `gv_ppp_web_zona` decidía con `barrio ~* 'retir'`, o sea POR SUBCADENA, y sobre un
-- solo campo (el primero no vacío de zona_expreso → localidad → dirección). Dos agujeros:
--
--   (a) **"Retiro" es un BARRIO de CABA** (Zona 2 - CABA Centro), no un retiro en fábrica.
--       Medido en LK el 18/09: 3 direcciones con `zona_expreso = 'Retiro'` (Uruguay 1140,
--       Talcahuano 963, Av. Santa Fe 1201) y 4 con `localidad = 'Retiro'`. Todas quedaban
--       marcadas Retira → nunca se reparten, esperan un cliente que no las va a buscar.
--
--   (b) **El retiro en fábrica que viene por el EXPRESO no se veía.** Cuando el cliente pasa a
--       buscar, LK deja `nombre_expreso = 'Retira'` (140 direcciones) y `zona_expreso` sigue
--       trayendo el barrio del cliente — Osa: 'Villa Lugano'. La Edge Function ya arma la
--       dirección como `Exp. Retira — Virgilio 2788, Retira (<la del cliente>)`, pero el
--       `coalesce` tomaba `zona_expreso` y la dirección no se miraba nunca. Idem cuando la
--       dirección de entrega ES el depósito (`Virgilio 2788`, 140 direcciones).
--
-- Efecto medido: 5 NP web programadas con zona numérica siendo retiras — LK 0011 y LK 0157
-- (BP Import), LK 0024 (Osa), LK 0143 y LK 0144 (Suppa) — o sea que salían al reparto.
-- Con la función nueva, de las 178 filas de `PPP_Web_Programacion` cambian **6**: esas 5 pasan a
-- Retira, 0 dejan de serlo, y la 6ª (LK 0103) es un artefacto de la medición, no del cambio.

create or replace function public.gv_ppp_web_zona(p_zona_expreso text DEFAULT NULL::text, p_localidad text DEFAULT NULL::text, p_direccion text DEFAULT NULL::text)
 returns text
 language sql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
  with s as (
    select btrim(coalesce(p_zona_expreso, '')) as ze,
           btrim(coalesce(p_localidad,    '')) as loc,
           btrim(coalesce(p_direccion,    '')) as dir
  ), b as (
    select ze, loc, dir,
           coalesce(nullif(ze, ''), nullif(loc, ''),
                    public.gv_ppp_web_barrio_de(dir)) as barrio,
           -- v19.86 — RETIRA se decide acá, y con tres correcciones sobre el `barrio ~* 'retir'`
           -- que había antes:
           --   (a) EXACTO: "Retiro" es un BARRIO de CABA (Zona 2), no un retiro en fábrica.
           --       Medido el 18/09 en LK: 3 direcciones con zona_expreso = 'Retiro' y 4 con
           --       localidad = 'Retiro' quedaban marcadas Retira y no se repartían nunca.
           --   (b) el EXPRESO manda aunque la zona diga otra cosa: cuando el cliente pasa a
           --       buscar, la Edge Function arma la dirección como "Exp. Retira — Virgilio
           --       2788, Retira (<la del cliente>)" y `zona_expreso` sigue trayendo el barrio
           --       del cliente (Osa: 'Villa Lugano'). Son 140 direcciones con
           --       nombre_expreso = 'Retira' en LK.
           --   (c) la dirección de entrega ES el depósito (Virgilio 2788): 140 direcciones.
           (ze  ~* '^retira$' or loc ~* '^retira$' or dir ~* '^retira$'
            or dir ~* '^exp\.\s*retira([^a-záéíóúñ]|$)'
            or dir ~* 'virgilio\s*2788') as es_retira
      from s
  )
  select case
           when es_retira                then 'Retira'
           when coalesce(barrio, '') = '' then null
           else public.gv_zona_de_barrio(barrio)
         end
    from b;
$function$;

-- Centinela: una NP (de ISIS o web) cuya DIRECCIÓN dice retiro en fábrica y cuya ZONA no, o al
-- revés. Vacía = todo bien. Se apoya en gv_np_prog_reparto (v19.82).
create or replace view public.gv_retira_sin_etiqueta as
with base as (
  select np, origen, zona, direccion, barrio, tanda, es_retira,
         (btrim(coalesce(barrio,'')) ~* '^retira$'
          or btrim(coalesce(direccion,'')) ~* 'virgilio\s*2788'
          or btrim(coalesce(direccion,'')) ~* '(^|[^a-z])retira([^a-z]|$)') as pinta_retira
    from public.gv_np_prog_reparto
)
select np, origen, zona, tanda, direccion, barrio,
       case when pinta_retira and not es_retira then 'RETIRA SIN ETIQUETA'
            else 'ETIQUETA SIN DIRECCION DE RETIRA' end as problema
  from base
 where pinta_retira <> es_retira;

alter view public.gv_retira_sin_etiqueta set (security_invoker = true);
grant select on public.gv_retira_sin_etiqueta to anon, authenticated;

-- Pruebas (las 9 tienen que dar lo de la derecha):
--   gv_ppp_web_zona('Retira',null,null)                                  -> Retira
--   gv_ppp_web_zona('Retiro',null,null)                                  -> Zona 2 - CABA Centro
--   gv_ppp_web_zona(null,'Retiro','Uruguay 1140')                        -> Zona 2 - CABA Centro
--   gv_ppp_web_zona('Villa Lugano','Villa Lugano',
--                   'Exp. Retira — Virgilio 2788, Retira (Zuviria…)')    -> Retira
--   gv_ppp_web_zona('Villa Devoto',null,'Retira')                        -> Retira
--   gv_ppp_web_zona('Villa Devoto',null,'Virgilio 2788')                 -> Retira
--   gv_ppp_web_zona('Villa Devoto',null,'Bahia Blanca 2300')             -> Zona 2 - CABA Centro
--   gv_ppp_web_zona('Villa Lugano','Villa Lugano','Exp. Andesmar — …')   -> Zona 1 - CABA Sur
--   gv_ppp_web_zona(null,null,null)                                      -> null
--
-- Chequeo:  select * from public.gv_retira_sin_etiqueta order by np;   -- vacía = todo bien
--
-- Rollback (vuelve la regla por subcadena, con el bug de "Retiro"):
--   …  when barrio ~* 'retir' then 'Retira'  …   y  drop view public.gv_retira_sin_etiqueta;

-- v24.76 (Luis, 30/09): "que diga para los que se despachan en expreso la dirección de entrega
-- real también en A programar y en Programación".
--
-- En la ficha de la página, `direccion_entrega` es el GALPÓN del expreso (Pergamino 2820, Juan
-- B. Justo 7594…) y la sucursal real del cliente vive en la ETIQUETA (`label`: "Chacabuco 228-
-- Mendoza", "Río Gall (25 de mayo)") + localidad y provincia. `gv_np_destino_lista` devolvía
-- sólo provincia y expreso, y el chip de Programación salía sólo si había nombre de expreso:
-- Multibazar (sin nombre de expreso cargado) no mostraba NADA.
--
-- Suma a la RPC: `localidad_destino`, `sucursal` (la etiqueta) y `es_expreso`.
--   · sucursal: la etiqueta que viajó con la NP web ("Exp. … — galpón (ETIQUETA)"); si no hay
--     (NP de ISIS), la del slot del padrón con esa localidad, sólo si es UNA (dos sucursales en
--     la misma ciudad — Multibazar Bariloche — no se adivina: queda la localidad sola).
--   · es_expreso: no es Retira y (la NP dice "Exp." · tiene expreso · la provincia no es CABA
--     ni Buenos Aires).
-- NO toca `gv_np_destino` (tiene centinela): la RPC lee de ella y completa.
-- Rollback: volver a crear la función con el RETURNS de 5 columnas (cuerpo en el git log).

begin;
drop function if exists public.gv_np_destino_lista(text[], date);
create function public.gv_np_destino_lista(p_nps text[] default null, p_desde date default null)
 returns table(np text, provincia text, expreso text, alerta boolean, destino_txt text,
               localidad_destino text, sucursal text, es_expreso boolean)
 language sql stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  with d as (
    select d.* from public.gv_np_destino d
     where (p_nps is null or d.np = any (
             select regexp_replace(btrim(x), '\.0+$', '') from unnest(p_nps) x))
       and (p_desde is null or d.fecha is null or d.fecha >= p_desde)
  ), w as (
    select distinct on (gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))
           gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as np, w.direccion
      from public."PPP_Web_Programacion" w
     where gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) in (select d.np from d)
  )
  select d.np, d.provincia, d.expreso, d.alerta, d.destino_txt, d.localidad_destino,
         nullif(btrim(coalesce(
           (regexp_match(coalesce(w.direccion,''), '\(((?:[^()]|\([^()]*\))*)\)\s*$'))[1],
           (select min(c.etiqueta) from public."GV_Clientes_Direcciones" c
             where lower(c.empresa) = lower(d.empresa) and btrim(c.cod) = d.cod
               and d.localidad_destino is not null
               and lower(c.localidad) = lower(d.localidad_destino)
            having count(*) = 1), '')), '') as sucursal,
         (coalesce(d.como,'') <> 'retira' and coalesce(d.expreso,'') !~* '^retira$'
          and (coalesce(w.direccion,'') ~* '^\s*exp\.'
               or coalesce(d.expreso,'') <> ''
               or (coalesce(d.provincia,'') <> ''
                   and d.provincia !~* '^(caba|c\.a\.b\.a\.?|capital( federal)?|ciudad aut.*|buenos aires|bs\.? ?as\.?)$'))) as es_expreso
    from d left join w using (np);
$function$;
revoke all on function public.gv_np_destino_lista(text[], date) from public;
grant execute on function public.gv_np_destino_lista(text[], date) to anon, authenticated, service_role;
commit;

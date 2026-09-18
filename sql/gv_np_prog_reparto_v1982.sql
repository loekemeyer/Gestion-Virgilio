-- v19.82 — «Carga Camión» mostraba en el REPARTO los pedidos que RETIRA el cliente.
--
-- Thomas, 2026-09-18: "Están apareciendo los pedidos que están marcados como que los retiran
-- los clientes en el módulo «cargar camión»".
--
-- Causa: `_ccAttachUbicYOrden` (index.html) leía la zona de la NP SOLO de
-- `gv_ppp_programacion_diaria`, que es la programación de ISIS y NO tiene las NP web
-- ("LK 0076", "CH 0011"; ésas viven en `PPP_Web_Programacion`). Sin zona, el front dejaba
-- `esRetira = false` y el pedido caía en el camión. De paso, tampoco entraban al orden de
-- carga por ruta (les faltaba zona y geocodificación).
--
-- La vista une las DOS programaciones con la NP ya etiquetada (`gv_ppp_web_np_label`) y
-- resuelve el Retira en el BACKEND (`es_retira`), que es donde va la regla de negocio.
-- Mismo criterio que la v19.65 con `gv_np_prog_info`.
--
-- Objeto NUEVO con prefijo gv_: no toca nada de lo que ya estaba.

create or replace view public.gv_np_prog_reparto as
select btrim(p.np)                                as np,
       'isis'::text                               as origen,
       btrim(coalesce(p.zona, ''))                as zona,
       btrim(coalesce(p.direccion, ''))           as direccion,
       btrim(coalesce(p.barrio, ''))              as barrio,
       coalesce(p.m3, 0)::numeric                 as m3,
       upper(btrim(coalesce(p.tanda, '')))        as tanda,
       (btrim(coalesce(p.zona, '')) ~* '^retira') as es_retira
  from public.gv_ppp_programacion_diaria p
 where nullif(btrim(p.np), '') is not null
union all
select public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as np,
       'web'::text,
       btrim(coalesce(w.zona, '')),
       btrim(coalesce(w.direccion, '')),
       btrim(coalesce(w.barrio, '')),
       coalesce(w.m3, 0)::numeric,
       upper(btrim(coalesce(w.tanda, ''))),
       (btrim(coalesce(w.zona, '')) ~* '^retira')
  from public."PPP_Web_Programacion" w
 where w.np is not null;

alter view public.gv_np_prog_reparto set (security_invoker = true);
grant select on public.gv_np_prog_reparto to anon, authenticated;

-- Chequeo: los Retira web tienen que salir con es_retira = true.
-- select np, origen, zona, es_retira from public.gv_np_prog_reparto where es_retira order by np;
--
-- Rollback (la vista es nueva; el front vuelve a la programación de ISIS sola):
-- drop view public.gv_np_prog_reparto;

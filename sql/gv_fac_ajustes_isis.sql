-- gv_fac_ajustes_isis.sql — CHECKLIST MANUAL DE ISIS en Facturación · v13.78 (2026-09-07) · Virgilio
-- Dueño: "cuando se va a facturar por Chef [artículos de Loeke, códigos con L] hay que: hacer ajuste NEGATIVO de
-- stock de LK en ISIS LK, y hacer ajuste POSITIVO en CH, para que al facturar quede neteado. Y para vos en GV,
-- descontá directo stock de LK." Migración gv_fac_ajustes_isis_v1378. Objetos nuevos (GV_/gv_), RLS prendida.
--   · GV_Fac_Ajustes_ISIS (np, paso 'lk_neg'|'ch_pos', hecho_at, legajo): la tilde de cada paso.
--   · gv_fac_ajustes_isis (security_invoker): por NP armada con artículos L (Entregas_Virgilio, 90 días), cajas
--     entregadas por artículo (última fila por np+cod, como el Excel), art_lk (sin L) / art_ch (con L),
--     facturado_at, lk_neg_at/por, ch_pos_at/por, completo. El front lista las no completas.
-- Rollback: drop view public.gv_fac_ajustes_isis; drop table public."GV_Fac_Ajustes_ISIS";
create table if not exists public."GV_Fac_Ajustes_ISIS" (
  np        text not null,
  paso      text not null check (paso in ('lk_neg', 'ch_pos')),
  hecho_at  timestamptz not null default now(),
  legajo    text,
  primary key (np, paso)
);
alter table public."GV_Fac_Ajustes_ISIS" enable row level security;
create policy gv_fac_ajustes_sel on public."GV_Fac_Ajustes_ISIS" for select to anon, authenticated using (true);
create policy gv_fac_ajustes_ins on public."GV_Fac_Ajustes_ISIS" for insert to authenticated with check (true);
create policy gv_fac_ajustes_del on public."GV_Fac_Ajustes_ISIS" for delete to authenticated using (true);
grant select on public."GV_Fac_Ajustes_ISIS" to anon, authenticated;
grant insert, delete on public."GV_Fac_Ajustes_ISIS" to authenticated;

create or replace view public.gv_fac_ajustes_isis
with (security_invoker = true) as
with ent as (
  select distinct on (regexp_replace(e.np, '\.0+$', ''), upper(btrim(e.cod_art)))
         regexp_replace(e.np, '\.0+$', '') as np, upper(btrim(e.cod_art)) as cod_art,
         coalesce(e.cajas_entregadas, 0) as cajas, e.cod_cliente, e.tanda, e.creado
    from public."Entregas_Virgilio" e
   where e.cod_art ~* '^[0-9]+E?L$' and e.creado >= now() - interval '90 days'
   order by regexp_replace(e.np, '\.0+$', ''), upper(btrim(e.cod_art)), e.id desc
), por_np as (
  select np, max(cod_cliente) as cod_cliente, max(tanda) as tanda, max(creado) as armada_at,
         sum(cajas) as cajas,
         jsonb_agg(jsonb_build_object('art_ch', cod_art, 'art_lk', regexp_replace(cod_art, 'L$', ''), 'cajas', cajas) order by cod_art) as articulos
    from ent where cajas > 0 group by np
)
select p.np, p.cod_cliente, p.tanda, p.armada_at, p.cajas, p.articulos,
       f.razon_social, f.facturado_at,
       a1.hecho_at as lk_neg_at, a1.legajo as lk_neg_por,
       a2.hecho_at as ch_pos_at, a2.legajo as ch_pos_por,
       (a1.np is not null and a2.np is not null) as completo
  from por_np p
  left join public."Facturacion_NP" f on f.np = p.np
  left join public."GV_Fac_Ajustes_ISIS" a1 on a1.np = p.np and a1.paso = 'lk_neg'
  left join public."GV_Fac_Ajustes_ISIS" a2 on a2.np = p.np and a2.paso = 'ch_pos';
grant select on public.gv_fac_ajustes_isis to anon, authenticated;

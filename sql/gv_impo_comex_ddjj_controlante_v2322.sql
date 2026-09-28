-- IMPO COMEX web: datos del controlante de la DDJJ fuera del código (Elías, 2026-09-28).
-- Aplicado con el "sí" de Elías. Los VALORES no van en este archivo (repo público): se cargaron
-- a mano en la base. La puerta Impo_Comex_web (supabase/impo-comex-web/index.ts) los lee con la RPC.
create table impo_comex.ddjj_controlante (
  id smallint primary key default 1 check (id = 1),
  denominacion text not null, apellido text not null,
  domicilio text not null, cuit text not null,
  actualizado_en timestamptz not null default now());
alter table impo_comex.ddjj_controlante enable row level security;
revoke all on impo_comex.ddjj_controlante from anon, authenticated;
-- insert into impo_comex.ddjj_controlante (denominacion, apellido, domicilio, cuit)
-- values ('<denominación>', '<apellido>', '<domicilio>', '<cuit>');

create or replace function public.gv_impo_comex_ddjj_controlante()
returns jsonb language sql stable security definer set search_path = impo_comex, public as $$
  select case when public.es_supervisor_virgilio() then
    (select jsonb_build_object('denominacion',denominacion,'apellido',apellido,
             'domicilio',domicilio,'cuit',cuit) from impo_comex.ddjj_controlante where id = 1)
  end $$;
revoke execute on function public.gv_impo_comex_ddjj_controlante() from public, anon;
grant execute on function public.gv_impo_comex_ddjj_controlante() to authenticated;

-- Verificado (transacción abortada): supervisor ve los datos · otro mail = null ·
-- authenticated no lee la tabla · anon no puede llamar la función.
-- Rollback: drop function public.gv_impo_comex_ddjj_controlante(); drop table impo_comex.ddjj_controlante;

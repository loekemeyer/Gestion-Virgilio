-- v29.92 (Thomas, 13/10): panel por ROL en el admin.
-- gv_rol_panel(): UN round-trip con los contadores que arma el checklist por area.
-- SECURITY DEFINER para que los numeros sean reales aunque el que llame sea anon
-- (algunas funciones base devuelven 0 a anon por su guard). Solo devuelve agregados,
-- ningun dato sensible. Medido: ~1,0 s.
-- Rollback: drop function public.gv_rol_panel();

create or replace function public.gv_rol_panel()
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select jsonb_build_object(
    'sin_zona_np',  (select count(*) from public."PPP_Web_Programacion" where (zona is null or btrim(zona)='')),
    'sin_zona_ped', (select count(distinct order_id) from public."PPP_Web_Programacion" where (zona is null or btrim(zona)='')),
    'atrasados',    (select count(*) from public.gv_ppp_atrasados(current_date)),
    'cuar_prog',    (select count(*) from public.gv_cuarentena_ya_programado()),
    'cuar_armado',  (select count(*) from public.gv_cuarentena_armado_lista()),
    'imp_ir',       (select count(*) from public.gv_imp_ir_avisos(14)),
    'expreso',      (select count(*) from public.gv_expreso_pendiente),
    'ads_tall',     public.gv_ads_badge(),
    'ads_stock',    public.gv_ads_badge_stock(),
    'conc',         (select coalesce(sum(preguntas+propuestos),0) from public.gv_conc_tablero())
  );
$$;
revoke all on function public.gv_rol_panel() from public;
grant execute on function public.gv_rol_panel() to anon, authenticated, service_role;

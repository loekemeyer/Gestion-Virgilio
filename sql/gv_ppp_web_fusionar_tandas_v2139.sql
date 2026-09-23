-- v21.39 (Luis, 2026-09-22): "Las tandas tienen que ser de 0,8 en promedio. Minimo 0,6, maximo 1"
-- y despues, sobre la fusion: "tiene que ser 0,80".
--
-- LO MEDIDO ANTES DE ESCRIBIR ESTO (22/09, tandas de reparto de los ultimos 7 dias + futuras):
--   62 tandas · promedio 0,631 m3 · 35 por debajo de 0,6 · 41 de UN solo cliente.
--   Caso testigo: 28/09 GBA Oeste, CINCO tandas para 0,846 m3 (E46A 0,248 · E46B 0,323 ·
--   E46C 0,042 · E49A 0,107 · E50A 0,126), tres de ellas del mismo sector M (Ciudadela).
--
-- LA CAUSA: `ppp_web_armar_tandas` acumula clientes NUEVOS en una tanda abierta del mismo dia y
-- camion (hasta `tanda_m3_max_mezcla`, v13.67), pero NUNCA vuelve a juntar dos tandas que ya
-- existen. Cada una nacio en su corrida con el dia que tenia en ese momento; cuando el dia se
-- movio (reprogramacion, ancla, cascada) quedaron varias en el mismo camion, chicas, y nadie
-- las volvio a mirar. Y `tanda_m3_min` (0,60) NO lo lee ninguna funcion: es un cartel del front.
--
-- ESTA FUNCION ES EL PASE DE FUSION. Por (fecha, camion) toma las tandas que se pueden juntar
-- —sin empezar, sin super, sin retira, sin cliente 'solo', de un solo camion, en dia con
-- reparto— y las junta de a pares, de la mas grande a la mas chica, hasta el OBJETIVO
-- (`tanda_m3_fusion`, 0,80) sin pasar nunca el MAXIMO (`tanda_m3_max_mezcla`, 1,00). Solo
-- absorbe una tanda cuyas paradas sean todas compatibles con las de la que recibe
-- (`gv_ppp_web_compat`: mismo camion, sectores vecinos o pares del dueno). La fusion en si la
-- hace `gv_ppp_tanda_renombrar`, que ya sabe mover programacion, eventos y stock (v19.69/v20.88).
--
-- ⚠ Solo tandas SIN EMPEZAR: un pallet con papel impreso no se renombra solo (regla v20.88,
--   "cuando el registro y el pallet no coinciden manda el pallet").
-- ⚠ p_simular = true (default) no escribe: devuelve lo que HARIA. Es la forma de probarlo.
-- ⚠ La llama el armador al final de cada corrida, solo si `tanda_fusion_activa` <> 0.
--   Apagarlo es un update, no un deploy.

insert into public."PPP_Web_Config" (clave, valor) values ('tanda_m3_fusion', 0.80)
  on conflict (clave) do nothing;
insert into public."PPP_Web_Config" (clave, valor) values ('tanda_fusion_activa', 0)
  on conflict (clave) do nothing;

create or replace function public.gv_ppp_web_fusionar_tandas(
  p_empresa text,
  p_desde   date    default null,
  p_simular boolean default true,
  p_por     text    default 'fusion-auto')
returns table (r_fecha date, r_camion text, r_destino text, r_absorbida text,
               r_m3_absorbida numeric, r_m3_antes numeric, r_m3_despues numeric)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_obj   numeric := coalesce((select valor from public."PPP_Web_Config" where clave = 'tanda_m3_fusion'), 0.80);
  v_max   numeric := coalesce((select valor from public."PPP_Web_Config" where clave = 'tanda_m3_max_mezcla'), 1.00);
  v_desde date    := coalesce(p_desde, current_date + 1);
  r_d     record;
  r_v     record;
  v_m3    numeric;
begin
  drop table if exists _fu_t;
  drop table if exists _fu_s;

  -- las tandas candidatas: web, con codigo de tanda de verdad, de un dia por delante
  create temp table _fu_t on commit drop as
  select upper(btrim(w.tanda)) as code, w.fecha_entrega as f,
         min(public.gv_ppp_web_camion(w.zona, public.gv_ppp_web_sector(w.zona, w.barrio, w.direccion))) as camion,
         count(distinct public.gv_ppp_web_camion(w.zona, public.gv_ppp_web_sector(w.zona, w.barrio, w.direccion))) as ncam,
         sum(coalesce(w.m3, 0)) as m3,
         bool_and(coalesce(w.zona, '') !~* 'super|retira|expo') as reparto,
         bool_or(public.gv_es_super(w.empresa, w.cod_cliente)) as tiene_super,
         bool_or(exists (select 1 from public."GV_Clientes_Reglas" g
                          where g.regla = 'solo' and g.empresa = p_empresa and g.cod_cliente = w.cod_cliente)) as tiene_solo,
         false as absorbida
    from public."PPP_Web_Programacion" w
   where w.empresa = p_empresa
     and w.fecha_entrega >= v_desde
     and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
     and upper(btrim(w.tanda)) ~ '^[A-Z]+[0-9]+[A-Z]+$'
   group by 1, 2;

  -- las que NO se tocan
  delete from _fu_t t
   where not t.reparto or t.tiene_super or t.tiene_solo or t.ncam <> 1
      or public.gv_es_dia_sin_reparto(t.f)
      -- una tanda en dos dias (problema 338) esta rota: no se le suma nada
      or t.code in (select code from _fu_t group by code having count(*) > 1)
      -- v20.88: lo que ya toco un operario tiene papel; no se renombra solo
      or exists (select 1 from public."Registros_Produccion_Virgilio" r
                  where split_part(r.texto, '|', 1) = t.code
                    and r.opcion in ('PK', 'PKC', 'EP', 'TP', 'TAP', 'AP', 'CC', 'CCN')
                    and r.legajo not in ('0', '1'))
      -- una tanda con stock ya movido tampoco (por si el evento se anulo con -X)
      or exists (select 1 from public."Movimientos_Stock" m where upper(btrim(m.ref)) = t.code);

  -- las paradas de cada candidata, para la compatibilidad de sectores
  create temp table _fu_s on commit drop as
  select upper(btrim(w.tanda)) as code, w.zona,
         public.gv_ppp_web_sector(w.zona, w.barrio, w.direccion) as sector,
         public.gv_ppp_web_barrio_norm(w.barrio, w.direccion) as bnorm
    from public."PPP_Web_Programacion" w
    join _fu_t t on t.code = upper(btrim(w.tanda)) and t.f = w.fecha_entrega
   where w.empresa = p_empresa;

  -- de la mas grande a la mas chica: la grande recibe, la chica se absorbe
  for r_d in select t.code, t.f, t.camion from _fu_t t order by t.f, t.camion, t.m3 desc, t.code loop
    continue when (select t.absorbida from _fu_t t where t.code = r_d.code);
    v_m3 := (select t.m3 from _fu_t t where t.code = r_d.code);
    loop
      exit when v_m3 >= v_obj;
      select v.code, v.m3 into r_v
        from _fu_t v
       where v.f = r_d.f and v.camion = r_d.camion
         and not v.absorbida and v.code <> r_d.code
         and v_m3 + v.m3 <= v_max
         and not exists (select 1
                           from _fu_s a
                           join _fu_s b on b.code = v.code
                          where a.code = r_d.code
                            and not public.gv_ppp_web_compat(a.zona, a.sector, a.bnorm, b.zona, b.sector, b.bnorm))
       order by v.m3 desc, v.code
       limit 1;
      exit when not found;

      update _fu_t set absorbida = true where code = r_v.code;
      r_fecha := r_d.f; r_camion := r_d.camion; r_destino := r_d.code; r_absorbida := r_v.code;
      r_m3_absorbida := round(r_v.m3, 3); r_m3_antes := round(v_m3, 3);
      v_m3 := v_m3 + r_v.m3;
      r_m3_despues := round(v_m3, 3);
      update _fu_t set m3 = v_m3 where code = r_d.code;
      if not p_simular then
        perform public.gv_ppp_tanda_renombrar(r_v.code, r_d.code, p_por);
      end if;
      return next;
    end loop;
  end loop;
end
$function$;

revoke execute on function public.gv_ppp_web_fusionar_tandas(text, date, boolean, text) from public, anon;
grant  execute on function public.gv_ppp_web_fusionar_tandas(text, date, boolean, text) to authenticated, service_role;

-- centinela: la regla no se puede perder del armador
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select 'gv_ppp_web_armar_pendientes', 'funcion', 'gv_ppp_web_fusionar_tandas',
       'al final de cada corrida el armador junta las tandas chicas del mismo dia y camion hasta tanda_m3_fusion (0,80), sin pasar tanda_m3_max_mezcla (1,00)',
       'Luis', 'v21.39'
 where not exists (select 1 from public."GV_Reglas_Centinela"
                    where objeto = 'gv_ppp_web_armar_pendientes' and patron = 'gv_ppp_web_fusionar_tandas');

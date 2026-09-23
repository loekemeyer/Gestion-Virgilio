-- v21.62 (Luis, 2026-09-23) — CLIENTES DE PRUEBA
--
-- Luis: "que sus pedidos solo se puedan programar como tanda unica (con un codigo especial
-- PruebaX donde X va aumentando) · si se programa automaticamente, con las reglas que ya hay
-- (las que aplican a Muller y Muller, que copia) · que no se considere cliente nuevo · que NO
-- le figuren a los operarios en su modulo (no son pedidos reales, no quiero que rompan la
-- operacion)".
--
-- Primer cliente de prueba: LK 99862 "Luiggy y Luiggy (PRUEBA)", creado en la pagina LK el
-- 23/09 como copia de Muller y Muller (LK 862). Login: usuario prueba123.
--
-- Cómo se cumple cada parte:
--   · tanda unica          -> GV_Clientes_Reglas regla 'solo' (ya existia: ppp_web_armar_tandas lo
--                              arma en su propia tanda y gv_ppp_web_fusionar_tandas no lo junta).
--   · codigo PRUEBAn       -> gv_prueba_tandas_normalizar() renombra (con gv_ppp_tanda_renombrar,
--                              que ya mueve todas las tablas) toda tanda web cuyos pedidos sean
--                              TODOS de clientes de prueba. Cron 'gv-prueba-tandas' cada 5 min.
--                              Mayusculas a proposito: renombrar hace upper() y todo el sistema
--                              compara codigos con upper(btrim()).
--   · reglas de Muller     -> la unica regla propia de Muller es su excepcion de cuarentena
--                              (gv_excepcion_cuarentena, 5 motivos incl. cliente_nuevo): se copia.
--   · no es cliente nuevo  -> esa misma excepcion. Es como el sistema saca a un cliente del reten
--                              sin esperar los 3 pedidos (gv_cuarentena_exento, lo usan la
--                              Cuarentena, el pipeline y el armado automatico).
--   · oculto al operario   -> front (index.html gvSinPrueba, monitor/tv.html): tanda PRUEBAn o
--                              cliente de esta tabla. El supervisor los sigue viendo en la PPP.
--   · cupo y camion        -> cuentan como cualquier pedido (Luis: "con las reglas que ya hay").
--
-- Centinela: select * from public.gv_prueba_mezclada;  -- vacia = ningun pedido de prueba quedo
--            adentro de una tanda con pedidos reales (esa tanda no se renombra y el operario
--            no ve el pedido de prueba, pero SI la tanda).
--
-- Rollback (una por una, en este orden):
--   select cron.unschedule('gv-prueba-tandas');
--   delete from public.gv_excepcion_cuarentena where empresa='lk' and cod='99862';
--   delete from public."GV_Clientes_Reglas" where empresa='lk' and cod_cliente='99862';
--   drop view public.gv_prueba_mezclada; drop function public.gv_prueba_tandas_normalizar(boolean);
--   drop function public.gv_es_cliente_prueba(text,text); drop table public."GV_Clientes_Prueba";

-- 1) la lista de clientes de prueba
create table if not exists public."GV_Clientes_Prueba" (
  empresa    text not null check (empresa in ('lk','chef')),
  cod        text not null,
  nombre     text,
  nota       text,
  creado_por text,
  creado_at  timestamptz not null default now(),
  primary key (empresa, cod)
);
alter table public."GV_Clientes_Prueba" enable row level security;
revoke insert, update, delete, truncate on public."GV_Clientes_Prueba" from anon, authenticated;
grant select on public."GV_Clientes_Prueba" to anon, authenticated;
-- el celular la lee para esconder los pedidos: sin policy, anon veria 0 filas (trampa v20.45)
drop policy if exists gv_clientes_prueba_select on public."GV_Clientes_Prueba";
create policy gv_clientes_prueba_select on public."GV_Clientes_Prueba" for select using (true);

-- 2) ¿es de prueba?
create or replace function public.gv_es_cliente_prueba(p_empresa text, p_cod text)
returns boolean language sql stable
set search_path to 'public', 'pg_temp'
as $$
  select exists (select 1 from public."GV_Clientes_Prueba" c
                  where c.empresa = public.gv_emp_norm(p_empresa)
                    and c.cod = regexp_replace(btrim(coalesce(p_cod, '')), '\.0+$', ''));
$$;

-- 3) renombrar a PRUEBAn las tandas que son SOLO de clientes de prueba
create or replace function public.gv_prueba_tandas_normalizar(p_simular boolean default false)
returns table(tanda_vieja text, tanda_nueva text, nps text)
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
declare r record; v_n int; v_code text;
begin
  select coalesce(max((regexp_match(z.c, '^PRUEBA([0-9]+)$'))[1]::int), 0) into v_n
    from (select upper(btrim(codigo)) c from public."GV_Tandas_Codigos_Usados"
          union all
          select upper(btrim(tanda)) from public."PPP_Web_Programacion" where tanda is not null) z;

  for r in
    select g.t, g.nps
      from (select upper(btrim(w.tanda)) as t,
                   string_agg(distinct public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx), ', ') as nps,
                   bool_and(public.gv_es_cliente_prueba(w.empresa, w.cod_cliente)) as todo_prueba
              from public."PPP_Web_Programacion" w
             where w.tanda is not null and btrim(w.tanda) <> ''
               and upper(btrim(w.tanda)) !~ '^PRUEBA[0-9]+$'
             group by 1) g
     where g.todo_prueba
       -- una tanda que ademas tenga NP de ISIS no es solo de prueba
       and not exists (select 1 from public."GV_PPP_Programacion_Diaria" d
                        where upper(btrim(d.tanda)) = g.t)
     order by 1
  loop
    loop
      v_n := v_n + 1;
      v_code := 'PRUEBA' || v_n;
      exit when not public.gv_ppp_web_codigo_tomado(v_code);
    end loop;
    if not coalesce(p_simular, false) then
      perform public.gv_ppp_tanda_renombrar(r.t, v_code, 'gv_prueba_tandas_normalizar');
    end if;
    tanda_vieja := r.t; tanda_nueva := v_code; nps := r.nps;
    return next;
  end loop;
end $$;
revoke execute on function public.gv_prueba_tandas_normalizar(boolean) from public, anon, authenticated;

-- 4) centinela: pedido de prueba metido en una tanda con pedidos reales
create or replace view public.gv_prueba_mezclada with (security_invoker = true) as
select g.tanda, g.fecha_entrega, g.nps_prueba, g.nps_reales,
       exists (select 1 from public."GV_PPP_Programacion_Diaria" d where upper(btrim(d.tanda)) = g.tanda) as con_isis
  from (select upper(btrim(w.tanda)) as tanda, min(w.fecha_entrega) as fecha_entrega,
               string_agg(distinct public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx), ', ')
                 filter (where public.gv_es_cliente_prueba(w.empresa, w.cod_cliente)) as nps_prueba,
               count(*) filter (where not public.gv_es_cliente_prueba(w.empresa, w.cod_cliente)) as nps_reales
          from public."PPP_Web_Programacion" w
         where w.tanda is not null and btrim(w.tanda) <> ''
         group by 1) g
 where g.nps_prueba is not null
   and (g.nps_reales > 0
        or exists (select 1 from public."GV_PPP_Programacion_Diaria" d where upper(btrim(d.tanda)) = g.tanda));

-- 5) DATOS — el cliente de prueba de Luis (requiere su "sí")
insert into public."GV_Clientes_Prueba" (empresa, cod, nombre, nota, creado_por)
values ('lk', '99862', 'Luiggy y Luiggy (PRUEBA)', 'Copia de Muller y Muller (LK 862), usuario prueba123', 'luis')
on conflict do nothing;

insert into public."GV_Clientes_Reglas" (cod_cliente, empresa, regla, nombre, nota)
values ('99862', 'lk', 'solo', 'Luiggy y Luiggy (PRUEBA)', 'v21.62 cliente de prueba: tanda propia (PRUEBAn), nunca mezclado')
on conflict do nothing;

insert into public.gv_excepcion_cuarentena (empresa, cod, nombre, motivos, origen, activo, nota, actualizado_por)
select 'lk', '99862', 'Luiggy y Luiggy (PRUEBA)', m.motivos, 'manual', true,
       'v21.62 cliente de prueba de Luis: copia la excepcion de Muller y Muller (862), no es cliente nuevo.', 'luis'
  from public.gv_excepcion_cuarentena m
 where m.empresa = 'lk' and m.cod = '862'
on conflict do nothing;

-- 6) cron (minuto 2, 7, 12…: no cae en el :00)
select cron.schedule('gv-prueba-tandas', '2-59/5 * * * *', 'select public.gv_prueba_tandas_normalizar()');

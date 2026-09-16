-- =============================================================================
-- gv_super_auto_programa_v1914.sql — v19.14 (2026-09-16)
-- Proyecto VIRGILIO (hrxfctzncixxqmpfhskv)
--
-- EXCEPCIÓN A LA REGLA DE LOS SÚPER: el INC se programa automáticamente siempre.
--
-- Thomas, 2026-09-16: *"hace una excepción a la regla de los super, ese INC se
-- programa automáticamente siempre"*.
--
-- La regla que sigue viva (v14.23, v18.28): un súper de `GV_Supers` **no lo toca el
-- armado automático** —lo programa el supervisor, porque tiene camión y turno propios—
-- y **un súper nunca se junta con clientes comunes**. Lo que cambia es sólo lo primero,
-- y sólo para el cliente que tenga la excepción cargada.
--
-- ⚠ LA EXCEPCIÓN NO AFLOJA LA REGLA DE MEZCLA. El auto_super entra al armado pero:
--   · queda marcado `va_solo` (mismo efecto que la regla 'solo'), así que **va solo en
--     su tanda** y ninguna tanda abierta lo absorbe;
--   · su camión sigue siendo `"Super"` (`gv_ppp_web_camion('Super', …)`), o sea que no
--     comparte camión con Capital / GBA *;
--   · `_ex` y `_open` siguen dejando afuera las tandas de súper (v18.60 / v18.87).
--   Chequeo: `select * from public.gv_ppp_super_mezclado;` — vacía = todo bien.
--
-- ── EL DÍA ES EL TURNO DE LA OC, NO EL PRÓXIMO DÍA CON CUPO ───────────────────
-- Un súper no se entrega "cuando haya cupo": se entrega el día que pidió. El turno
-- viene en la OC de Krikos y **ya estaba en Virgilio**: LK lo empuja cada 15 min a
-- `lk_pedidos_match.fecha_entrega` (`sync_pedidos_match_virgilio`, v13.77+) y el texto
-- crudo con hora queda en `fecha_entrega_txt` ("29/09/2026 14:00"). Por eso la
-- excepción no necesitó tocar ni la Edge Function ni el front: la lee
-- `gv_web_turno_pactado(empresa, order_id)`.
-- El pase nuevo va con `p_forzar_cods` → el cliente entra como **prioritario**, o sea
-- que **pisa el cupo del día**: el turno no se negocia. Si la OC no trae turno, el
-- pedido cae al pase (b) y sale el próximo día hábil con cupo.
--
-- ── DÓNDE SE PRENDE Y SE APAGA (sin código) ───────────────────────────────────
--   -- prender para otro súper:
--   insert into public."GV_Clientes_Reglas" (cod_cliente, empresa, regla, nombre, nota)
--   values ('<cod>', 'lk', 'auto_super', '<nombre>', '<quién lo pidió y cuándo>');
--   -- apagar (vuelve a "lo programa el supervisor"):
--   delete from public."GV_Clientes_Reglas" where regla = 'auto_super' and cod_cliente = '<cod>';
-- Hoy: **(lk, 1651) Inc Sociedad Anonima (Carrefour)**.
--
-- ── PROBADO CORRIENDO EL ARMADOR (no leyendo la función) ──────────────────────
-- `gv_ppp_web_armar_pendientes_simular` (corre el armado de verdad y lo deshace):
--   INC 1468 (súper, turno 29/09) + un cliente común de Zona 1 + Coto 801 (súper sin
--   excepción) →
--     · 1651 → **2026-09-29**, tanda PROPIA, zona "Super", 1 cliente  ✅ (su turno)
--     · 9991 → 2026-09-23, tanda aparte                               ✅ (cascada normal)
--     · 801  → **no se programa**                                    ✅ (sigue a mano)
-- Y el chip de A Programar (`gv_ppp_web_dia_salida`):
--     · 1651 con turno  → 29/09 · `super_auto` · "…para el turno de la OC, el 29/09"
--     · 1651 sin turno  → 23/09 · `super_auto` · "…la OC no trajo turno: va al próximo…"
--     · 801 y 4263      → `super` · "camión propio, lo programa el supervisor"
--
-- ROLLBACK: borrar la fila de `GV_Clientes_Reglas` (la excepción se apaga sola, el
-- código queda inerte). Para sacar el código: los replaces al revés en las 3 funciones.
-- =============================================================================

-- ── 1. la excepción es un dato, no código ────────────────────────────────────
alter table public."GV_Clientes_Reglas" drop constraint gv_clientes_reglas_regla_chk;
alter table public."GV_Clientes_Reglas" add constraint gv_clientes_reglas_regla_chk
  check (regla = any (array['solo'::text, 'prioritario'::text, 'auto_super'::text]));

insert into public."GV_Clientes_Reglas" (cod_cliente, empresa, regla, nombre, nota)
values ('1651', 'lk', 'auto_super', 'Inc Sociedad Anonima (Carrefour)',
        'Excepcion del dueno 2026-09-16: "hace una excepcion a la regla de los super, ese INC se programa automaticamente siempre". Entra al armado automatico aunque este en GV_Supers; sigue SOLO en su tanda y en su camion Super (la regla "el super no se junta con clientes" no se toca). Si la OC trae turno, ese es el dia.')
on conflict (cod_cliente, empresa, regla) do update set nota = excluded.nota, nombre = excluded.nombre;

-- ── 2. los dos helpers ───────────────────────────────────────────────────────
create or replace function public.gv_cliente_auto_super(p_empresa text, p_cod text)
returns boolean language sql stable
set search_path to 'public'
as $fn$
  select exists (
    select 1 from public."GV_Clientes_Reglas" g
     where g.regla = 'auto_super'
       and g.empresa = p_empresa
       and g.cod_cliente = nullif(btrim(coalesce(p_cod,'')), ''))
$fn$;

create or replace function public.gv_web_turno_pactado(p_empresa text, p_order_id bigint)
returns date language sql stable
set search_path to 'public'
as $fn$
  /* La fecha de entrega que exige el super, tal como la trae su OC. Llega de LK por el FDW
     (sync_pedidos_match_virgilio, cron cada 15 min) a lk_pedidos_match.fecha_entrega; el texto
     crudo con hora queda en fecha_entrega_txt. NULL = la OC no trajo turno. */
  select m.fecha_entrega
    from public.lk_pedidos_match m
   where m.empresa = p_empresa and m.order_id = p_order_id
   limit 1
$fn$;

-- ── 3. `ppp_web_armar_tandas`: que el auto_super pase las dos puertas, y solo ──
do $mig$
declare v_def text; v_new text;
begin
  v_def := pg_get_functiondef('public.ppp_web_armar_tandas(text,date,jsonb,text[],boolean)'::regprocedure);
  v_new := v_def;

  -- (a) va SOLO en su tanda: misma semantica que la regla 'solo'
  if position('where g.regla = ''solo'' and g.empresa = p_empresa
                    and g.cod_cliente = nullif(x->>''cod'','''')) as va_solo' in v_new) = 0
    then raise exception 'no encontre va_solo'; end if;
  v_new := replace(v_new,
    'where g.regla = ''solo'' and g.empresa = p_empresa
                    and g.cod_cliente = nullif(x->>''cod'','''')) as va_solo',
    'where g.regla in (''solo'', ''auto_super'') and g.empresa = p_empresa
                    and g.cod_cliente = nullif(x->>''cod'','''')) as va_solo' );

  -- (b) el padron de supers lo deja pasar
  if position('delete from _sin_tanda s where public.gv_es_super(p_empresa, s.cliente);' in v_new) = 0
    then raise exception 'no encontre el delete de supers'; end if;
  v_new := replace(v_new,
    'delete from _sin_tanda s where public.gv_es_super(p_empresa, s.cliente);',
'-- v19.14 (Thomas, 16/09): el super con regla ''auto_super'' en GV_Clientes_Reglas SI entra al
  -- armado. Sigue solo en su tanda (va_solo, arriba) y en su camion "Super", asi que la regla
  -- "el super no se junta con clientes" queda intacta.
  delete from _sin_tanda s where public.gv_es_super(p_empresa, s.cliente)
                             and not public.gv_cliente_auto_super(p_empresa, s.cliente);');

  -- (c) su zona es "Super", no "Zona N": el filtro de zona tampoco lo saca
  if position('delete from _sin_tanda
   where not public.gv_ppp_web_zona_automatica(zona)
     and not (p_incluir_manuales and zona ~ ''^\s*Zona\s*[0-9]+'');' in v_new) = 0
    then raise exception 'no encontre el delete por zona'; end if;
  v_new := replace(v_new,
    'delete from _sin_tanda
   where not public.gv_ppp_web_zona_automatica(zona)
     and not (p_incluir_manuales and zona ~ ''^\s*Zona\s*[0-9]+'');',
    'delete from _sin_tanda
   where not public.gv_ppp_web_zona_automatica(zona)
     and not (p_incluir_manuales and zona ~ ''^\s*Zona\s*[0-9]+'')
     -- v19.14: la zona de un super es "Super", no "Zona N": sin esto la excepcion no sirve
     and not public.gv_cliente_auto_super(p_empresa, cliente);');

  execute v_new;
end
$mig$;

-- ── 4. `gv_ppp_web_armar_pendientes`: el pase (a3), el turno es el día ────────
--    (el texto completo del pase está en la función; acá el parche que lo instala)
do $mig$
declare v_def text; v_new text;
begin
  v_def := pg_get_functiondef('public.gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)'::regprocedure);
  v_new := v_def;

  if position('  -- (b) zonas automaticas en cascada' in v_new) = 0
    then raise exception 'no encontre el pase (b)'; end if;
  v_new := replace(v_new, '  -- (b) zonas automaticas en cascada',
'  -- (a3) v19.14 (Thomas, 2026-09-16) — EL SUPER CON REGLA `auto_super` SE PROGRAMA SOLO, Y SI
  --   SU OC TRAE TURNO, ESE ES EL DIA. El turno viaja de LK cada 15 min
  --   (lk_pedidos_match.fecha_entrega -> gv_web_turno_pactado). Va con p_forzar_cods ->
  --   prioritario, o sea que PISA EL CUPO (el turno no se negocia) y con p_incluir_manuales
  --   porque su zona es "Super", no "Zona N". Sigue solo en su tanda y en su camion "Super".
  --   Sin turno en la OC cae al pase (b) y sale el proximo dia con cupo.
  for r in
    select t.d, jsonb_agg(t.x) as filas, array_agg(distinct t.x->>''cod'') as cods
      from (
        select greatest(public.gv_web_turno_pactado(p_empresa, (x->>''order_id'')::bigint),
                        current_date + 1) as d, x
          from jsonb_array_elements(p_filas) x
         where x->>''order_id'' ~ ''^[0-9]+$''
           and public.gv_cliente_auto_super(p_empresa, x->>''cod'')
           and public.gv_web_turno_pactado(p_empresa, (x->>''order_id'')::bigint) is not null
           and not exists (select 1 from public."PPP_Web_Programacion" g
                            where g.empresa = p_empresa and g.order_id = (x->>''order_id'')::bigint
                              and g.np_idx = (x->>''np_idx'')::int
                              and coalesce(nullif(trim(g.tanda),''''),'''') <> '''')
      ) t
     where t.d is not null
     group by t.d order by t.d
  loop
    delete from _gv_tmp where true;
    insert into _gv_tmp select * from public.ppp_web_armar_tandas(p_empresa, r.d, r.filas, r.cods, true);
    insert into _gv_res
    select r.d, t.r_tanda, t.r_zona, t.r_np_count, t.r_m3, t.r_clientes,
           (select array_agg(distinct s.cliente) from _asig a join _sin_tanda s on s.order_id = a.order_id and s.np_idx = a.np_idx where a.tanda = t.r_tanda)
      from _gv_tmp t;
  end loop;

  -- (b) zonas automaticas en cascada');

  if position('     where public.gv_ppp_web_zona_automatica(x->>''zona'')
       and not exists (select 1 from public."PPP_Web_Programacion" g' in v_new) = 0
    then raise exception 'no encontre el conteo del pase (b)'; end if;
  v_new := replace(v_new,
    '     where public.gv_ppp_web_zona_automatica(x->>''zona'')
       and not exists (select 1 from public."PPP_Web_Programacion" g',
    '     where (public.gv_ppp_web_zona_automatica(x->>''zona'')
              -- v19.14: sin esto, un auto_super solo en la lista no hacia correr el pase (b)
              or public.gv_cliente_auto_super(p_empresa, x->>''cod''))
       and not exists (select 1 from public."PPP_Web_Programacion" g');

  execute v_new;
end
$mig$;

-- ── 5. el chip de A Programar deja de decir "a mano" para el auto_super ──────
do $mig$
declare v_def text; v_new text;
begin
  v_def := pg_get_functiondef('public.gv_ppp_web_dia_salida(jsonb,timestamp with time zone)'::regprocedure);
  v_new := v_def;

  -- guarda de idempotencia: los replaces de esta seccion NO se pueden correr dos veces
  if position('  aut as (' in v_new) > 0 then raise notice 'ya aplicado, no toco nada'; return; end if;
  if position('       and public.gv_es_super(f.empresa,' in v_new) = 0
    then raise exception 'no encontre el CTE sup'; end if;
  v_new := replace(v_new, '       and public.gv_es_super(f.empresa,',
    '       -- v19.14: el super con excepcion (auto_super) SI lo programa el automatico
       and not public.gv_cliente_auto_super(f.empresa, f.cod)
       and public.gv_es_super(f.empresa,');

  if position('  ret as (' in v_new) = 0 then raise exception 'no encontre el CTE ret'; end if;
  v_new := replace(v_new, '  ret as (',
'  /* v19.14 — el super con regla `auto_super` se arma solo, y el dia es el TURNO de su OC
     (lk_pedidos_match.fecha_entrega). Sin turno cae a la cascada. Va antes que la rama de
     super, que si no lo rotula "a mano" por su zona "Super". */
  aut as (
    select f.idx,
           public.gv_web_turno_pactado(f.empresa, f.order_id) as turno,
           case when public.gv_web_turno_pactado(f.empresa, f.order_id) is not null
                  then greatest(public.gv_web_turno_pactado(f.empresa, f.order_id), v_local::date + 1)
                else v_dia_job end as d
      from f
     where f.empresa is not null
       and public.gv_cliente_auto_super(f.empresa,
             coalesce(f.cod,
               (select g.cod_cliente from public."PPP_Web_Programacion" g
                 where g.empresa = f.empresa and g.order_id = f.order_id limit 1)))
  ),
  ret as (');

  v_new := replace(v_new, 'when exists (select 1 from ret where ret.idx = f.idx) then null',
    'when exists (select 1 from ret where ret.idx = f.idx) then null
           when exists (select 1 from aut where aut.idx = f.idx)
             then (select a.d from aut a where a.idx = f.idx)');

  v_new := replace(v_new, 'when exists (select 1 from ret where ret.idx = f.idx) then ''retenido''',
    'when exists (select 1 from ret where ret.idx = f.idx) then ''retenido''
           when exists (select 1 from aut where aut.idx = f.idx) then ''super_auto''');

  -- el detalle: la rama va despues de la de "retenido" (que termina en "Ponele el dia vos.")
  v_new := replace(v_new, 'Ponele el dia vos.''',
    'Ponele el dia vos.''
           when exists (select 1 from aut where aut.idx = f.idx)
             then ''Súper con excepción del dueño (auto_super): lo programa el automático''
                  || coalesce('' para el turno de la OC, el '' ||
                       to_char((select a.turno from aut a where a.idx = f.idx), ''DD/MM''),
                       '', y la OC no trajo turno: va al próximo día hábil con cupo'')');

  execute v_new;
end
$mig$;

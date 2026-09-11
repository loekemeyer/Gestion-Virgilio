-- =============================================================================
-- gv_ppp_web_diferido.sql — La NP que espera mercadería se programa aparte y
-- nunca antes del reingreso. (2026-09-11, v15.61)
-- =============================================================================
-- Regla del dueño (Thomas, 11/09/2026): *"si un cliente igualmente me pide un
-- item que no voy a tener hasta xx/xx, quiero separar el pedido de ese cliente:
-- 1) lo que va normal, con las condiciones normales de programación;
-- 2) lo que se programa para entregar recién a partir de que llega esa
-- mercadería"*.
--
-- EL CORTE LO HACE LK, NO ACÁ. `v_pedidos_web_np` (proyecto kwkclwhmoygunqmlegrg,
-- `sql/pedido_diferido.sql` del repo pagina-LK-copia) ya devuelve el bloque que
-- espera mercadería como una NP aparte, con dos columnas nuevas: `diferido` y
-- `no_antes_de` (fecha piso, resuelta en vivo contra `reingreso_cache`: si el
-- artículo ya entró viene NULL y la NP se programa como cualquier otra).
-- Acá sólo se decide CUÁNDO se programa esa NP.
--
-- ⚠ CHOCA CON EL CANDADO v15.52, Y GANA ESTE. El 11/09 a la mañana el dueño
--   pidió *"nunca si hay +1 pedido de un cliente puede ir separado en la PPP…
--   salvo los súper"* (`gv_ppp_web_juntar_clientes`, pase (d)). A la tarde pidió
--   justamente separar. No se contradicen: el candado existe para que no se
--   parta un cliente POR EL ARMADO (cupo, cascada); acá se parte porque la
--   mercadería no está. La excepción es sólo la NP diferida: todo lo demás del
--   cliente se sigue juntando en un día.
-- =============================================================================

-- 1) Registro de las NP diferidas que ve el armado. Tabla nuestra (prefijo GV_),
--    no toca nada compartido.
create table if not exists public."GV_PPP_Web_Diferido" (
  empresa      text   not null,
  order_id     bigint not null,
  np_idx       int    not null,
  no_antes_de  date   not null,
  creado_at    timestamptz not null default now(),
  primary key (empresa, order_id, np_idx)
);
alter table public."GV_PPP_Web_Diferido" enable row level security;
create policy gv_ppp_web_diferido_sel on public."GV_PPP_Web_Diferido"
  for select to authenticated using (true);

comment on table public."GV_PPP_Web_Diferido" is
  'NP web cuyo contenido espera un reingreso de importado: no se programa antes de no_antes_de y queda fuera del candado mismo-cliente-mismo-dia (v15.52). La llena gv_ppp_web_armar_pendientes con lo que manda el feed de LK.';

-- 2) gv_ppp_web_armar_pendientes: aparta lo diferido de los pases normales y le
--    da su propio pase (b2). Se parchea la definición viva para no re-tipear
--    10 kB de función (y que un error de transcripción no se lleve puesto el
--    armado); si un ancla no está exactamente una vez, no se aplica nada.
do $do$
declare
  src text;
  a1  text := E'  r        record;\n';
  a2  text := '  -- (a) forzados con fecha';
  a3  text := '  -- (d) v15.52';
begin
  select pg_get_functiondef(p.oid) into src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'gv_ppp_web_armar_pendientes';

  if src is null then raise exception 'no existe gv_ppp_web_armar_pendientes'; end if;
  if src like '%GV_PPP_Web_Diferido%' then
    raise notice 'gv_ppp_web_armar_pendientes ya tiene el pase de diferidos: no se toca';
    return;
  end if;
  if (length(src) - length(replace(src, a1, ''))) / length(a1) <> 1 then
    raise exception 'ancla 1 (declaraciones) no aparece exactamente una vez';
  end if;
  if (length(src) - length(replace(src, a2, ''))) / length(a2) <> 1 then
    raise exception 'ancla 2 (pase a) no aparece exactamente una vez';
  end if;
  if (length(src) - length(replace(src, a3, ''))) / length(a3) <> 1 then
    raise exception 'ancla 3 (pase d) no aparece exactamente una vez';
  end if;

  src := replace(src, a1, a1 || E'  v_dif    jsonb := ''[]''::jsonb;\n  v_piso   date;\n');

  src := replace(src, a2,
$b$  -- (a0) v15.61 -- LO QUE ESPERA MERCADERIA SALE DE LOS PASES NORMALES.
  --   LK manda esas lineas como una NP aparte (v_pedidos_web_np.diferido / no_antes_de).
  --   Aca se apartan para que ningun pase las programe antes de tiempo: las toma el (b2).
  v_dif := coalesce((select jsonb_agg(x) from jsonb_array_elements(p_filas) x
                      where nullif(x->>'no_antes_de','')::date > v_min), '[]'::jsonb);
  p_filas := coalesce((select jsonb_agg(x) from jsonb_array_elements(p_filas) x
                        where coalesce(nullif(x->>'no_antes_de','')::date, v_min) <= v_min), '[]'::jsonb);

  insert into public."GV_PPP_Web_Diferido" (empresa, order_id, np_idx, no_antes_de)
  select p_empresa, (x->>'order_id')::bigint, (x->>'np_idx')::int, (x->>'no_antes_de')::date
    from jsonb_array_elements(v_dif) x
  on conflict (empresa, order_id, np_idx) do update set no_antes_de = excluded.no_antes_de;

$b$ || a2);

  src := replace(src, a3,
$c$  -- (b2) v15.61 -- LO DIFERIDO: cada piso de fecha, su dia.
  --   El dia es el primer habil CON CUPO a partir del reingreso, nunca antes. Va con
  --   tandas propias: no se puede sumar a la tanda que el cliente ya tiene esta semana,
  --   porque esa sale antes de que la mercaderia entre al deposito.
  for r in
    select nullif(x->>'no_antes_de','')::date as piso,
           jsonb_agg(x) as filas,
           array_agg(distinct x->>'cod') as cods
      from jsonb_array_elements(v_dif) x
     where nullif(btrim(coalesce(x->>'cod','')),'') is not null
       and coalesce(x->>'zona','') ~ '^\s*Zona\s*[0-9]+'
       and not exists (select 1 from public."PPP_Web_Programacion" g
                        where g.empresa = p_empresa and g.order_id = (x->>'order_id')::bigint
                          and g.np_idx = (x->>'np_idx')::int and coalesce(nullif(trim(g.tanda),''),'') <> '')
     group by 1 order by 1
  loop
    v_piso := public.gv_ppp_web_proximo_dia_con_cupo(greatest(r.piso, v_min));
    delete from _gv_tmp where true;
    insert into _gv_tmp select * from public.ppp_web_armar_tandas(p_empresa, v_piso, r.filas, r.cods, true);
    insert into _gv_res
    select v_piso, t.r_tanda, t.r_zona, t.r_np_count, t.r_m3, t.r_clientes,
           (select array_agg(distinct s.cliente) from _asig a join _sin_tanda s
             on s.order_id = a.order_id and s.np_idx = a.np_idx where a.tanda = t.r_tanda)
      from _gv_tmp t;
  end loop;

$c$ || a3);

  execute src;
  raise notice 'gv_ppp_web_armar_pendientes parcheada con el pase de diferidos';
end
$do$;

-- 3) El candado mismo-cliente-mismo-dia (v15.52) NO toca las NP diferidas: si
--    las juntara con el resto, las traeria al dia de la semana que viene y el
--    bloque saldria sin la mercaderia que espera.
do $do$
declare
  src  text;
  anc  text := $a$coalesce(w.zona,'') ~ '^\s*Zona\s*[0-9]+'$a$;
  add  text := $a$ and not exists (select 1 from public."GV_PPP_Web_Diferido" d where d.empresa = w.empresa and d.order_id = w.order_id and d.np_idx = w.np_idx)$a$;
  n    int;
begin
  select pg_get_functiondef(p.oid) into src
    from pg_proc p join pg_namespace n2 on n2.oid = p.pronamespace
   where n2.nspname = 'public' and p.proname = 'gv_ppp_web_juntar_clientes';

  if src is null then raise exception 'no existe gv_ppp_web_juntar_clientes'; end if;
  if src like '%GV_PPP_Web_Diferido%' then
    raise notice 'gv_ppp_web_juntar_clientes ya excluye las diferidas: no se toca';
    return;
  end if;

  n := (length(src) - length(replace(src, anc, ''))) / length(anc);
  if n <> 3 then raise exception 'el ancla de zona aparece % veces, se esperaban 3', n; end if;

  src := replace(src, anc, anc || add);
  execute src;
  raise notice 'gv_ppp_web_juntar_clientes parcheada: excluye las NP diferidas';
end
$do$;

-- =============================================================================
-- CONTROLES (correr a mano)
-- =============================================================================
--   -- a) qué NP están esperando mercadería y para cuándo
--   select * from public."GV_PPP_Web_Diferido" order by no_antes_de, order_id;
--
--   -- b) ninguna NP diferida programada ANTES de su piso (tiene que dar 0)
--   select w.empresa, w.order_id, w.np_idx, w.np, w.fecha_entrega, d.no_antes_de
--     from public."PPP_Web_Programacion" w
--     join public."GV_PPP_Web_Diferido" d
--       on d.empresa = w.empresa and d.order_id = w.order_id and d.np_idx = w.np_idx
--    where w.fecha_entrega < d.no_antes_de;
--
--   -- c) el armado sigue dando lo mismo para lo que NO es diferido: correr
--   --    gv_ppp_web_armar_simular(...) antes y después y comparar.
--
-- ROLLBACK: restaurar las dos funciones desde
--   sql/backups/gv_ppp_web_armar_pendientes_<fecha>.sql y
--   sql/backups/gv_ppp_web_juntar_clientes_<fecha>.sql (volcarlas ANTES de
--   aplicar con pg_get_functiondef), y `drop table public."GV_PPP_Web_Diferido"`.
--   Nada de esto toca objetos de Producción: ver docs/ROLLBACK-PRODUCCION.md.
-- =============================================================================

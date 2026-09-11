-- =============================================================================
-- gv_ppp_web_diferido.sql — La NP que espera mercadería se programa aparte y
-- nunca antes del reingreso. (2026-09-11, v15.67)
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

-- La LLENA LK por el FDW (`sync_diferido_virgilio`, cron 41 cada 10 min, mismo
-- patrón que `lk_pedidos_match`): así el armado no depende de que el front ni la
-- Edge Function del cron manden el dato en el payload, y no hubo que redeployar
-- nada. `lk_ppp_reader` escribe SOLO esta tabla y `lk_pedidos_match`.
grant select, insert, update, delete on public."GV_PPP_Web_Diferido" to lk_ppp_reader;
create policy gv_ppp_web_diferido_lk on public."GV_PPP_Web_Diferido"
  for all to lk_ppp_reader using (true) with check (true);

comment on table public."GV_PPP_Web_Diferido" is
  'NP web cuyo contenido espera un reingreso de importado: no se programa antes de no_antes_de y queda fuera del candado mismo-cliente-mismo-dia (v15.52). La llena LK por el FDW: sync_diferido_virgilio, cron 41, cada 10 min.';

-- 2) gv_ppp_web_armar_pendientes: aparta lo diferido de los pases normales (a0)
--    y le da su propio pase (b2). Se parchea la definición viva para no re-tipear
--    10 kB de función (y que un error de transcripción no se lleve puesto el
--    armado); si un ancla no está exactamente una vez, no se aplica nada.
--    El backup de la versión anterior está en `GV_Backup_Funciones`
--    (motivo 'pre v15.61 diferido'), que es de donde se restaura.
--
--    (a0) saca de `p_filas` toda NP que figure en GV_PPP_Web_Diferido con un piso
--         posterior al día mínimo, y las guarda en `v_dif` con el piso adentro.
--    (b2) las programa: primer día hábil CON CUPO a partir del piso, nunca antes,
--         con tandas propias (no se suman a la tanda que el cliente ya tiene esta
--         semana, que sale antes de que la mercadería entre).
--    Cuando la mercadería entra, LK borra la fila y la NP vuelve sola a los pases
--    normales — pero sigue siendo una NP aparte: el corte no se deshace.
--
--    El SQL exacto que se ejecutó está en el commit de esta misma fecha; para
--    verlo tal como quedó: select prosrc from pg_proc where proname =
--    'gv_ppp_web_armar_pendientes'.

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
--   `GV_Backup_Funciones` (motivo 'pre v15.61 diferido'):
--   execute la columna `def` de cada una, y `drop table public."GV_PPP_Web_Diferido"`.
--   Del lado LK: borrar el cron `sync-diferido-virgilio` (jobid 41).
--   Nada de esto toca objetos de Producción: ver docs/ROLLBACK-PRODUCCION.md.
-- =============================================================================

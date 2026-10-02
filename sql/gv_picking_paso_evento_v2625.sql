-- v26.25 (D12, 02/10/2026): MÉTRICAS DEL PICKING POR PASO.
-- Pedido: "evaluar el desempeño de los operarios durante una tanda de pickeo … que no
-- afecte la operación". El registro de cada artículo (PKC) guarda sólo la hora de la
-- ÚLTIMA confirmación (un reconfirmado pisa la primera), junta góndola y excedente en una
-- fila y no dice qué celda se mostró, ni los saltos con Adelante/Atrás, ni cuándo el
-- celular se bloqueó. Esto lo captura APARTE, en una tabla propia:
--   * PKC NO se toca (mueve el stock y lo leen 12 objetos).
--   * Registros_Produccion_Virgilio NO se toca (lo leen el monitor, el Resumen de hoy,
--     los avisos de Telegram y el contador de tiempo muerto).
-- La app escribe sólo con INSERT (anon no lee, no modifica ni borra) y por su propia cola
-- local: si esto falla, el picking sigue igual.
-- ⚠ Sin ON CONFLICT: exige SELECT y la RLS lo rechaza para anon (medido 02/10). Un reenvío
--   del mismo client_id da 23505 → 409 y la app lo descarta.
-- Aplicado el 02/10 statement por statement (la migración entera se colgaba en el permiso).
-- Probado en transacción abortada: como anon inserta (1 fila), el duplicado choca 23505, y
-- no lee, no borra ni modifica (42501). La vista: reconfirmado conserva la 1.ª hora, ráfaga
-- < 3 s sale medible=false, y el bloqueo de 60 s se descuenta en seg_oculto.

create table if not exists public."GV_Picking_Paso_Evento" (
  id          bigserial primary key,
  client_id   text not null unique,          -- idempotencia de la cola offline (un reenvío choca 409 y se descarta)
  legajo      text not null,
  tanda       text not null,
  evento      text not null check (evento in
                ('mostrado','ok','faltan','sin_stock','adelante','atras','oculta','visible')),
  paso        text,                          -- clave del paso: '546' o '546·EXC'
  art         text,                          -- código que se levanta (el elegido si es par nac/imp)
  sector      text,                          -- la celda (o el excedente) que la app MOSTRÓ
  es_exc      boolean,                       -- paso de excedente
  nota        text,                          -- 'salteado' (excedente cubre todo) · 'forzado' · 'resumen'
  idx         integer,                       -- posición del paso en la lista (0..total)
  total       integer,
  esp         numeric,
  real        numeric,
  dur_seg     numeric,                       -- en 'visible': cuánto estuvo bloqueado / en 2.º plano
  ts_cliente  timestamptz not null,          -- hora del celular
  dispositivo text,
  app_version text,
  created_at  timestamptz not null default now()
);
alter table public."GV_Picking_Paso_Evento" enable row level security;
revoke all on public."GV_Picking_Paso_Evento" from anon, authenticated;
grant insert on public."GV_Picking_Paso_Evento" to anon, authenticated;
grant usage on sequence public."GV_Picking_Paso_Evento_id_seq" to anon, authenticated;
drop policy if exists gv_pk_paso_insert on public."GV_Picking_Paso_Evento";
create policy gv_pk_paso_insert on public."GV_Picking_Paso_Evento" for insert to anon, authenticated
  with check (length(client_id) between 8 and 160 and length(tanda) between 1 and 40);
create index if not exists gv_pk_paso_tanda_idx on public."GV_Picking_Paso_Evento"(tanda, legajo, ts_cliente);
create index if not exists gv_pk_paso_ts_idx on public."GV_Picking_Paso_Evento"(ts_cliente);

-- Lectura: una fila por (tanda, operario, paso). Sólo MCP / postgres (anon no lee).
--   seg_desde_anterior = primera confirmación de este paso − la confirmación anterior de la tanda
--   seg_oculto         = lo que el celular estuvo bloqueado o en 2.º plano en ese tramo
--   medible            = false si se confirmó en ráfaga (< 3 s de la anterior)
create or replace view public.gv_picking_paso with (security_invoker = true) as
with e as (
  select * from public."GV_Picking_Paso_Evento" where not public.es_legajo_test(legajo)
),
conf as (
  select tanda, legajo, paso,
         min(art) art, min(sector) sector, bool_or(es_exc) es_exc,
         min(ts_cliente) primera_conf, max(ts_cliente) ultima_conf, count(*) confirmaciones,
         (array_agg(evento order by ts_cliente desc))[1] accion_final,
         (array_agg(esp order by ts_cliente desc))[1] esp,
         (array_agg(real order by ts_cliente desc))[1] real_final
    from e where evento in ('ok','faltan','sin_stock') and paso is not null
   group by 1,2,3
),
vis as (
  select tanda, legajo, paso, count(*) visitas, min(ts_cliente) primera_vez
    from e where evento = 'mostrado' and paso is not null group by 1,2,3
),
seq as (
  select c.*, v.visitas, v.primera_vez,
         lag(c.primera_conf) over (partition by c.tanda, c.legajo order by c.primera_conf) conf_anterior
    from conf c left join vis v using (tanda, legajo, paso)
)
select s.tanda, s.legajo, s.paso, s.art, s.sector, s.es_exc,
       s.visitas, s.primera_vez, s.primera_conf, s.ultima_conf, s.confirmaciones,
       s.accion_final, s.esp, s.real_final,
       round(extract(epoch from s.primera_conf - s.conf_anterior)::numeric, 1) seg_desde_anterior,
       coalesce((select sum(o.dur_seg) from e o
                  where o.evento = 'visible' and o.tanda = s.tanda and o.legajo = s.legajo
                    and o.ts_cliente > s.conf_anterior and o.ts_cliente <= s.primera_conf), 0) seg_oculto,
       not (s.conf_anterior is not null
            and s.primera_conf - s.conf_anterior < interval '3 seconds') medible
  from seq s;
revoke all on public.gv_picking_paso from anon, authenticated;

-- Interrupciones por tanda (celular bloqueado o app en 2.º plano durante el picking).
create or replace view public.gv_picking_interrupcion with (security_invoker = true) as
select tanda, legajo, count(*) veces, round(sum(dur_seg)::numeric) seg_total,
       round(max(dur_seg)::numeric) seg_max, min(ts_cliente) primera, max(ts_cliente) ultima
  from public."GV_Picking_Paso_Evento"
 where evento = 'visible' and not public.es_legajo_test(legajo)
 group by 1,2;
revoke all on public.gv_picking_interrupcion from anon, authenticated;

-- Chequeo:
--   select evento, count(*) from public."GV_Picking_Paso_Evento"
--    where created_at >= current_date group by 1;
--   select * from public.gv_picking_paso where tanda = '<T>' order by primera_conf;
-- Rollback (antes sacar el envío del front, pkmEvento en index.html):
--   drop view public.gv_picking_interrupcion; drop view public.gv_picking_paso;
--   drop table public."GV_Picking_Paso_Evento";

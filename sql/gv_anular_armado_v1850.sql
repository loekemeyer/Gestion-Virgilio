-- v18.50 — "No la armo yo": soltar un armado agarrado por error.
-- Pedido de Luis (2026-09-15): "FO tiene el armado de la E11B pero la seleccionó por error, él no
-- la hace". Hasta acá las únicas salidas eran dar TAP (marcarla armada y mover stock, o sea
-- mentir) o dejarla abierta — y abierta queda con candado para TODOS por la exclusividad v5.74.
-- Así se colgó E11B 3 h 30 el 15/09.
-- Es el espejo de anular_picking_virgilio, que existe desde la v8.00 y nunca tuvo su hermano.

create table if not exists public."GV_Tanda_Anulada" (
  id          bigserial primary key,
  tanda       text        not null,
  fase        text        not null check (fase in ('picking','armado')),
  legajo      text        not null,
  motivo      text,
  ts_evento   timestamptz,
  anulado_en  timestamptz not null default now()
);
alter table public."GV_Tanda_Anulada" enable row level security;   -- sin policies: sólo service_role / postgres
create index if not exists gv_tanda_anulada_tanda_idx on public."GV_Tanda_Anulada" (upper(tanda), fase);

comment on table public."GV_Tanda_Anulada" is
 'v18.50 - registro de las tandas que un operario SOLTO sin terminar (pidio Luis, 15/09: "o la termina, o la cancelan, queda el registro que se cancela y queda para que la armen de vuelta"). La escriben las RPC anular_*_virgilio, que son SECURITY DEFINER; anon no la lee ni la escribe directo. Antes anular un picking borraba el EP y no dejaba ningun rastro de que habia pasado.';

create or replace function public.anular_armado_virgilio(p_legajo text, p_tanda text, p_motivo text default null)
 returns text
 language plpgsql
 security definer
 set search_path to 'public','pg_temp'
as $function$
declare v_id uuid; v_ts timestamptz; v_leg text; v_tanda text; v_tal int; v_ent int; v_etl int;
begin
  v_leg   := btrim(coalesce(p_legajo, ''));
  v_tanda := upper(btrim(coalesce(p_tanda, '')));
  if v_leg = '' or v_tanda = '' then return 'faltan_datos'; end if;

  -- el AP abierto de ESTE legajo sobre ESTA tanda. 72 h: un armado puede cruzar el fin de semana.
  select id, created_at into v_id, v_ts
    from public."Registros_Produccion_Virgilio"
   where opcion = 'AP' and legajo = v_leg
     and upper(btrim(coalesce(texto, ''))) = v_tanda
     and created_at > now() - interval '72 hours'
   order by created_at desc limit 1;
  if v_id is null then return 'sin_ap'; end if;

  -- ya terminado → no hay nada que soltar
  if exists (select 1 from public."Registros_Produccion_Virgilio"
              where opcion = 'TAP' and upper(btrim(coalesce(texto, ''))) = v_tanda
                and created_at >= v_ts) then
    return 'ya_cerrado';
  end if;

  -- ⚠ El asistente NO escribe nada en el servidor mientras el operario arma: los líos (TAL), las
  -- Entregas y el TAP salen TODOS JUNTOS recién al tocar «Terminar» (compTerminar). O sea que en
  -- el caso normal —empecé, fui marcando, me dicen que está mal— acá no hay nada y se suelta
  -- limpio, como si nunca lo hubiera agarrado. Este chequeo es para el caso raro en que
  -- «Terminar» grabó a medias (pasó el 14/09: el POST a Entregas murió con 42501 y el TAP llegó
  -- igual). Ahí sí hay que mirarlo a mano: borrar Entregas mueve stock y facturación.
  -- Se acota a lo creado DESDE el AP, así una entrega vieja de cuando el código de tanda se usó
  -- antes no frena una anulación legítima de hoy.
  select count(*) into v_tal from public."Registros_Produccion_Virgilio"
   where opcion = 'TAL' and upper(split_part(btrim(coalesce(texto,'')), '|', 3)) = v_tanda
     and created_at >= v_ts;
  select count(*) into v_ent from public."Entregas_Virgilio"
   where upper(btrim(coalesce(tanda,''))) = v_tanda and creado >= v_ts;
  if v_tal > 0 or v_ent > 0 then return 'tiene_registros'; end if;

  insert into public."GV_Tanda_Anulada" (tanda, fase, legajo, motivo, ts_evento)
  values (v_tanda, 'armado', v_leg, nullif(btrim(coalesce(p_motivo,'')),''), v_ts);

  -- Lo único que SÍ sale durante el armado son las etiquetas de lío, que se encolan al cerrar
  -- cada lío. Las que todavía no se imprimieron se cancelan: si no, la impresora escupe papel
  -- de un armado que se deshizo. Las ya impresas quedan (el papel ya salió) con su estado.
  update public."Etiquetas_Lio" set estado = 'anulada'
   where upper(btrim(coalesce(tanda,''))) = v_tanda
     and coalesce(estado,'') = 'pendiente' and creado_en >= v_ts;
  get diagnostics v_etl = row_count;

  delete from public."Registros_Produccion_Virgilio" where id = v_id;

  begin perform public.tanda_liberar(v_tanda, 'armado', v_leg); exception when others then null; end;
  return 'ok';
end $function$;

comment on function public.anular_armado_virgilio(text,text,text) is
 'v18.50 - suelta un armado empezado por error: borra el AP, libera el lock y deja el registro en GV_Tanda_Anulada. La tanda vuelve a quedar PENDIENTE DE ARMAR. Espejo de anular_picking_virgilio. No toca el picking. Devuelve ok | sin_ap | ya_cerrado | tiene_registros | faltan_datos. NO anula si el asistente Completar ya grabo (TAL o Entregas): eso mueve stock y lo resuelve sistemas.';

-- Chequeo de lo soltado:
--   select * from public."GV_Tanda_Anulada" order by anulado_en desc;

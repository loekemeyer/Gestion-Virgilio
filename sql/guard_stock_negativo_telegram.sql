-- =====================================================================
--  guard_stock_negativo_telegram.sql — Alerta Telegram "en el momento"
--  cuando un movimiento deja un depósito de stock en NEGATIVO. (v7.00)
--
--  Pedido del usuario: "nunca algo puede quedar en negativo, mandá una alerta
--  en ese momento por Telegram". DEPLOYADO en Supabase (proyecto Virgilio).
--
--  Complementa a la alerta SSG (picking→góndola, que se emite desde el cliente
--  con el evento opcion='SSG' y la relaya notificar_picking_sin_stock_telegram).
--  Esta cubre TODO lo demás, server-side, robusto. Ambas comparten el MISMO
--  switch: Stock_Config.alerta_sin_stock_gondola ('1' on / '0' off) — el toggle
--  admin "📦 Aviso Telegram 'stock en negativo'".
--
--  Excluye a propósito:
--   • tipo 'inicial'      → reset/conteo controlado (el reset baja a 0 a propósito).
--   • picking→'terminado' → ya lo avisa SSG (evita duplicar).
--  v7.01: 'insumos' YA NO se excluye (pedido del usuario "que mande"). La dedup
--  (cod+depósito+día) limita a 1 aviso por código de insumo por día.
--  NO bloquea el insert (un fallo de aviso jamás rompe el pipeline de stock).
--  Dedup: 1 aviso por (cod_art, depósito, día) vía tg_enqueue.
-- =====================================================================
create or replace function public.notificar_stock_negativo_telegram()
returns trigger language plpgsql security definer
set search_path to 'public','pg_temp' as $fn$
declare
  cutoff timestamptz;
  saldo  numeric;
  dep_nom text;
  msg text;
begin
  if new.delta is null or new.delta >= 0 then return new; end if;        -- sólo decrementos
  if new.tipo = 'inicial' then return new; end if;                        -- reset/conteo
  if new.tipo = 'picking' and new.deposito = 'terminado' then return new; end if;  -- lo cubre SSG
  if coalesce((select valor from public."Stock_Config" where clave='alerta_sin_stock_gondola' limit 1),'0') <> '1' then
    return new;                                                           -- switch apagado
  end if;
  select (valor)::timestamptz into cutoff from public."Stock_Config" where clave='cutoff_ts' limit 1;
  select coalesce(sum(m.delta),0) into saldo
    from public."Movimientos_Stock" m
   where m.cod_art = new.cod_art and m.deposito = new.deposito
     and (cutoff is null or m.tipo='inicial' or m.ts >= cutoff);
  if saldo >= 0 then return new; end if;                                  -- no quedó negativo
  dep_nom := case new.deposito when 'terminado' then 'góndola' else new.deposito end;
  msg := '⛔ STOCK EN NEGATIVO — ' || new.cod_art
      || coalesce(' (' || nullif(btrim(new.descripcion),'') || ')','')
      || E'\nDepósito ' || dep_nom || ' quedó en ' || saldo::text || '.'
      || E'\nMovimiento: ' || coalesce(new.tipo,'?') || ' ' || new.delta::text
      || ' (ref ' || coalesce(new.ref,'-') || ', legajo ' || coalesce(new.legajo,'?') || ').'
      || E'\nAlgo se descontó de más — revisá stock / recepción.';
  perform public.tg_enqueue(msg, 'neg_'||new.cod_art||'_'||new.deposito||'_'||to_char((now() at time zone 'America/Argentina/Buenos_Aires')::date,'YYYYMMDD'));
  perform public.tg_outbox_flush();
  return new;
exception when others then
  return new;   -- un fallo de aviso NUNCA debe romper el insert de stock
end $fn$;

drop trigger if exists trg_stock_negativo_telegram on public."Movimientos_Stock";
create trigger trg_stock_negativo_telegram
  after insert on public."Movimientos_Stock"
  for each row execute function public.notificar_stock_negativo_telegram();

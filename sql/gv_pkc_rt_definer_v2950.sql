-- v29.50 (Luis, 13/10/2026): prueba de punta a punta del módulo de operarios, como celular (rol anon).
-- El PKC de la tablet disparaba trg_pkc_reconciliar_rt, que era SECURITY INVOKER: con la clave
-- pública fallaba con «permission denied for table Movimientos_Stock», el error se tragaba y la
-- góndola recién se movía con el cron 68 (hasta 10 min). docs/SEGURIDAD-MATRIZ-FUNCIONES.md ya lo pedía.
-- Medido en vivo después del cambio: PKC 09:04:28 → movimiento de picking 09:04:28. ~290 ms por PKC.
alter function public.trg_pkc_reconciliar_rt() security definer set search_path = public;
-- ROLLBACK: alter function public.trg_pkc_reconciliar_rt() security invoker reset search_path;

-- v29.53 (Luis, 13/10): CORREGIR una línea ya pickeada (el celular hace upsert del PKC con el mismo client_id)
-- es un UPDATE, y el trigger de arriba es AFTER INSERT: la góndola esperaba al cron 68. Probado como anon.
-- No duplica: reconciliar_stock_articulo_rt hace upsert sobre mov_stock_pipeline_dedup (ref, cod, empresa,
-- depósito, tipo) y recalcula el total desde los PKC; el cron 68 corre la misma cuenta y deja el mismo número.
create or replace function public.trg_pkc_reconciliar_rt_upd()
 returns trigger language plpgsql security definer set search_path = public as $f$
-- v29.53 (Luis 13/10): corregir (upsert) o anular (PKC->PKCX) una linea de picking mueve la gondola EN EL MOMENTO.
declare v_t text; v_a text; v_t2 text; v_a2 text;
begin
  v_t := upper(trim(split_part(OLD.texto,'|',1))); v_a := trim(split_part(OLD.texto,'|',2));
  v_t2 := upper(trim(split_part(NEW.texto,'|',1))); v_a2 := trim(split_part(NEW.texto,'|',2));
  begin
    if coalesce(v_a,'') <> '' then perform reconciliar_stock_articulo_rt(v_t, v_a); end if;
    if coalesce(v_a2,'') <> '' and (v_t2, upper(v_a2)) is distinct from (v_t, upper(v_a)) then
      perform reconciliar_stock_articulo_rt(v_t2, v_a2); end if;
  exception when others then null;   -- nunca bloquear al operario: el cron 68 lo rehace
  end;
  return NEW;
end; $f$;
create or replace trigger trg_pkc_reconciliar_rt_upd after update of texto, opcion on public."Registros_Produccion_Virgilio"
  for each row when ((old.opcion = 'PKC' or new.opcion = 'PKC') and (old.texto is distinct from new.texto or old.opcion is distinct from new.opcion))
  execute function public.trg_pkc_reconciliar_rt_upd();
-- ROLLBACK: alter table public."Registros_Produccion_Virgilio" disable trigger trg_pkc_reconciliar_rt_upd;

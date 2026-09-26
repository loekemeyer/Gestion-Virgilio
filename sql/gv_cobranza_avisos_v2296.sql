-- v22.96 · Avisos de cobranza para Vivi (Thomas, 26/09: "cuando alguien paga mal… un módulo de cobranzas dentro del
-- Planify de Vivi para que sólo ahí le aparezca la alerta. Tanto si pagó bien como si pagó mal, separados").
--
-- GV_Cobranza_Aviso: una fila por pago (recibo o grupo de recibos que el agente imputó) con su veredicto:
--   'mal'     → se tomó más descuento del que le correspondía (a_reclamar > 0)
--   'tarde'   → sin descuento que reclamar pero pagó después del plazo de la condición
--   'bien'    → pagó en plazo y con el descuento correcto
--   'revisar' → el recibo no cierra con ninguna factura (pago a cuenta, parcial, de otra cosa)
-- Se llena al final de cada gv_cobranza_imputacion_refrescar (cron min 49): sólo pagos NUEVOS (desde 01/09/2026) y
-- sin pisar lo que Vivi ya marcó como visto. Planify lo lee con planify.planify_cobranza_avisos (ver repo Planify).
-- Rollback: drop table "GV_Cobranza_Aviso" cascade; volver gv_cobranza_imputacion_refrescar sin el bloque de avisos.
create table if not exists public."GV_Cobranza_Aviso" (
  id bigserial primary key, empresa text not null, cod_cliente text not null, cliente text, recibo text not null,
  fecha_pago date, pagado numeric, facturas text, facturado numeric, dias int, estado text not null,
  a_reclamar numeric, explicacion text, creado_en timestamptz not null default now(),
  visto_en timestamptz, visto_por text, nota text,
  unique (empresa, cod_cliente, recibo));
alter table public."GV_Cobranza_Aviso" enable row level security;
drop policy if exists sup_lee on public."GV_Cobranza_Aviso";
create policy sup_lee on public."GV_Cobranza_Aviso" for select to authenticated using (public.es_supervisor_virgilio());
revoke all on public."GV_Cobranza_Aviso" from anon;
revoke insert, update, delete, truncate on public."GV_Cobranza_Aviso" from authenticated;
grant select on public."GV_Cobranza_Aviso" to authenticated;

create or replace function public.gv_cobranza_avisos_generar(p_desde date default date '2026-09-01')
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into "GV_Cobranza_Aviso" (empresa, cod_cliente, cliente, recibo, fecha_pago, pagado, facturas, facturado, dias, estado, a_reclamar, explicacion)
  select g.empresa, g.cod_cliente, g.nombre, g.recibo, g.fecha_pago, g.pagado, g.facturas, g.facturado, g.dias,
         g.estado, g.a_reclamar,
         case g.estado
           when 'revisar' then 'Recibo ' || g.recibo || ' por ' || gv_cob_pesos(g.pagado) || ': no cierra con ninguna factura (pago a cuenta, parcial o de otra cosa).'
           else 'Recibo ' || g.recibo || ' del ' || to_char(g.fecha_pago, 'DD/MM') || ': ' || gv_cob_pesos(g.pagado)
                || ' por ' || g.facturas || ' (lista ' || gv_cob_pesos(g.facturado) || ')'
                || case when g.dto > 0 then ', se descontó ' || round(g.dto * 100) || ' %' else '' end
                || case when g.ret > 0.005 then ' y ' || replace(to_char(g.ret * 100, 'FM90.0'), '.', ',') || ' % de retención' else '' end
                || '. Pagó a los ' || g.dias || ' días'
                || case g.estado when 'mal' then ': le correspondía ' || round(g.ganado * 100) || ' % → reclamar ' || gv_cob_pesos(g.a_reclamar) || '.'
                                 when 'tarde' then ', ' || g.atraso || ' días después del plazo.'
                                 else ' ✔ en plazo.' end
         end
    from (select i.empresa, i.cod_cliente, max(i.nombre) nombre, i.recibo, max(i.fecha_pago) fecha_pago, max(i.pagado) pagado,
                 string_agg(i.facturas, ' + ' order by i.pedido) facturas, sum(i.lista) facturado, max(i.dias) dias,
                 max(i.dto_tomado) dto, min(i.dto_ganado) ganado, max(i.retencion) ret, max(i.atraso) atraso,
                 sum(i.a_reclamar) a_reclamar,
                 case when bool_and(i.grupo is null) then 'revisar'
                      when sum(i.a_reclamar) > 0 then 'mal'
                      when max(i.atraso) > 0 then 'tarde' else 'bien' end estado
            from "GV_Cobranza_Imputacion" i
           where i.recibo is not null and i.fecha_pago >= p_desde and i.fecha_pago <= current_date
           group by i.empresa, i.cod_cliente, i.recibo) g
  on conflict (empresa, cod_cliente, recibo) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.gv_cobranza_avisos_generar(date) from public, anon, authenticated;

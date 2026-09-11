-- v15.51 (2026-09-11) — REGLA DEL DUEÑO: "nunca si hay +1 pedido de un cliente puede ir separado
-- en la PPP" ... "salvo los super". Mismo cliente = mismo día. Es un candado, no una alerta.
--
-- Dónde se rompía: al MOVER una NP a mano (caso Orfali: el 10/09 12:10 LK 0002 pasó al 16/09 y
-- dejó a LK 0053 sola en el 15/09 — un camión a GBA Norte por una caja). El armado automático
-- ya junta por cliente (bloques a1/a2 de gv_ppp_web_armar_pendientes); el trigger cubre el
-- movimiento manual, que era el agujero.
--
-- PPP_Web_Programacion es tabla NUESTRA (PPP_Web_*), no compartida con Producción: el trigger
-- está permitido. Sólo dispara en UPDATE de fecha_entrega (no en INSERT: los inserts del armado
-- en cascada pelearían con él; lo que se escape lo muestra gv_ppp_cliente_dos_dias).

-- ¿la tanda ya la tocó un operario? (mismo criterio que gv_ppp_web_tanda_abierta_cliente)
create or replace function public.gv_ppp_tanda_tocada(p_tanda text)
returns boolean language sql stable set search_path to 'public' as $function$
  select exists (
    select 1 from public."Registros_Produccion_Virgilio" r
     where r.opcion in ('EP','TP','AP','TAP')
       and (   upper(btrim(split_part(r.texto, '|', 1))) = upper(btrim(coalesce(p_tanda,'')))
            or upper(btrim(split_part(r.texto, '|', 2))) = upper(btrim(coalesce(p_tanda,'')))
            or upper(btrim(split_part(r.texto, '|', 3))) = upper(btrim(coalesce(p_tanda,''))))
       and coalesce(nullif(btrim(p_tanda),''),'') <> ''
  );
$function$;

create or replace function public.gv_web_cliente_un_solo_dia()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare
  r        record;
  v_tanda  text;
  v_movidas int := 0;
begin
  if pg_trigger_depth() > 1 then return null; end if;                       -- una sola vuelta
  if NEW.fecha_entrega is null or coalesce(nullif(btrim(NEW.tanda),''),'') = '' then return null; end if;
  if NEW.fecha_entrega < current_date then return null; end if;
  -- "salvo los super": por zona, o por estar en el padrón de cadenas (el mismo que usa Cuarentena)
  if coalesce(NEW.zona,'') ~* 'super|retira|expo' then return null; end if;
  if exists (select 1 from public.cobranzas_cliente_cadena cc
              where btrim(cc.cod_cliente) = btrim(coalesce(NEW.cod_cliente,''))
                and lower(cc.empresa) in (lower(NEW.empresa),
                      case lower(NEW.empresa) when 'chef' then 'ch' when 'ch' then 'chef' else lower(NEW.empresa) end))
  then return null; end if;

  for r in
    select w.order_id, w.np_idx, w.np, w.tanda, w.fecha_entrega
      from public."PPP_Web_Programacion" w
     where w.empresa = NEW.empresa
       and btrim(coalesce(w.cod_cliente,'')) = btrim(coalesce(NEW.cod_cliente,''))
       and (w.order_id, w.np_idx) is distinct from (NEW.order_id, NEW.np_idx)
       and coalesce(nullif(btrim(w.tanda),''),'') <> ''
       and w.fecha_entrega is not null
       and w.fecha_entrega >= current_date
       and w.fecha_entrega <> NEW.fecha_entrega
       and coalesce(w.zona,'') !~* 'super|retira|expo'
  loop
    -- la otra ya se pickeó: moverla rompe el picking → no se separa NI se mueve, se avisa cuál
    if public.gv_ppp_tanda_tocada(r.tanda) then
      raise exception 'No se puede: % ya tiene otro pedido en la tanda % del % y esa tanda ya se empezo a trabajar. Los pedidos de un cliente no pueden salir en dias distintos.',
        coalesce(NEW.razon_social, NEW.cod_cliente), r.tanda, to_char(r.fecha_entrega, 'DD/MM')
        using errcode = 'raise_exception';
    end if;
    -- al mismo día, y a la tanda web abierta del cliente ese día (si no hay, a la de la NP movida)
    v_tanda := coalesce(
      public.gv_ppp_web_tanda_abierta_cliente(NEW.empresa, NEW.cod_cliente, NEW.fecha_entrega),
      NEW.tanda);
    update public."PPP_Web_Programacion"
       set fecha_entrega = NEW.fecha_entrega, tanda = v_tanda, actualizado_at = now()
     where empresa = NEW.empresa and order_id = r.order_id and np_idx = r.np_idx;
    v_movidas := v_movidas + 1;
  end loop;

  if v_movidas > 0 then
    raise notice 'gv_web_cliente_un_solo_dia: % NP de % se movieron al % para no separarlas',
      v_movidas, coalesce(NEW.razon_social, NEW.cod_cliente), NEW.fecha_entrega;
  end if;
  return null;
end;
$function$;

drop trigger if exists gv_web_cliente_un_solo_dia on public."PPP_Web_Programacion";
create trigger gv_web_cliente_un_solo_dia
after update of fecha_entrega, tanda on public."PPP_Web_Programacion"
for each row
when (old.fecha_entrega is distinct from new.fecha_entrega)
execute function public.gv_web_cliente_un_solo_dia();

-- PRUEBAS (2026-09-11, todas con rollback, sobre Orfali 4188 = LK 0002 + LK 0053 en D69D/16-09):
--   1. mover LK 0002 al 17/09 (tanda ZZT1)      → LK 0053 la siguió: las dos 17/09 ZZT1
--   2. con un evento TP simulado sobre D69D,
--      mover LK 0053 al 17/09                    → cortó "No se puede: …", nada se movió
--   3. las dos con zona 'Super', mover LK 0002   → se movió sola, LK 0053 se quedó
--
-- ROLLBACK:
--   drop trigger gv_web_cliente_un_solo_dia on public."PPP_Web_Programacion";
--   drop function public.gv_web_cliente_un_solo_dia();
--   drop function public.gv_ppp_tanda_tocada(text);

-- v29.49 (Luis, 13/10/2026): auditoría del módulo de operarios.
-- PROBLEMA: en el armado, «⚠ Hay un artículo diferente a la mesa» → «de menos / no hay en
-- góndola» (_compDifResolve, index.html) descuenta `qty = pedido − real` de separar_pedidos.
-- Pero si el PICKING ya registró ese faltante (PKC esperadas > reales), esas cajas nunca
-- entraron a separar_pedidos: se descuentan DOS veces. Caso F58A/102E: PKC 19|7 (faltan 12),
-- NPD de menos 12 → pila 7 − 12 = −5, y el separado de ese código no se pudo hacer.
-- Medido 60 días: E09A 198E (70), E41A 865ED (15), F13F 396 (3), F56C 102E (30), F58A 102E (12).
-- ARREGLO (backend, vale para cualquier celular): trigger BEFORE INSERT que topa el descuento
-- de un NPD (client_id 'npd_…_<qty>') con el faltante que el picking ya registró para esa
-- tanda y código y que los NPD anteriores todavía no usaron. No toca góndola.
-- ROLLBACK: drop trigger aa_gv_npd_tope_picking on public."Movimientos_Stock";

create or replace function public.gv_npd_tope_faltante_picking()
 returns trigger language plpgsql
 set search_path to 'public'
as $f$
-- v29.49-npd-tope
declare v_artn text; v_q numeric; v_cred numeric := 0; v_usado numeric := 0; v_resto numeric;
begin
  if new.client_id is null or new.client_id not like 'npd\_%' or new.tipo <> 'ajuste'
     or new.deposito <> 'separar_pedidos' or coalesce(new.delta,0) >= 0 then
    return new;
  end if;
  v_artn := upper(regexp_replace(regexp_replace(regexp_replace(btrim(new.cod_art),'([0-9E])L$','\1'),' +(LK|CH)$',''),'^0+(?=.)',''));
  v_q := -new.delta;
  -- faltante ya registrado por el picking: último PKC por (tanda, código) → esperadas − reales
  select coalesce(sum(greatest(0, z.esp - z.re)),0) into v_cred
    from (select distinct on (split_part(r.texto,'|',2))
                 nullif(split_part(r.texto,'|',3),'')::numeric esp, nullif(split_part(r.texto,'|',4),'')::numeric re
            from "Registros_Produccion_Virgilio" r
           where r.opcion = 'PKC'
             and upper(btrim(split_part(r.texto,'|',1))) = upper(btrim(new.ref))
             and upper(regexp_replace(regexp_replace(btrim(split_part(r.texto,'|',2)),' +(LK|CH)$',''),'^0+(?=.)','')) = v_artn
             and split_part(r.texto,'|',3) ~ '^\d+(\.\d+)?$' and split_part(r.texto,'|',4) ~ '^\d+(\.\d+)?$'
           order by split_part(r.texto,'|',2), r.ts_cliente desc) z;
  if v_cred <= 0 then return new; end if;
  -- lo que los NPD anteriores de esa tanda y código ya usaron del crédito (qty pedido − descontado)
  select coalesce(sum(greatest(0, nullif(regexp_replace(m.client_id,'^.*_',''),'')::numeric + m.delta)),0) into v_usado
    from "Movimientos_Stock" m
   where m.client_id like 'npd\_%' and m.tipo = 'ajuste' and m.deposito = 'separar_pedidos'
     and upper(btrim(m.ref)) = upper(btrim(new.ref))
     and m.client_id is distinct from new.client_id
     and regexp_replace(m.client_id,'^.*_','') ~ '^\d+(\.\d+)?$'
     and upper(regexp_replace(regexp_replace(regexp_replace(btrim(m.cod_art),'([0-9E])L$','\1'),' +(LK|CH)$',''),'^0+(?=.)','')) = v_artn;
  v_resto := greatest(0, v_cred - v_usado);
  if v_resto > 0 then
    new.delta := -greatest(0, v_q - v_resto);
    new.descripcion := left(coalesce(nullif(new.descripcion,''),'Picking difiere de mesa')
      || ' · el picking ya registró ' || least(v_q, v_resto) || ' de faltante (no se descuenta dos veces)', 300);
  end if;
  return new;
end;
$f$;

create or replace trigger aa_gv_npd_tope_picking
  before insert on public."Movimientos_Stock"
  for each row execute function public.gv_npd_tope_faltante_picking();

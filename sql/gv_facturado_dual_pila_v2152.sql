-- v21.52 (Luis, 23/09): al facturar un código DUAL, la caja se descuenta de la pila de la
-- EMPRESA DONDE ESTÁ, no de la que dice el pedido.
--
-- Caso: 438E de Chef con «a facturar» en -1. Tanda D47B, pedido CH 0030 (cliente Chef 2600,
-- artículos de Loeke con L). El armado (TAL del 27/08) anotó "438E" SIN la L; al facturar el
-- 21/09, stockSalidaFacturadoNP no vio la L y le puso la empresa de la NP (CH). La caja estaba
-- en la pila LK de la tanda (PKC "438E LK"), así que Chef quedó en -1 y LK con +1 de más.
-- El guard zzz_facturado_no_negativo no lo frenó porque mide la pila SIN empresa (a propósito,
-- v19.49) y LK tenía saldo. Es el único caso en toda la historia (medido 23/09).
--
-- Arreglo en el backend, dentro del mismo guard (corre ÚLTIMO, después de zz_normalizar_empresa):
-- en un dual, si la empresa que viene no tiene saldo en esa tanda y la otra sí, se descuenta de
-- la otra. No se toca trg_normalizar_empresa_stock (la tocan varias sesiones).
-- Aplicado sobre pg_get_functiondef del 23/09. Probado en transacción abortada:
-- dual 438E facturado CH contra pila LK -> queda LK · no dual 501 -> sin cambios.

CREATE OR REPLACE FUNCTION public.trg_facturado_no_negativo()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_tanda text; v_base text; v_saldo numeric; v_propia numeric; v_otra text;
begin
  -- Solo el drenaje de a_facturar. Todo lo demas pasa derecho.
  if NEW.tipo <> 'facturado' or NEW.deposito <> 'a_facturar' or coalesce(NEW.delta,0) >= 0 then
    return NEW;
  end if;

  v_tanda := upper(btrim(split_part(btrim(coalesce(NEW.ref,'')),'|',1)));

  -- SOLO cuando el ref empieza con un CODIGO DE TANDA (E12C, D66D). Ahi la pila esta
  -- garantizado bajo el mismo prefijo: el 'separado' entra con ref = tanda y los
  -- drenajes salen con ref = tanda o tanda|NP.
  -- NO se mide cuando el prefijo es una NP ('98507', 'LK 0034'): el drenaje de CP
  -- sale con ref = NP|CP contra una pila que se lleva por tanda, asi que medirla por
  -- prefijo daria un bloqueo falso. Tampoco los refs de texto libre de las
  -- correcciones a mano, que netean contra OTRO ref.
  if v_tanda !~ '^[A-Z][0-9]{2}[A-Z]$' then
    return NEW;
  end if;

  v_base := regexp_replace(upper(btrim(NEW.cod_art)), '^0+(?=.)', '');

  -- La pila de la tanda, SIN mirar empresa: el doble drenaje de D66D (17/09) y el
  -- picking duplicado de D72A (problema 390) pasaron justamente porque una etiqueta
  -- de empresa distinta hacia que el mismo movimiento pareciera otro.
  select coalesce(sum(m.delta),0) into v_saldo
    from public."Movimientos_Stock" m
   where m.deposito = 'a_facturar'
     and regexp_replace(upper(btrim(m.cod_art)), '^0+(?=.)', '') = v_base
     and upper(btrim(split_part(btrim(coalesce(m.ref,'')),'|',1))) = v_tanda;

  if v_saldo <= 0 then
    insert into public."GV_Stock_Drenaje_Bloqueado"
      (cod_art, ref, tanda, deposito, tipo, delta, empresa, saldo_tanda, motivo)
    values (NEW.cod_art, NEW.ref, v_tanda, NEW.deposito, NEW.tipo, NEW.delta, NEW.empresa, v_saldo,
            'la pila de esa tanda ya estaba en '||v_saldo::text||': drenar de nuevo dejaba a_facturar en negativo');
    return null;   -- fila descartada, sin error: el operario no tiene nada que hacer con esto
  end if;

  -- v21.52 (Luis, 23/09): en un codigo DUAL la caja se descuenta de la pila de la EMPRESA
  -- DONDE ESTA. Caso 438E / D47B / CH 0030: el armado anoto 438E sin la L, la facturacion
  -- tomo la empresa del pedido (CH) y la pila de Chef quedo en -1 con la caja en la de LK.
  -- Si la empresa que viene no tiene saldo en esa tanda y la OTRA si, se descuenta de la otra.
  if NEW.empresa in ('LK','CH')
     and exists (select 1 from public.codigos_duales d
                  where regexp_replace(upper(btrim(d.cod)),'^0+(?=.)','') = v_base) then
    select coalesce(sum(m.delta),0) into v_propia
      from public."Movimientos_Stock" m
     where m.deposito = 'a_facturar' and m.empresa = NEW.empresa
       and regexp_replace(upper(btrim(m.cod_art)), '^0+(?=.)', '') = v_base
       and upper(btrim(split_part(btrim(coalesce(m.ref,'')),'|',1))) = v_tanda;
    if v_propia <= 0 then
      v_otra := case NEW.empresa when 'LK' then 'CH' else 'LK' end;
      if (select coalesce(sum(m.delta),0) from public."Movimientos_Stock" m
           where m.deposito = 'a_facturar' and m.empresa = v_otra
             and regexp_replace(upper(btrim(m.cod_art)), '^0+(?=.)', '') = v_base
             and upper(btrim(split_part(btrim(coalesce(m.ref,'')),'|',1))) = v_tanda) > 0 then
        NEW.empresa := v_otra;
      end if;
    end if;
  end if;

  return NEW;
end;
$function$;

-- centinela: que la regla no se pierda en un CREATE OR REPLACE desde una copia vieja
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('trg_facturado_no_negativo','funcion','v_otra',
        'al facturar un codigo dual, la caja se descuenta de la pila de la empresa donde esta en esa tanda',
        'Luis','v21.52');

-- corrección del caso (autorizada por Luis, 23/09: "corregí el stock").
-- backup: zz_backups."GV_Backup_MovStock_438E_D47B_20260923" (1 fila, id 80082812)
update public."Movimientos_Stock" set empresa = 'LK' where id = 80082812 and empresa = 'CH';
-- rollback: update public."Movimientos_Stock" set empresa = 'CH' where id = 80082812;
-- el caché de la pantalla (stocks_carga_rapida) se recalcula por el trigger sólo para la empresa
-- NUEVA de la fila (LK); la fila "438E CH" se refrescó con un update sin cambios sobre un
-- movimiento 438E CH. Verificado: 438E CH a_facturar 0 · 438E LK 7.

-- =====================================================================
--  v19.42 (2026-09-17) — el NPD "de menos / no hay en góndola" sobre una
--  tanda donde el código NUNCA se pickeó dejaba Pickeados en negativo
--  (problema 378)
--
--  ── EL SÍNTOMA (lo vio un supervisor en el picking) ─────────────────
--  Artículo 323E, tanda E03C:
--
--    16/09 (picking)  Jhonny Cartaya (277)  pickeó E03C (33 códigos)  323E NO está
--    16/09 11:38      Franco Ortiz (237)    ajuste "de menos"         separar_pedidos −1  LK
--
--  Saldo: separar_pedidos (Pickeados) de 323E = **−1** en LK. Era el único
--  negativo de toda la base (barrido del 17/09).
--
--  ── LA CAUSA ────────────────────────────────────────────────────────
--  El −1 lo emite el wizard de armado cuando el armador marca "de menos / no hay
--  en góndola" (evento NPD, `_compDifResolve` en index.html). Ese −qty sobre
--  separar_pedidos existe para DESCONTAR las cajas fantasma que el picking habría
--  registrado ahí (ver v12.12). Pero si el código NUNCA se pickeó en esa tanda
--  (0 picking de 323E en E03C), no hay ninguna caja fantasma que descontar: el
--  −qty queda solo y deja Pickeados negativo.
--
--  Es el caso que la v18.30 NO cubría: su neteo (etapa 2) sólo actúa cuando el
--  net es > 0 (emite el `separado`); un ajuste negativo aislado, sin picking
--  contra qué netear, nunca se limpia.
--
--  ── EL FIX (backend, fuente de verdad) ──────────────────────────────
--  `trg_normalizar_empresa_stock` (BEFORE INSERT en Movimientos_Stock): una fila
--  `ajuste` sobre `separar_pedidos`, con delta < 0 y client_id de NPD ('npd_…'),
--  cuyo `ref` es una tanda SIN picking del código en separar_pedidos, se DESCARTA
--  (RETURN NULL). No cumple ninguna función y sólo crea un negativo fantasma.
--
--  Conservador: si HAY picking de esa (tanda, código) la fila pasa igual que hoy
--  (hay caja fantasma real que descontar). Sólo dispara con el client_id 'npd_…'
--  determinístico del wizard, así que no toca ajustes manuales ni otras fuentes.
--
--  Probado en transacción abortada: ZZPHANTOM sin picking en E03C → descartada
--  (0 filas); 315 con picking en E03C → insertada (1 fila).
--
--  ── EL DATO YA ESCRITO ──────────────────────────────────────────────
--  El −1 de 323E/E03C se neutralizó (protocolo = AGREGAR, no borrar) con un
--  ajuste +1 (separar_pedidos, LK, ref E03C, client_id 'fix378_323E_E03C_neutraliza_npd').
--  El registro NPD de Franco NO se tocó. Saldo verificado: 0.
--  Backup: zz_backups."GV_Backup_323E_sepped_20260917".
--
--  Rollback del trigger: reaplicar sql/gv_ajuste_hereda_empresa_v1830.sql
--  (esa es la versión inmediatamente anterior de la función).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.trg_normalizar_empresa_stock()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_base text; v_dual boolean; v_np text; v_emp2 text; v_explicita boolean; v_tanda text;
BEGIN
  IF NEW.deposito = 'insumos' THEN
    NEW.cod_art := regexp_replace(NEW.cod_art,'\s+(LK|CH|LOKE)$','');
    RETURN NEW;
  END IF;

  v_explicita := NEW.empresa IS NOT NULL AND NEW.empresa IN ('LK','CH');

  IF NEW.cod_art ~ '\s+(LK|LOKE)$' THEN NEW.empresa:='LK'; NEW.cod_art:=regexp_replace(NEW.cod_art,'\s+(LK|LOKE)$','');
  ELSIF NEW.cod_art ~ '\s+CH$' THEN NEW.empresa:='CH'; NEW.cod_art:=regexp_replace(NEW.cod_art,'\s+CH$',''); END IF;
  IF NEW.cod_art ~ '[0-9E]L$' THEN
    NEW.empresa := 'LK';
    NEW.cod_art := regexp_replace(NEW.cod_art,'([0-9E])L$','\1');
    v_explicita := true;
  END IF;

  v_base := regexp_replace(upper(btrim(NEW.cod_art)),'^0+(?=.)','');
  SELECT true INTO v_dual FROM public.codigos_duales WHERE regexp_replace(upper(btrim(cod)),'^0+(?=.)','')=v_base LIMIT 1;

  v_tanda := upper(btrim(split_part(coalesce(NEW.ref,''),'|',1)));

  -- v19.42 (problema 378): un NPD "de menos / no hay en gondola" sobre una tanda donde el codigo
  -- NUNCA se pickeo no tiene caja fantasma que descontar. Su -qty sobre separar_pedidos queda
  -- solo y deja Pickeados en negativo (caso 323E/E03C: ajuste -1 sin picking -> saldo -1). Si no
  -- hay picking de (tanda, codigo) en separar_pedidos, se descarta la fila (no cumple funcion).
  IF NEW.tipo = 'ajuste'
     AND NEW.deposito = 'separar_pedidos'
     AND coalesce(NEW.delta,0) < 0
     AND left(coalesce(NEW.client_id,''),4) = 'npd_'
     AND v_tanda ~ '^[A-Z][0-9]{2}[A-Z]$' THEN
    IF coalesce((
         SELECT sum(m.delta) FROM public."Movimientos_Stock" m
          WHERE m.tipo='picking' AND m.deposito='separar_pedidos'
            AND regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') = v_base
            AND upper(btrim(split_part(m.ref,'|',1))) = v_tanda
       ),0) <= 0 THEN
      RETURN NULL;
    END IF;
  END IF;

  -- v18.30: una fila SIN empresa cuyo `ref` es una tanda ya pickeada hereda la empresa de ESE
  -- picking. Si no, cae en `Mixto` y no se netea contra el picking (que desde el 11/09 sale LK/CH).
  IF NOT v_explicita
     AND NEW.deposito IN ('separar_pedidos','a_facturar','terminado')
     AND v_tanda ~ '^[A-Z][0-9]{2}[A-Z]$' THEN
    SELECT CASE WHEN count(DISTINCT m.empresa)=1 THEN max(m.empresa) END
      INTO v_emp2
      FROM public."Movimientos_Stock" m
     WHERE m.tipo='picking' AND m.deposito='separar_pedidos'
       AND m.empresa IN ('LK','CH')
       AND regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') = v_base
       AND upper(btrim(split_part(m.ref,'|',1))) = v_tanda;
    IF v_emp2 IS NOT NULL THEN
      NEW.empresa := v_emp2;
      RETURN NEW;
    END IF;
  END IF;

  IF NOT COALESCE(v_dual,false) THEN
    IF NOT v_explicita THEN NEW.empresa := 'Mixto'; END IF;
  ELSE
    IF NEW.empresa IS NULL OR NEW.empresa = 'Mixto' THEN
      v_np := nullif(regexp_replace(split_part(coalesce(NEW.ref,''),'|',2),'\D','','g'),'');
      IF v_np IS NOT NULL THEN NEW.empresa := public.empresa_de_np(v_np); END IF;
      IF (NEW.empresa IS NULL OR NEW.empresa = '' OR NEW.empresa = 'Mixto')
         AND NEW.deposito = 'a_facturar' AND NEW.tipo = 'facturado' THEN
        SELECT CASE WHEN count(DISTINCT m.empresa)=1 THEN max(m.empresa) END
          INTO v_emp2
          FROM public."Movimientos_Stock" m
         WHERE m.deposito='a_facturar' AND m.tipo='separado'
           AND regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') = v_base
           AND upper(btrim(split_part(m.ref,'|',1))) = upper(btrim(split_part(coalesce(NEW.ref,''),'|',1)))
           AND m.empresa IN ('LK','CH');
        IF v_emp2 IS NOT NULL THEN NEW.empresa := v_emp2; END IF;
      END IF;
      IF NEW.empresa IS NULL OR NEW.empresa = '' THEN NEW.empresa := 'Mixto'; END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

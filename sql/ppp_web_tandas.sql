-- ══════════════════════════════════════════════════════════════════════════
-- Armado AUTOMÁTICO de tandas de la PPP Web · 2026-09-04
-- Corre en VIRGILIO (hrxfctzncixxqmpfhskv)
-- ══════════════════════════════════════════════════════════════════════════
-- ⚠⚠ NO TOCA PRODUCCIÓN VIRGILIO. Todo se escribe en `PPP_Web_Programacion`.
--   `PPP_Programacion_Diaria` —la que usan hoy los operarios— se LEE en un solo
--   lugar (`ppp_web_proxima_letra`, para no repetir un código de tanda) y no hay
--   un solo INSERT ni UPDATE contra ella en todo este archivo. Esta es la
--   estructura de reemplazo, montada aparte, para el día que se haga el cambio.
--
-- ══════════════════════════════════════════════════════════════════════════
-- ⚠⚠⚠  CUANDO GESTIÓN TOMA CONTROL Y SE VUELVE LA VERSIÓN QUE USAMOS,
--       SEGUIR CON LA NUMERACIÓN QUE DEJÓ VIRGILIO
-- ══════════════════════════════════════════════════════════════════════════
-- Se hace con UNA línea, vaciando el parámetro:
--
--   update public."PPP_Web_Config" set valor_texto = '' where clave = 'tanda_prefijo';
--
-- Con el prefijo vacío la función vuelve sola a la codificación histórica
-- LETRA+NN+LETRA (D19J) y `ppp_web_proxima_letra()` retoma desde la última letra
-- que dejó Producción, mirando LAS DOS tablas. No hay nada más que tocar.
--
-- MIENTRAS TANTO (hoy, mientras conviven las dos apps): las tandas que arma
-- Gestión son DE PRUEBA y llevan prefijo propio **`GV-`** → `GV-01A`, `GV-02B`.
-- No se pueden confundir con las de Producción (D19J y compañía) ni colisionar
-- con ellas: el prefijo rompe el patrón `^[A-Z]+[0-9]+[A-Z]+$`, así que además
-- no ensucian el contador de letras de `ppp_web_proxima_letra()`.
--
-- Probado el 2026-09-04 en transacción revertida, los dos modos:
--   con prefijo  → GV-01A · GV-02A · GV-03A   (0 matchean el patrón de ISIS)
--   sin prefijo  → E01A · E02A · E03A         (sigue después de la D de Virgilio)
-- ══════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════
-- LA REGLA SALIÓ DE LAS TANDAS REALES, NO DE UNA SUPOSICIÓN
-- ══════════════════════════════════════════════════════════════════════════
-- Ingeniería inversa sobre `PPP_Programacion_Diaria`, 120 días, 61 tandas:
--
--   · **Una tanda = UNA fecha de entrega.** 0 de 61 tandas tienen más de una.
--   · **No se mezclan zonas.** Sólo 3 de 56 lo hacen (5%): es la excepción.
--   · **Súper: una tanda por cliente.** Las 3 tandas de súper tienen exactamente
--     1 cliente y 1 NP, con 3–4,5 m³.
--   · **El tope de m³ es para juntar clientes distintos, NO para partir a uno.**
--     Ésta es la que más importa y la que el sugeridor del front no respeta: las
--     **6 tandas de más de 2 m³ son TODAS de un solo cliente**, y el máximo real
--     es 9,25 m³ contra un T_MAX de 1,00 en el front. En el rango 0,60–1,00 hay
--     13 tandas con 4 NP promedio y sólo 4 de un cliente: ahí sí se junta gente.
--   · **El mínimo no retiene nada.** 33 de 56 tandas salieron bajo 0,60 m³.
--   · **Retira se junta como una zona más.** 2 tandas, 1,5 clientes cada una,
--     0,04–0,09 m³.
--   · **Expo: sin evidencia** (0 tandas en 120 días) → se trata como una zona
--     más, que es lo que pidió el dueño para lo que no esté definido.
--
-- ── LA FECHA: no hay regla histórica que copiar ────────────────────────────
-- Se buscó y no está. La `fecha_entrega` de la PPP de ISIS la carga una persona:
-- entre el último pedido de la tanda y su entrega hay una **mediana de 11 días,
-- mínimo 2 y máximo 96**, y 56 de 61 tandas pasan de una semana. Eso no es un
-- plazo, es una decisión. Tampoco hay calendario zona→día: la Zona 1 reparte
-- miércoles, jueves y viernes; la Zona 5 lunes, martes, jueves y viernes.
-- Lo único sólido: **nunca se entrega fin de semana** (0 casos en 120 días).
--
-- Así que se toma el criterio del dueño: *"las tandas se cierran al final del día
-- para arrancar el siguiente"* y *"a las 00:01 se arman las tandas para el día"*.
--   fecha_entrega = día en que se arma + `dias_hasta_entrega` (config, arranca en
--   0 = mismo día), corrido al lunes si cae sábado o domingo.
-- **Si el criterio real es otro, se mueve ese parámetro y listo.**
--
-- ── ABIERTA HASTA EL FINAL DEL DÍA ─────────────────────────────────────────
-- La función es IDEMPOTENTE y sólo toca lo que TODAVÍA NO tiene tanda. Por eso
-- se puede correr todas las veces que haga falta durante el día: la tanda de hoy
-- queda "abierta" y los pedidos que van entrando se le suman sin mover nada de
-- lo ya programado. Reacomodar lo que YA tiene tanda es tarea de
-- `ppp_web_resync` (ver sql/ppp_web_programacion.sql §3).
--
-- ══════════════════════════════════════════════════════════════════════════
-- v2/v3 · REGLAS QUE AGREGÓ EL DUEÑO EL 2026-09-04
-- ══════════════════════════════════════════════════════════════════════════
--   · **Tope 0,80 m³** (era 1,00). Sale de `PPP_Web_Config`, no está hardcodeado.
--   · **Zonas 2+3 pueden juntarse, y 6+7. Todas las demás por separado.**
--     Lo resuelve `gv_ppp_web_grupo_zona`, y el bucle recorre GRUPOS, no zonas.
--   · **Retira: se juntan, y es su propio grupo** (no se mezcla con reparto).
--     ⚠ Acá me equivoqué primero. Leí *"los retira separados, sólo se juntan si
--     retiran el mismo día"* como que hacía falta un dato de "día de retiro" que
--     no existe, y los separé a todos. El dueño lo aclaró: **la tanda es la que
--     DEFINE el día**. Juntar dos Retira en una tanda es exactamente lo que hace
--     que retiren el mismo día. No falta ningún dato: se juntan como cualquier
--     grupo, bajo el tope.
--   · **Cupo diario de 4 a 5 m³** (`m3_max_dia`, se tomó 5). El depósito no arma
--     todo lo pendiente: arma hasta ahí y el resto espera. **Esa cola es la
--     demora de 7 a 15 días** que hoy es la real — no hay que programarla aparte.
--   · **Orden de la cola:** primero los clientes `prioritario`, después por
--     ANTIGÜEDAD del pedido. Antes se tomaba por m³ descendente: empaquetaba
--     mejor pero dejaba a los pedidos chicos esperando para siempre.
--   · **Clientes que no pueden esperar:** `GV_Clientes_Reglas` con
--     `regla='prioritario'`. Hoy Osa (2533), Horcada (85) y Torres y Liva
--     (LK 288 / CH 271). Entran aunque el cupo esté lleno.
--   · **Misma razón social pidiendo LK y CH → el mismo día.** LK se arma primero
--     y los clientes que entraron se mapean a sus códigos de Chef por CUIT
--     (vista `gv_clientes_lk_ch` en LK, 357 pares); esos entran forzados en la
--     corrida de Chef. Por CUIT y no por nombre: los padrones escriben distinto
--     la misma razón social.
--   · **Súper: una tanda por cliente.** Sin cambio, ya era así.
--   · **Clientes que van solos siempre:** `GV_Clientes_Reglas` con `regla='solo'`.
--     Hoy Extralimp (4114) y Distribuidora GM (4080), códigos verificados contra
--     el padrón de LK. Es una tabla, se edita sin tocar código.
--   · **+0,80 m³ es su propia tanda.** Ya lo hacía; ahora con el tope nuevo.
--   · **LK y CH no se mezclan.** Sale gratis: la función se llama por empresa y
--     `ppp_web_proxima_letra` avanza entre llamadas, así que ni el código de
--     tanda se repite entre las dos.
--
-- ── PROBADO (transacciones revertidas, producción verificada intacta) ──────
--   cliente de 5 m³ en Zona 1        → tanda propia, no se parte          ✔
--   3 clientes de 0,30/0,25/0,30     → una sola tanda (0,85 < tope)       ✔
--   2 clientes de Súper              → una tanda cada uno                 ✔
--   Retira, 2 clientes, 3 NP         → una tanda, y las 2 NP del mismo
--                                      pedido viajan juntas               ✔
--   NP sin zona                      → NO se programa (falta el barrio)   ✔
--   misma entrada dos veces          → la segunda no toca nada            ✔
--   armado un domingo                → entrega corrida al lunes           ✔
--   códigos                          → arrancan en E (Producción va por D)✔
--
--   v2, 2026-09-04, 14 casos armados a propósito:
--   Súper Uno y Súper Dos            → una tanda cada uno                 ✔
--   Extralimp + otro de Zona 5       → tandas distintas, aunque sumaban
--                                      0,10 y entraban holgados           ✔
--   Distribuidora GM en Zonas 2+3    → tanda propia, con lugar al lado    ✔
--   Chico Z2 + Chico Z3              → JUNTOS (0,60 < 0,80)               ✔
--   Chico Z6 + Chico Z7              → JUNTOS                             ✔
--   Chico Z1 y Chico Z4              → separados, no se agrupan           ✔
--   Grande Z1 de 0,85                → tanda propia (pasa el tope)        ✔
--
--   v3, 2026-09-04, 14 NP reales de LK con fechas de recepción reales y el
--   cupo de 5 m³ puesto:
--   se armaron 4,628 m³ en 7 tandas    → NO se pasó del cupo               ✔
--   Coto (4,56) y Messina (1,21)       → quedaron EN COLA por ser los más
--                                        nuevos                            ✔
--   Osa y Torres y Liva                → entraron igual siendo los MÁS
--                                        nuevos, por prioritarios          ✔
--   Merajver + Garbarino (Retira)      → JUNTOS, o sea retiran el mismo día ✔
--   Dapelo (Z2) + Guini (Z3)           → JUNTOS                            ✔
--   Linea Ge 1,375 y Torres 0,985      → tanda propia cada uno             ✔
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public."PPP_Web_Config" (
  clave       text primary key,
  valor       numeric,
  descripcion text,
  actualizado timestamptz not null default now()
);

insert into public."PPP_Web_Config" (clave, valor, descripcion) values
  ('tanda_m3_max_mezcla', 0.80,
   'Tope de m³ para JUNTAR clientes distintos (dueño, 2026-09-04). No parte a un cliente: si uno solo pide más, se va solo con todo lo suyo.'),
  ('tanda_m3_min', 0.60,
   'm³ deseable mínimo. NO bloquea: 33 de 56 tandas históricas salieron por debajo.'),
  ('dias_hasta_entrega', 0,
   'Días desde que se arma la tanda hasta la entrega. 0 = mismo día. Sin evidencia histórica; es el parámetro a mover.'),
  ('saltar_fin_de_semana', 1,
   '1 = si cae sábado o domingo, corre al lunes. 0 entregas de fin de semana en 120 días.'),
  ('m3_max_dia', 5.00,
   'Cuántos m³ se arman por día en total (las dos empresas juntas). El dueño dijo 4 a 5; se tomó 5. Lo que no entra espera al día siguiente: esa cola es la demora.')
on conflict (clave) do nothing;

-- `valor` es numeric; el prefijo es texto. La tabla es NUESTRA, así que agregar
-- una columna está permitido: nullable y sin default que reescriba nada.
alter table public."PPP_Web_Config" add column if not exists valor_texto text;

insert into public."PPP_Web_Config" (clave, valor, valor_texto, descripcion) values
  ('tanda_prefijo', null, 'GV-',
   'Prefijo de los códigos de tanda de Gestión MIENTRAS CONVIVE con Producción: son tandas de prueba y no se pueden confundir con las de ISIS. ⚠ CUANDO GESTIÓN TOME CONTROL Y SEA LA VERSIÓN QUE USAMOS, VACIAR ESTE CAMPO ('''') PARA SEGUIR CON LA NUMERACIÓN QUE DEJÓ VIRGILIO (LETRA+NN+LETRA, D19J).')
on conflict (clave) do nothing;

alter table public."PPP_Web_Config" enable row level security;
drop policy if exists ppp_web_config_select on public."PPP_Web_Config";
create policy ppp_web_config_select on public."PPP_Web_Config"
  for select to anon, authenticated using (true);
drop policy if exists ppp_web_config_write_sup on public."PPP_Web_Config";
create policy ppp_web_config_write_sup on public."PPP_Web_Config"
  for all to authenticated
  using      ((auth.jwt() ->> 'email') = any (array['loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']))
  with check ((auth.jwt() ->> 'email') = any (array['loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']));
grant select on public."PPP_Web_Config" to anon, authenticated;
grant insert, update on public."PPP_Web_Config" to authenticated;

-- ── Código de tanda: LETRA + NN + LETRA (A02A, D19J), heredado de Producción.
-- `ppp_web_proxima_letra` mira LAS DOS tablas para no repetir un código que
-- Producción esté usando. Es el ÚNICO punto que lee `PPP_Programacion_Diaria`.
create or replace function public.ppp_web_letra(p_idx int)
returns text language sql immutable as $$
  select case when p_idx < 26 then chr(65 + p_idx)
              else chr(65 + (p_idx / 26) - 1) || chr(65 + (p_idx % 26)) end;
$$;

create or replace function public.ppp_web_letra_idx(p_letra text)
returns int language sql immutable as $$
  select case when length(coalesce(p_letra,'')) = 1 then ascii(upper(p_letra)) - 65
              when length(p_letra) = 2 then (ascii(upper(left(p_letra,1))) - 64) * 26
                                             + (ascii(upper(right(p_letra,1))) - 65)
              else -1 end;
$$;

create or replace function public.ppp_web_proxima_letra()
returns int language sql stable as $$
  select coalesce(max(idx), -1) + 1 from (
    select public.ppp_web_letra_idx((regexp_match(tanda, '^([A-Z]+)[0-9]+[A-Z]+$'))[1]) as idx
      from public."PPP_Programacion_Diaria" where tanda ~ '^[A-Z]+[0-9]+[A-Z]+$'
    union all
    select public.ppp_web_letra_idx((regexp_match(tanda, '^([A-Z]+)[0-9]+[A-Z]+$'))[1])
      from public."PPP_Web_Programacion"   where tanda ~ '^[A-Z]+[0-9]+[A-Z]+$'
  ) t;
$$;

-- ⚠ Este cuerpo se volcó del vivo el 2026-09-04: el archivo sólo decía "está
--   aplicado en la base", así que el repo no lo tenía y no había forma de
--   revisarlo sin abrir Supabase. Notas de implementación que importan al tocarlo:
--
--   · Los clientes se recorren de MAYOR a MENOR m³ (first-fit decreasing):
--     empaqueta mejor que tomarlos en el orden que vengan.
--   · Se agrupa por CLIENTE, no por pedido. Es más fuerte e incluye por
--     construcción la regla "todas las NP de un pedido en la misma tanda".
--   · ⚠ El `drop table if exists` de las temporales NO es paranoia: `on commit
--     drop` sólo limpia al cerrar la transacción, así que dos llamadas en la
--     MISMA transacción reventaban con "relation _sin_tanda already exists".
--   · Va SECURITY INVOKER: la RLS de `PPP_Web_Programacion` (los tres mails de
--     supervisor) decide quién puede escribir.

create or replace function public.ppp_web_armar_tandas(
  p_empresa text,
  p_fecha date default current_date,
  p_filas jsonb default '[]'::jsonb,
  p_forzar_cods text[] default '{}')
returns table (r_tanda text, r_zona text, r_np_count int, r_m3 numeric, r_clientes int)
language plpgsql
as $function$
declare
  v_tope   numeric := coalesce((select valor from public."PPP_Web_Config" where clave='tanda_m3_max_mezcla'), 0.80);
  v_cupo   numeric := coalesce((select valor from public."PPP_Web_Config" where clave='m3_max_dia'), 5.00);
  v_dias   int     := coalesce((select valor from public."PPP_Web_Config" where clave='dias_hasta_entrega'), 0)::int;
  v_saltar boolean := coalesce((select valor from public."PPP_Web_Config" where clave='saltar_fin_de_semana'), 1) <> 0;
  -- Vacio = codificacion historica de Virgilio. VER LA NOTA DEL ENCABEZADO.
  v_pref   text    := coalesce((select valor_texto from public."PPP_Web_Config" where clave='tanda_prefijo'), '');
  v_letra  int     := public.ppp_web_proxima_letra();
  v_fecha  date;
  v_usado  numeric;
  v_resta  numeric;
  v_acumsel numeric := 0;
  v_grupo  text;
  v_zn     int := 0;
  v_ti     int;
  v_code   text;
  v_acum   numeric;
  r_cli    record;
begin
  v_fecha := p_fecha + v_dias;
  if v_saltar then
    while extract(dow from v_fecha) in (0, 6) loop v_fecha := v_fecha + 1; end loop;
  end if;

  drop table if exists _sin_tanda;
  drop table if exists _sel;
  drop table if exists _asig;

  create temp table _sin_tanda on commit drop as
  select (x->>'order_id')::bigint as order_id,
         (x->>'np_idx')::int      as np_idx,
         nullif(x->>'np','')::int as np,
         coalesce(nullif(x->>'zona',''), '(sin zona)') as zona,
         public.gv_ppp_web_grupo_zona(coalesce(nullif(x->>'zona',''), '(sin zona)')) as grupo,
         coalesce(nullif(x->>'cod',''), nullif(x->>'razon_social',''), '?') as cliente,
         nullif(x->>'razon_social','') as razon_social,
         nullif(x->>'direccion','')    as direccion,
         nullif(x->>'barrio','')       as barrio,
         coalesce(nullif(x->>'fecha_recep','')::date, current_date) as fecha_recep,
         coalesce(nullif(x->>'m3','')::numeric, 0)    as m3,
         coalesce((x->>'m3_parcial')::boolean, false) as m3_parcial,
         nullif(x->>'lineas','')::int                 as lineas,
         nullif(x->>'cajas','')::numeric              as cajas,
         exists (select 1 from public."GV_Clientes_Reglas" g
                  where g.regla = 'solo' and g.empresa = p_empresa
                    and g.cod_cliente = nullif(x->>'cod','')) as va_solo,
         (exists (select 1 from public."GV_Clientes_Reglas" g
                   where g.regla = 'prioritario' and g.empresa = p_empresa
                     and g.cod_cliente = nullif(x->>'cod',''))
          or coalesce(nullif(x->>'cod','') = any(p_forzar_cods), false)) as prioritario
    from jsonb_array_elements(p_filas) x
   where not exists (
           select 1 from public."PPP_Web_Programacion" g
            where g.empresa = p_empresa
              and g.order_id = (x->>'order_id')::bigint
              and g.np_idx   = (x->>'np_idx')::int
              and coalesce(nullif(trim(g.tanda),''), '') <> '');

  -- Sin zona no se programa: falta el barrio y la elige una persona.
  delete from _sin_tanda where zona = '(sin zona)';

  -- ── Cuanto queda de cupo para esa fecha ────────────────────────────────
  -- Cuenta las DOS empresas: el cupo es del deposito, no de una razon social.
  select coalesce(sum(m3), 0) into v_usado
    from public."PPP_Web_Programacion"
   where fecha_entrega = v_fecha and coalesce(nullif(trim(tanda),''),'') <> '';
  v_resta := greatest(v_cupo - v_usado, 0);

  -- ── Seleccion: quien entra hoy ─────────────────────────────────────────
  -- La unidad es el CLIENTE (no la NP): un cliente entra entero o no entra.
  -- Orden: prioritarios primero, despues el pedido mas viejo.
  create temp table _sel (cliente text primary key) on commit drop;
  for r_cli in
    select cliente, sum(m3) as m3_cli, bool_or(prioritario) as prio,
           min(fecha_recep) as desde
      from _sin_tanda
     group by cliente
     order by bool_or(prioritario) desc, min(fecha_recep), sum(m3) desc, cliente
  loop
    -- El prioritario entra siempre. El resto, mientras quede cupo. Y el primero
    -- entra aunque el solo se pase: un cliente no se parte ni se posterga
    -- eternamente por ser mas grande que el cupo de un dia.
    if r_cli.prio
       or v_acumsel = 0 and v_resta > 0
       or v_acumsel + r_cli.m3_cli <= v_resta then
      insert into _sel (cliente) values (r_cli.cliente) on conflict do nothing;
      v_acumsel := v_acumsel + r_cli.m3_cli;
    end if;
  end loop;

  delete from _sin_tanda s where not exists (select 1 from _sel where cliente = s.cliente);

  -- ── Armado de tandas con lo seleccionado ───────────────────────────────
  create temp table _asig (order_id bigint, np_idx int, tanda text) on commit drop;

  -- Se recorre por GRUPO de zona, no por zona: asi 2 y 3 caen en el mismo bucle
  -- y pueden compartir tanda, y el resto no. Retira es su propio grupo.
  for v_grupo in select distinct grupo from _sin_tanda order by 1 loop
    v_zn := v_zn + 1; v_ti := 0; v_acum := 0; v_code := null;
    for r_cli in
      select cliente, sum(m3) as m3_cli, bool_or(va_solo) as solo
        from _sin_tanda where grupo = v_grupo
       group by cliente order by sum(m3) desc, cliente
    loop
      -- Abre tanda nueva si: el cliente va solo por regla propia, si es Super
      -- (uno por cliente), si el cliente solo ya pasa el tope, o si sumarlo lo
      -- pasaria. Retira NO abre siempre: juntarlos es lo que hace que retiren
      -- el mismo dia.
      if v_grupo = 'Super' or r_cli.solo or r_cli.m3_cli >= v_tope
         or v_code is null or (v_acum + r_cli.m3_cli) > v_tope then
        -- Con prefijo: GV-01A (prueba). Sin prefijo: E01A (codificacion Virgilio).
        -- ⚠ VER LA NOTA DEL ENCABEZADO ANTES DE TOCAR ESTO.
        v_code := case when v_pref <> '' then v_pref
                       else public.ppp_web_letra(v_letra) end
                  || lpad(v_zn::text, 2, '0') || public.ppp_web_letra(v_ti);
        v_ti := v_ti + 1; v_acum := 0;
      end if;
      insert into _asig (order_id, np_idx, tanda)
      select s.order_id, s.np_idx, v_code
        from _sin_tanda s where s.grupo = v_grupo and s.cliente = r_cli.cliente;
      v_acum := v_acum + r_cli.m3_cli;
      if v_grupo = 'Super' or r_cli.solo or r_cli.m3_cli >= v_tope then
        v_code := null; v_acum := 0;
      end if;
    end loop;
  end loop;

  insert into public."PPP_Web_Programacion"
    (empresa, order_id, np_idx, np, cod_cliente, razon_social, direccion, barrio,
     tanda, zona, fecha_entrega, m3, m3_parcial, lineas, cajas)
  select p_empresa, s.order_id, s.np_idx, s.np,
         s.cliente, s.razon_social, s.direccion, s.barrio,
         a.tanda, s.zona, v_fecha, s.m3, s.m3_parcial, s.lineas, s.cajas
    from _sin_tanda s join _asig a on a.order_id = s.order_id and a.np_idx = s.np_idx
  on conflict (empresa, order_id, np_idx) do update
     set tanda = excluded.tanda, zona = excluded.zona,
         fecha_entrega = excluded.fecha_entrega,
         m3 = excluded.m3, m3_parcial = excluded.m3_parcial,
         lineas = excluded.lineas, cajas = excluded.cajas;

  return query
    select a.tanda, min(s.grupo), count(*)::int, round(sum(s.m3), 3), count(distinct s.cliente)::int
      from _asig a join _sin_tanda s on s.order_id = a.order_id and s.np_idx = a.np_idx
     group by a.tanda order by a.tanda;
end
$function$;

-- ⚠ La v3 agrego `p_forzar_cods` CON DEFAULT, asi que quedaron dos sobrecargas y
--   la llamada de 3 argumentos se volvio ambigua ("could not choose a best
--   candidate function"). Eso rompia la Edge Function. Hay que borrar la vieja:
--     drop function if exists public.ppp_web_armar_tandas(text, date, jsonb);

-- ⚠ NO escribe `PPP_Web_Base` (la foto de artículos del picking). El front la
--   escribe aparte en `pwebGuardarProg`, y el armado automático la escribe en
--   `gv-ppp-web-tandas-diarias`. Sin ella la tanda queda programada y el operario
--   la abre VACÍA.
--
-- ── Controles ─────────────────────────────────────────────────────────────
--   -- Cómo quedaron las tandas del día:
--   select tanda, zona, count(*) np, count(distinct cod_cliente) clientes,
--          round(sum(m3),3) m3, min(fecha_entrega) entrega
--     from public."PPP_Web_Programacion"
--    where fecha_entrega = current_date group by 1,2 order by 1;
--
--   -- Ninguna tanda puede mezclar zonas ni fechas (tienen que dar 0):
--   select count(*) from (select tanda from public."PPP_Web_Programacion"
--     group by tanda having count(distinct zona) > 1
--        or count(distinct fecha_entrega) > 1) x;
--
--   -- Producción intacta: ninguna NP web se coló en la PPP de ISIS (0):
--   select count(*) from public."PPP_Programacion_Diaria" where np ~* '^(LK|CH) ';
-- ══════════════════════════════════════════════════════════════════════════

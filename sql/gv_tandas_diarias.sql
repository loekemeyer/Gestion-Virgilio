-- ══════════════════════════════════════════════════════════════════════════
-- Armado automático de tandas al comienzo de cada día hábil · 2026-09-04
-- Corre en VIRGILIO (hrxfctzncixxqmpfhskv)
-- ══════════════════════════════════════════════════════════════════════════
-- QUÉ RESUELVE
-- ──────────────────────────────────────────────────────────────────────────
-- `ppp_web_armar_tandas` ya existía y estaba probada, pero **no la llamaba
-- nadie**: 0 referencias en `index.html`, 0 crons. Por eso `PPP_Web_Programacion`
-- tenía 0 filas con 350 NP ya numeradas — la cadena se cortaba justo ahí.
--
-- Lo que pidió el dueño: *"para el comienzo de cada día (lunes a viernes no
-- feriado) tiene que elegir las tandas a armar a ese día"*.
--
-- Este archivo trae lo que faltaba del lado de la BASE. El disparador en sí es
-- la Edge Function `gv-ppp-web-tandas-diarias` + su cron (ver el final).
--
-- ──────────────────────────────────────────────────────────────────────────
-- ⚠⚠ NADA DE ESTO TOCA PRODUCCIÓN VIRGILIO
-- ──────────────────────────────────────────────────────────────────────────
-- Verificado con el grep obligatorio contra `loekemeyer/produccion-virgilio`
-- (HEAD a7b3368) el 2026-09-04:
--
--   ppp_web_armar_tandas ........ 0    PPP_Web_Programacion ... 0
--   PPP_Web_Config .............. 0    ppp_web_proxima_letra .. 0
--   gv_zona_de_barrio ........... 0    planify.feriados ....... 1  (sólo lectura)
--   Zonas_Barrios .............. 18    (sólo lectura, no se escribe)
--
-- Todo lo que se CREA acá es nuevo y con prefijo (`gv_*`, `GV_*`). De lo
-- compartido sólo se LEE: `Zonas_Barrios` y `planify.feriados`. No hay un
-- `create or replace` sobre nada ajeno, ni un trigger sobre tabla compartida, ni
-- un INSERT contra `PPP_Programacion_Diaria`.
--
-- **`ppp_web_armar_tandas` NO se modifica**, aunque sea nuestra y el grep dé 0.
-- Se pensó agregarle el salto de feriados a la fecha de entrega, y no hace falta:
-- si el job sólo corre en día hábil y `dias_hasta_entrega = 0`, la entrega cae en
-- día hábil por construcción. Recién si ese parámetro pasa a > 0 habría que
-- mirarlo — queda anotado abajo, no hecho.
-- ══════════════════════════════════════════════════════════════════════════


-- ── 1 · ¿Es día hábil? ────────────────────────────────────────────────────
-- Lunes a viernes y que no sea feriado. Los feriados salen de `planify.feriados`,
-- que ya mantiene al día el cron `planify_sync_feriados` (35 filas al 2026-09-04,
-- de 2026-01-01 a 2027-12-25, 21 futuros). Se LEE, no se toca.
--
-- SECURITY DEFINER porque `planify` no está abierto a `authenticated`; la función
-- devuelve un booleano y nada más, así que no filtra nada.
create or replace function public.gv_es_dia_habil(p_fecha date default current_date)
returns boolean
language sql
stable
security definer
set search_path = public, planify
as $function$
  select extract(dow from p_fecha) not in (0, 6)
     and not exists (select 1 from planify.feriados f where f.fecha = p_fecha);
$function$;

comment on function public.gv_es_dia_habil(date) is
  'Día hábil = lunes a viernes y no feriado (planify.feriados). Lo usa el armado automático de tandas.';

revoke all on function public.gv_es_dia_habil(date) from public;
grant execute on function public.gv_es_dia_habil(date) to anon, authenticated, service_role;


-- ── 2 · La zona, del lado del servidor ────────────────────────────────────
-- Hasta hoy la zona se resolvía SÓLO en el front (`pwebZonaSugerida` +
-- `pwebLocalidad` + `pwebBarrioDe`). Un job que corre a las 00:01 no tiene front,
-- así que la regla tiene que existir en el backend — que además es donde manda
-- el protocolo del CLAUDE.md: *la lógica de negocio va en el backend y el front
-- puede duplicarla como optimización de UX, nunca al revés*.
--
-- Es la MISMA cascada que hace el front, sin inventar nada:
--   zona_expreso → localidad → parsear la dirección por el último guión
-- y después el diccionario compartido. `zona_expreso` guarda el BARRIO del punto
-- de entrega (el depósito del expreso, para el interior), no la zona, pese al
-- nombre de la columna.

-- 2.a El barrio que sale de una sucursal: "Bragado 5742 - Mataderos" → "Mataderos".
--     Corta por el ÚLTIMO separador y acepta las tres rayas que aparecen en el
--     padrón (-, —, –). Sin exigir espacios: el padrón real no los respeta
--     ("1737-Palermo", "2579- Constitucion").
-- El front hace: i = lastIndexOf(sep); return (i > 0 ? t.slice(i+1) : t).trim()
--   · sin separador           → la cadena entera
--   · separador en la pos. 0  → la cadena entera   (i > 0 es falso)
--   · separador al final      → cadena VACÍA       (slice(i+1) = "")
-- ⚠ La primera versión usaba `rpos > 1` y se equivocaba en los dos últimos casos.
--   `rpos` es la posición desde la DERECHA. Probado contra 13 casos, los 4 bordes
--   incluidos.
create or replace function public.gv_ppp_web_barrio_de(p_sucursal text)
returns text
language sql
immutable
as $function$
  with t as (select btrim(coalesce(p_sucursal, '')) as s),
       p as (select s, length(s) as len,
                    greatest(strpos(reverse(s), '-'),
                             strpos(reverse(s), '—'),
                             strpos(reverse(s), '–')) as rpos
               from t)
  select case
           when s = ''       then ''
           when s ~* 'retir' then 'Retira'
           when rpos = 0     then s        -- sin separador
           when rpos = len   then s        -- separador en el primer caracter
           else btrim(right(s, rpos - 1))  -- rpos = 1 (separador al final) → ''
         end
    from p;
$function$;

comment on function public.gv_ppp_web_barrio_de(text) is
  'Barrio a partir de la sucursal de entrega, cortando por el último guión. Espejo backend de pwebBarrioDe() del front.';

-- 2.b La cascada completa → la zona.
create or replace function public.gv_ppp_web_zona(
  p_zona_expreso text default null,
  p_localidad    text default null,
  p_direccion    text default null)
returns text
language sql
stable
as $function$
  with b as (
    select coalesce(nullif(btrim(coalesce(p_zona_expreso,'')), ''),
                    nullif(btrim(coalesce(p_localidad,'')),    ''),
                    public.gv_ppp_web_barrio_de(p_direccion)) as barrio
  )
  select case
           when coalesce(barrio,'') = '' then null
           when barrio ~* 'retir'        then 'Retira'
           else public.gv_zona_de_barrio(barrio)
         end
    from b;
$function$;

comment on function public.gv_ppp_web_zona(text, text, text) is
  'Zona de un pedido web: zona_expreso → localidad → parseo de la dirección, y después Zonas_Barrios (+ override GV_). Espejo backend de pwebZonaSugerida() del front.';

-- 2.c La misma cuenta, en lote. La Edge Function resuelve 350+ NP por corrida:
--     una llamada por fila serían cientos de round trips.
create or replace function public.gv_ppp_web_zona_lote(p_filas jsonb)
returns table (r_idx int, r_zona text)
language sql
stable
as $function$
  select (x.ord - 1)::int,
         public.gv_ppp_web_zona(x.v->>'ze', x.v->>'loc', x.v->>'dir')
    from jsonb_array_elements(coalesce(p_filas, '[]'::jsonb)) with ordinality as x(v, ord);
$function$;

comment on function public.gv_ppp_web_zona_lote(jsonb) is
  'gv_ppp_web_zona aplicada a un lote. Entrada: [{ze,loc,dir}, ...]. Salida: (índice base 0, zona).';

revoke all on function public.gv_ppp_web_barrio_de(text) from public;
revoke all on function public.gv_ppp_web_zona(text, text, text) from public;
revoke all on function public.gv_ppp_web_zona_lote(jsonb) from public;
grant execute on function public.gv_ppp_web_barrio_de(text)        to anon, authenticated, service_role;
grant execute on function public.gv_ppp_web_zona(text, text, text) to anon, authenticated, service_role;
grant execute on function public.gv_ppp_web_zona_lote(jsonb)       to authenticated, service_role;


-- ── 2.d Agrupación de zonas ───────────────────────────────────────────────
-- Regla del dueño 2026-09-04: *"por zona: 2 y 3 pueden juntarse. 6 con 7. Todas
-- las demás por separado"*. Devuelve la CLAVE con la que se agrupa al armar: dos
-- zonas con la misma clave pueden compartir tanda.
create or replace function public.gv_ppp_web_grupo_zona(p_zona text)
returns text
language sql
immutable
as $function$
  select case
           when coalesce(btrim(p_zona),'') = '' then null
           when (regexp_match(p_zona, '^Zona\s*([0-9]+)'))[1] in ('2','3') then 'Zonas 2+3'
           when (regexp_match(p_zona, '^Zona\s*([0-9]+)'))[1] in ('6','7') then 'Zonas 6+7'
           else btrim(p_zona)
         end;
$function$;

comment on function public.gv_ppp_web_grupo_zona(text) is
  'Clave de agrupación de zonas para armar tandas: 2+3 juntas, 6+7 juntas, el resto sola.';
revoke all on function public.gv_ppp_web_grupo_zona(text) from public;
grant execute on function public.gv_ppp_web_grupo_zona(text) to anon, authenticated, service_role;


-- ── 2.e Clientes con regla propia ─────────────────────────────────────────
-- Tabla, no lista hardcodeada: el dueño va a agregar y sacar clientes de acá sin
-- que haya que tocar una función.
--   'solo'        → siempre tanda propia, no se junta con nadie
--   'prioritario' → no puede esperar en la cola; se programa dentro de la semana
create table if not exists public."GV_Clientes_Reglas" (
  cod_cliente text not null,
  empresa     text not null default 'lk',
  regla       text not null,
  nombre      text,
  nota        text,
  creado_en   timestamptz not null default now(),
  primary key (cod_cliente, empresa, regla),
  constraint gv_clientes_reglas_regla_chk   check (regla in ('solo','prioritario')),
  constraint gv_clientes_reglas_empresa_chk check (empresa in ('lk','chef'))
);

alter table public."GV_Clientes_Reglas" enable row level security;
revoke all on public."GV_Clientes_Reglas" from anon, authenticated;
drop policy if exists gv_clientes_reglas_select on public."GV_Clientes_Reglas";
create policy gv_clientes_reglas_select on public."GV_Clientes_Reglas"
  for select to authenticated using (true);
drop policy if exists gv_clientes_reglas_write on public."GV_Clientes_Reglas";
create policy gv_clientes_reglas_write on public."GV_Clientes_Reglas"
  for all to authenticated
  using      ((auth.jwt() ->> 'email') = any (array['loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']))
  with check ((auth.jwt() ->> 'email') = any (array['loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']));
grant select on public."GV_Clientes_Reglas" to authenticated;
grant insert, update, delete on public."GV_Clientes_Reglas" to authenticated;

-- Códigos VERIFICADOS contra `public.customers` de LK el 2026-09-04, no tipeados
-- de memoria: el dueño los nombró como "extralim", "dist gm", "osa" y "horcada".
insert into public."GV_Clientes_Reglas" (cod_cliente, empresa, regla, nombre, nota) values
  ('4114','lk','solo',        'Extralimp S.A.',                'Regla del dueño 2026-09-04: va solo.'),
  ('4080','lk','solo',        'Distribuidora GM S.R.L.',       'Regla del dueño 2026-09-04: va solo.'),
  ('2533','lk','prioritario', 'Osa Distribuidora SRLChemelo',  'Regla del dueño 2026-09-04: se programa sí o sí dentro de la semana.'),
  ('85',  'lk','prioritario', 'Horcada Marcelo Horcada Gustav','Regla del dueño 2026-09-04: se programa sí o sí dentro de la semana.')
on conflict do nothing;

-- ⚠ FALTA UNO. El dueño nombró "torres filigas" y **no existe en ningún padrón**:
--   ni en `customers` de LK ni en `chef_padron`. Los candidatos son
--   `Torres Y Liva S.A Cif` (LK 288 / CH 271) y `Torres Juan Luis` (LK 2266).
--   No se cargó ninguno: meter el cliente equivocado en una regla de prioridad es
--   peor que no tener la regla.


-- ── 3 · Bitácora de las corridas ──────────────────────────────────────────
-- Un job que corre solo a las 00:01 y no deja rastro es un job que nadie puede
-- auditar. Acá queda qué hizo cada corrida, incluidas las que NO hicieron nada
-- (fin de semana, feriado) — que son las que uno quiere poder explicar cuando
-- una mañana no hay tandas.
create table if not exists public."GV_Tandas_Auto_Log" (
  id              bigint generated always as identity primary key,
  corrida_en      timestamptz not null default now(),
  fecha_objetivo  date        not null,
  estado          text        not null,   -- 'ok' | 'salteada' | 'error'
  motivo          text,                   -- por qué se salteó, o el error
  np_leidas       int  not null default 0,
  np_programadas  int  not null default 0,
  tandas          int  not null default 0,
  ms              int,
  detalle         jsonb,                  -- por empresa: tandas, m³, zonas
  constraint gv_tandas_auto_log_estado_chk check (estado in ('ok','salteada','error'))
);

create index if not exists gv_tandas_auto_log_fecha_idx
  on public."GV_Tandas_Auto_Log" (fecha_objetivo desc, corrida_en desc);

alter table public."GV_Tandas_Auto_Log" enable row level security;
revoke all on public."GV_Tandas_Auto_Log" from anon, authenticated;

-- Lectura sólo para los supervisores (los mismos tres de PPP_Web_Config).
-- La escribe la Edge Function con service_role, que saltea RLS.
drop policy if exists gv_tandas_auto_log_select on public."GV_Tandas_Auto_Log";
create policy gv_tandas_auto_log_select on public."GV_Tandas_Auto_Log"
  for select to authenticated
  using ((auth.jwt() ->> 'email') = any (array[
    'loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']));
grant select on public."GV_Tandas_Auto_Log" to authenticated;


-- ── 4 · Un parámetro más ──────────────────────────────────────────────────
-- La ventana que el job le pide a LK/Chef. El front usa 30 días
-- (`PWEB_VENTANA_DIAS`); acá queda configurable sin tocar código.
-- INSERT-only (`do nothing`): si ya existe, manda lo que haya elegido una persona.
insert into public."PPP_Web_Config" (clave, valor, descripcion) values
  ('ventana_dias', 30,
   'Días hacia atrás que el armado automático le pide a LK/Chef. Espejo de PWEB_VENTANA_DIAS del front.')
on conflict (clave) do nothing;


-- ══════════════════════════════════════════════════════════════════════════
-- CÓMO SE DISPARA
-- ══════════════════════════════════════════════════════════════════════════
-- La Edge Function `gv-ppp-web-tandas-diarias` (código en
-- `supabase/functions/gv-ppp-web-tandas-diarias/index.ts`) hace, en orden:
--
--   1. `gv_es_dia_habil(hoy)` → si es sábado, domingo o feriado, loguea
--      'salteada' y corta. **El día lo mira en hora argentina**, no en UTC.
--   2. Lee LK (`v_pedidos_web_np`) y Chef (RPC `get_pedidos_web_np_chef`) del
--      proyecto de LK, con la ventana de `PPP_Web_Config.ventana_dias`.
--   3. `ppp_web_np_asignar` → numera lo que todavía no tiene número.
--   4. `ppp_web_resync`     → pone al día lo YA programado que cambió anoche.
--   5. `gv_ppp_web_zona_lote` → resuelve la zona de cada NP.
--   6. `ppp_web_armar_tandas` → arma las tandas del día con lo que quedó sin tanda.
--   7. `PPP_Web_Base` → la FOTO de artículos que después pickea el operario.
--      ⚠ `ppp_web_armar_tandas` NO la escribe: el front la escribe aparte, en
--      `pwebGuardarProg`. Sin este paso la tanda queda programada y el operario
--      la abre VACÍA — el propio front tiene ese error escrito a mano.
--   8. Escribe una fila en `GV_Tandas_Auto_Log`.
--
-- La función va con `verify_jwt = true`; el cron le manda la service key, que
-- lee de `lecturacvs.app_secrets` para que no quede literal en `cron.job`.
--
-- Cron APLICADO el 2026-09-04 (jobid 71). 00:01 de Argentina = 03:01 UTC; el
-- rango 1-5 es de más, porque el chequeo de día hábil está adentro de la función
-- y además cubre los feriados, que el cron no sabe:
--
--   select cron.schedule('gv-ppp-web-tandas-diarias', '1 3 * * 1-5', $cron$
--     select net.http_post(
--       url     := 'https://hrxfctzncixxqmpfhskv.supabase.co/functions/v1/gv-ppp-web-tandas-diarias',
--       headers := jsonb_build_object(
--                    'Content-Type', 'application/json',
--                    'Authorization', 'Bearer ' || (select v from lecturacvs.app_secrets
--                                                    where k = 'SUPABASE_SERVICE_ROLE_KEY')),
--       body    := '{}'::jsonb)
--   $cron$);
--
-- Para probar a mano: `?forzar=1` corre aunque sea sábado o feriado, `?dry=1`
-- lee y resuelve zonas sin escribir nada, y `?fecha=YYYY-MM-DD` fija el día.
--
-- ⚠ SECRETO QUE HAY QUE CARGAR A MANO (sin esto la función no arranca):
--   `GV_LK_SERVICE_KEY` = service_role key del proyecto **LK**
--   (`kwkclwhmoygunqmlegrg`), en Edge Functions → Secrets del proyecto Virgilio.
--   Hace falta porque `v_pedidos_web_np` y `get_pedidos_web_np_chef` piden
--   `authenticated` — con la anon key de LK dan 401, y así tiene que seguir:
--   esas dos traen razón social, dirección y detalle de pedidos.
--
-- ══════════════════════════════════════════════════════════════════════════
-- PROBADO CON DATOS REALES (2026-09-04, transacción revertida)
-- ══════════════════════════════════════════════════════════════════════════
-- 32 NP reales de LK (pedidos 1312-1344) por toda la cadena. 31 programadas en
-- 13 tandas; la única que quedó afuera es la única sin zona. Las reglas se
-- cumplen sobre datos de verdad, no sobre casos inventados:
--
--   E02A  Súper    1 cli · 1 NP · 4,560 m³   una tanda por cliente
--   E04A  Zona 2   1 cli · 2 NP · 1,375 m³   pasa el tope, pero es UN cliente
--                                            → no se parte
--   E03A  Zona 1   1 cli · 1 NP · 1,330 m³   ídem
--   E03D  Zona 1   4 cli · 7 NP · 0,643 m³   junta chicos bajo 1 m³
--   E01A  Retira   2 cli · 2 NP · 0,075 m³   Retira se junta como una zona más
--
-- Y además: ninguna tanda mezcla zonas, las NP de un mismo pedido viajan juntas
-- (un cliente con 5 NP en dos sucursales de la misma zona quedó en UNA tanda), y
-- los códigos arrancan en E porque Producción va por D.
--
-- La zona del backend contra 30 días de pedidos reales de LK: **340 de 355 NP
-- (95,8%)**. Las 15 restantes son del interior sin `zona_expreso` cargado en el
-- padrón —Santa Cruz, Aguilares, Concepción del Uruguay, Río Cuarto— más una
-- fila basura. No es el diccionario: es el padrón de LK.
--
-- Verificado después de la prueba: `PPP_Web_Programacion` volvió a 0 filas,
-- `PPP_Programacion_Diaria` sigue en 182 y no tiene ni una NP web.
--
-- ══════════════════════════════════════════════════════════════════════════
-- CONTROLES
-- ══════════════════════════════════════════════════════════════════════════
--   -- Las corridas de la última semana:
--   select corrida_en, fecha_objetivo, estado, motivo, np_leidas, np_programadas, tandas, ms
--     from public."GV_Tandas_Auto_Log" order by id desc limit 20;
--
--   -- Las tandas armadas para hoy:
--   select tanda, zona, count(*) np, count(distinct cod_cliente) clientes,
--          round(sum(m3),3) m3
--     from public."PPP_Web_Programacion" where fecha_entrega = current_date
--    group by 1,2 order by 1;
--
--   -- Producción intacta: ninguna NP web se coló en la PPP de ISIS (tiene que dar 0):
--   select count(*) from public."PPP_Programacion_Diaria" where np ~* '^(LK|CH) ';
--
--   -- La zona del backend y la del front tienen que coincidir (tiene que dar 0):
--   select count(*) from public."PPP_Web_Programacion" p
--    where p.barrio is not null
--      and p.zona is distinct from public.gv_ppp_web_zona(p.barrio, null, null);
--
-- ══════════════════════════════════════════════════════════════════════════
-- PENDIENTE (anotado, no hecho)
-- ══════════════════════════════════════════════════════════════════════════
-- · `ppp_web_armar_tandas` corre la fecha de entrega al lunes si cae fin de
--   semana, pero **no saltea feriados**. Hoy da igual (`dias_hasta_entrega = 0`
--   y el job sólo corre en día hábil). Si ese parámetro pasa a > 0, la entrega
--   puede caer en feriado y ahí sí hay que meterle `gv_es_dia_habil`.
-- · Retira / Súper / Expo: Súper ya sale una tanda por cliente y Retira se junta
--   como una zona más. **Expo no tiene evidencia histórica** (0 tandas en 120
--   días) y hoy se trata como una zona más. Sin definir.
-- ══════════════════════════════════════════════════════════════════════════

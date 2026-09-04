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
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public."PPP_Web_Config" (
  clave       text primary key,
  valor       numeric,
  descripcion text,
  actualizado timestamptz not null default now()
);

insert into public."PPP_Web_Config" (clave, valor, descripcion) values
  ('tanda_m3_max_mezcla', 1.00,
   'Tope de m³ para JUNTAR clientes distintos. No parte a un cliente: si uno solo pide más, se va solo con todo lo suyo.'),
  ('tanda_m3_min', 0.60,
   'm³ deseable mínimo. NO bloquea: 33 de 56 tandas históricas salieron por debajo.'),
  ('dias_hasta_entrega', 0,
   'Días desde que se arma la tanda hasta la entrega. 0 = mismo día. Sin evidencia histórica; es el parámetro a mover.'),
  ('saltar_fin_de_semana', 1,
   '1 = si cae sábado o domingo, corre al lunes. 0 entregas de fin de semana en 120 días.')
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

-- El cuerpo de `ppp_web_armar_tandas` está aplicado en la base (migración
-- `ppp_web_armar_tandas`). Notas de implementación que importan al tocarlo:
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

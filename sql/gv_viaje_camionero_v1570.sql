-- v15.70 (2026-09-11) — EL VIAJE DEL CAMIONERO. Pedido de Thomas:
--   CC: "a medida que den click en lo que cargan, en lugar de un simple tilde, que diga 1°, 2°, 3°…
--        una vez que ya terminó de cargar el camión, que le pregunte el nombre del camionero".
--   RR: "primero lo deja elegir una NP igual que ahora (podemos entregar más de un camión por día);
--        una vez elegida, ya tenés el dato de qué camionero corresponde → que muestre las NP que
--        entregó Guille el 11/9".
--   + si una NP de ese viaje no se controló (y al menos una sí) → alerta a la operadora en la PPP.
--   + al terminar de controlar, cuántas horas dice la hoja de ruta → ritmo m³/hora.
--   Excepciones: Retira no tiene camionero (se controla y guarda en el momento). El súper NO se
--   compara contra los clientes ("se demora mucho más para entregar un supermercado").
--
-- NO HACE FALTA TABLA DE VIAJES. El camionero ya viaja en el evento CCN desde la v11.47
-- (texto = 'NP|TANDA|CAMIONERO'); la v15.70 agrega un 4º campo con el ORDEN de carga real:
-- 'NP|TANDA|CAMIONERO|ORDEN'. Los lectores viejos usan split_part [1] y [2] y no se enteran.
-- VUELTA (Thomas: "son 2, pero no hacen dos vueltas casi nunca"): no se pregunta — la vuelta 2 se
-- detecta sola porque el orden vuelve a empezar en 1 dentro del mismo camionero+día.
--
-- MEDIDO al aplicar: 8 viajes históricos reconstruidos sin tocar un dato (Guillermo 03/09: 29 NP,
-- 16 paradas, 5,28 m³) · gv_viajes_sin_controlar = 0 · 773 NP con CCN sin camionero (el campo era
-- opcional y se salteaba: 10 y 11/09 = 33 cargas sin camionero, 08/09 = 10). Por eso la v15.70
-- lo hace OBLIGATORIO en la app.
--
-- ROLLBACK:
--   drop view public.gv_viajes_sin_controlar, public.gv_viaje, public.gv_viaje_np;
--   drop table public."GV_Viaje_Horas";
--   (y en el front, volver ccSendDetail a 3 campos)
-- Migración aplicada: gv_viaje_camionero_v1

create table if not exists public."GV_Viaje_Horas" (
  fecha       date        not null,
  camionero   text        not null,
  vuelta      smallint    not null default 1,
  horas       numeric     not null check (horas > 0 and horas <= 24),
  legajo      text,
  nota        text,
  creado_at   timestamptz not null default now(),
  primary key (fecha, camionero, vuelta)
);
alter table public."GV_Viaje_Horas" enable row level security;
drop policy if exists gvvh_all on public."GV_Viaje_Horas";
create policy gvvh_all on public."GV_Viaje_Horas" for all to anon, authenticated using (true) with check (true);

-- gv_viaje_np      → una fila por NP cargada, con viaje (fecha+camionero+vuelta), orden y control
-- gv_viaje         → el viaje resumido + horas de hoja de ruta + ritmo m³/hora (sin súper)
-- gv_viajes_sin_controlar → LA ALERTA: viaje empezado a controlar con NP sin controlar
-- El cuerpo de las tres vistas está en la migración gv_viaje_camionero_v1; se reproduce con
--   select pg_get_viewdef('public.gv_viaje_np'::regclass, true);
-- PRUEBA:
--   select fecha, camionero, vuelta, nps, controladas, paradas, m3, m3_por_hora from public.gv_viaje order by fecha desc limit 5;
--   select * from public.gv_viajes_sin_controlar;     -- vacía = ningún viaje quedó a medio controlar

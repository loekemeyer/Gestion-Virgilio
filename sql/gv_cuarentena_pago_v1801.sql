-- v18.01 — Cuarentena · "Ya pagó" (problema 205)
--
-- SÍNTOMA (Luis, 2026-09-15: *"el botón ya pagó me parece que no hace nada"*): tenía razón.
-- No hacía NADA desde que existe (v15.46, 2026-09-11): `GV_Cuarentena_Pagados` estaba vacía.
--
-- CAUSA 1 (la que rompía) — `gv_cuarentena_pago` devuelve OUT params llamados `cod` y `empresa`,
-- y adentro hacía `insert ... on conflict (empresa, cod) do update`. plpgsql no sabe si ese
-- target del conflicto es la COLUMNA o la VARIABLE y aborta con
--   ERROR 42702: column reference "empresa" is ambiguous
-- La función levantaba excepción antes de escribir una sola fila, siempre, para cualquier
-- cliente. Medido el 2026-09-15 recreando la definición vieja con otro nombre y llamándola.
-- ARREGLO: `on conflict on constraint "GV_Cuarentena_Pagados_pkey"` (la PK es (empresa, cod)),
-- que no pasa por la resolución de nombres de plpgsql. No se pueden renombrar los OUT params:
-- definen el tipo de retorno, así que cambiarlos obliga a DROP + CREATE y a tocar el front.
--
-- CAUSA 2 (la que habría seguido rompiendo) — guardaba el par CRUDO del pedido (el de la página:
-- `lk` + código LK). Desde la v17.74/v17.75 el motivo `deuda` se evalúa contra el padrón que
-- resuelve `gv_cuarentena_ident` (GV_Cliente_Isis): para los 9 clientes de Tierra del Fuego el
-- par evaluado es `(chef, cod_isis)`, y el `not exists` de `gv_cuarentena_marcar_calc` /
-- `gv_cuarentena_ya_programado` busca ESE par. ARREGLO: resolver la identidad acá también y
-- guardar los DOS pares. Son el mismo cliente —el mapeo va por CUIT—, así que el pago vale
-- se lo mire desde una NP de la página (que se remapea) o desde una tipeada en ISIS (que no).
-- Sin mapeo los dos pares son el mismo y el `union` deja una sola fila.
--
-- MEDICIÓN: `select * from public.gv_cuarentena_pago('lk','ZZ_PRUEBA_V1798');` devolvió la fila
-- y escribió en la tabla (antes: 42702). La fila de prueba se borró; la tabla quedó en 0.
--
-- ROLLBACK: `sql/backups/gv_cuarentena_pago_pre_v1801.sql` (vuelve a la versión rota, ojo).

create or replace function public.gv_cuarentena_pago(p_empresa text, p_cod text)
 returns table(cod text, empresa text, deuda_al_pagar numeric, pedidos_liberados integer)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_emp    text := lower(nullif(btrim(p_empresa), ''));
  v_cod    text := nullif(btrim(p_cod), '');
  v_emp_ev text;
  v_cod_ev text;
  v_deuda  numeric;
  v_n      int := 0;
  v_mail   text := lower(coalesce(auth.jwt()->>'email',''));
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede marcar un cliente como pagado.' using errcode='42501';
  end if;
  if v_emp is null or v_cod is null then
    raise exception 'Falta empresa o codigo de cliente.' using errcode='22023';
  end if;

  -- v18.01 (problema 205) — a que padron se le mira la deuda (causa 2 de la cabecera).
  select id.empresa, id.cod into v_emp_ev, v_cod_ev
    from public.gv_cuarentena_ident(v_emp, v_cod, true) id;

  -- ⚠ ON CONFLICT ON CONSTRAINT, no ON CONFLICT (empresa, cod): ver causa 1 de la cabecera.
  -- El pago vale contra el reporte de deuda VIGENTE de cada empresa (`fuente_at`): si manana se
  -- sube uno mas nuevo y el cliente sigue debiendo, vuelve solo a Cuarentena.
  insert into public."GV_Cuarentena_Pagados" (empresa, cod, pagado_at, pagado_por, fuente_at, deuda_al_pagar)
  select x.emp, x.cd, now(), v_mail,
         (select max(f.cargado_at) from public."GV_Cuarentena_Fuente" f
           where f.empresa = x.emp and f.tipo = 'deuda'),
         (select round(f.deuda, 2) from public."GV_Cuarentena_Fuente" f
           where f.empresa = x.emp and f.tipo = 'deuda' and f.cod = x.cd limit 1)
    from (select v_emp as emp, v_cod as cd
          union
          select v_emp_ev, v_cod_ev) x
  on conflict on constraint "GV_Cuarentena_Pagados_pkey" do update
    set pagado_at = now(), pagado_por = excluded.pagado_por,
        fuente_at = excluded.fuente_at, deuda_al_pagar = excluded.deuda_al_pagar;

  -- la deuda que se informa es la del padron con el que SE EVALUA, que es la que se estaba viendo
  select round(f.deuda, 2) into v_deuda
    from public."GV_Cuarentena_Fuente" f
   where f.empresa = v_emp_ev and f.tipo = 'deuda' and f.cod = v_cod_ev
   limit 1;

  -- cuantos pedidos de ese cliente estaban esperando: informativo para el aviso del front
  select count(*) into v_n
    from public."PPP_Web_Programacion" pw
   where pw.empresa = v_emp and pw.cod_cliente = v_cod and pw.tanda is null;

  return query select v_cod, v_emp, v_deuda, v_n;
end;
$function$;

revoke all on function public.gv_cuarentena_pago(text, text) from public, anon;
grant execute on function public.gv_cuarentena_pago(text, text) to authenticated, service_role;

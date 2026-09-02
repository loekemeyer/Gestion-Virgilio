-- =====================================================================
-- BACKUP LIMPIEZA 2026-09-02 (propuesta 2496, "arregla todo lo que este de sobra")
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv). Restore: correr tal cual en el SQL editor.
--
-- Se borran:
--   . recalcular_maximo_por_cod / recalcular_maximo_por_desc: usaban el numero "E. Madre" de
--     E. Madre LK/CH (cargado a mano en marzo) para fijar Partes x Tallerista.maximo. Sin
--     llamadores (front, cron, trigger), 0 de 954 filas con maximo > 0, y ejecutables por anon.
--   . refresh_proyeccion_madre: el pull HTTP con anon key que fallaba en silencio; lo
--     reemplazo sync_proyeccion_madre_virgilio() (push desde LK). Ya sin cron.
--   . la columna "E. Madre" de las tablas E. Madre LK / E. Madre CH: se BORRO y se RESTAURO
--     el mismo dia (2026-09-02, ~1 h despues) al descubrir por los logs de la API que la app
--     GestionProductivaEntero (Vercel) la pide 42 veces por dia (select=Cod,"E. Madre") en
--     7 modulos. Restaurada desde este archivo: LK 290 filas / 288 con valor / suma 299.111,
--     CH 302 / 302 / 43.314 — identico al backup. La leccion: el catalogo de un proyecto no
--     dice quien lo consume desde OTRA app; los logs de la API si.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.recalcular_maximo_por_cod(p_cod text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  update public."Partes x Tallerista" p
  set maximo = coalesce(em.est_madre, 0) * coalesce(p.partes_x_uni, 0) * coalesce(p.kgxuni, 0)
  from (
    select x.cod, max(x.est_madre) as est_madre
    from (
      select trim("Cod") as cod, coalesce("E. Madre", 0)::float8 as est_madre
      from public."E. Madre LK"

      union all

      select trim("Cod") as cod, coalesce("E. Madre", 0)::float8 as est_madre
      from public."E. Madre CH"
    ) x
    group by x.cod
  ) em
  where trim(p.cod) = trim(p_cod)
    and trim(p.cod) = em.cod;

  -- si no existe ese código en E Madre, dejar maximo en 0
  update public."Partes x Tallerista" p
  set maximo = 0
  where trim(p.cod) = trim(p_cod)
    and not exists (
      select 1
      from (
        select trim("Cod") as cod from public."E. Madre LK"
        union
        select trim("Cod") as cod from public."E. Madre CH"
      ) z
      where z.cod = trim(p.cod)
    );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.recalcular_maximo_por_desc()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN

    UPDATE public."Partes x Tallerista" p
    SET maximo =
        (
          COALESCE(em.est_madre, 0) * COALESCE(p.partes_x_uni, 0)
        )
        / NULLIF(p.partes_x_cja, 0)
    FROM (
        SELECT
            TRIM(x."Desc") AS desc_pieza,
            MAX(COALESCE(x."E. Madre", 0)::float8) AS est_madre
        FROM (
            SELECT "Desc", "E. Madre" FROM public."E. Madre LK"
            UNION ALL
            SELECT "Desc", "E. Madre" FROM public."E. Madre CH"
        ) x
        GROUP BY TRIM(x."Desc")
    ) em
    WHERE TRIM(p.descripcion_parte) = em.desc_pieza;

    UPDATE public."Partes x Tallerista" p
    SET maximo = 0
    WHERE NOT EXISTS (
        SELECT 1
        FROM (
            SELECT TRIM("Desc") AS desc_pieza FROM public."E. Madre LK"
            UNION
            SELECT TRIM("Desc") AS desc_pieza FROM public."E. Madre CH"
        ) z
        WHERE TRIM(p.descripcion_parte) = z.desc_pieza
    );

END;
$function$
;

CREATE OR REPLACE FUNCTION public.refresh_proyeccion_madre()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  resp public.http_response;
  body jsonb;
  n integer;
  v_err text;
  v_dia text := to_char((now() at time zone 'America/Argentina/Buenos_Aires'), 'YYYYMMDD');
  k constant text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt3a2Nsd2htb3lndW5xbWxlZ3JnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk1MjA2NzUsImV4cCI6MjA4NTA5NjY3NX0.soqPY5hfA3RkAJ9jmIms8UtEGUc4WpZztpEbmDijOgU';
begin
  begin
    resp := public.http(('GET',
      'https://kwkclwhmoygunqmlegrg.supabase.co/rest/v1/rpc/fn_proyeccion_oc_virgilio',
      array[ public.http_header('apikey', k), public.http_header('Authorization', 'Bearer ' || k) ],
      null, null)::public.http_request);
  exception when others then
    resp := null; v_err := 'excepción HTTP: ' || coalesce(sqlerrm, '?');
  end;

  if resp is null or resp.status <> 200 then
    v_err := coalesce(v_err, 'HTTP ' || coalesce(resp.status::text, '?') || ' — ' || left(coalesce(resp.content, ''), 180));
    begin
      perform public.tg_enqueue(
        '🚨 PROYECCIÓN NO ACTUALIZADA — ' || to_char((now() at time zone 'America/Argentina/Buenos_Aires'), 'DD/MM') || E'\n' ||
        'El generador de OCs sigue con la última proyección buena. Motivo: ' || v_err || E'\n' ||
        'Revisá el motor fn_proyeccion_oc_virgilio en "loekemeyer''s web".',
        'projmadre_fail_' || v_dia);
      perform public.tg_outbox_flush();
    exception when others then null; end;
    raise notice 'refresh_proyeccion_madre: %', v_err;
    return -1;
  end if;

  body := resp.content::jsonb;
  if jsonb_typeof(body) <> 'array' or jsonb_array_length(body) = 0 then
    begin
      perform public.tg_enqueue(
        '🚨 PROYECCIÓN NO ACTUALIZADA — ' || to_char((now() at time zone 'America/Argentina/Buenos_Aires'), 'DD/MM') || E'\n' ||
        'El motor de proyección devolvió una respuesta vacía o inesperada. El generador de OCs sigue con la última proyección buena.',
        'projmadre_fail_' || v_dia);
      perform public.tg_outbox_flush();
    exception when others then null; end;
    raise notice 'refresh_proyeccion_madre: respuesta vacia/inesperada';
    return -1;
  end if;

  delete from public.proyeccion_madre;
  insert into public.proyeccion_madre (cod, proy_cajas_mes, uxb, proy_uni_mes, actualizado)
  select upper(btrim(x.cod)), x.proy_cajas_mes, x.uxb, x.proy_uni_mes, now()
  from jsonb_to_recordset(body) as x(cod text, proy_cajas_mes numeric, uxb integer, proy_uni_mes numeric)
  where x.proy_cajas_mes > 0 and coalesce(btrim(x.cod), '') <> '';
  get diagnostics n = row_count;
  return n;
end $function$
;

-- ---- columna "E. Madre" de E. Madre LK ----
-- alter table public."E. Madre LK" add column "E. Madre" integer;
update public."E. Madre LK" set "E. Madre" = 0 where id = 287;
update public."E. Madre LK" set "E. Madre" = 7236 where id = 288;
update public."E. Madre LK" set "E. Madre" = 4512 where id = 289;
update public."E. Madre LK" set "E. Madre" = 0 where id = 290;
update public."E. Madre LK" set "E. Madre" = 0 where id = 291;
update public."E. Madre LK" set "E. Madre" = 0 where id = 292;
update public."E. Madre LK" set "E. Madre" = 18192 where id = 293;
update public."E. Madre LK" set "E. Madre" = 1536 where id = 294;
update public."E. Madre LK" set "E. Madre" = 0 where id = 295;
update public."E. Madre LK" set "E. Madre" = 744 where id = 296;
update public."E. Madre LK" set "E. Madre" = 312 where id = 297;
update public."E. Madre LK" set "E. Madre" = 144 where id = 298;
update public."E. Madre LK" set "E. Madre" = 2100 where id = 299;
update public."E. Madre LK" set "E. Madre" = 840 where id = 300;
update public."E. Madre LK" set "E. Madre" = 300 where id = 301;
update public."E. Madre LK" set "E. Madre" = 1024 where id = 302;
update public."E. Madre LK" set "E. Madre" = 1140 where id = 303;
update public."E. Madre LK" set "E. Madre" = 408 where id = 304;
update public."E. Madre LK" set "E. Madre" = 1200 where id = 305;
update public."E. Madre LK" set "E. Madre" = 552 where id = 306;
update public."E. Madre LK" set "E. Madre" = 360 where id = 307;
update public."E. Madre LK" set "E. Madre" = 360 where id = 308;
update public."E. Madre LK" set "E. Madre" = 264 where id = 309;
update public."E. Madre LK" set "E. Madre" = 312 where id = 310;
update public."E. Madre LK" set "E. Madre" = 600 where id = 311;
update public."E. Madre LK" set "E. Madre" = 600 where id = 312;
update public."E. Madre LK" set "E. Madre" = 480 where id = 313;
update public."E. Madre LK" set "E. Madre" = 456 where id = 314;
update public."E. Madre LK" set "E. Madre" = 2136 where id = 315;
update public."E. Madre LK" set "E. Madre" = 1860 where id = 316;
update public."E. Madre LK" set "E. Madre" = 276 where id = 317;
update public."E. Madre LK" set "E. Madre" = 600 where id = 318;
update public."E. Madre LK" set "E. Madre" = 144 where id = 319;
update public."E. Madre LK" set "E. Madre" = 540 where id = 320;
update public."E. Madre LK" set "E. Madre" = 396 where id = 321;
update public."E. Madre LK" set "E. Madre" = 600 where id = 322;
update public."E. Madre LK" set "E. Madre" = 276 where id = 323;
update public."E. Madre LK" set "E. Madre" = 588 where id = 324;
update public."E. Madre LK" set "E. Madre" = 2400 where id = 325;
update public."E. Madre LK" set "E. Madre" = 24 where id = 326;
update public."E. Madre LK" set "E. Madre" = 1008 where id = 327;
update public."E. Madre LK" set "E. Madre" = 0 where id = 328;
update public."E. Madre LK" set "E. Madre" = 0 where id = 329;
update public."E. Madre LK" set "E. Madre" = 0 where id = 330;
update public."E. Madre LK" set "E. Madre" = 384 where id = 331;
update public."E. Madre LK" set "E. Madre" = 0 where id = 332;
update public."E. Madre LK" set "E. Madre" = 0 where id = 333;
update public."E. Madre LK" set "E. Madre" = 120 where id = 334;
update public."E. Madre LK" set "E. Madre" = 0 where id = 335;
update public."E. Madre LK" set "E. Madre" = 924 where id = 336;
update public."E. Madre LK" set "E. Madre" = 0 where id = 337;
update public."E. Madre LK" set "E. Madre" = 0 where id = 338;
update public."E. Madre LK" set "E. Madre" = 0 where id = 339;
update public."E. Madre LK" set "E. Madre" = 1300 where id = 340;
update public."E. Madre LK" set "E. Madre" = 324 where id = 341;
update public."E. Madre LK" set "E. Madre" = 96 where id = 342;
update public."E. Madre LK" set "E. Madre" = 204 where id = 343;
update public."E. Madre LK" set "E. Madre" = 4500 where id = 344;
update public."E. Madre LK" set "E. Madre" = 3120 where id = 345;
update public."E. Madre LK" set "E. Madre" = 0 where id = 346;
update public."E. Madre LK" set "E. Madre" = 264 where id = 347;
update public."E. Madre LK" set "E. Madre" = 0 where id = 348;
update public."E. Madre LK" set "E. Madre" = 0 where id = 349;
update public."E. Madre LK" set "E. Madre" = 2256 where id = 350;
update public."E. Madre LK" set "E. Madre" = 144 where id = 351;
update public."E. Madre LK" set "E. Madre" = 264 where id = 352;
update public."E. Madre LK" set "E. Madre" = 288 where id = 353;
update public."E. Madre LK" set "E. Madre" = 192 where id = 354;
update public."E. Madre LK" set "E. Madre" = 120 where id = 355;
update public."E. Madre LK" set "E. Madre" = 216 where id = 356;
update public."E. Madre LK" set "E. Madre" = 96 where id = 357;
update public."E. Madre LK" set "E. Madre" = 240 where id = 358;
update public."E. Madre LK" set "E. Madre" = 0 where id = 359;
update public."E. Madre LK" set "E. Madre" = 720 where id = 360;
update public."E. Madre LK" set "E. Madre" = 0 where id = 361;
update public."E. Madre LK" set "E. Madre" = 120 where id = 362;
update public."E. Madre LK" set "E. Madre" = 192 where id = 363;
update public."E. Madre LK" set "E. Madre" = 312 where id = 364;
update public."E. Madre LK" set "E. Madre" = 312 where id = 365;
update public."E. Madre LK" set "E. Madre" = 360 where id = 366;
update public."E. Madre LK" set "E. Madre" = 600 where id = 367;
update public."E. Madre LK" set "E. Madre" = 180 where id = 368;
update public."E. Madre LK" set "E. Madre" = 0 where id = 369;
update public."E. Madre LK" set "E. Madre" = 0 where id = 370;
update public."E. Madre LK" set "E. Madre" = 24 where id = 371;
update public."E. Madre LK" set "E. Madre" = 144 where id = 372;
update public."E. Madre LK" set "E. Madre" = 144 where id = 373;
update public."E. Madre LK" set "E. Madre" = 1440 where id = 374;
update public."E. Madre LK" set "E. Madre" = 6912 where id = 375;
update public."E. Madre LK" set "E. Madre" = 5796 where id = 376;
update public."E. Madre LK" set "E. Madre" = 6996 where id = 377;
update public."E. Madre LK" set "E. Madre" = 30000 where id = 378;
update public."E. Madre LK" set "E. Madre" = 18840 where id = 379;
update public."E. Madre LK" set "E. Madre" = 792 where id = 380;
update public."E. Madre LK" set "E. Madre" = 420 where id = 381;
update public."E. Madre LK" set "E. Madre" = 192 where id = 382;
update public."E. Madre LK" set "E. Madre" = 6456 where id = 383;
update public."E. Madre LK" set "E. Madre" = 484 where id = 384;
update public."E. Madre LK" set "E. Madre" = 1656 where id = 385;
update public."E. Madre LK" set "E. Madre" = 18204 where id = 386;
update public."E. Madre LK" set "E. Madre" = 0 where id = 387;
update public."E. Madre LK" set "E. Madre" = 442 where id = 388;
update public."E. Madre LK" set "E. Madre" = 500 where id = 389;
update public."E. Madre LK" set "E. Madre" = 0 where id = 390;
update public."E. Madre LK" set "E. Madre" = 780 where id = 391;
update public."E. Madre LK" set "E. Madre" = 600 where id = 392;
update public."E. Madre LK" set "E. Madre" = 3120 where id = 393;
update public."E. Madre LK" set "E. Madre" = 2220 where id = 394;
update public."E. Madre LK" set "E. Madre" = 2400 where id = 395;
update public."E. Madre LK" set "E. Madre" = 24 where id = 396;
update public."E. Madre LK" set "E. Madre" = 0 where id = 397;
update public."E. Madre LK" set "E. Madre" = 0 where id = 398;
update public."E. Madre LK" set "E. Madre" = 3600 where id = 399;
update public."E. Madre LK" set "E. Madre" = 1440 where id = 400;
update public."E. Madre LK" set "E. Madre" = 312 where id = 401;
update public."E. Madre LK" set "E. Madre" = 144 where id = 402;
update public."E. Madre LK" set "E. Madre" = 1584 where id = 403;
update public."E. Madre LK" set "E. Madre" = 0 where id = 404;
update public."E. Madre LK" set "E. Madre" = 384 where id = 405;
update public."E. Madre LK" set "E. Madre" = 396 where id = 406;
update public."E. Madre LK" set "E. Madre" = 7464 where id = 407;
update public."E. Madre LK" set "E. Madre" = 7200 where id = 408;
update public."E. Madre LK" set "E. Madre" = 24 where id = 409;
update public."E. Madre LK" set "E. Madre" = 0 where id = 410;
update public."E. Madre LK" set "E. Madre" = 1368 where id = 411;
update public."E. Madre LK" set "E. Madre" = 468 where id = 412;
update public."E. Madre LK" set "E. Madre" = 0 where id = 413;
update public."E. Madre LK" set "E. Madre" = 0 where id = 414;
update public."E. Madre LK" set "E. Madre" = 192 where id = 415;
update public."E. Madre LK" set "E. Madre" = 1800 where id = 416;
update public."E. Madre LK" set "E. Madre" = 24 where id = 417;
update public."E. Madre LK" set "E. Madre" = 1400 where id = 418;
update public."E. Madre LK" set "E. Madre" = 2124 where id = 419;
update public."E. Madre LK" set "E. Madre" = 996 where id = 420;
update public."E. Madre LK" set "E. Madre" = 660 where id = 421;
update public."E. Madre LK" set "E. Madre" = 612 where id = 422;
update public."E. Madre LK" set "E. Madre" = 1200 where id = 423;
update public."E. Madre LK" set "E. Madre" = 96 where id = 424;
update public."E. Madre LK" set "E. Madre" = 444 where id = 425;
update public."E. Madre LK" set "E. Madre" = 432 where id = 426;
update public."E. Madre LK" set "E. Madre" = 168 where id = 427;
update public."E. Madre LK" set "E. Madre" = 432 where id = 428;
update public."E. Madre LK" set "E. Madre" = 0 where id = 429;
update public."E. Madre LK" set "E. Madre" = 0 where id = 430;
update public."E. Madre LK" set "E. Madre" = 360 where id = 431;
update public."E. Madre LK" set "E. Madre" = 0 where id = 432;
update public."E. Madre LK" set "E. Madre" = 1092 where id = 433;
update public."E. Madre LK" set "E. Madre" = 984 where id = 434;
update public."E. Madre LK" set "E. Madre" = 0 where id = 435;
update public."E. Madre LK" set "E. Madre" = 660 where id = 436;
update public."E. Madre LK" set "E. Madre" = 684 where id = 437;
update public."E. Madre LK" set "E. Madre" = 768 where id = 438;
update public."E. Madre LK" set "E. Madre" = 6996 where id = 439;
update public."E. Madre LK" set "E. Madre" = 3600 where id = 440;
update public."E. Madre LK" set "E. Madre" = 552 where id = 441;
update public."E. Madre LK" set "E. Madre" = 0 where id = 442;
update public."E. Madre LK" set "E. Madre" = 0 where id = 443;
update public."E. Madre LK" set "E. Madre" = 312 where id = 444;
update public."E. Madre LK" set "E. Madre" = 288 where id = 445;
update public."E. Madre LK" set "E. Madre" = 108 where id = 446;
update public."E. Madre LK" set "E. Madre" = 48 where id = 447;
update public."E. Madre LK" set "E. Madre" = 912 where id = 448;
update public."E. Madre LK" set "E. Madre" = 0 where id = 449;
update public."E. Madre LK" set "E. Madre" = 0 where id = 450;
update public."E. Madre LK" set "E. Madre" = 0 where id = 451;
update public."E. Madre LK" set "E. Madre" = 0 where id = 452;
update public."E. Madre LK" set "E. Madre" = 108 where id = 453;
update public."E. Madre LK" set "E. Madre" = 0 where id = 454;
update public."E. Madre LK" set "E. Madre" = 180 where id = 455;
update public."E. Madre LK" set "E. Madre" = 0 where id = 456;
update public."E. Madre LK" set "E. Madre" = 0 where id = 457;
update public."E. Madre LK" set "E. Madre" = 4000 where id = 458;
update public."E. Madre LK" set "E. Madre" = 1500 where id = 459;
update public."E. Madre LK" set "E. Madre" = 480 where id = 460;
update public."E. Madre LK" set "E. Madre" = 0 where id = 461;
update public."E. Madre LK" set "E. Madre" = 120 where id = 462;
update public."E. Madre LK" set "E. Madre" = 24 where id = 463;
update public."E. Madre LK" set "E. Madre" = 312 where id = 464;
update public."E. Madre LK" set "E. Madre" = 180 where id = 465;
update public."E. Madre LK" set "E. Madre" = 480 where id = 466;
update public."E. Madre LK" set "E. Madre" = 0 where id = 467;
update public."E. Madre LK" set "E. Madre" = 144 where id = 468;
update public."E. Madre LK" set "E. Madre" = 0 where id = 469;
update public."E. Madre LK" set "E. Madre" = 0 where id = 470;
update public."E. Madre LK" set "E. Madre" = 48 where id = 471;
update public."E. Madre LK" set "E. Madre" = 120 where id = 472;
update public."E. Madre LK" set "E. Madre" = 480 where id = 473;
update public."E. Madre LK" set "E. Madre" = 336 where id = 474;
update public."E. Madre LK" set "E. Madre" = 0 where id = 475;
update public."E. Madre LK" set "E. Madre" = 0 where id = 476;
update public."E. Madre LK" set "E. Madre" = 284 where id = 477;
update public."E. Madre LK" set "E. Madre" = 0 where id = 478;
update public."E. Madre LK" set "E. Madre" = 0 where id = 479;
update public."E. Madre LK" set "E. Madre" = 912 where id = 480;
update public."E. Madre LK" set "E. Madre" = 700 where id = 481;
update public."E. Madre LK" set "E. Madre" = 120 where id = 482;
update public."E. Madre LK" set "E. Madre" = 120 where id = 483;
update public."E. Madre LK" set "E. Madre" = 0 where id = 484;
update public."E. Madre LK" set "E. Madre" = 0 where id = 485;
update public."E. Madre LK" set "E. Madre" = 0 where id = 486;
update public."E. Madre LK" set "E. Madre" = 4400 where id = 487;
update public."E. Madre LK" set "E. Madre" = 0 where id = 488;
update public."E. Madre LK" set "E. Madre" = 0 where id = 489;
update public."E. Madre LK" set "E. Madre" = 360 where id = 490;
update public."E. Madre LK" set "E. Madre" = 0 where id = 491;
update public."E. Madre LK" set "E. Madre" = 0 where id = 492;
update public."E. Madre LK" set "E. Madre" = 0 where id = 493;
update public."E. Madre LK" set "E. Madre" = 0 where id = 494;
update public."E. Madre LK" set "E. Madre" = 0 where id = 495;
update public."E. Madre LK" set "E. Madre" = 1800 where id = 496;
update public."E. Madre LK" set "E. Madre" = 4400 where id = 497;
update public."E. Madre LK" set "E. Madre" = 0 where id = 498;
update public."E. Madre LK" set "E. Madre" = 120 where id = 499;
update public."E. Madre LK" set "E. Madre" = 600 where id = 500;
update public."E. Madre LK" set "E. Madre" = 564 where id = 501;
update public."E. Madre LK" set "E. Madre" = 180 where id = 502;
update public."E. Madre LK" set "E. Madre" = 0 where id = 503;
update public."E. Madre LK" set "E. Madre" = 0 where id = 504;
update public."E. Madre LK" set "E. Madre" = 0 where id = 505;
update public."E. Madre LK" set "E. Madre" = 648 where id = 506;
update public."E. Madre LK" set "E. Madre" = 0 where id = 507;
update public."E. Madre LK" set "E. Madre" = 0 where id = 508;
update public."E. Madre LK" set "E. Madre" = 648 where id = 509;
update public."E. Madre LK" set "E. Madre" = 435 where id = 510;
update public."E. Madre LK" set "E. Madre" = 450 where id = 511;
update public."E. Madre LK" set "E. Madre" = 600 where id = 512;
update public."E. Madre LK" set "E. Madre" = 0 where id = 513;
update public."E. Madre LK" set "E. Madre" = 240 where id = 514;
update public."E. Madre LK" set "E. Madre" = 600 where id = 515;
update public."E. Madre LK" set "E. Madre" = 0 where id = 516;
update public."E. Madre LK" set "E. Madre" = 1440 where id = 517;
update public."E. Madre LK" set "E. Madre" = 240 where id = 518;
update public."E. Madre LK" set "E. Madre" = 480 where id = 519;
update public."E. Madre LK" set "E. Madre" = 800 where id = 520;
update public."E. Madre LK" set "E. Madre" = 120 where id = 521;
update public."E. Madre LK" set "E. Madre" = 240 where id = 522;
update public."E. Madre LK" set "E. Madre" = 360 where id = 523;
update public."E. Madre LK" set "E. Madre" = 600 where id = 524;
update public."E. Madre LK" set "E. Madre" = 0 where id = 525;
update public."E. Madre LK" set "E. Madre" = 36 where id = 526;
update public."E. Madre LK" set "E. Madre" = 0 where id = 527;
update public."E. Madre LK" set "E. Madre" = 1872 where id = 528;
update public."E. Madre LK" set "E. Madre" = 420 where id = 529;
update public."E. Madre LK" set "E. Madre" = 0 where id = 530;
update public."E. Madre LK" set "E. Madre" = 600 where id = 531;
update public."E. Madre LK" set "E. Madre" = 80 where id = 532;
update public."E. Madre LK" set "E. Madre" = 0 where id = 533;
update public."E. Madre LK" set "E. Madre" = 120 where id = 534;
update public."E. Madre LK" set "E. Madre" = 120 where id = 535;
update public."E. Madre LK" set "E. Madre" = 120 where id = 536;
update public."E. Madre LK" set "E. Madre" = 120 where id = 537;
update public."E. Madre LK" set "E. Madre" = 120 where id = 538;
update public."E. Madre LK" set "E. Madre" = 120 where id = 539;
update public."E. Madre LK" set "E. Madre" = 0 where id = 540;
update public."E. Madre LK" set "E. Madre" = 48 where id = 541;
update public."E. Madre LK" set "E. Madre" = 24 where id = 542;
update public."E. Madre LK" set "E. Madre" = 24 where id = 543;
update public."E. Madre LK" set "E. Madre" = 24 where id = 544;
update public."E. Madre LK" set "E. Madre" = 0 where id = 545;
update public."E. Madre LK" set "E. Madre" = 48 where id = 546;
update public."E. Madre LK" set "E. Madre" = 0 where id = 547;
update public."E. Madre LK" set "E. Madre" = 120 where id = 548;
update public."E. Madre LK" set "E. Madre" = 120 where id = 549;
update public."E. Madre LK" set "E. Madre" = 0 where id = 550;
update public."E. Madre LK" set "E. Madre" = 120 where id = 551;
update public."E. Madre LK" set "E. Madre" = 0 where id = 552;
update public."E. Madre LK" set "E. Madre" = 0 where id = 553;
update public."E. Madre LK" set "E. Madre" = 0 where id = 554;
update public."E. Madre LK" set "E. Madre" = 600 where id = 555;
update public."E. Madre LK" set "E. Madre" = 0 where id = 556;
update public."E. Madre LK" set "E. Madre" = 0 where id = 557;
update public."E. Madre LK" set "E. Madre" = 0 where id = 558;
update public."E. Madre LK" set "E. Madre" = 0 where id = 559;
update public."E. Madre LK" set "E. Madre" = 0 where id = 560;
update public."E. Madre LK" set "E. Madre" = 0 where id = 561;
update public."E. Madre LK" set "E. Madre" = 0 where id = 562;
update public."E. Madre LK" set "E. Madre" = 0 where id = 563;
update public."E. Madre LK" set "E. Madre" = 0 where id = 564;
update public."E. Madre LK" set "E. Madre" = 0 where id = 565;
update public."E. Madre LK" set "E. Madre" = 0 where id = 566;
update public."E. Madre LK" set "E. Madre" = 0 where id = 567;
update public."E. Madre LK" set "E. Madre" = 0 where id = 568;
update public."E. Madre LK" set "E. Madre" = 0 where id = 569;
update public."E. Madre LK" set "E. Madre" = 0 where id = 570;
update public."E. Madre LK" set "E. Madre" = 0 where id = 571;
update public."E. Madre LK" set "E. Madre" = 0 where id = 572;
update public."E. Madre LK" set "E. Madre" = null where id = 573;
update public."E. Madre LK" set "E. Madre" = 30000 where id = 574;
update public."E. Madre LK" set "E. Madre" = null where id = 575;
update public."E. Madre LK" set "E. Madre" = 0 where id = 576;

-- ---- columna "E. Madre" de E. Madre CH ----
-- alter table public."E. Madre CH" add column "E. Madre" integer;
update public."E. Madre CH" set "E. Madre" = 0 where id = 108;
update public."E. Madre CH" set "E. Madre" = 0 where id = 109;
update public."E. Madre CH" set "E. Madre" = 0 where id = 110;
update public."E. Madre CH" set "E. Madre" = 0 where id = 111;
update public."E. Madre CH" set "E. Madre" = 0 where id = 112;
update public."E. Madre CH" set "E. Madre" = 0 where id = 113;
update public."E. Madre CH" set "E. Madre" = 0 where id = 114;
update public."E. Madre CH" set "E. Madre" = 0 where id = 115;
update public."E. Madre CH" set "E. Madre" = 0 where id = 116;
update public."E. Madre CH" set "E. Madre" = 240 where id = 117;
update public."E. Madre CH" set "E. Madre" = 0 where id = 118;
update public."E. Madre CH" set "E. Madre" = 24 where id = 119;
update public."E. Madre CH" set "E. Madre" = 48 where id = 120;
update public."E. Madre CH" set "E. Madre" = 24 where id = 121;
update public."E. Madre CH" set "E. Madre" = 96 where id = 122;
update public."E. Madre CH" set "E. Madre" = 0 where id = 123;
update public."E. Madre CH" set "E. Madre" = 0 where id = 124;
update public."E. Madre CH" set "E. Madre" = 0 where id = 125;
update public."E. Madre CH" set "E. Madre" = 0 where id = 126;
update public."E. Madre CH" set "E. Madre" = 0 where id = 127;
update public."E. Madre CH" set "E. Madre" = 0 where id = 128;
update public."E. Madre CH" set "E. Madre" = 0 where id = 129;
update public."E. Madre CH" set "E. Madre" = 840 where id = 130;
update public."E. Madre CH" set "E. Madre" = 0 where id = 131;
update public."E. Madre CH" set "E. Madre" = 2976 where id = 132;
update public."E. Madre CH" set "E. Madre" = 0 where id = 133;
update public."E. Madre CH" set "E. Madre" = 0 where id = 134;
update public."E. Madre CH" set "E. Madre" = 0 where id = 135;
update public."E. Madre CH" set "E. Madre" = 0 where id = 136;
update public."E. Madre CH" set "E. Madre" = 0 where id = 137;
update public."E. Madre CH" set "E. Madre" = 0 where id = 138;
update public."E. Madre CH" set "E. Madre" = 0 where id = 139;
update public."E. Madre CH" set "E. Madre" = 0 where id = 140;
update public."E. Madre CH" set "E. Madre" = 0 where id = 141;
update public."E. Madre CH" set "E. Madre" = 360 where id = 142;
update public."E. Madre CH" set "E. Madre" = 0 where id = 143;
update public."E. Madre CH" set "E. Madre" = 0 where id = 144;
update public."E. Madre CH" set "E. Madre" = 0 where id = 145;
update public."E. Madre CH" set "E. Madre" = 0 where id = 146;
update public."E. Madre CH" set "E. Madre" = 0 where id = 147;
update public."E. Madre CH" set "E. Madre" = 480 where id = 148;
update public."E. Madre CH" set "E. Madre" = 0 where id = 149;
update public."E. Madre CH" set "E. Madre" = 60 where id = 150;
update public."E. Madre CH" set "E. Madre" = 0 where id = 151;
update public."E. Madre CH" set "E. Madre" = 0 where id = 152;
update public."E. Madre CH" set "E. Madre" = 48 where id = 153;
update public."E. Madre CH" set "E. Madre" = 72 where id = 154;
update public."E. Madre CH" set "E. Madre" = 48 where id = 155;
update public."E. Madre CH" set "E. Madre" = 24 where id = 156;
update public."E. Madre CH" set "E. Madre" = 36 where id = 157;
update public."E. Madre CH" set "E. Madre" = 12 where id = 158;
update public."E. Madre CH" set "E. Madre" = 48 where id = 159;
update public."E. Madre CH" set "E. Madre" = 48 where id = 160;
update public."E. Madre CH" set "E. Madre" = 24 where id = 161;
update public."E. Madre CH" set "E. Madre" = 0 where id = 162;
update public."E. Madre CH" set "E. Madre" = 0 where id = 163;
update public."E. Madre CH" set "E. Madre" = 0 where id = 164;
update public."E. Madre CH" set "E. Madre" = 0 where id = 165;
update public."E. Madre CH" set "E. Madre" = 0 where id = 166;
update public."E. Madre CH" set "E. Madre" = 0 where id = 167;
update public."E. Madre CH" set "E. Madre" = 0 where id = 168;
update public."E. Madre CH" set "E. Madre" = 0 where id = 169;
update public."E. Madre CH" set "E. Madre" = 0 where id = 170;
update public."E. Madre CH" set "E. Madre" = 0 where id = 171;
update public."E. Madre CH" set "E. Madre" = 0 where id = 172;
update public."E. Madre CH" set "E. Madre" = 0 where id = 173;
update public."E. Madre CH" set "E. Madre" = 0 where id = 174;
update public."E. Madre CH" set "E. Madre" = 0 where id = 175;
update public."E. Madre CH" set "E. Madre" = 0 where id = 176;
update public."E. Madre CH" set "E. Madre" = 0 where id = 177;
update public."E. Madre CH" set "E. Madre" = 0 where id = 178;
update public."E. Madre CH" set "E. Madre" = 0 where id = 179;
update public."E. Madre CH" set "E. Madre" = 0 where id = 180;
update public."E. Madre CH" set "E. Madre" = 96 where id = 181;
update public."E. Madre CH" set "E. Madre" = 618 where id = 182;
update public."E. Madre CH" set "E. Madre" = 504 where id = 183;
update public."E. Madre CH" set "E. Madre" = 0 where id = 184;
update public."E. Madre CH" set "E. Madre" = 3144 where id = 185;
update public."E. Madre CH" set "E. Madre" = 48 where id = 186;
update public."E. Madre CH" set "E. Madre" = 72 where id = 187;
update public."E. Madre CH" set "E. Madre" = 24 where id = 188;
update public."E. Madre CH" set "E. Madre" = 0 where id = 189;
update public."E. Madre CH" set "E. Madre" = 0 where id = 190;
update public."E. Madre CH" set "E. Madre" = 2280 where id = 191;
update public."E. Madre CH" set "E. Madre" = 192 where id = 192;
update public."E. Madre CH" set "E. Madre" = 0 where id = 193;
update public."E. Madre CH" set "E. Madre" = 48 where id = 194;
update public."E. Madre CH" set "E. Madre" = 72 where id = 195;
update public."E. Madre CH" set "E. Madre" = 24 where id = 196;
update public."E. Madre CH" set "E. Madre" = 24 where id = 197;
update public."E. Madre CH" set "E. Madre" = 372 where id = 198;
update public."E. Madre CH" set "E. Madre" = 0 where id = 199;
update public."E. Madre CH" set "E. Madre" = 480 where id = 200;
update public."E. Madre CH" set "E. Madre" = 0 where id = 201;
update public."E. Madre CH" set "E. Madre" = 600 where id = 202;
update public."E. Madre CH" set "E. Madre" = 264 where id = 203;
update public."E. Madre CH" set "E. Madre" = 96 where id = 204;
update public."E. Madre CH" set "E. Madre" = 96 where id = 205;
update public."E. Madre CH" set "E. Madre" = 24 where id = 206;
update public."E. Madre CH" set "E. Madre" = 0 where id = 207;
update public."E. Madre CH" set "E. Madre" = 0 where id = 208;
update public."E. Madre CH" set "E. Madre" = 0 where id = 209;
update public."E. Madre CH" set "E. Madre" = 0 where id = 210;
update public."E. Madre CH" set "E. Madre" = 0 where id = 211;
update public."E. Madre CH" set "E. Madre" = 288 where id = 212;
update public."E. Madre CH" set "E. Madre" = 48 where id = 213;
update public."E. Madre CH" set "E. Madre" = 24 where id = 214;
update public."E. Madre CH" set "E. Madre" = 480 where id = 215;
update public."E. Madre CH" set "E. Madre" = 504 where id = 216;
update public."E. Madre CH" set "E. Madre" = 0 where id = 217;
update public."E. Madre CH" set "E. Madre" = 0 where id = 218;
update public."E. Madre CH" set "E. Madre" = 0 where id = 219;
update public."E. Madre CH" set "E. Madre" = 0 where id = 220;
update public."E. Madre CH" set "E. Madre" = 240 where id = 221;
update public."E. Madre CH" set "E. Madre" = 0 where id = 222;
update public."E. Madre CH" set "E. Madre" = 0 where id = 223;
update public."E. Madre CH" set "E. Madre" = 0 where id = 224;
update public."E. Madre CH" set "E. Madre" = 0 where id = 225;
update public."E. Madre CH" set "E. Madre" = 0 where id = 226;
update public."E. Madre CH" set "E. Madre" = 1056 where id = 227;
update public."E. Madre CH" set "E. Madre" = 0 where id = 228;
update public."E. Madre CH" set "E. Madre" = 0 where id = 229;
update public."E. Madre CH" set "E. Madre" = 72 where id = 230;
update public."E. Madre CH" set "E. Madre" = 36 where id = 231;
update public."E. Madre CH" set "E. Madre" = 540 where id = 232;
update public."E. Madre CH" set "E. Madre" = 0 where id = 233;
update public."E. Madre CH" set "E. Madre" = 1296 where id = 234;
update public."E. Madre CH" set "E. Madre" = 0 where id = 235;
update public."E. Madre CH" set "E. Madre" = 204 where id = 236;
update public."E. Madre CH" set "E. Madre" = 312 where id = 237;
update public."E. Madre CH" set "E. Madre" = 0 where id = 238;
update public."E. Madre CH" set "E. Madre" = 0 where id = 239;
update public."E. Madre CH" set "E. Madre" = 1920 where id = 240;
update public."E. Madre CH" set "E. Madre" = 2328 where id = 241;
update public."E. Madre CH" set "E. Madre" = 0 where id = 242;
update public."E. Madre CH" set "E. Madre" = 120 where id = 243;
update public."E. Madre CH" set "E. Madre" = 96 where id = 244;
update public."E. Madre CH" set "E. Madre" = 0 where id = 245;
update public."E. Madre CH" set "E. Madre" = 2400 where id = 246;
update public."E. Madre CH" set "E. Madre" = 0 where id = 247;
update public."E. Madre CH" set "E. Madre" = 180 where id = 248;
update public."E. Madre CH" set "E. Madre" = 2400 where id = 249;
update public."E. Madre CH" set "E. Madre" = 0 where id = 250;
update public."E. Madre CH" set "E. Madre" = 120 where id = 251;
update public."E. Madre CH" set "E. Madre" = 48 where id = 252;
update public."E. Madre CH" set "E. Madre" = 48 where id = 253;
update public."E. Madre CH" set "E. Madre" = 168 where id = 254;
update public."E. Madre CH" set "E. Madre" = 192 where id = 255;
update public."E. Madre CH" set "E. Madre" = 1440 where id = 256;
update public."E. Madre CH" set "E. Madre" = 24 where id = 257;
update public."E. Madre CH" set "E. Madre" = 60 where id = 258;
update public."E. Madre CH" set "E. Madre" = 96 where id = 259;
update public."E. Madre CH" set "E. Madre" = 24 where id = 260;
update public."E. Madre CH" set "E. Madre" = 96 where id = 261;
update public."E. Madre CH" set "E. Madre" = 72 where id = 262;
update public."E. Madre CH" set "E. Madre" = 0 where id = 263;
update public."E. Madre CH" set "E. Madre" = 0 where id = 264;
update public."E. Madre CH" set "E. Madre" = 180 where id = 265;
update public."E. Madre CH" set "E. Madre" = 48 where id = 266;
update public."E. Madre CH" set "E. Madre" = 48 where id = 267;
update public."E. Madre CH" set "E. Madre" = 0 where id = 268;
update public."E. Madre CH" set "E. Madre" = 312 where id = 269;
update public."E. Madre CH" set "E. Madre" = 0 where id = 270;
update public."E. Madre CH" set "E. Madre" = 0 where id = 271;
update public."E. Madre CH" set "E. Madre" = 240 where id = 272;
update public."E. Madre CH" set "E. Madre" = 24 where id = 273;
update public."E. Madre CH" set "E. Madre" = 24 where id = 274;
update public."E. Madre CH" set "E. Madre" = 1440 where id = 275;
update public."E. Madre CH" set "E. Madre" = 228 where id = 276;
update public."E. Madre CH" set "E. Madre" = 0 where id = 277;
update public."E. Madre CH" set "E. Madre" = 0 where id = 278;
update public."E. Madre CH" set "E. Madre" = 0 where id = 279;
update public."E. Madre CH" set "E. Madre" = 60 where id = 280;
update public."E. Madre CH" set "E. Madre" = 276 where id = 281;
update public."E. Madre CH" set "E. Madre" = 864 where id = 282;
update public."E. Madre CH" set "E. Madre" = 336 where id = 283;
update public."E. Madre CH" set "E. Madre" = 0 where id = 284;
update public."E. Madre CH" set "E. Madre" = 144 where id = 285;
update public."E. Madre CH" set "E. Madre" = 696 where id = 286;
update public."E. Madre CH" set "E. Madre" = 0 where id = 287;
update public."E. Madre CH" set "E. Madre" = 0 where id = 288;
update public."E. Madre CH" set "E. Madre" = 0 where id = 289;
update public."E. Madre CH" set "E. Madre" = 0 where id = 290;
update public."E. Madre CH" set "E. Madre" = 0 where id = 291;
update public."E. Madre CH" set "E. Madre" = 0 where id = 292;
update public."E. Madre CH" set "E. Madre" = 0 where id = 293;
update public."E. Madre CH" set "E. Madre" = 0 where id = 294;
update public."E. Madre CH" set "E. Madre" = 0 where id = 295;
update public."E. Madre CH" set "E. Madre" = 0 where id = 296;
update public."E. Madre CH" set "E. Madre" = 0 where id = 297;
update public."E. Madre CH" set "E. Madre" = 0 where id = 298;
update public."E. Madre CH" set "E. Madre" = 0 where id = 299;
update public."E. Madre CH" set "E. Madre" = 0 where id = 300;
update public."E. Madre CH" set "E. Madre" = 0 where id = 301;
update public."E. Madre CH" set "E. Madre" = 0 where id = 302;
update public."E. Madre CH" set "E. Madre" = 0 where id = 303;
update public."E. Madre CH" set "E. Madre" = 0 where id = 304;
update public."E. Madre CH" set "E. Madre" = 0 where id = 305;
update public."E. Madre CH" set "E. Madre" = 0 where id = 306;
update public."E. Madre CH" set "E. Madre" = 0 where id = 307;
update public."E. Madre CH" set "E. Madre" = 0 where id = 308;
update public."E. Madre CH" set "E. Madre" = 0 where id = 309;
update public."E. Madre CH" set "E. Madre" = 0 where id = 310;
update public."E. Madre CH" set "E. Madre" = 0 where id = 311;
update public."E. Madre CH" set "E. Madre" = 0 where id = 312;
update public."E. Madre CH" set "E. Madre" = 0 where id = 313;
update public."E. Madre CH" set "E. Madre" = 0 where id = 314;
update public."E. Madre CH" set "E. Madre" = 0 where id = 315;
update public."E. Madre CH" set "E. Madre" = 0 where id = 316;
update public."E. Madre CH" set "E. Madre" = 0 where id = 317;
update public."E. Madre CH" set "E. Madre" = 0 where id = 318;
update public."E. Madre CH" set "E. Madre" = 0 where id = 319;
update public."E. Madre CH" set "E. Madre" = 0 where id = 320;
update public."E. Madre CH" set "E. Madre" = 0 where id = 321;
update public."E. Madre CH" set "E. Madre" = 0 where id = 322;
update public."E. Madre CH" set "E. Madre" = 0 where id = 323;
update public."E. Madre CH" set "E. Madre" = 0 where id = 324;
update public."E. Madre CH" set "E. Madre" = 0 where id = 325;
update public."E. Madre CH" set "E. Madre" = 0 where id = 326;
update public."E. Madre CH" set "E. Madre" = 0 where id = 327;
update public."E. Madre CH" set "E. Madre" = 0 where id = 328;
update public."E. Madre CH" set "E. Madre" = 0 where id = 329;
update public."E. Madre CH" set "E. Madre" = 0 where id = 330;
update public."E. Madre CH" set "E. Madre" = 0 where id = 331;
update public."E. Madre CH" set "E. Madre" = 0 where id = 332;
update public."E. Madre CH" set "E. Madre" = 0 where id = 333;
update public."E. Madre CH" set "E. Madre" = 0 where id = 334;
update public."E. Madre CH" set "E. Madre" = 0 where id = 335;
update public."E. Madre CH" set "E. Madre" = 0 where id = 336;
update public."E. Madre CH" set "E. Madre" = 0 where id = 337;
update public."E. Madre CH" set "E. Madre" = 0 where id = 338;
update public."E. Madre CH" set "E. Madre" = 0 where id = 339;
update public."E. Madre CH" set "E. Madre" = 0 where id = 340;
update public."E. Madre CH" set "E. Madre" = 0 where id = 341;
update public."E. Madre CH" set "E. Madre" = 0 where id = 342;
update public."E. Madre CH" set "E. Madre" = 0 where id = 343;
update public."E. Madre CH" set "E. Madre" = 0 where id = 344;
update public."E. Madre CH" set "E. Madre" = 0 where id = 345;
update public."E. Madre CH" set "E. Madre" = 0 where id = 346;
update public."E. Madre CH" set "E. Madre" = 0 where id = 347;
update public."E. Madre CH" set "E. Madre" = 0 where id = 348;
update public."E. Madre CH" set "E. Madre" = 0 where id = 349;
update public."E. Madre CH" set "E. Madre" = 0 where id = 350;
update public."E. Madre CH" set "E. Madre" = 0 where id = 351;
update public."E. Madre CH" set "E. Madre" = 0 where id = 352;
update public."E. Madre CH" set "E. Madre" = 0 where id = 353;
update public."E. Madre CH" set "E. Madre" = 0 where id = 354;
update public."E. Madre CH" set "E. Madre" = 0 where id = 355;
update public."E. Madre CH" set "E. Madre" = 0 where id = 356;
update public."E. Madre CH" set "E. Madre" = 0 where id = 357;
update public."E. Madre CH" set "E. Madre" = 0 where id = 358;
update public."E. Madre CH" set "E. Madre" = 0 where id = 359;
update public."E. Madre CH" set "E. Madre" = 0 where id = 360;
update public."E. Madre CH" set "E. Madre" = 0 where id = 361;
update public."E. Madre CH" set "E. Madre" = 0 where id = 362;
update public."E. Madre CH" set "E. Madre" = 168 where id = 363;
update public."E. Madre CH" set "E. Madre" = 336 where id = 364;
update public."E. Madre CH" set "E. Madre" = 0 where id = 365;
update public."E. Madre CH" set "E. Madre" = 0 where id = 366;
update public."E. Madre CH" set "E. Madre" = 0 where id = 367;
update public."E. Madre CH" set "E. Madre" = 0 where id = 368;
update public."E. Madre CH" set "E. Madre" = 0 where id = 369;
update public."E. Madre CH" set "E. Madre" = 0 where id = 370;
update public."E. Madre CH" set "E. Madre" = 0 where id = 371;
update public."E. Madre CH" set "E. Madre" = 0 where id = 372;
update public."E. Madre CH" set "E. Madre" = 0 where id = 373;
update public."E. Madre CH" set "E. Madre" = 0 where id = 374;
update public."E. Madre CH" set "E. Madre" = 0 where id = 375;
update public."E. Madre CH" set "E. Madre" = 24 where id = 376;
update public."E. Madre CH" set "E. Madre" = 0 where id = 377;
update public."E. Madre CH" set "E. Madre" = 240 where id = 378;
update public."E. Madre CH" set "E. Madre" = 0 where id = 379;
update public."E. Madre CH" set "E. Madre" = 1200 where id = 380;
update public."E. Madre CH" set "E. Madre" = 0 where id = 381;
update public."E. Madre CH" set "E. Madre" = 240 where id = 382;
update public."E. Madre CH" set "E. Madre" = 0 where id = 383;
update public."E. Madre CH" set "E. Madre" = 1080 where id = 384;
update public."E. Madre CH" set "E. Madre" = 240 where id = 385;
update public."E. Madre CH" set "E. Madre" = 276 where id = 386;
update public."E. Madre CH" set "E. Madre" = 792 where id = 387;
update public."E. Madre CH" set "E. Madre" = 0 where id = 388;
update public."E. Madre CH" set "E. Madre" = 0 where id = 389;
update public."E. Madre CH" set "E. Madre" = 0 where id = 390;
update public."E. Madre CH" set "E. Madre" = 24 where id = 391;
update public."E. Madre CH" set "E. Madre" = 0 where id = 392;
update public."E. Madre CH" set "E. Madre" = 0 where id = 393;
update public."E. Madre CH" set "E. Madre" = 1680 where id = 394;
update public."E. Madre CH" set "E. Madre" = 0 where id = 395;
update public."E. Madre CH" set "E. Madre" = 0 where id = 396;
update public."E. Madre CH" set "E. Madre" = 0 where id = 397;
update public."E. Madre CH" set "E. Madre" = 0 where id = 398;
update public."E. Madre CH" set "E. Madre" = 0 where id = 399;
update public."E. Madre CH" set "E. Madre" = 0 where id = 400;
update public."E. Madre CH" set "E. Madre" = 120 where id = 401;
update public."E. Madre CH" set "E. Madre" = 0 where id = 402;
update public."E. Madre CH" set "E. Madre" = 0 where id = 403;
update public."E. Madre CH" set "E. Madre" = 204 where id = 404;
update public."E. Madre CH" set "E. Madre" = 252 where id = 405;
update public."E. Madre CH" set "E. Madre" = 0 where id = 406;
update public."E. Madre CH" set "E. Madre" = 0 where id = 407;
update public."E. Madre CH" set "E. Madre" = 0 where id = 408;
update public."E. Madre CH" set "E. Madre" = 0 where id = 409;

-- =====================================================================
-- VISTAS BORRADAS EN LA MISMA LIMPIEZA. Usaban el numero "E. Madre" de E. Madre LK/CH como
-- "consumo" de piezas por tallerista: otra proyeccion con otro criterio (numero fijo de marzo).
-- Sin consumidores (ninguna funcion, vista, front ni doc las referencia). Restore: primero
-- recrear la columna "E. Madre" (arriba), despues estas dos.
-- =====================================================================
create or replace view public.v_debug_piezas_consumo as
 WITH piezas AS (
   SELECT r."Tallerista" AS tallerista, r.pieza, r.cod_articulos FROM v_piezas_por_tallerista_resumen r
 ), codigos_separados AS (
   SELECT p.tallerista, p.pieza, p.cod_articulos, TRIM(x.cod) AS cod_original,
          regexp_replace(TRIM(x.cod), '\D', '', 'g') AS cod_solo_numeros,
          lpad(regexp_replace(TRIM(x.cod), '\D', '', 'g'), 3, '0') AS cod_norm_3,
          lpad(regexp_replace(TRIM(x.cod), '\D', '', 'g'), 4, '0') AS cod_norm_4
   FROM piezas p CROSS JOIN LATERAL unnest(string_to_array(COALESCE(p.cod_articulos, ''), ',')) x(cod)
 ), ch AS (
   SELECT TRIM("Cod") AS cod_ch_original, regexp_replace(TRIM("Cod"), '\D', '', 'g') AS cod_ch_solo_numeros,
          lpad(regexp_replace(TRIM("Cod"), '\D', '', 'g'), 3, '0') AS cod_ch_norm_3,
          lpad(regexp_replace(TRIM("Cod"), '\D', '', 'g'), 4, '0') AS cod_ch_norm_4,
          "E. Madre" AS e_madre_ch
   FROM "E. Madre CH"
 ), lk AS (
   SELECT TRIM("Cod") AS cod_lk_original, regexp_replace(TRIM("Cod"), '\D', '', 'g') AS cod_lk_solo_numeros,
          lpad(regexp_replace(TRIM("Cod"), '\D', '', 'g'), 3, '0') AS cod_lk_norm_3,
          lpad(regexp_replace(TRIM("Cod"), '\D', '', 'g'), 4, '0') AS cod_lk_norm_4,
          "E. Madre" AS e_madre_lk
   FROM "E. Madre LK"
 )
 SELECT c.tallerista, c.pieza, c.cod_articulos, c.cod_original, c.cod_solo_numeros, c.cod_norm_3, c.cod_norm_4,
        ch.cod_ch_original, ch.e_madre_ch, lk.cod_lk_original, lk.e_madre_lk
 FROM codigos_separados c
 LEFT JOIN ch ON ch.cod_ch_original = c.cod_original OR ch.cod_ch_solo_numeros = c.cod_solo_numeros OR ch.cod_ch_norm_3 = c.cod_norm_3 OR ch.cod_ch_norm_4 = c.cod_norm_4
 LEFT JOIN lk ON lk.cod_lk_original = c.cod_original OR lk.cod_lk_solo_numeros = c.cod_solo_numeros OR lk.cod_lk_norm_3 = c.cod_norm_3 OR lk.cod_lk_norm_4 = c.cod_norm_4;

create or replace view public.v_piezas_por_tallerista_consumo_final as
 WITH piezas_base AS (
   SELECT r."Tallerista"::text AS tallerista, r.pieza, r.cod_articulos FROM v_piezas_por_tallerista_resumen r
 ), codigos_separados AS (
   SELECT p.tallerista, p.pieza, p.cod_articulos, TRIM(x.cod) AS cod_original, lpad(TRIM(x.cod), 3, '0') AS cod_normalizado
   FROM piezas_base p CROSS JOIN LATERAL unnest(string_to_array(COALESCE(p.cod_articulos, ''), ',')) x(cod)
   WHERE TRIM(x.cod) <> ''
 ), consumos_ch AS (
   SELECT lpad(TRIM("Cod"), 3, '0') AS cod_normalizado, COALESCE("E. Madre", 0)::bigint AS consumo_ch
   FROM "E. Madre CH" WHERE TRIM("Cod") ~ '^[0-9]+$'
 ), consumos_lk AS (
   SELECT lpad(TRIM("Cod"), 3, '0') AS cod_normalizado, COALESCE("E. Madre", 0)::bigint AS consumo_lk
   FROM "E. Madre LK" WHERE TRIM("Cod") ~ '^[0-9]+$'
 ), consumos_por_codigo AS (
   SELECT COALESCE(ch.cod_normalizado, lk.cod_normalizado) AS cod_normalizado,
          COALESCE(ch.consumo_ch, 0) AS consumo_ch, COALESCE(lk.consumo_lk, 0) AS consumo_lk,
          GREATEST(COALESCE(ch.consumo_ch, 0), COALESCE(lk.consumo_lk, 0)) AS consumo_elegido
   FROM consumos_ch ch FULL JOIN consumos_lk lk ON lk.cod_normalizado = ch.cod_normalizado
 ), detalle_final AS (
   SELECT c.tallerista, c.pieza, c.cod_articulos, c.cod_original, c.cod_normalizado,
          COALESCE(cp.consumo_ch, 0) AS consumo_ch, COALESCE(cp.consumo_lk, 0) AS consumo_lk,
          COALESCE(cp.consumo_elegido, 0) AS consumo_codigo
   FROM codigos_separados c LEFT JOIN consumos_por_codigo cp ON cp.cod_normalizado = c.cod_normalizado
 )
 SELECT tallerista, pieza,
        string_agg(cod_original, ', ' ORDER BY cod_original) AS cod_articulos,
        string_agg(cod_original || ': ' || consumo_codigo::text, ' | ' ORDER BY cod_original) AS detalle_consumo,
        sum(consumo_codigo) AS total_consumo
 FROM detalle_final GROUP BY tallerista, pieza;

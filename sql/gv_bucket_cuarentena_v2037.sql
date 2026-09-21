-- v20.37 — el Excel de deuda queda GUARDADO.
--
-- Luis, 2026-09-21: "no tenes los ultimos archivos subidos de deuda?". No: el archivo nunca se
-- subio a ningun lado. Se parsea en el navegador con SheetJS y a la base llega solo lo mapeado.
-- Medido: no habia bucket de cuarentena, y de los 13 buckets del proyecto el unico .xls* es
-- planify_bot-assets/prueba-excel-3.xlsx (17/07). Lo ultimo cargado eran los totales del 17/09.
--
-- El front (cuarImportGuardar) sube el archivo DESPUES del guardado y con su propio catch.

insert into storage.buckets (id, name, public)
values ('cuarentena', 'cuarentena', false)
on conflict (id) do nothing;

do $$ begin
  if not exists (select 1 from pg_policy where polname = 'gv_cuarentena_files_lee') then
    create policy gv_cuarentena_files_lee on storage.objects
      for select to authenticated
      using (bucket_id = 'cuarentena' and es_supervisor_virgilio());
  end if;
  if not exists (select 1 from pg_policy where polname = 'gv_cuarentena_files_sube') then
    create policy gv_cuarentena_files_sube on storage.objects
      for insert to authenticated
      with check (bucket_id = 'cuarentena' and es_supervisor_virgilio());
  end if;
end $$;

-- Rollback:
--   drop policy gv_cuarentena_files_lee on storage.objects;
--   drop policy gv_cuarentena_files_sube on storage.objects;
--   delete from storage.buckets where id = 'cuarentena';   -- vaciar los objetos primero

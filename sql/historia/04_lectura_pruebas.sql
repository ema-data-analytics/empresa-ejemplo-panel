-- Pruebas como el usuario real (Anibal, super activo). Solo lectura; al final se deshace todo igual.
do $$
declare res text := ''; t text; n numeric; u uuid := 'a7581332-ef44-4d49-af7a-ffc85b943ce2';
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select ultima_venta::text into t from public.api_fecha_corte();
  res := res || 'P01 funcion ORIGINAL con usuario logueado (muestra el problema): ultima_venta=' || coalesce(t, 'VACIO') || chr(10);
  select ultima_venta::text || ' / ' || corte_recomendado::text into t from public.api_fecha_corte_v2();
  res := res || 'P02 fecha_corte_v2 con usuario logueado (esperado 2026-06-22 / 2024-06-21): ' || coalesce(t, 'VACIO') || case when t = '2026-06-22 / 2024-06-21' then ' PASA' else ' FALLA' end || chr(10);
  select venta_neta_total into n from public.api_ventas_resumen_v2(null, null, null);
  res := res || 'P03 ventas_resumen_v2 con usuario logueado (esperado 2273491.99): ' || coalesce(n::text, 'VACIO') || case when n = 2273491.99 then ' PASA' else ' FALLA' end || chr(10);
  select margen_neto into n from public.api_ventas_resumen_v2(null, null, null);
  res := res || 'P04 margen con usuario logueado (esperado 299884.61): ' || coalesce(n::text, 'VACIO') || case when n = 299884.61 then ' PASA' else ' FALLA' end || chr(10);
  select round(sum(venta_total), 2) into n from public.api_ventas_por_mes_v2(null, null, null);
  res := res || 'P05 por mes con usuario logueado suma 2273491.99: ' || coalesce(n::text, 'VACIO') || case when n = 2273491.99 then ' PASA' else ' FALLA' end || chr(10);
  begin
    select count(*) into n from public.gva12;
    res := res || 'P06 lectura DIRECTA de tablas sigue cerrada (0 filas): ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  exception when others then res := res || 'P06 lectura DIRECTA de tablas sigue cerrada: PASA (' || sqlerrm || ')' || chr(10); end;
  reset role;
  select string_agg(p.proname, ',') into t from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'api\_%\_v2' and has_function_privilege('anon', p.oid, 'execute');
  res := res || 'P07 ninguna _v2 abierta al anonimo: ' || coalesce(t, 'ninguna') || case when t is null then ' PASA' else ' FALLA' end || chr(10);
  select string_agg(p.proname, ',') into t from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'api\_%\_v2' and p.prosecdef and not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%');
  res := res || 'P08 toda _v2 con permiso de dueno tiene search_path fijo: ' || coalesce(t, 'todas') || case when t is null then ' PASA' else ' FALLA' end || chr(10);
  raise exception 'RESULTADOS (solo lectura)%', chr(10) || res;
end $$;

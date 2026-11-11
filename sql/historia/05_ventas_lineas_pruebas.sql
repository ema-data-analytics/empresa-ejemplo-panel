-- PRUEBAS (como el usuario real, solo lectura)
do $$
declare res text := ''; n numeric; m numeric; k bigint; t text; u uuid := 'a7581332-ef44-4d49-af7a-ffc85b943ce2';
begin
  select count(*) into k from public.vista_venta_linea_v2 where estado_comprobante <> 'ANU';
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*), round(sum(venta),2), round(sum(margen),2) into n, m, t from public.api_ventas_lineas_v2();
  res := res || 'P01 renglones = vista sin anulados (' || k || '): ' || n || case when n = k then ' PASA' else ' FALLA' end || chr(10);
  res := res || 'P02 venta total 2273491.99: ' || m || case when m = 2273491.99 then ' PASA' else ' FALLA' end || chr(10);
  res := res || 'P03 margen total 299884.61: ' || t || case when t = '299884.61' then ' PASA' else ' FALLA' end || chr(10);
  select round(sum(venta),2) into m from public.api_ventas_lineas_v2('2023-01-01', '2023-12-31');
  select round(sum(venta_total),2) into n from public.api_ventas_por_mes_v2('2023-01-01', '2023-12-31', null);
  res := res || 'P04 filtro de fechas 2023 = ventas por mes 2023 (' || n || '): ' || m || case when m = n then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from public.api_ventas_lineas_v2() where cliente like 'Cliente %';
  res := res || 'P05 renglones sin nombre de cliente: ' || n || chr(10);
  select count(*) into n from public.api_ventas_lineas_v2() where vendedor like 'Vendedor %';
  res := res || 'P06 renglones sin nombre de vendedor: ' || n || chr(10);
  select count(*) into n from public.api_ventas_lineas_v2() where provincia = 'Sin provincia';
  res := res || 'P07 renglones sin provincia: ' || n || chr(10);
  select string_agg(distinct tipo_comprobante || '(' || signo || ')', ', ') into t from public.api_ventas_lineas_v2();
  res := res || 'P08 tipos de comprobante y signo: ' || t || chr(10);
  reset role;
  res := res || 'P09 anonimo no puede ejecutar: ' || case when not has_function_privilege('anon', 'public.api_ventas_lineas_v2(date,date)', 'execute') then 'PASA' else 'FALLA' end || chr(10);
  raise exception 'RESULTADOS (solo lectura)%', chr(10) || res;
end $$;

-- PRUEBAS Compras (como el usuario real, solo lectura)
do $$
declare res text := ''; n numeric; m numeric; k numeric; t text; u uuid := 'a7581332-ef44-4d49-af7a-ffc85b943ce2';
  r record;
begin
  select * into r from public.api_compras_resumen(null, null);
  select count(*), round(sum(neto),2), round(sum(total),2) into k, m, n from public.api_compras_comprobantes_v2();
  res := res || 'P01 comprobantes = resumen existente (' || r.comprobantes || '): ' || k || case when k = r.comprobantes then ' PASA' else ' FALLA' end || chr(10);
  res := res || 'P02 neto gravado = resumen (' || r.neto_gravado || '): ' || m || case when m = r.neto_gravado then ' PASA' else ' FALLA' end || chr(10);
  res := res || 'P03 total = resumen (' || r.total || '): ' || n || case when n = r.total then ' PASA' else ' FALLA' end || chr(10);
  select round(sum(iva),2) into n from public.api_compras_comprobantes_v2();
  res := res || 'P04 IVA = resumen (' || r.iva || '): ' || n || case when n = r.iva then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from (select c.cod_provee, round(sum(c.total),2) s from public.api_compras_comprobantes_v2() c group by 1) a
    join public.api_compras_por_proveedor(null, null, 100000) b on b.cod_provee = a.cod_provee where a.s <> b.total;
  res := res || 'P05 total por proveedor = funcion existente (0 diferencias): ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select count(*), round(sum(importe),2) into k, m from public.api_compras_articulos_v2();
  select count(*) into n from public.cpa46 l left join public.cpa04 c on c.id_cpa04 = l.id_cpa04 where coalesce(c.estado,'') <> 'ANU';
  res := res || 'P06 renglones de articulos = cpa46 sin anulados (' || n || '): ' || k || case when k = n then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from public.api_compras_articulos_v2() where n_comp is null;
  res := res || 'P07 renglones de articulos sin comprobante: ' || n || chr(10);
  select count(*) into n from public.api_compras_comprobantes_v2() where vencimiento is null;
  res := res || 'P08 comprobantes sin vencimiento (1800 = sin fecha): ' || n || chr(10);
  select string_agg(estado || ':' || c, ', ') into t from (select estado, count(*) c from public.api_compras_comprobantes_v2() group by 1 order by 2 desc) x;
  res := res || 'P09 estados: ' || t || chr(10);
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select round(sum(total),2) into m from public.api_compras_comprobantes_v2();
  select count(*) into k from public.api_compras_articulos_v2();
  reset role;
  res := res || 'P10 con usuario logueado se leen los mismos datos (' || r.total || ' / ' || k || ' renglones): ' || m || case when m = r.total and k > 0 then ' PASA' else ' FALLA' end || chr(10);
  res := res || 'P11 anonimo no puede ejecutar: ' || case when not has_function_privilege('anon','public.api_compras_comprobantes_v2(date,date)','execute') and not has_function_privilege('anon','public.api_compras_articulos_v2(date,date)','execute') then 'PASA' else 'FALLA' end || chr(10);
  select round(sum(total),2) into m from public.api_compras_comprobantes_v2('2023-01-01','2023-12-31');
  select total into n from public.api_compras_resumen('2023-01-01','2023-12-31');
  res := res || 'P12 filtro 2023 = resumen 2023 (' || n || '): ' || m || case when m = n then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from (select a.id_cpa04, sum(a.importe) s from public.api_compras_articulos_v2() a group by 1) a
    join public.api_compras_comprobantes_v2() c on c.id_cpa04 = a.id_cpa04 where abs(a.s - (c.neto + c.exento)) > 0.05;
  res := res || 'P13 renglones de articulos = neto + exento de su comprobante (0 diferencias): ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select round(sum(total - neto - exento - iva),2), count(*) filter (where provincia ~ '^[0-9]+$') into m, k from public.api_compras_comprobantes_v2();
  res := res || 'P14 provincia con nombre, no codigo (0 codigos sueltos): ' || k || case when k = 0 then ' PASA' else ' FALLA' end || chr(10);
  select string_agg(provincia || ':' || c, ', ') into t from (select provincia, count(*) c from public.api_compras_comprobantes_v2() group by 1 order by 2 desc) x;
  res := res || 'P15 provincias: ' || t || ' | otros impuestos y percepciones (total - neto - exento - IVA): ' || m || chr(10);
  raise exception 'RESULTADOS (solo lectura)%', chr(10) || res;
end $$;

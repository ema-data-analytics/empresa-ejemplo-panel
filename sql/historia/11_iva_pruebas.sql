-- PRUEBAS IVA (solo lectura: todo se deshace al final)
do $$
declare res text := ''; n numeric; m numeric; k numeric; t text; u uuid := 'a7581332-ef44-4d49-af7a-ffc85b943ce2';
begin
  select count(*) into k from public.api_iva_ventas_v2();
  select count(*) into n from public.gva12 where coalesce(trim(estado), '') <> 'ANU' and trim(t_comp) <> 'REC';
  res := res || 'I01 comprobantes de venta = gva12 sin anulados ni recibos (' || n || '): ' || k || case when k = n then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from public.api_iva_ventas_v2() v where v.signo <> case when v.t_comp in ('CDE', 'AJC', 'N/C') then -1 else 1 end;
  res := res || 'I02 el signo por tipo interno de Tango coincide con el codigo (creditos CDE, AJC, N/C restan; 0 diferencias): ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select round(sum(iva), 2) into m from public.api_iva_ventas_v2();
  select round(sum(case when trim(t_comp) in ('CDE', 'AJC', 'N/C') then -1 else 1 end * importe_iv), 2) into n from public.gva12 where coalesce(trim(estado), '') <> 'ANU' and trim(t_comp) <> 'REC';
  res := res || 'I03 debito fiscal = IVA de gva12 con signo (' || n || '): ' || m || case when m = n then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from public.api_iva_ventas_v2() where abs(total - (gravado + exento + iva + internos + otros)) >= 0.01;
  res := res || 'I04 ventas: total = gravado + exento + IVA + internos + otros (0 diferencias): ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select count(*), round(sum(iva), 2) into k, m from public.api_iva_compras_v2();
  select count(*), round(sum(iva), 2) into n, t from public.api_compras_comprobantes_v2();
  res := res || 'I05 credito fiscal = IVA del modulo Compras ya probado (' || n || ' comprobantes, ' || t || '): ' || k || ', ' || m || case when k = n and m = t::numeric then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from public.api_iva_compras_v2() where abs(iva - (iva_21 + iva_105 + iva_27 + iva_otras)) >= 0.01;
  res := res || 'I06 compras: IVA = suma por alicuota (0 diferencias): ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from public.api_iva_compras_v2() where abs(total - (neto + exento + iva + otros)) >= 0.01;
  res := res || 'I07 compras: total = neto + exento + IVA + otros (0 diferencias): ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select round(sum(otros), 2) into m from public.api_iva_compras_v2();
  select round(sum(total - neto - exento - iva), 2) into n from public.api_compras_comprobantes_v2();
  res := res || 'I08 compras: otros impuestos y percepciones = modulo Compras (' || n || '): ' || m || case when m = n then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into k from public.api_iva_ventas_v2('2023-01-01', '2023-12-31');
  select count(*) into n from public.gva12 where coalesce(trim(estado), '') <> 'ANU' and trim(t_comp) <> 'REC' and fecha_emis::date between '2023-01-01' and '2023-12-31';
  res := res || 'I09 filtro 2023 en ventas (' || n || '): ' || k || case when k = n then ' PASA' else ' FALLA' end || chr(10);
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into k from public.api_iva_ventas_v2();
  select count(*) into m from public.api_iva_compras_v2();
  reset role;
  res := res || 'I10 con usuario logueado (' || k || ' ventas, ' || m || ' compras): ' || case when k > 0 and m > 0 then 'PASA' else 'FALLA' end || chr(10);
  res := res || 'I11 anonimo no puede ejecutar: ' || case when not has_function_privilege('anon', 'public.api_iva_ventas_v2(date,date)', 'execute') and not has_function_privilege('anon', 'public.api_iva_compras_v2(date,date)', 'execute') then 'PASA' else 'FALLA' end || chr(10);
  select string_agg(a || ' debito ' || d || ' credito ' || c || ' saldo ' || (d - c), ' | ' order by a) into t from (
    select a, coalesce(sum(d), 0) d, coalesce(sum(c), 0) c from (
      select to_char(fecha, 'YYYY') a, iva d, 0 c from public.api_iva_ventas_v2() union all select to_char(fecha, 'YYYY'), 0, iva from public.api_iva_compras_v2()) x group by 1) y;
  res := res || 'I12 posicion de IVA por año: ' || t || chr(10);
  select string_agg(t_comp || ':' || c || ' ' || s, ', ') into t from (select t_comp, count(*) c, sum(iva) s from public.api_iva_ventas_v2() group by 1 order by 1) x;
  res := res || 'I13 ventas por tipo (IVA con signo): ' || t || chr(10);
  select 'sin cuit en ventas: ' || count(*) filter (where nullif(trim(coalesce(cuit, '')), '') is null) || ' de ' || count(*) into t from public.api_iva_ventas_v2();
  res := res || 'I14 ' || t || '; comprobantes AFIP cargados para cruzar: ' || (select count(*) from public.comprobante_afip_compras) || chr(10);
  raise exception 'RESULTADOS (solo lectura)%', chr(10) || res;
end $$;

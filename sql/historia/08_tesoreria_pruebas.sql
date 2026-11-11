-- PRUEBAS Tesoreria (solo lectura: todo se deshace al final)
do $$
declare res text := ''; n numeric; m numeric; k numeric; t text; u uuid := 'a7581332-ef44-4d49-af7a-ffc85b943ce2';
begin
  select count(*) into k from public.api_tesoreria_cuentas_v2();
  res := res || 'E01 cuentas = filas de sba01 (' || (select count(*) from public.sba01) || '): ' || k || case when k = (select count(*) from public.sba01) then ' PASA' else ' FALLA' end || chr(10);
  select count(*), sum(debe), sum(haber) into k, m, n from public.api_tesoreria_movimientos_v2();
  res := res || 'E02 movimientos = filas de sba05 (' || (select count(*) from public.sba05) || '): ' || k || case when k = (select count(*) from public.sba05) then ' PASA' else ' FALLA' end || chr(10);
  res := res || 'E03 total debe = total haber (' || m || ' / ' || n || ')' || case when m = n then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from (select id_sba04 from public.api_tesoreria_movimientos_v2() group by 1 having abs(sum(importe)) >= 0.01) x;
  res := res || 'E04 cada comprobante cierra (debe = haber); desbalanceados: ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from public.api_tesoreria_cuentas_v2() c
    left join (select cod_cta, sum(importe) s from public.api_tesoreria_movimientos_v2() group by 1) x using (cod_cta)
    where abs(c.saldo - (c.saldo_inicial + coalesce(x.s, 0))) >= 0.01;
  res := res || 'E05 saldo de cada cuenta = saldo inicial + movimientos (0 diferencias): ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select count(*), string_agg(cod_cta || ' ' || cuenta || ' ' || diferencia_ficha, ', ') into k, t from public.api_tesoreria_cuentas_v2() where abs(diferencia_ficha) >= 0.01;
  res := res || 'E06 cuentas donde el saldo guardado en la ficha de Tango no coincide con sus movimientos: ' || k || ' (' || coalesce(t, '') || ')' || chr(10);
  select count(*) into n from (select cod_cta, sum(importe) s from public.api_tesoreria_movimientos_v2() where situacion in ('A', 'C') group by 1) x where abs(s) >= 0.01;
  res := res || 'E07 anulados y sus reversiones se cancelan en cada cuenta (0 cuentas con resto): ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select round(sum(importe), 2) into m from public.api_tesoreria_cheques_v2() where estado = 'C';
  select round(sum(saldo), 2) into n from public.api_tesoreria_cuentas_v2() where tipo = 'C';
  res := res || 'E08 cheques en cartera (C) = saldo de la cuenta de valores a depositar (' || n || '): ' || m || case when m = n then ' PASA' else ' FALLA' end || chr(10);
  select round(sum(importe), 2) into m from public.api_tesoreria_cheques_v2() where estado = 'R';
  select round(sum(saldo), 2) into n from public.api_tesoreria_cuentas_v2() where cuenta ilike 'CHEQUES RECHAZADOS%';
  res := res || 'E09 cheques rechazados (R) = saldo de la cuenta de cheques rechazados (' || n || '): ' || m || case when m = n then ' PASA' else ' FALLA' end || chr(10);
  select string_agg(estado || ':' || c || ' ' || s, ', ') into t from (select estado, count(*) c, round(sum(importe), 2) s from public.api_tesoreria_cheques_v2() group by 1 order by 1) x;
  res := res || 'E10 cheques por estado: ' || t || ' (sba14: ' || (select count(*) from public.sba14) || ')' || chr(10);
  select string_agg(grupo || ':' || c || ' ' || s, ', ') into t from (select grupo, count(*) c, round(sum(saldo), 2) s from public.api_tesoreria_cuentas_v2() group by 1 order by 1) x;
  res := res || 'E11 saldo por grupo de cuentas: ' || t || chr(10);
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into k from public.api_tesoreria_movimientos_v2();
  select count(*) into m from public.api_tesoreria_cheques_v2();
  reset role;
  res := res || 'E12 con usuario logueado (' || k || ' movimientos, ' || m || ' cheques): ' || case when k = (select count(*) from public.sba05) and m = (select count(*) from public.sba14) then 'PASA' else 'FALLA' end || chr(10);
  res := res || 'E13 anonimo no puede ejecutar: ' || case when not has_function_privilege('anon', 'public.api_tesoreria_cuentas_v2()', 'execute') and not has_function_privilege('anon', 'public.api_tesoreria_movimientos_v2(date,date)', 'execute') and not has_function_privilege('anon', 'public.api_tesoreria_cheques_v2()', 'execute') then 'PASA' else 'FALLA' end || chr(10);
  select count(*) into k from public.api_tesoreria_movimientos_v2('2023-01-01', '2023-12-31');
  select count(*) into n from public.sba05 where fecha::date between '2023-01-01' and '2023-12-31';
  res := res || 'E14 filtro 2023 = sba05 2023 (' || n || '): ' || k || case when k = n then ' PASA' else ' FALLA' end || chr(10);
  select string_agg(cuenta || ' pesos ' || saldo || ' / moneda ext ' || saldo_moneda_ext, ', ') into t from public.api_tesoreria_cuentas_v2() where moneda_ext and movimientos > 0;
  res := res || 'E15 cuentas en moneda extranjera: ' || coalesce(t, 'ninguna') || chr(10);
  select count(*) into n from public.api_tesoreria_cuentas_v2() c join public.api_tesoreria_por_cuenta(1000) v on v.cod_cta = c.cod_cta where abs(v.saldo_por_movimientos - c.saldo) >= 0.01;
  res := res || 'E16 cuentas donde la funcion vieja da otro saldo (no sumaba el saldo inicial): ' || n || chr(10);
  raise exception 'RESULTADOS (solo lectura)%', chr(10) || res;
end $$;

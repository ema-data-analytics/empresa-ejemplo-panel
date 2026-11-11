-- Pruebas del paso 6 (Cobranzas). No deja nada grabado: lo que se escribe se deshace dentro de la prueba.
create temp table pr13 (n int, prueba text, esperado text, obtenido text) on commit drop;
do $$
declare j jsonb; e text; uid uuid; idn bigint; cnt int; res text[] := '{}';
begin
  j := public.api_cobranzas_v2();
  insert into pr13 values
  (1, 'Cuotas devueltas = cuotas de Tango de comprobantes no anulados',
      (select count(*)::text from gva46 v join gva12 g on g.t_comp = v.t_comp and g.n_comp = v.n_comp where coalesce(g.estado,'') <> 'ANU'),
      jsonb_array_length(j->'cuotas')::text),
  (2, 'Pendiente de cuotas PEN (importe − aplicado a esa cuota), calculado aparte: 455536.75',
      '455536.75',
      (select round(sum((x->>'importe_vt')::numeric - (x->>'aplicado')::numeric), 2)::text from jsonb_array_elements(j->'cuotas') x where x->>'estado_vto' = 'PEN')),
  (3, 'La función vieja api_cartera_por_cliente da menos (resta todo lo cobrado del comprobante a cada cuota)',
      'menor',
      case when (select sum(saldo) from public.api_cartera_por_cliente(null, 1000)) < 455536.75 then 'menor' else 'igual o mayor' end),
  (4, 'No hay dos cuotas del mismo comprobante con la misma fecha de vencimiento',
      '0', (select count(*)::text from (select t_comp, n_comp, fecha_vto from gva46 group by 1,2,3 having count(*) > 1) z)),
  (5, 'Todos los cobros de Tango quedan en alguna cuota (suma de aplicado = suma de gva07)',
      (select round(sum(import_can), 2)::text from gva07),
      (select round(sum((x->>'aplicado')::numeric), 2)::text from jsonb_array_elements(j->'cuotas') x)),
  (6, 'Cobros sin fecha',
      '0', (select count(*)::text from gva07 where f_comp_can is null)),
  (7, 'Suma de cobros fechados de cada cuota = su aplicado',
      '0', (select count(*)::text from jsonb_array_elements(j->'cuotas') x
             where abs((x->>'aplicado')::numeric - coalesce((select sum((c->>1)::numeric) from jsonb_array_elements(x->'cobros') c), 0)) > 0.01)),
  (8, 'Saldo por comprobantes (todos los clientes) = suma de saldos de las fichas',
      (select round(sum(saldo_cc), 2)::text from gva14),
      (select round(sum((x->>'importe')::numeric), 2)::text from jsonb_array_elements(j->'comprobantes') x)),
  (9, 'Clientes cuyo saldo por comprobantes difiere de la ficha (se espera 020025 +100 y 020031 −100)',
      '020025:100.00,020031:-100.00',
      (select string_agg(k.cod_client || ':' || round(s.s - k.saldo_cc, 2)::text, ',' order by k.cod_client)
         from gva14 k join (select x->>'cod_client' c, sum((x->>'importe')::numeric) s from jsonb_array_elements(j->'comprobantes') x group by 1) s on s.c = k.cod_client
        where abs(s.s - k.saldo_cc) > 0.005)),
  (10, 'Clientes devueltos (7 fichas + ocasionales 000000)',
      '8', jsonb_array_length(j->'clientes')::text),
  (11, 'Ventas por cliente y mes suman lo mismo que la vista de ventas',
      (select round(sum(importe_con_signo), 2)::text from vista_venta_linea_v2 where estado_comprobante <> 'ANU'),
      (select round(sum((x->>'venta')::numeric), 2)::text from jsonb_array_elements(j->'ventas') x)),
  (12, 'Anónimo no puede leer cobranzas',
      'false', has_function_privilege('anon', 'public.api_cobranzas_v2()', 'execute')::text),
  (13, 'Usuario logueado sí puede (el portero exige perfil activo)',
      'true', has_function_privilege('authenticated', 'public.api_cobranzas_v2()', 'execute')::text),
  (14, 'La tabla de seguimiento no se lee directo (ni anónimo ni logueado)',
      'false,false', has_table_privilege('anon', 'public.cobranza_seguimiento', 'select')::text || ',' || has_table_privilege('authenticated', 'public.cobranza_seguimiento', 'select')::text),
  (15, 'Anónimo no puede agregar seguimiento',
      'false', has_function_privilege('anon', 'public.api_cobranzas_seguimiento_agregar_v2(text,date,text,text,text,date,numeric)', 'execute')::text);

  -- 16: sin usuario no se puede agregar
  begin
    perform public.api_cobranzas_seguimiento_agregar_v2('010001', current_date, 'x', 'En gestión', 'prueba');
    e := 'lo dejó agregar';
  exception when others then e := sqlerrm; end;
  insert into pr13 values (16, 'Sin usuario activo no se puede agregar', 'No autorizado', e);

  -- 17 a 20: con un usuario activo (simulado), dentro de un bloque que se deshace
  select p.id into uid from public.perfiles p where p.activo order by p.creado limit 1;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    begin perform public.api_cobranzas_seguimiento_agregar_v2('010001', current_date, 'x', 'En gestión', '   '); e := 'aceptó vacío';
    exception when others then e := sqlerrm; end;
    res := res || e;
    begin perform public.api_cobranzas_seguimiento_agregar_v2('NOEXISTE', current_date, 'x', 'En gestión', 'hola'); e := 'aceptó cliente inexistente';
    exception when others then e := sqlerrm; end;
    res := res || e;
    begin perform public.api_cobranzas_seguimiento_agregar_v2('010001', current_date, 'x', 'Cualquiera', 'hola'); e := 'aceptó estado inválido';
    exception when others then e := 'rechazado'; end;
    res := res || e;
    idn := public.api_cobranzas_seguimiento_agregar_v2('010001', current_date, 'Prueba', 'Compromiso de pago', 'prueba automática', current_date + 7, 1000);
    select count(*) into cnt from public.api_cobranzas_seguimiento_v2() s where s.id = idn and s.cargado_por <> 'sistema' and s.compromiso_monto = 1000;
    res := res || cnt::text;
    raise exception 'deshacer';
  exception when raise_exception then
    if sqlerrm <> 'deshacer' then res := res || ('error: ' || sqlerrm); end if;
  end;
  insert into pr13 values
  (17, 'Comentario vacío se rechaza', 'Falta el comentario', res[1]),
  (18, 'Cliente inexistente se rechaza', 'No existe el cliente NOEXISTE', res[2]),
  (19, 'Estado fuera de la lista se rechaza', 'rechazado', res[3]),
  (20, 'Con usuario activo se agrega y se lee con quién lo cargó', '1', res[4]),
  (22, 'Usuario activo usado para la prueba', 'encontrado', case when uid is null then 'no hay' else 'encontrado' end);
  insert into pr13 values (21, 'Después de la prueba la tabla de seguimiento quedó como estaba (sin la prueba)', '0',
    (select count(*)::text from public.cobranza_seguimiento where texto = 'prueba automática'));
end $$;
select json_build_object('ok', (select count(*) from pr13 where esperado = obtenido), 'total', (select count(*) from pr13),
  'detalle', (select json_agg(json_build_array(n, case when esperado = obtenido then 'OK' else 'MAL' end, prueba, esperado, obtenido) order by n) from pr13))::text as j;

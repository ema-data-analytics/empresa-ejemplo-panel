-- Paso 4e: Tesoreria para la pantalla interactiva. Tres funciones nuevas; no se toca nada existente.
-- Saldo de cada cuenta = saldo inicial de la ficha (sba01.saldo, a sba01.fecha_sald) + debe - haber de sus movimientos (sba05.monto, en pesos).
-- La funcion vieja api_tesoreria_por_cuenta no sumaba el saldo inicial. El saldo guardado en la ficha (saldo_act) se muestra aparte, como control.
-- Cuentas de fondo (sba01.fondo): cajas, bancos, valores y tarjetas. Las demas son contrapartidas (deudores, proveedores, gastos...).
create or replace function public.api_tesoreria_cuentas_v2()
returns table (cod_cta integer, cuenta text, tipo text, grupo text, es_fondo boolean, moneda_ext boolean,
  saldo_inicial numeric, fecha_saldo_inicial date, movimientos bigint, debe numeric, haber numeric, saldo numeric,
  saldo_ficha numeric, diferencia_ficha numeric, saldo_moneda_ext numeric, ultimo_movimiento date)
language sql stable security definer set search_path = public, pg_temp as $$
  with m as (
    select r.cod_cta, count(*) n,
           sum(coalesce(r.monto, 0)) filter (where r.d_h = 'D') d,
           sum(coalesce(r.monto, 0)) filter (where r.d_h = 'H') h,
           sum(case when r.d_h = 'D' then 1 else -1 end * coalesce(r.cant_mone, 0)) me,
           max(r.fecha::date) ult
    from public.sba05 r group by 1)
  select c.cod_cta::integer, trim(c.descripcio)::text, c.tipo::text,
         case when c.fondo then case c.tipo when 'B' then 'Bancos' when 'C' then 'Valores a depositar' when 'T' then 'Tarjetas' else 'Cajas y otros fondos' end
              else 'Contrapartidas' end,
         coalesce(c.fondo, false), coalesce(c.moneda_ex, false),
         coalesce(c.saldo, 0)::numeric, nullif(c.fecha_sald::date, date '1800-01-01'),
         coalesce(m.n, 0), round(coalesce(m.d, 0), 2), round(coalesce(m.h, 0), 2),
         round(coalesce(c.saldo, 0) + coalesce(m.d, 0) - coalesce(m.h, 0), 2),
         round(coalesce(c.saldo_act, 0), 2),
         round(coalesce(c.saldo_act, 0) - (coalesce(c.saldo, 0) + coalesce(m.d, 0) - coalesce(m.h, 0)), 2),
         case when c.moneda_ex then round(coalesce(m.me, 0), 2) end,
         m.ult
  from public.sba01 c left join m on m.cod_cta = c.cod_cta
  order by 2;
$$;

create or replace function public.api_tesoreria_movimientos_v2(p_desde date default null, p_hasta date default null)
returns table (id_sba05 bigint, id_sba04 bigint, fecha date, cod_comp text, comprobante text, n_comp text, situacion text,
  cod_cta integer, cuenta text, grupo text, es_fondo boolean, d_h text, debe numeric, haber numeric, importe numeric,
  leyenda text, cod_client text, cliente text, cod_provee text, proveedor text)
language sql stable security definer set search_path = public, pg_temp as $$
  select r.id_sba05::bigint, r.id_sba04::bigint, r.fecha::date, trim(r.cod_comp)::text,
         coalesce(trim(t.desc_comp), trim(r.cod_comp))::text, trim(r.n_comp)::text,
         coalesce(nullif(trim(h.situacion), ''), 'N')::text,
         r.cod_cta::integer, trim(c.descripcio)::text,
         case when c.fondo then case c.tipo when 'B' then 'Bancos' when 'C' then 'Valores a depositar' when 'T' then 'Tarjetas' else 'Cajas y otros fondos' end
              else 'Contrapartidas' end,
         coalesce(c.fondo, false), r.d_h::text,
         case when r.d_h = 'D' then round(coalesce(r.monto, 0), 2) else 0 end,
         case when r.d_h = 'H' then round(coalesce(r.monto, 0), 2) else 0 end,
         round(case when r.d_h = 'D' then 1 else -1 end * coalesce(r.monto, 0), 2),
         coalesce(nullif(trim(r.leyenda), ''), nullif(trim(h.concepto), ''))::text,
         nullif(trim(r.cod_gva14), '')::text, k.razon_soci::text,
         nullif(trim(r.cod_cpa01), '')::text, p.nom_provee::text
  from public.sba05 r
  left join public.sba04 h on h.id_sba04 = r.id_sba04
  left join public.sba01 c on c.cod_cta = r.cod_cta
  left join lateral (select x.desc_comp from public.sba02 x where x.cod_comp = r.cod_comp limit 1) t on true
  left join lateral (select g.razon_soci from public.gva14 g where g.cod_client = r.cod_gva14 limit 1) k on true
  left join lateral (select q.nom_provee from public.cpa01 q where q.cod_provee = r.cod_cpa01 limit 1) p on true
  where (p_desde is null or r.fecha::date >= p_desde)
    and (p_hasta is null or r.fecha::date <= p_hasta)
  order by 3, 2, 1;
$$;

-- Cheques de terceros (sba14). Estados segun como cierran contra las cuentas: C = en cartera (suma = cuenta VALORES A DEPOSITAR),
-- R = rechazado (suma = cuenta CHEQUES RECHAZADOS), A = aplicado (depositado o entregado), X = anulado.
create or replace function public.api_tesoreria_cheques_v2()
returns table (id_sba14 bigint, n_cheque text, banco text, importe numeric, fecha_emision date, fecha_cheque date,
  fecha_recepcion date, fecha_salida date, estado text, cod_client text, cliente text, cod_provee text, proveedor text)
language sql stable security definer set search_path = public, pg_temp as $$
  select q.id_sba14::bigint, q.n_cheque::text,
         coalesce(b.nombre, 'Banco ' || q.id_banco)::text,
         round(coalesce(q.importe_ch, 0), 2),
         nullif(q.f_emision::date, date '1800-01-01'), nullif(q.fecha_cheq::date, date '1800-01-01'),
         nullif(q.fecha_rec::date, date '1800-01-01'), nullif(q.fecha_sal::date, date '1800-01-01'),
         trim(q.estado)::text,
         nullif(trim(q.cliente), '')::text, k.razon_soci::text,
         nullif(trim(q.proveedor), '')::text, p.nom_provee::text
  from public.sba14 q
  left join lateral (select x.nombre from public.sba03 x where x.id_sba03 = q.id_banco limit 1) b on true
  left join lateral (select g.razon_soci from public.gva14 g where g.cod_client = q.cliente limit 1) k on true
  left join lateral (select y.nom_provee from public.cpa01 y where y.cod_provee = q.proveedor limit 1) p on true
  order by 6, 1;
$$;

revoke all on function public.api_tesoreria_cuentas_v2(), public.api_tesoreria_movimientos_v2(date, date), public.api_tesoreria_cheques_v2() from public, anon;
grant execute on function public.api_tesoreria_cuentas_v2(), public.api_tesoreria_movimientos_v2(date, date), public.api_tesoreria_cheques_v2() to authenticated;
comment on function public.api_tesoreria_cuentas_v2() is 'Cuentas de tesoreria con saldo inicial + movimientos y control contra la ficha. 26/09/2026.';
comment on function public.api_tesoreria_movimientos_v2(date, date) is 'Renglones de tesoreria con signo (+debe -haber). 26/09/2026.';
comment on function public.api_tesoreria_cheques_v2() is 'Cheques de terceros. 26/09/2026.';
notify pgrst, 'reload schema';
select 'instalado' as estado;

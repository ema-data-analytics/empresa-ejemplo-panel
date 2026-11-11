-- Paso 4h: IVA para la pantalla interactiva. Dos funciones nuevas; no se toca nada existente
-- (las funciones viejas api_afip_resumen y api_afip_faltantes_en_tango quedan como estaban).
-- Debito fiscal: comprobantes de venta (gva12) sin anulados ni recibos. Credito fiscal: comprobantes de compra (cpa04: FAC, N/C, N/D) sin anulados.
-- Signo: los comprobantes de credito restan. En ventas se usa el tipo interno de Tango (tcomp_in_v CC o NC = credito; DC = debito; FR/FC = factura)
-- y, si falta, el codigo (CDE, AJC, N/C). Primera version usaba solo 'NC' y sumaba los CDE: la prueba I02/I03 lo detecto y se corrigio.
-- Otros = total - (gravado + exento + IVA + impuestos internos): percepciones, fletes y otros conceptos del comprobante.
create or replace function public.api_iva_ventas_v2(p_desde date default null, p_hasta date default null)
returns table (id_gva12 bigint, fecha date, t_comp text, tipo text, n_comp text, signo int, estado text, cod_client text, cliente text,
  cuit text, gravado numeric, exento numeric, iva numeric, internos numeric, otros numeric, total numeric)
language sql stable security definer set search_path = public, pg_temp as $$
  with c as (
    select g.*, case when upper(trim(coalesce(g.tcomp_in_v, ''))) in ('CC', 'NC') or (nullif(trim(coalesce(g.tcomp_in_v, '')), '') is null and trim(g.t_comp) in ('CDE', 'AJC', 'N/C')) then -1 else 1 end s
    from public.gva12 g
    where coalesce(trim(g.estado), '') <> 'ANU' and trim(g.t_comp) <> 'REC'
      and (p_desde is null or g.fecha_emis::date >= p_desde)
      and (p_hasta is null or g.fecha_emis::date <= p_hasta))
  select c.id_gva12::bigint, c.fecha_emis::date, trim(c.t_comp)::text,
         case trim(c.t_comp) when 'FAC' then 'Factura' when 'CDE' then 'Crédito por devolución' when 'N/C' then 'Nota de crédito'
              when 'N/D' then 'Nota de débito' when 'NDM' then 'Nota de débito' when 'AJC' then 'Ajuste crédito' when 'AJD' then 'Ajuste débito'
              when 'DDC' then 'Débito por diferencia de cambio' else trim(c.t_comp) end::text,
         trim(c.n_comp)::text, c.s, coalesce(nullif(trim(c.estado), ''), 'sin estado')::text,
         nullif(trim(c.cod_client), '')::text, k.razon_soci::text, k.cuit::text,
         round(c.s * coalesce(c.importe_gr, 0), 2), round(c.s * coalesce(c.importe_ex, 0), 2), round(c.s * coalesce(c.importe_iv, 0), 2),
         round(c.s * coalesce(c.importe_in, 0), 2),
         round(c.s * (coalesce(c.importe, 0) - coalesce(c.importe_gr, 0) - coalesce(c.importe_ex, 0) - coalesce(c.importe_iv, 0) - coalesce(c.importe_in, 0)), 2),
         round(c.s * coalesce(c.importe, 0), 2)
  from c
  left join lateral (select x.razon_soci, coalesce(to_jsonb(x) ->> 'cuit', to_jsonb(x) ->> 'n_cuit') cuit from public.gva14 x where x.cod_client = c.cod_client limit 1) k on true
  order by 2, 5;
$$;

create or replace function public.api_iva_compras_v2(p_desde date default null, p_hasta date default null)
returns table (id_cpa04 bigint, fecha date, t_comp text, n_comp text, signo int, estado text, cod_provee text, proveedor text, cuit text,
  neto numeric, exento numeric, iva numeric, iva_21 numeric, iva_105 numeric, iva_27 numeric, iva_otras numeric, otros numeric, total numeric)
language sql stable security definer set search_path = public, pg_temp as $$
  with c as (
    select x.*, case when x.t_comp ~ 'N/C' then -1 else 1 end s,
           coalesce(x.imp_iva1, 0) + coalesce(x.imp_iva2, 0) + coalesce(x.imp_iva3, 0) + coalesce(x.imp_iva4, 0) + coalesce(x.imp_iva5, 0) iv
    from public.cpa04 x
    where x.t_comp in ('FAC', 'N/C', 'N/D') and coalesce(x.estado, '') <> 'ANU'
      and (p_desde is null or x.fecha_emis::date >= p_desde)
      and (p_hasta is null or x.fecha_emis::date <= p_hasta)),
  a as (
    select c.id_cpa04, sum(case when v.p = 21 then v.i else 0 end) i21, sum(case when v.p in (9, 10.5) then v.i else 0 end) i105, sum(case when v.p = 27 then v.i else 0 end) i27
    from c cross join lateral (values (c.porc_iva1, coalesce(c.imp_iva1, 0)), (c.porc_iva2, coalesce(c.imp_iva2, 0)), (c.porc_iva3, coalesce(c.imp_iva3, 0)),
                                      (c.porc_iva4, coalesce(c.imp_iva4, 0)), (c.porc_iva5, coalesce(c.imp_iva5, 0))) v(p, i)
    group by 1)
  select c.id_cpa04::bigint, c.fecha_emis::date, c.t_comp::text, c.n_comp::text, c.s, coalesce(nullif(trim(c.estado), ''), 'sin estado')::text,
         c.cod_provee::text, coalesce(p.nom_provee, 'Proveedor ' || c.cod_provee)::text, p.n_cuit::text,
         round(c.s * coalesce(c.importe_ne, 0), 2), round(c.s * coalesce(c.importe_ex, 0), 2), round(c.s * c.iv, 2),
         round(c.s * a.i21, 2), round(c.s * a.i105, 2), round(c.s * a.i27, 2), round(c.s * (c.iv - a.i21 - a.i105 - a.i27), 2),
         round(c.s * (coalesce(c.importe_to, 0) - coalesce(c.importe_ne, 0) - coalesce(c.importe_ex, 0) - c.iv), 2),
         round(c.s * coalesce(c.importe_to, 0), 2)
  from c
  join a on a.id_cpa04 = c.id_cpa04
  left join lateral (select y.nom_provee, y.n_cuit from public.cpa01 y where y.cod_provee = c.cod_provee limit 1) p on true
  order by 2, 4;
$$;

revoke all on function public.api_iva_ventas_v2(date, date), public.api_iva_compras_v2(date, date) from public, anon;
grant execute on function public.api_iva_ventas_v2(date, date), public.api_iva_compras_v2(date, date) to authenticated;
comment on function public.api_iva_ventas_v2(date, date) is 'Libro IVA ventas (debito fiscal) desde gva12. 26/09/2026.';
comment on function public.api_iva_compras_v2(date, date) is 'Libro IVA compras (credito fiscal) desde cpa04, con IVA por alicuota. 26/09/2026.';
notify pgrst, 'reload schema';
select 'instalado' as estado;

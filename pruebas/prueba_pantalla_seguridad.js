// Prueba de pantalla del panel con una base SIMULADA (no es la prueba en vivo: esa se hace después en el sistema real).
// Uso: node pruebas/prueba_pantalla_seguridad.js   (desde la raíz del repo)
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const INDEX = 'file://' + path.resolve(__dirname, '..', 'index.html');
const resultados = []; let fallas = 0;
function ok(cond, que) { resultados.push((cond ? 'OK   ' : 'FALLA') + '  ' + que); if (!cond) fallas++; }

// Supabase simulado: cada escenario define el perfil, los permisos y qué devuelve cada función
function stubSupabase(esc) {
  return `
  window.__llamadas = [];
  window.__esc = ${JSON.stringify(esc)};
  window.supabase = { createClient: function () {
    var sesion = window.__esc.sesion ? { access_token: 'tok' } : null;
    var oyentes = [];
    return {
      auth: {
        onAuthStateChange: function (f) { oyentes.push(f); },
        getSession: function () { return Promise.resolve({ data: { session: sesion } }); },
        signInWithPassword: function () { sesion = { access_token: 'tok' }; return Promise.resolve({ data: {}, error: null }); },
        signOut: function () { sesion = null; return Promise.resolve({}); },
        updateUser: function (u) { window.__llamadas.push(['updateUser']); window.__esc.yo.debe_cambiar_clave = false; return Promise.resolve({ data: {}, error: null }); }
      },
      rpc: function (fn, args) {
        window.__llamadas.push([fn, args || null]);
        var r = window.__esc.rpc[fn];
        if (fn === 'api_seg_yo_v2') r = [window.__esc.yo];
        if (r === undefined) r = [];
        if (r && r.__error) return Promise.resolve({ data: null, error: { message: r.__error } });
        return Promise.resolve({ data: r, error: null });
      }
    };
  } };`;
}
const CHART = 'window.Chart = function () { return { destroy: function () {}, update: function () {}, data: { datasets: [] }, options: {} }; };';

const MODS = [['radar','Radar · Tablero central','Inicio',1],['ventas','Ventas','Ventas',2],['cobranzas','Cobranzas','Cobranzas',3],
  ['compras','Compras','Compras',4],['stock','Stock','Stock',5],['tesoreria','Tesorería','Tesoreria',6],['legajos','Legajos y sueldos','Legajos',7],
  ['activo_fijo','Activo Fijo','ActivoFijo',8],['iva','IVA','IVA',9]];
function permisos(niveles, conSeg) {
  const p = MODS.filter(m => (niveles[m[0]] || 'no') !== 'no').map(m => ({ modulo: m[0], nombre: m[1], pantalla: m[2], orden: m[3], nivel: niveles[m[0]], carga: m[0] === 'cobranzas' && niveles.__carga !== false }));
  if (conSeg) p.push({ modulo: 'seguridad', nombre: 'Seguridad', pantalla: 'Seguridad', orden: 99, nivel: 'exporta', carga: true });
  return p;
}
const ROLES = [{ codigo: 'super', nombre: 'Super', descripcion: 'Todo', es_sistema: true, activo: true, usuarios: 1 },
  { codigo: 'admin', nombre: 'Administrador', descripcion: '', es_sistema: true, activo: true, usuarios: 0 },
  { codigo: 'usuario', nombre: 'Usuario', descripcion: '', es_sistema: true, activo: true, usuarios: 1 },
  { codigo: 'vendedor', nombre: 'Vendedor', descripcion: 'Solo ventas', es_sistema: false, activo: true, usuarios: 0 }];

async function abrir(browser, esc) {
  const page = await browser.newPage({ viewport: { width: 1280, height: 860 } });
  const errores = []; page.on("pageerror", e => errores.push(e.message)); page.on("console", c => { if (c.type() === "error") errores.push("consola: " + c.text()); });
  await page.route('**/supabase.min.js', r => r.fulfill({ contentType: 'text/javascript', body: stubSupabase(esc) }));
  await page.route('**/chart.umd.min.js', r => r.fulfill({ contentType: 'text/javascript', body: CHART }));
  await page.route('https://fonts.googleapis.com/**', r => r.fulfill({ contentType: 'text/css', body: '' }));
  await page.route('**/functions/v1/usuarios', r => {
    const b = JSON.parse(r.request().postData());
    if (b.accion === 'crear') return r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ ok: true, id: 'x', email: b.email, clave_temporal: 'PRUEBAabc23456' }) });
    return r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ ok: true, id: b.id, email: 'prueba@x.com', clave_temporal: 'PRUEBAblq98765' }) });
  });
  await page.goto(INDEX); await page.waitForTimeout(700);
  return { page, errores };
}
const visibles = page => page.$$eval('#menu .nav-item', ns => ns.filter(n => getComputedStyle(n).display !== 'none').map(n => n.dataset.modulo));
const vis = (page, sel) => page.$eval(sel, e => getComputedStyle(e).display !== 'none' && !e.closest('.oculto')).catch(() => false);

(async () => {
  const browser = await chromium.launch();

  // 1. Usuario con rol "vendedor": solo Ventas (ve, sin exportar). Fail closed en todo lo demás.
  let esc = { sesion: true, yo: { id: 'u1', nombre: 'PRUEBA Vendedor', email: 'v@x', rol: 'vendedor', rol_nombre: 'Vendedor', activo: true, debe_cambiar_clave: false },
    rpc: { api_seg_mis_permisos: permisos({ ventas: 've' }, false), api_ventas_lineas_v2: [], api_fecha_corte_v2: [{}] } };
  let { page, errores } = await abrir(browser, esc);
  let m = await visibles(page);
  ok(JSON.stringify(m) === '["Ventas"]', 'Vendedor: el menú muestra solo Ventas (' + m.join(',') + ')');
  ok(await page.$eval('#tituloModulo', e => e.textContent) === 'Ventas', 'Vendedor: sin Radar, abre en Ventas');
  ok(!(await vis(page, '#vBtnCsv')), 'Vendedor con "ve": no ve Descargar CSV');
  ok(!(await vis(page, '#btnImprimir')), 'Vendedor con "ve": no ve Imprimir / PDF');
  ok(await vis(page, '#btnCambiarClave'), 'Botón "Cambiar contraseña" visible arriba');
  await page.evaluate(() => window.abrirModuloFiltrado && window.abrirModuloFiltrado('Compras', {}));
  await page.evaluate(() => irA('Compras'));
  ok(/no tiene acceso a Compras/.test(await page.$eval('#avisoSinAcceso', e => e.textContent).catch(() => '')), 'Vendedor: abrir Compras a la fuerza muestra "no tiene acceso"');
  ok(!(await page.evaluate(() => window.__llamadas.some(l => /compras|seg_listar|legajos/.test(l[0])))), 'Vendedor: nunca se pidió una función de Compras, Legajos ni Seguridad');
  ok(errores.length === 0, 'Vendedor: sin errores de JavaScript ' + errores.join(' | '));
  await page.close();

  // 2. Usuario con Cobranzas "exporta" pero SIN carga
  esc = { sesion: true, yo: { id: 'u2', nombre: 'PRUEBA Cobrador', email: 'c@x', rol: 'cobrador', rol_nombre: 'Cobrador', activo: true, debe_cambiar_clave: false },
    rpc: { api_seg_mis_permisos: permisos({ cobranzas: 'exporta', __carga: false }, false), api_cobranzas_v2: [], api_cobranzas_seguimiento_v2: [], api_fecha_corte_v2: [{}] } };
  ({ page, errores } = await abrir(browser, esc));
  ok(await page.$eval('body', b => b.dataset.carga) === '0', 'Cobrador sin carga: marca data-carga=0');
  ok(!(await page.$eval('#cFicha .c-form', e => getComputedStyle(e).display !== 'none')), 'Cobrador sin carga: el formulario de seguimiento no se ve');
  ok(await page.$eval('#cBtnCsvCli', e => getComputedStyle(e).display !== 'none'), 'Cobrador con "exporta": el botón Descargar CSV no está tapado por permisos');
  ok(errores.length === 0, 'Cobrador: sin errores de JavaScript ' + errores.join(' | '));
  await page.close();

  // 3. Contraseña temporal: entra y lo obliga a cambiarla antes de ver nada
  esc = { sesion: true, yo: { id: 'u3', nombre: 'PRUEBA Nuevo', email: 'n@x', rol: 'usuario', rol_nombre: 'Usuario', activo: true, debe_cambiar_clave: true },
    rpc: { api_seg_mis_permisos: permisos({ radar: 'exporta', ventas: 'exporta' }, false), api_fecha_corte_v2: [{}], api_radar_hoy_v2: [], api_radar_mensual_v2: [] } };
  ({ page, errores } = await abrir(browser, esc));
  ok(await vis(page, '#modalClave'), 'Temporal: se abre la ventana de cambio de contraseña');
  ok(!(await vis(page, '#btnCancelarClave')), 'Temporal: la ventana no tiene Cancelar');
  ok(!(await page.evaluate(() => window.__llamadas.some(l => l[0] === 'api_seg_mis_permisos'))), 'Temporal: no se leyeron permisos ni datos antes de cambiarla');
  await page.fill('#clave1', 'NuevaClave2026'); await page.fill('#clave2', 'NuevaClave2026');
  await page.click('#btnGuardarClave'); await page.waitForTimeout(500);
  ok(!(await vis(page, '#modalClave')), 'Temporal: después de cambiarla se cierra la ventana');
  ok(await page.$eval('#tituloModulo', e => e.textContent) === 'Radar · Tablero central', 'Temporal: después entra al Radar');
  ok(errores.length === 0, 'Temporal: sin errores de JavaScript ' + errores.join(' | '));
  await page.close();

  // 4. Super: Seguridad completa
  const todos = {}; MODS.forEach(x => todos[x[0]] = 'exporta');
  esc = { sesion: true, yo: { id: 's1', nombre: 'PRUEBA Super', email: 'a@x', rol: 'super', rol_nombre: 'Super', activo: true, debe_cambiar_clave: false },
    rpc: { api_seg_mis_permisos: permisos(todos, true), api_fecha_corte_v2: [{}], api_radar_hoy_v2: [], api_radar_mensual_v2: [], api_seg_roles: ROLES,
      api_seg_listar_v2: [{ id: 's1', nombre: 'PRUEBA Super', email: 'a@x', rol: 'super', rol_nombre: 'Super', activo: true, debe_cambiar_clave: false, ultimo_ingreso: '2026-11-11T15:18:00Z' },
                          { id: 'p1', nombre: 'PRUEBA Usuario', email: 'p@x', rol: 'usuario', rol_nombre: 'Usuario', activo: true, debe_cambiar_clave: true, ultimo_ingreso: null }],
      api_seg_permisos: MODS.map(x => ({ modulo: x[0], nombre: x[1], orden: x[3], tiene_carga: x[0] === 'cobranzas', nivel: x[0] === 'ventas' ? 've' : 'no', carga: false })),
      api_seg_permiso_guardar: { ok: true }, api_seg_rol_guardar: { ok: true, codigo: 'cobrador' }, api_seg_editar_v2: { ok: true },
      api_seg_bitacora: [{ cuando: '2026-11-11T15:16:04Z', quien: 'sistema', accion: 'clave_temporal', sobre: 'PRUEBA Super', detalle: { motivo: 'olvido' } },
                         { cuando: '2026-11-11T16:00:00Z', quien: 'PRUEBA Super', accion: 'cambiar permiso', sobre: null, detalle: { rol: 'vendedor', modulo: 'ventas', antes: { nivel: 'no' }, despues: { nivel: 've', carga: false } } }] } };
  ({ page, errores } = await abrir(browser, esc));
  m = await visibles(page);
  ok(m.length === 10 && m.indexOf('Seguridad') >= 0, 'Super: ve los 9 módulos y Seguridad (' + m.length + ')');
  await page.click("#navSeguridad"); await page.waitForTimeout(400);
  ok((await page.$$('#tablaUsuarios tr')).length === 2, 'Super: lista 2 usuarios');
  ok(/Temporal/.test(await page.$eval('#tablaUsuarios', e => e.textContent)), 'Super: marca al que tiene contraseña temporal');
  ok((await page.$$eval('#tablaUsuarios tr:first-child button', bs => bs.map(b => b.textContent))).indexOf('Blanquear contraseña') < 0, 'Super: no puede blanquearse a sí mismo desde la lista');
  await page.fill('#segBuscarUsuario', 'usuario'); await page.waitForTimeout(100);
  ok((await page.$$('#tablaUsuarios tr')).length === 1, 'Super: el buscador filtra');
  await page.fill('#segBuscarUsuario', '');
  await page.click('#btnNuevoUsuario');
  ok(await page.$$eval('#nuevoRol option', o => o.map(x => x.value).join(',')) === 'super,admin,usuario,vendedor', 'Nuevo usuario: el rol sale de la tabla de roles');
  await page.fill('#nuevoNombre', 'PRUEBA Alta'); await page.fill('#nuevoEmail', 'prueba.alta@x.com'); await page.selectOption('#nuevoRol', 'vendedor');
  await page.click('#btnCrearUsuario'); await page.waitForTimeout(500);
  ok(await vis(page, '#modalTemporal') && (await page.$eval('#temporalClave', e => e.textContent)) === 'PRUEBAabc23456', 'Nuevo usuario: muestra la contraseña temporal una vez');
  await page.click('#btnCerrarTemporal'); await page.waitForTimeout(200);
  ok((await page.$eval('#temporalClave', e => e.textContent)) === '', 'Nuevo usuario: al cerrar, la contraseña se borra de la pantalla');
  await page.click('#tablaUsuarios tr:nth-child(2) button:nth-child(2)'); await page.waitForTimeout(100);
  ok(await vis(page, '#modalBlanquear'), 'Blanquear: pide confirmación en ventana propia');
  await page.click('#btnConfirmarBlanqueo'); await page.waitForTimeout(500);
  ok((await page.$eval('#temporalClave', e => e.textContent)) === 'PRUEBAblq98765', 'Blanquear: muestra la temporal nueva');
  await page.click('#btnCerrarTemporal');
  await page.click('[data-segtab="Roles"]'); await page.waitForTimeout(400);
  ok((await page.$$('#tablaRoles tr')).length === 4, 'Roles: lista 4 roles');
  ok((await page.$$eval('#tablaRoles tr:first-child button', bs => bs.map(b => b.textContent))).indexOf('Editar') < 0, 'Roles: el rol super no se edita');
  await page.selectOption('#segRolPermisos', 'vendedor'); await page.waitForTimeout(300);
  ok((await page.$$('#tablaPermisos tr')).length === 9, 'Permisos: grilla con los 9 módulos');
  await page.selectOption('#tablaPermisos tr:nth-child(4) select', 've'); await page.waitForTimeout(300);
  const g = await page.evaluate(() => window.__llamadas.filter(l => l[0] === 'api_seg_permiso_guardar').pop());
  ok(g && g[1].p_rol === 'vendedor' && g[1].p_modulo === 'compras' && g[1].p_nivel === 've', 'Permisos: cambiar Compras a "Ve" guarda en la base');
  ok(/Guardado/.test(await page.$eval('#tablaPermisos tr:nth-child(4)', e => e.textContent)), 'Permisos: muestra "Guardado"');
  await page.click('#btnNuevoRol'); await page.fill('#rolNombre', 'Cobrador Calle');
  ok(await page.$eval('#rolCodigo', e => e.value) === 'cobrador_calle', 'Nuevo rol: arma el código solo');
  await page.click('#btnGuardarRol'); await page.waitForTimeout(300);
  const rg = await page.evaluate(() => window.__llamadas.filter(l => l[0] === 'api_seg_rol_guardar').pop());
  ok(rg && rg[1].p_codigo === 'cobrador_calle', 'Nuevo rol: guarda en la base');
  await page.click('[data-segtab="Bitacora"]'); await page.waitForTimeout(400);
  ok((await page.$$('#tablaBitacora tr')).length === 2, 'Bitácora: 2 movimientos');
  ok(/vendedor · ventas: no → ve/.test(await page.$eval('#tablaBitacora', e => e.textContent)), 'Bitácora: explica el cambio de permiso');
  await page.selectOption('#segFiltroAccion', 'clave_temporal'); await page.waitForTimeout(100);
  ok((await page.$$('#tablaBitacora tr')).length === 1, 'Bitácora: filtra por acción');
  await page.screenshot({ path: path.resolve(__dirname, 'seguridad_bitacora.png') });
  await page.click('[data-segtab="Roles"]'); await page.waitForTimeout(300);
  await page.screenshot({ path: path.resolve(__dirname, 'seguridad_permisos.png'), fullPage: true });
  ok(errores.length === 0, 'Super: sin errores de JavaScript ' + errores.join(' | '));
  await page.close();

  // 5. Usuario inactivo: no entra
  esc = { sesion: true, yo: { id: 'u9', nombre: 'PRUEBA Baja', email: 'b@x', rol: 'usuario', rol_nombre: 'Usuario', activo: false, debe_cambiar_clave: false }, rpc: {} };
  ({ page, errores } = await abrir(browser, esc));
  ok(await vis(page, '#zonaLogin') && /no está activo/.test(await page.$eval('#loginMensaje', e => e.textContent)), 'Inactivo: vuelve al ingreso con el aviso');
  await page.close();

  await browser.close();
  const txt = resultados.join('\n') + '\n\n' + (resultados.length - fallas) + ' de ' + resultados.length + ' OK';
  fs.writeFileSync(path.resolve(__dirname, 'resultado_pantalla_seguridad.txt'), txt);
  console.log(txt);
  process.exit(fallas ? 1 : 0);
})();

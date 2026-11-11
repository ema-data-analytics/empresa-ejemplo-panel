  // ---------- Seguridad: usuarios, roles y permisos, bitácora ----------
  var ROLES = [], USUARIOS = [], BITACORA = [], SEG_TAB = 'Usuarios', blanqueando = null, rolEditando = null;

  function cargarSeguridad() {
    cargarRoles().then(function () {
      if (SEG_TAB === 'Usuarios') cargarUsuarios();
      if (SEG_TAB === 'Roles') { pintarRoles(); cargarGrillaPermisos(); }
      if (SEG_TAB === 'Bitacora') cargarBitacora();
    });
  }
  document.querySelectorAll('[data-segtab]').forEach(function (b) {
    b.addEventListener('click', function () {
      SEG_TAB = b.dataset.segtab;
      document.querySelectorAll('[data-segtab]').forEach(function (x) { x.classList.toggle('activo', x === b); });
      mostrar('segUsuarios', SEG_TAB === 'Usuarios'); mostrar('segRoles', SEG_TAB === 'Roles');
      mostrar('segPermisos', SEG_TAB === 'Roles'); mostrar('segBitacora', SEG_TAB === 'Bitacora');
      cargarSeguridad();
    });
  });
  $('btnRecargarUsuarios').addEventListener('click', cargarSeguridad);
  $('btnRecargarBitacora').addEventListener('click', cargarBitacora);

  function cargarRoles() {
    return sb.rpc('api_seg_roles').then(function (r) {
      if (r.error) { aviso('segMensaje', 'No se pudieron leer los roles: ' + textoError(r.error)); ROLES = []; return; }
      ROLES = r.data || [];
      llenarSelectRoles($('editarRol'), false, true); llenarSelectRoles($('nuevoRol'), false, true);
      llenarSelectRoles($('segFiltroRol'), true, false);
      var actual = $('segRolPermisos').value; llenarSelectRoles($('segRolPermisos'), false, false);
      if (actual) $('segRolPermisos').value = actual;
    }).catch(function (e) { aviso('segMensaje', 'Error de conexión: ' + textoError(e)); });
  }
  function llenarSelectRoles(sel, conTodos, soloActivos) {
    var v = sel.value; sel.innerHTML = '';
    if (conTodos) { var o0 = document.createElement('option'); o0.value = ''; o0.textContent = 'Todos los roles'; sel.appendChild(o0); }
    ROLES.forEach(function (x) {
      if (soloActivos && !x.activo) return;
      var o = document.createElement('option'); o.value = x.codigo; o.textContent = x.nombre + (x.activo ? '' : ' (desactivado)'); sel.appendChild(o);
    });
    if (v) sel.value = v;
  }
  function nombreRol(c) { for (var i = 0; i < ROLES.length; i++) if (ROLES[i].codigo === c) return ROLES[i].nombre; return c; }

  // --- Usuarios ---
  function cargarUsuarios() {
    var tb = $('tablaUsuarios'); tb.innerHTML = '<tr><td colspan="7" class="gris">Cargando…</td></tr>'; limpiarAviso('segMensaje');
    return sb.rpc('api_seg_listar_v2').then(function (r) {
      if (r.error) { tb.innerHTML = ''; aviso('segMensaje', 'No se pudo listar: ' + textoError(r.error)); return; }
      USUARIOS = r.data || []; pintarUsuarios();
    }).catch(function (e) { tb.innerHTML = ''; aviso('segMensaje', 'Error de conexión: ' + textoError(e)); });
  }
  ['segBuscarUsuario', 'segFiltroRol', 'segFiltroEstado'].forEach(function (id) { $(id).addEventListener('input', pintarUsuarios); });
  function pintarUsuarios() {
    var tb = $('tablaUsuarios'); tb.innerHTML = '';
    var q = $('segBuscarUsuario').value.trim().toLowerCase(), fr = $('segFiltroRol').value, fe = $('segFiltroEstado').value;
    var lista = USUARIOS.filter(function (u) {
      if (q && ((u.nombre || '') + ' ' + (u.email || '')).toLowerCase().indexOf(q) < 0) return false;
      if (fr && u.rol !== fr) return false;
      if (fe === '1' && !u.activo) return false;
      if (fe === '0' && u.activo) return false;
      return true;
    });
    if (!lista.length) { var tr0 = document.createElement('tr'); celda(tr0, USUARIOS.length ? 'Ningún usuario cumple el filtro.' : 'No hay usuarios.', 'gris').colSpan = 7; tb.appendChild(tr0); return; }
    lista.forEach(function (u) {
      var tr = document.createElement('tr');
      celda(tr, u.nombre); celda(tr, u.email, 'gris');
      chip(celda(tr, ''), u.rol_nombre || u.rol, 'rol');
      chip(celda(tr, ''), u.activo ? 'Activo' : 'Inactivo', u.activo ? 'activo' : 'inactivo');
      var tc = celda(tr, ''); if (u.debe_cambiar_clave) chip(tc, 'Temporal: la tiene que cambiar', 'temporal'); else tc.textContent = 'Propia';
      celda(tr, fechaHora(u.ultimo_ingreso), 'gris');
      var td = celda(tr, ''); var caja = document.createElement('div'); caja.className = 'seg-acciones'; td.appendChild(caja);
      var b = document.createElement('button'); b.type = 'button'; b.className = 'btn secundario chico'; b.textContent = 'Editar';
      b.addEventListener('click', function () { abrirEditar(u); }); caja.appendChild(b);
      if (!YO || u.id !== YO.id) {
        var b2 = document.createElement('button'); b2.type = 'button'; b2.className = 'btn secundario chico'; b2.textContent = 'Blanquear contraseña';
        b2.addEventListener('click', function () { abrirBlanqueo(u); }); caja.appendChild(b2);
      }
      tb.appendChild(tr);
    });
  }

  function abrirEditar(u) {
    editando = u; limpiarAviso('editarMensaje');
    $('editarEmail').textContent = u.email || ''; $('editarNombre').value = u.nombre || '';
    llenarSelectRoles($('editarRol'), false, true);
    if (!Array.prototype.some.call($('editarRol').options, function (o) { return o.value === u.rol; })) {
      var o = document.createElement('option'); o.value = u.rol; o.textContent = (u.rol_nombre || u.rol) + ' (desactivado)'; $('editarRol').appendChild(o);
    }
    $('editarRol').value = u.rol; $('editarActivo').checked = !!u.activo;
    mostrar('modalEditar', true);
  }
  $('formEditar').addEventListener('submit', function (ev) {
    ev.preventDefault(); if (!editando) return;
    $('btnGuardarUsuario').disabled = true; limpiarAviso('editarMensaje');
    sb.rpc('api_seg_editar_v2', { p_id: editando.id, p_nombre: $('editarNombre').value, p_rol: $('editarRol').value, p_activo: $('editarActivo').checked })
      .then(function (r) {
        if (r.error) { aviso('editarMensaje', textoError(r.error)); return; }
        mostrar('modalEditar', false); cargarSeguridad();
      }).catch(function (e) { aviso('editarMensaje', 'Error de conexión: ' + textoError(e)); })
      .then(function () { $('btnGuardarUsuario').disabled = false; });
  });

  // Alta y blanqueo: los hace la función "usuarios" de Supabase (la única que tiene la clave de servicio)
  function llamarUsuarios(cuerpo) {
    return sb.auth.getSession().then(function (s) {
      var tok = s && s.data && s.data.session && s.data.session.access_token;
      if (!tok) throw new Error('Tu sesión venció: volvé a ingresar.');
      return fetch(CFG.url + '/functions/v1/usuarios', { method: 'POST',
        headers: { 'Authorization': 'Bearer ' + tok, 'apikey': CFG.clave, 'Content-Type': 'application/json' },
        body: JSON.stringify(cuerpo) });
    }).then(function (resp) {
      return resp.text().then(function (t) {
        var j = null; try { j = JSON.parse(t); } catch (e) { j = null; }
        if (!resp.ok || !j || !j.ok) throw new Error((j && j.error) || ('La función de usuarios respondió ' + resp.status));
        return j;
      });
    });
  }
  function mostrarTemporal(titulo, para, clave) {
    $('temporalTitulo').textContent = titulo; $('temporalPara').textContent = para;
    $('temporalClave').textContent = clave; limpiarAviso('temporalMensaje');
    mostrar('modalTemporal', true);
  }
  $('btnCopiarTemporal').addEventListener('click', function () {
    var t = $('temporalClave').textContent;
    var ok = function () { aviso('temporalMensaje', 'Copiada.', 'ok'); };
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(t).then(ok, function () { aviso('temporalMensaje', 'No se pudo copiar: seleccionala y copiala a mano.'); });
    else aviso('temporalMensaje', 'Seleccionala y copiala a mano.');
  });
  $('btnCerrarTemporal').addEventListener('click', function () { $('temporalClave').textContent = ''; mostrar('modalTemporal', false); cargarSeguridad(); });

  $('btnNuevoUsuario').addEventListener('click', function () {
    $('nuevoNombre').value = ''; $('nuevoEmail').value = ''; llenarSelectRoles($('nuevoRol'), false, true);
    if (Array.prototype.some.call($('nuevoRol').options, function (o) { return o.value === 'usuario'; })) $('nuevoRol').value = 'usuario';
    limpiarAviso('nuevoMensaje'); mostrar('modalNuevo', true); setTimeout(function () { $('nuevoNombre').focus(); }, 50);
  });
  $('formNuevo').addEventListener('submit', function (ev) {
    ev.preventDefault(); $('btnCrearUsuario').disabled = true; limpiarAviso('nuevoMensaje');
    var nombre = $('nuevoNombre').value.trim(), email = $('nuevoEmail').value.trim(), rol = $('nuevoRol').value;
    llamarUsuarios({ accion: 'crear', nombre: nombre, email: email, rol: rol }).then(function (j) {
      mostrar('modalNuevo', false);
      mostrarTemporal('Usuario creado', nombre + ' · ' + j.email + ' · rol ' + nombreRol(rol), j.clave_temporal);
    }).catch(function (e) { aviso('nuevoMensaje', textoError(e)); })
      .then(function () { $('btnCrearUsuario').disabled = false; });
  });

  function abrirBlanqueo(u) { blanqueando = u; limpiarAviso('blanquearMensaje'); $('blanquearPara').textContent = u.nombre + ' · ' + u.email; mostrar('modalBlanquear', true); }
  $('btnConfirmarBlanqueo').addEventListener('click', function () {
    if (!blanqueando) return; var u = blanqueando;
    $('btnConfirmarBlanqueo').disabled = true; limpiarAviso('blanquearMensaje');
    llamarUsuarios({ accion: 'blanquear', id: u.id }).then(function (j) {
      mostrar('modalBlanquear', false);
      mostrarTemporal('Contraseña blanqueada', u.nombre + ' · ' + j.email, j.clave_temporal);
    }).catch(function (e) { aviso('blanquearMensaje', textoError(e)); })
      .then(function () { $('btnConfirmarBlanqueo').disabled = false; });
  });

  // --- Roles ---
  function pintarRoles() {
    var tb = $('tablaRoles'); tb.innerHTML = ''; limpiarAviso('rolesMensaje');
    if (!ROLES.length) { var tr0 = document.createElement('tr'); celda(tr0, 'No hay roles.', 'gris').colSpan = 6; tb.appendChild(tr0); return; }
    ROLES.forEach(function (x) {
      var tr = document.createElement('tr');
      celda(tr, x.nombre); celda(tr, x.codigo, 'gris'); celda(tr, x.descripcion || '', 'gris'); celda(tr, x.usuarios);
      chip(celda(tr, ''), x.activo ? 'Activo' : 'Desactivado', x.activo ? 'activo' : 'inactivo');
      var td = celda(tr, ''); var caja = document.createElement('div'); caja.className = 'seg-acciones'; td.appendChild(caja);
      if (x.codigo !== 'super') {
        var b = document.createElement('button'); b.type = 'button'; b.className = 'btn secundario chico'; b.textContent = 'Editar';
        b.addEventListener('click', function () { abrirRol(x); }); caja.appendChild(b);
      }
      var b2 = document.createElement('button'); b2.type = 'button'; b2.className = 'btn secundario chico'; b2.textContent = 'Permisos';
      b2.addEventListener('click', function () { $('segRolPermisos').value = x.codigo; cargarGrillaPermisos(); $('segPermisos').scrollIntoView({ behavior: 'smooth' }); });
      caja.appendChild(b2);
      tb.appendChild(tr);
    });
  }
  function abrirRol(x) {
    rolEditando = x || null; limpiarAviso('rolMensaje');
    $('rolTitulo').textContent = x ? 'Editar rol' : 'Nuevo rol';
    $('rolAyuda').textContent = x ? 'El código no se cambia. Desactivar un rol solo se puede si no tiene usuarios activos.' : 'Un rol nuevo nace sin acceso a ningún módulo: después marcás sus permisos.';
    $('rolNombre').value = x ? x.nombre : ''; $('rolCodigo').value = x ? x.codigo : ''; $('rolCodigo').readOnly = !!x;
    $('rolDescripcion').value = x ? (x.descripcion || '') : ''; $('rolActivo').checked = x ? !!x.activo : true;
    mostrar('modalRol', true); setTimeout(function () { $('rolNombre').focus(); }, 50);
  }
  $('btnNuevoRol').addEventListener('click', function () { abrirRol(null); });
  $('rolNombre').addEventListener('input', function () {
    if (rolEditando) return;
    $('rolCodigo').value = $('rolNombre').value.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '_').replace(/^[^a-z]+/, '').replace(/_+$/, '').slice(0, 30);
  });
  $('formRol').addEventListener('submit', function (ev) {
    ev.preventDefault(); $('btnGuardarRol').disabled = true; limpiarAviso('rolMensaje');
    var cod = $('rolCodigo').value.trim();
    sb.rpc('api_seg_rol_guardar', { p_codigo: cod, p_nombre: $('rolNombre').value, p_descripcion: $('rolDescripcion').value, p_activo: $('rolActivo').checked })
      .then(function (r) {
        if (r.error) { aviso('rolMensaje', textoError(r.error)); return; }
        mostrar('modalRol', false);
        return cargarRoles().then(function () { pintarRoles(); $('segRolPermisos').value = r.data.codigo; cargarGrillaPermisos(); });
      }).catch(function (e) { aviso('rolMensaje', 'Error de conexión: ' + textoError(e)); })
      .then(function () { $('btnGuardarRol').disabled = false; });
  });

  // --- Permisos (grilla por módulo del rol elegido) ---
  $('segRolPermisos').addEventListener('change', cargarGrillaPermisos);
  function cargarGrillaPermisos() {
    var rol = $('segRolPermisos').value, tb = $('tablaPermisos'); limpiarAviso('permisosMensaje');
    if (!rol) { tb.innerHTML = '<tr><td colspan="4" class="gris">Elegí un rol.</td></tr>'; return; }
    tb.innerHTML = '<tr><td colspan="4" class="gris">Cargando…</td></tr>';
    sb.rpc('api_seg_permisos', { p_rol: rol }).then(function (r) {
      tb.innerHTML = '';
      if (r.error) { aviso('permisosMensaje', 'No se pudieron leer: ' + textoError(r.error)); return; }
      var esSuper = rol === 'super';
      (r.data || []).forEach(function (p) {
        var tr = document.createElement('tr'); celda(tr, p.nombre);
        var sel = document.createElement('select');
        [['no', 'No ve'], ['ve', 'Ve'], ['exporta', 'Ve y exporta']].forEach(function (o) { var op = document.createElement('option'); op.value = o[0]; op.textContent = o[1]; sel.appendChild(op); });
        sel.value = p.nivel; sel.disabled = esSuper; celda(tr, '').appendChild(sel);
        var tdc = celda(tr, ''), chk = null;
        if (p.tiene_carga) {
          var lab = document.createElement('label'); lab.className = 'check'; chk = document.createElement('input'); chk.type = 'checkbox';
          chk.checked = !!p.carga; chk.disabled = esSuper || p.nivel === 'no'; lab.appendChild(chk); lab.appendChild(document.createTextNode(' Agregar seguimiento')); tdc.appendChild(lab);
        } else { tdc.textContent = '—'; tdc.className = 'gris'; }
        var est = celda(tr, esSuper ? 'Siempre todo' : '', 'gris');
        function guardar() {
          if (chk) { if (sel.value === 'no') chk.checked = false; chk.disabled = sel.value === 'no'; }
          est.textContent = 'Guardando…'; sel.disabled = true; if (chk) chk.disabled = true;
          sb.rpc('api_seg_permiso_guardar', { p_rol: rol, p_modulo: p.modulo, p_nivel: sel.value, p_carga: chk ? chk.checked : false })
            .then(function (x) { est.textContent = x.error ? ('Error: ' + textoError(x.error)) : 'Guardado'; })
            .catch(function (e) { est.textContent = 'Error de conexión: ' + textoError(e); })
            .then(function () { sel.disabled = false; if (chk) chk.disabled = sel.value === 'no'; });
        }
        if (!esSuper) { sel.addEventListener('change', guardar); if (chk) chk.addEventListener('change', guardar); }
        tb.appendChild(tr);
      });
    }).catch(function (e) { tb.innerHTML = ''; aviso('permisosMensaje', 'Error de conexión: ' + textoError(e)); });
  }

  // --- Bitácora ---
  function detalleBitacora(b) {
    var d = b.detalle || {};
    if (d.despues && d.antes && d.despues.rol !== undefined && d.modulo === undefined && d.rol === undefined)
      return 'rol ' + d.antes.rol + ' → ' + d.despues.rol + ', ' + (d.antes.activo ? 'activo' : 'inactivo') + ' → ' + (d.despues.activo ? 'activo' : 'inactivo');
    if (d.modulo) return 'rol ' + d.rol + ' · ' + d.modulo + ': ' + (d.antes && d.antes.nivel || 'sin dato') + ' → ' + d.despues.nivel + (d.despues.carga ? ' + carga' : '');
    if (d.rol && d.despues) return 'rol ' + d.rol + ' → ' + d.despues.nombre + (d.despues.activo ? '' : ' (desactivado)');
    if (d.clave) return (d.rol ? 'rol ' + d.rol + ' · ' : '') + 'contraseña ' + d.clave;
    return d.email || d.motivo || '';
  }
  function cargarBitacora() {
    var tb = $('tablaBitacora'); tb.innerHTML = '<tr><td colspan="5" class="gris">Cargando…</td></tr>';
    sb.rpc('api_seg_bitacora', { p_limite: 1000 }).then(function (r) {
      if (r.error) { tb.innerHTML = ''; var tre = document.createElement('tr'); celda(tre, 'No se pudo leer: ' + textoError(r.error)).colSpan = 5; tb.appendChild(tre); return; }
      BITACORA = r.data || [];
      var acciones = {}; BITACORA.forEach(function (b) { acciones[b.accion] = true; });
      var sel = $('segFiltroAccion'), v = sel.value; sel.innerHTML = '<option value="">Todas las acciones</option>';
      Object.keys(acciones).sort().forEach(function (a) { var o = document.createElement('option'); o.value = a; o.textContent = a; sel.appendChild(o); });
      sel.value = v; pintarBitacora();
    }).catch(function (e) { tb.innerHTML = ''; var tr = document.createElement('tr'); celda(tr, 'Error de conexión: ' + textoError(e)).colSpan = 5; tb.appendChild(tr); });
  }
  ['segBuscarBitacora', 'segFiltroAccion', 'segBitDesde', 'segBitHasta'].forEach(function (id) { $(id).addEventListener('input', pintarBitacora); });
  function bitacoraFiltrada() {
    var q = $('segBuscarBitacora').value.trim().toLowerCase(), fa = $('segFiltroAccion').value, d = $('segBitDesde').value, h = $('segBitHasta').value;
    return BITACORA.filter(function (b) {
      var dia = b.cuando ? new Date(b.cuando).toLocaleDateString('sv-SE') : '';
      if (fa && b.accion !== fa) return false;
      if (d && dia < d) return false;
      if (h && dia > h) return false;
      if (q && [b.quien, b.accion, b.sobre, detalleBitacora(b)].join(' ').toLowerCase().indexOf(q) < 0) return false;
      return true;
    });
  }
  function pintarBitacora() {
    var tb = $('tablaBitacora'); tb.innerHTML = ''; var lista = bitacoraFiltrada();
    if (!lista.length) { var tr0 = document.createElement('tr'); celda(tr0, BITACORA.length ? 'Ningún movimiento cumple el filtro.' : 'Sin movimientos.', 'gris').colSpan = 5; tb.appendChild(tr0); }
    lista.forEach(function (b) {
      var tr = document.createElement('tr');
      celda(tr, fechaHora(b.cuando), 'gris'); celda(tr, b.quien); celda(tr, b.accion); celda(tr, b.sobre || ''); celda(tr, detalleBitacora(b), 'gris');
      tb.appendChild(tr);
    });
    $('bitacoraPie').textContent = 'Mostrando ' + lista.length + ' de ' + BITACORA.length + ' movimientos (los últimos 1.000).';
  }
  $('btnBitacoraCsv').addEventListener('click', function () {
    var filas = [['Cuando', 'Quien', 'Accion', 'Sobre', 'Detalle']];
    bitacoraFiltrada().forEach(function (b) { filas.push([fechaHora(b.cuando), b.quien, b.accion, b.sobre || '', detalleBitacora(b)]); });
    var txt = filas.map(function (f) { return f.map(function (v) { v = v == null ? '' : String(v); return /[;"\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; }).join(';'); }).join('\r\n');
    var bl = new Blob(['﻿' + txt], { type: 'text/csv;charset=utf-8' }), a = document.createElement('a');
    a.href = URL.createObjectURL(bl); a.download = 'bitacora_seguridad.csv'; document.body.appendChild(a); a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 500);
  });

  // ---------- Mi contraseña ----------
  $('btnMiClave').addEventListener('click', function () { abrirCambioClave(false); });
  $('formClave').addEventListener('submit', function (ev) {
    ev.preventDefault();
    var a = $('clave1').value, b = $('clave2').value;
    if (a.length < 8) { aviso('claveMensaje', 'Tiene que tener al menos 8 caracteres.'); return; }
    if (a !== b) { aviso('claveMensaje', 'Las dos no coinciden.'); return; }
    $('btnGuardarClave').disabled = true;
    sb.auth.updateUser({ password: a }).then(function (r) {
      $('clave1').value = ''; $('clave2').value = '';
      if (r.error) { aviso('claveMensaje', /different from the old|same/i.test(r.error.message) ? 'Tiene que ser distinta de la anterior.' : textoError(r.error)); return; }
      if (CLAVE_OBLIGATORIA) { CLAVE_OBLIGATORIA = false; mostrar('modalClave', false); return cargarPerfil(false); }
      aviso('claveMensaje', 'Listo, tu contraseña quedó cambiada.', 'ok');
    }).catch(function (e) { aviso('claveMensaje', 'Error de conexión: ' + textoError(e)); })
      .then(function () { $('btnGuardarClave').disabled = false; });
  });

  $('formLogin').addEventListener('submit', function (ev) {
    ev.preventDefault();
    var email = $('loginEmail').value.trim(), clave = $('loginClave').value;
    $('btnEntrar').disabled = true; $('btnEntrar').textContent = 'Ingresando…'; limpiarAviso('loginMensaje');
    sb.auth.signInWithPassword({ email: email, password: clave }).then(function (r) {
      $('loginClave').value = '';
      if (r.error) { aviso('loginMensaje', /Invalid login/i.test(r.error.message) ? 'Email o contraseña incorrectos.' : textoError(r.error)); return; }
      return cargarPerfil(true);
    }).catch(function (e) { aviso('loginMensaje', 'Error de conexión: ' + textoError(e)); })
      .then(function () { $('btnEntrar').disabled = false; $('btnEntrar').textContent = 'Ingresar'; });
  });

  // PERMISOS: lo que la base dice que puede ver ESTE usuario (pantalla -> {nivel, carga}). Sin dato = no ve.
  var PERMISOS = {};
  var CLAVE_OBLIGATORIA = false;

  function cargarPerfil(recienIngresa) {
    return sb.rpc('api_seg_yo_v2').then(function (r) {
      if (r.error || !r.data || !r.data.length) {
        var t = r.error ? textoError(r.error) : 'No se encontró tu perfil.';
        return sb.auth.signOut().then(function () { mostrarLogin(t === 'Tu usuario no está activo.' ? 'Tu usuario todavía no está activo. Pedile a un administrador que lo active.' : t); });
      }
      YO = r.data[0];
      if (!YO.activo) return sb.auth.signOut().then(function () { mostrarLogin('Tu usuario no está activo. Pedile a un administrador que lo active.'); });
      $('nombreUsuario').textContent = YO.nombre; $('rolUsuario').textContent = YO.rol_nombre || YO.rol;
      $('avatarInicial').textContent = (YO.nombre || '?').charAt(0).toUpperCase();
      if (recienIngresa) sb.rpc('api_seg_registrar_ingreso').then(function () {}, function () {});
      mostrar('zonaLogin', false); mostrar('zonaApp', true);
      if (YO.debe_cambiar_clave) { pedirClaveObligatoria(); return; }
      return cargarPermisos();
    }).catch(function (e) { mostrarLogin('Error de conexión: ' + textoError(e)); });
  }

  function cargarPermisos() {
    return sb.rpc('api_seg_mis_permisos').then(function (r) {
      PERMISOS = {};
      document.querySelectorAll('#menu .nav-item').forEach(function (n) { n.classList.remove('permitido'); });
      if (r.error) { mostrarSinAcceso('No se pudieron leer tus permisos: ' + textoError(r.error)); return; }
      (r.data || []).forEach(function (p) { if (p.nivel && p.nivel !== 'no') PERMISOS[p.pantalla] = { nivel: p.nivel, carga: !!p.carga, nombre: p.nombre, orden: p.orden }; });
      document.querySelectorAll('#menu .nav-item').forEach(function (n) { if (PERMISOS[n.dataset.modulo]) n.classList.add('permitido'); });
      var primero = primeraPantalla();
      if (!primero) { mostrarSinAcceso('Tu rol no tiene ningún módulo habilitado. Pedile a un administrador que te asigne permisos.'); return; }
      irA(PERMISOS.Inicio ? 'Inicio' : primero);
    }).catch(function (e) { mostrarSinAcceso('Error de conexión: ' + textoError(e)); });
  }

  function primeraPantalla() {
    var mejor = null;
    Object.keys(PERMISOS).forEach(function (k) { if (!mejor || PERMISOS[k].orden < PERMISOS[mejor].orden) mejor = k; });
    return mejor;
  }

  function mostrarSinAcceso(texto) {
    document.querySelectorAll('.modulo').forEach(function (m) { m.classList.remove('visible'); });
    $('tituloModulo').textContent = 'Sin acceso';
    var c = $('avisoSinAcceso');
    if (!c) { c = document.createElement('div'); c.id = 'avisoSinAcceso'; c.className = 'mensaje error'; $('contenido').insertBefore(c, $('contenido').firstChild); }
    c.textContent = texto; c.classList.remove('oculto');
  }

  $('btnSalir').addEventListener('click', function () { sb.auth.signOut().catch(function () {}).then(function () { YO = null; PERMISOS = {}; mostrarLogin(); }); });

  // ---------- menu ----------
  var TITULOS = { Inicio: 'Radar · Tablero central', Seguridad: 'Seguridad' };
  var CARGAS = { Inicio: cargarInicio, Seguridad: cargarSeguridad };
  $('menu').addEventListener('click', function (ev) {
    var item = ev.target.closest('.nav-item'); if (!item || item.classList.contains('deshabilitado') || !item.dataset.modulo) return;
    irA(item.dataset.modulo);
  });
  function irA(modulo) {
    if (CLAVE_OBLIGATORIA) { pedirClaveObligatoria(); return; }
    var aviso0 = $('avisoSinAcceso'); if (aviso0) aviso0.classList.add('oculto');
    if (!PERMISOS[modulo]) {   // falla cerrado: lo que la base no habilitó, no se abre (ni desde un clic del Radar)
      var p = primeraPantalla();
      if (!p) { mostrarSinAcceso('Tu rol no tiene ningún módulo habilitado.'); return; }
      mostrarSinAcceso('Tu rol no tiene acceso a ' + (TITULOS[modulo] || modulo) + '.');
      return;
    }
    var per = PERMISOS[modulo];
    document.body.setAttribute('data-exporta', per.nivel === 'exporta' ? '1' : '0');
    document.body.setAttribute('data-carga', per.carga ? '1' : '0');
    document.querySelectorAll('.nav-item').forEach(function (n) { n.classList.toggle('activo', n.dataset.modulo === modulo); });
    document.querySelectorAll('.modulo').forEach(function (m) { m.classList.toggle('visible', m.id === 'mod' + modulo); });
    var ext = (window.MODULOS || {})[modulo];
    $('tituloModulo').textContent = TITULOS[modulo] || (ext && ext.titulo) || modulo;
    if (CARGAS[modulo]) CARGAS[modulo](); else if (ext) ext.cargar();
  }

  // ---------- Contraseña: botón visible arriba y cambio obligatorio si es temporal ----------
  function abrirCambioClave(obligatoria) {
    $('clave1').value = ''; $('clave2').value = ''; limpiarAviso('claveMensaje');
    $('claveAyuda').textContent = obligatoria ? 'Tu contraseña es temporal: elegí una nueva para seguir. Mínimo 8 caracteres.' : 'Mínimo 8 caracteres.';
    mostrar('btnCancelarClave', !obligatoria);
    mostrar('modalClave', true);
    setTimeout(function () { $('clave1').focus(); }, 50);
  }
  function pedirClaveObligatoria() {
    CLAVE_OBLIGATORIA = true;
    document.querySelectorAll('.modulo').forEach(function (m) { m.classList.remove('visible'); });
    $('tituloModulo').textContent = 'Cambiar contraseña';
    abrirCambioClave(true);
  }
  $('btnCambiarClave').addEventListener('click', function () { abrirCambioClave(false); });

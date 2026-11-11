  function textoError(e) {
    var m = (e && (e.message || e.error_description || e.error)) || String(e);
    if (/usuario sin perfil activo/.test(m)) return 'Tu usuario no está activo.';
    if (/Tenés que cambiar tu contraseña/.test(m)) return 'Tenés que cambiar tu contraseña antes de seguir.';
    var d = /Acceso denegado: (.*)/.exec(m);
    if (d) return d[1].charAt(0).toUpperCase() + d[1].slice(1) + '.';
    if (/No autorizado/.test(m)) return 'No tenés permiso para esto.';
    return m; }
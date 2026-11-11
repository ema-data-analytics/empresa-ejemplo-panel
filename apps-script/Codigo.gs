/**
 * Sistema de Gestion — EMPRESA EJEMPLO. EMA DATA ANALYTIC.
 *
 * Este archivo solo sirve la pagina. No habla con la base ni guarda sesiones:
 * el login y los datos van directo del navegador de cada usuario a Supabase,
 * con el permiso de ESE usuario. Asi cada uno tiene su propia sesion y la base
 * decide que puede ver cada uno (perfil activo, rol).
 *
 * No hay ninguna funcion que se pueda llamar desde el navegador (google.script.run):
 * todas las auxiliares terminan en "_" y Apps Script las deja privadas.
 *
 * Propiedades del Script (Configuracion del proyecto -> Propiedades del script):
 *   SUPABASE_URL              https://ushvdubzbpctctodujen.supabase.co
 *   SUPABASE_PUBLISHABLE_KEY  la clave PUBLICABLE (anon) del proyecto. Nunca la de servicio.
 * Ninguna clave se escribe en este codigo.
 */

function doGet() {
  var props = PropertiesService.getScriptProperties();
  var clave = props.getProperty('SUPABASE_PUBLISHABLE_KEY') || '';
  var aviso = '';
  // Candado: si por error se carga la clave SECRETA (o la service_role), NO se manda a la pagina.
  if (esClaveSecreta_(clave)) {
    clave = '';
    aviso = 'La propiedad SUPABASE_PUBLISHABLE_KEY tiene una clave SECRETA. Por seguridad no se usa. Cargar la clave publicable (empieza con sb_publishable_).';
  }
  var t = HtmlService.createTemplateFromFile('Index');
  t.cfg = JSON.stringify({
    url: props.getProperty('SUPABASE_URL') || '',
    clave: clave,
    aviso: aviso
  });
  return t.evaluate()
    .setTitle('Empresa Ejemplo · Sistema de Gestión')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1');
}

/** true si la clave es secreta: formato nuevo sb_secret_ o JWT viejo con role service_role. Privada. */
function esClaveSecreta_(clave) {
  if (!clave) return false;
  if (/^sb_secret_/i.test(clave)) return true;
  var partes = clave.split('.');
  if (partes.length === 3) {
    try {
      var s = partes[1]; while (s.length % 4) s += '=';
      var json = Utilities.newBlob(Utilities.base64DecodeWebSafe(s)).getDataAsString();
      return /"role"\s*:\s*"service_role"/.test(json);
    } catch (e) { return true; }   // si no se puede leer, no se arriesga
  }
  return false;
}

/** Se usa desde las plantillas HTML para sumar cada modulo. Privada. */
function incluir_(nombre) {
  return HtmlService.createHtmlOutputFromFile(nombre).getContent();
}

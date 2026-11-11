# Arma index.html (panel estático para GitHub Pages) desde fuente/Index.html (el de Apps Script) y sus módulos.
# Cada cambio se aplica sobre un ancla que tiene que aparecer EXACTAMENTE una vez: si no, corta y no escribe nada.
# Uso: python3 herramientas/armar_panel.py   (desde la raíz del repo)
import re, hashlib, sys, os

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
F = lambda *p: os.path.join(RAIZ, *p)
src = open(F('fuente', 'Index.html'), encoding='utf-8').read()
PARTES = os.path.join(RAIZ, 'herramientas', 'partes')
parte = lambda n: open(os.path.join(PARTES, n), encoding='utf-8').read()

def una_vez(texto, ancla, nuevo, nombre):
    n = texto.count(ancla)
    if n != 1:
        sys.exit('CORTE: el ancla "%s" aparece %d veces (tiene que ser 1)' % (nombre, n))
    return texto.replace(ancla, nuevo)

URL = 'https://ushvdubzbpctctodujen.supabase.co'
CLAVE = 'sb_publishable_yALG3r--TgrZWHCqUXggoA_ZGdZCFM_'   # publicable: hecha para el navegador. La de servicio NUNCA va acá.
assert CLAVE.startswith('sb_publishable_')

s = src
# 1. Configuración fija (en Apps Script venía de las Propiedades del Script)
s = una_vez(s, 'var CFG = <?!= cfg ?>;', "var CFG = { url: '%s', clave: '%s', aviso: '' };" % (URL, CLAVE), 'CFG')
s = una_vez(s, '  <base target="_top">\n', '  <title>Empresa Ejemplo · Sistema de Gestión</title>\n  <meta name="viewport" content="width=device-width, initial-scale=1">\n', 'base')
# 2. CSS nuevo (permisos y Seguridad)
s = una_vez(s, '    .oculto { display:none !important; }', '    .oculto { display:none !important; }\n' + parte('estilos.css'), 'css')
# 3. Botón visible "Cambiar contraseña" arriba, al lado de Imprimir / PDF
s = una_vez(s, '<div id="fechaHoy"></div>', '<button class="btn secundario chico" id="btnCambiarClave" type="button" title="Cambiar mi contraseña">Cambiar contraseña</button><div id="fechaHoy"></div>', 'topbar')
# 3b. El ítem Seguridad del menú ya no se esconde con "oculto": lo habilita la base (clase permitido), como los demás
s = una_vez(s, '<div class="nav-item oculto" id="navSeguridad" data-modulo="Seguridad">', '<div class="nav-item" id="navSeguridad" data-modulo="Seguridad">', 'nav seguridad')
# 4. Pantalla Seguridad completa (reemplaza la vieja)
ini = s.index('        <!-- Seguridad (solo super) -->')
fin = s.index('        </section>', ini) + len('        </section>')
if s.count('        <!-- Seguridad (solo super) -->') != 1: sys.exit('CORTE: Seguridad vieja')
s = s[:ini] + parte('seguridad.html') + s[fin:]
# 5. Ventanas nuevas (alta, clave temporal, blanquear, rol) antes de "mi contraseña"
s = una_vez(s, '<!-- Ventana: mi contraseña -->', parte('ventanas.html') + '\n<!-- Ventana: mi contraseña -->', 'ventanas')
s = una_vez(s, '<h4>Cambiar mi contraseña</h4><div class="gris">Mínimo 8 caracteres.</div>',
            '<h4>Cambiar mi contraseña</h4><div class="gris" id="claveAyuda">Mínimo 8 caracteres.</div>', 'ayuda clave')
s = una_vez(s, '<button type="button" class="btn secundario" data-cerrar="modalClave">Cancelar</button>',
            '<button type="button" class="btn secundario" data-cerrar="modalClave" id="btnCancelarClave">Cancelar</button>', 'cancelar clave')
# 6. Editar usuario: el rol sale de la tabla de roles (no fijo)
s = una_vez(s, '<select id="editarRol"><option value="usuario">Usuario</option><option value="admin">Admin</option><option value="super">Super (administra usuarios)</option></select>',
            '<select id="editarRol"></select>', 'select rol')
# 7. JavaScript: todo el bloque de perfil, menú y Seguridad se reemplaza por el nuevo
ini = s.index('  function textoError(e) {')
fin = s.index('    return m; }', ini) + len('    return m; }')
s = s[:ini] + parte('texto_error.js') + s[fin:]
ini = s.index('  $(\'formLogin\').addEventListener(\'submit\'')
fin = s.index('  // ---------- Tablero central ----------')
s = s[:ini] + parte('perfil_menu.js') + '\n' + s[fin:]
ini = s.index('  // ---------- Seguridad ----------')
fin = s.index('  document.querySelectorAll(\'[data-cerrar]\')')
s = s[:ini] + parte('seguridad.js') + '\n' + s[fin:]

# 8. Módulos adentro
s = re.sub(r"<\?!= incluir_\('(\w+)'\); \?>", lambda m: open(F('fuente', m.group(1) + '.html'), encoding='utf-8').read(), s)
# Puerta: dos funciones con el mismo nombre en el script principal (pasó el 11/11: la segunda pisaba a la primera)
from collections import Counter
principal = re.findall(r'<script>(.*?)</script>', s, re.S)[-1]
rep = [k for k, v in Counter(re.findall(r'^\s*function\s+([A-Za-z0-9_$]+)', principal, re.M)).items() if v > 1]
if rep:
    sys.exit('CORTE: funciones repetidas en el script principal: %s' % ', '.join(rep))
ids = re.findall(r'\bid="([^"]+)"', s)
rep = [k for k, v in Counter(ids).items() if v > 1]
if rep:
    sys.exit('CORTE: ids repetidos: %s' % ', '.join(rep))
for prohibido in ['<?', 'incluir_(', 'google.script', 'sb_secret_', 'service_role']:
    if prohibido in s:
        sys.exit('CORTE: quedó "%s" en el panel' % prohibido)
open(F('index.html'), 'w', encoding='utf-8').write(s)
print('index.html', len(s.encode('utf-8')), 'bytes  sha256', hashlib.sha256(s.encode('utf-8')).hexdigest())

# Herramienta de Migración de Historial - Antigravity IDE

Este directorio contiene la herramienta diseñada para migrar automáticamente el historial de conversaciones y proyectos recientes de la barra lateral desde una instalación antigua de **Antigravity** a la nueva versión de **Antigravity IDE**.

---

## ¿Qué hace esta herramienta?

Cuando actualizas el IDE, la ruta de datos locales cambia de `Antigravity` a `Antigravity IDE`, lo que provoca que la barra lateral aparezca vacía (solo con las conversaciones de la sesión actual). 

Este script soluciona este problema de manera automatizada:
1. **Fusión Inteligente de la Base de Datos (`state.vscdb`):** 
   * Combina el historial antiguo (resúmenes de conversaciones) con el historial nuevo en la clave `trajectorySummaries`, deduplicándolos por su UUID único.
   * Fusiona los proyectos recientes de la barra lateral (`sidebarWorkspaces`) para que no tengas que volver a abrirlos manualmente.
2. **Espera Segura al Cierre del IDE:**
   * VS Code (en el que se basa el IDE) guarda su estado de la UI al cerrarse. Si modificas la base de datos con el IDE abierto, al cerrarlo se sobrescribirán los cambios.
   * El script detecta si el IDE está abierto y se queda esperando en segundo plano. En cuanto cierras el IDE, aplica la migración en menos de 1 segundo de forma totalmente segura.
3. **Copia de Archivos de Sesión:**
   * Copia los archivos de conversación `.pb` y los logs completos en la carpeta `brain/` de las sesiones antiguas a la nueva instalación.

---

## Archivos del Proyecto

* **`migrate_antigravity.py`:** El script de migración en Python portable y dinámico.
* **`README.md`:** Esta guía de uso.

---

## 🐧 Instalación de Antigravity IDE en Linux

Si necesitas instalar **Antigravity IDE** en tu sistema Linux, puedes seguir estos pasos para descargarlo, extraerlo y configurarlo adecuadamente:

### 1. Obtener dinámicamente el enlace de la última versión estable
Los detalles de los lanzamientos estables se obtienen de la API de lanzamientos. Para automatizar la descarga de la última versión, se realiza una petición a `https://antigravity-ide-auto-updater-974169037036.us-central1.run.app/releases` y se obtiene la primera versión de la lista para construir la URL de descarga.

La estructura de la URL de descarga para la versión de Linux de 64 bits es la siguiente:
```text
https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/{versión}-{execution_id}/linux-x64/Antigravity%20IDE.tar.gz
```

### 2. Comandos de terminal
Ejecuta los siguientes comandos para descargar dinámicamente la última versión estable, descomprimir, configurar los permisos de ejecución del IDE y de su sandbox, y finalmente iniciar la aplicación:

```bash
# Opción A: Obtener la última versión con 'jq'
LATEST_RELEASE=$(curl -s https://antigravity-ide-auto-updater-974169037036.us-central1.run.app/releases | jq -r '.[0] | "\(.version)-\(.execution_id)"')

# Opción B: Obtener la última versión con 'python3' (si no tienes 'jq' instalado)
# LATEST_RELEASE=$(curl -s https://antigravity-ide-auto-updater-974169037036.us-central1.run.app/releases | python3 -c "import sys, json; r=json.load(sys.stdin)[0]; print(f\"{r['version']}-{r['execution_id']}\")")

# Descargar el archivo usando la URL construida dinámicamente
wget "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${LATEST_RELEASE}/linux-x64/Antigravity%20IDE.tar.gz"

# Extraer el archivo tar.gz
tar -xzf "Antigravity IDE.tar.gz"

# Renombrar la carpeta extraída a Antigravity_IDE
mv "Antigravity IDE" Antigravity_IDE

# Entrar al directorio
cd Antigravity_IDE

# Asignar permisos de ejecución al binario principal
chmod +x antigravity-ide

# Configurar permisos para chrome-sandbox (necesario para el sandboxing de Chromium)
sudo chown root:root chrome-sandbox
sudo chmod 4755 chrome-sandbox

# Ejecutar Antigravity IDE
./antigravity-ide
```

---

## Cómo Ejecutar la Migración

```bash
python migrate_antigravity.py
```
*El script te mostrará el mensaje: `Waiting for Antigravity IDE to close...`*

### Paso 3: Cerrar el IDE
1. Cierra completamente la ventana de **Antigravity IDE**.
2. Al cerrarse, el script detectará el cierre automáticamente, esperará 2 segundos y completará el proceso de migración mostrando:
   ```text
   Antigravity IDE closed! Waiting 2 seconds for locks to release...
   Step 1: Merging globalState keys in state.vscdb...
     Merged 101 old and 7 new -> 108 entries.
   ...
   ALL MIGRATION STEPS SUCCESSFUL!
   ```

### Paso 4: Reabrir el IDE
Vuelve a abrir **Antigravity IDE**. ¡Listo! Todo tu historial de conversaciones y tus proyectos previos aparecerán cargados y listos en la interfaz de usuario.

---

## 🔌 Administración y Sincronización de Plugins de Claude

Esta carpeta también incluye herramientas para portar y sincronizar los plugins oficiales de **Claude Code**, así como instalar plugins de desarrolladores externos, para que funcionen con **Antigravity CLI** en cualquier entorno (Windows, macOS o Linux).

### Instalación Directa desde Internet (Recomendado)

Puedes ejecutar los instaladores directamente sin necesidad de clonar previamente el repositorio.

#### A. Sincronizar repositorio oficial de Claude (Optimizado para Antigravity)

Por defecto, los scripts implementan **optimización inteligente de la ventana de contexto** (`Customization Token Budget`). Se instalan las herramientas esenciales de desarrollo (`feature-dev`, `code-review`, `code-simplifier`, `commit-commands`, `pr-review-toolkit`, `frontend-design`, `mcp-server-dev`, `hookify`, `playwright`, etc.) y **se omiten automáticamente los plugins redundantes o no esenciales**:
* **LSPs de lenguajes (12 plugins):** `clangd`, `pyright`, `typescript-lsp`, `rust-analyzer`, etc. (*Antigravity IDE ya incluye soporte nativo integrado para estos lenguajes a través de su motor VS Code*).
* **Herramientas exclusivas del CLI de Claude:** `receipts`, `session-report`, `claude-md-management`, `claude-security` (*diseñadas para `~/.claude/projects` y Claude Code CLI*).
* **Puentes de mensajería externa:** `discord`, `telegram`, `imessage` (*inyectan skills persistentes de configuración/acceso en cada turno*).
* **Herramientas de nicho:** `cwc-makers` (firmware M5Stack Cardputer), `math-olympiad`, `math-proof`.
* **Servicios externos no configurados:** `asana`, `linear`, `gitlab`, `laravel-boost`, `fakechat`, `explanatory-output-style`.

> 💡 **Limpieza automática:** Al ejecutar la sincronización estándar, el script también desinstala automáticamente los plugins excluidos que hayan quedado de versiones previas, liberando de inmediato tokens de personalización para evitar el aviso de *"Customization token budget exceeded"*.

**Windows (PowerShell):**

> ⚠️ **Importante:** Ejecuta tu terminal de PowerShell **como Administrador** para evitar errores de permisos con Git (`fatal: detected dubious ownership in repository`).

```powershell
# Sincronización estándar optimizada (Recomendada)
irm https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.ps1 | iex

# Para incluir plugins específicos que normalmente se excluirían (ej: math-olympiad, pyright-lsp):
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.ps1))) -Include "math-olympiad,pyright-lsp"

# Para eliminar una skill o plugin específico (ej: science, math-olympiad):
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.ps1))) -Remove "science"

# Para forzar la instalación de TODOS los plugins (incluyendo LSPs y nichos):
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.ps1))) -All

# Para realizar solo limpieza de plugins no esenciales instalados previamente:
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.ps1))) -CleanUnneeded
```

**macOS / Linux (Bash):**

```bash
# Sincronización estándar optimizada (Recomendada)
curl -sSf https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.sh | bash

# Para incluir plugins específicos que normalmente se excluirían:
curl -sSf https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.sh | bash -s -- --include "math-olympiad,pyright-lsp"

# Para eliminar una skill o plugin específico:
curl -sSf https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.sh | bash -s -- --remove "science"

# Para forzar la instalación de TODOS los plugins:
curl -sSf https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.sh | bash -s -- --all

# Para realizar solo limpieza de plugins no esenciales:
curl -sSf https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.sh | bash -s -- --clean
```

#### B. Instalar un plugin externo desde Git

Puedes instalar un repositorio de un desarrollador externo pasando la URL de Git como argumento. El script ejecutará automáticamente un análisis de seguridad previo con **NVIDIA SkillSpector**.

**Windows (PowerShell):**

> ⚠️ **Importante:** Ejecuta tu terminal de PowerShell **como Administrador**.

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.ps1))) -ExternalUrl "https://github.com/usuario/repositorio-plugin.git"
```

*Para omitir el análisis de seguridad:*
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.ps1))) -ExternalUrl "https://github.com/usuario/repositorio-plugin.git" -SkipScan
```

**macOS / Linux (Bash):**

```bash
curl -sSf https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.sh | bash -s -- "https://github.com/usuario/repositorio-plugin.git"
```

*Para omitir el análisis de seguridad:*
```bash
curl -sSf https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.sh | bash -s -- "https://github.com/usuario/repositorio-plugin.git" --skip-scan
```

### Ejecución Local

Si prefieres descargar y ejecutar el proceso usando los scripts locales de este repositorio:

#### A. Sincronizar repositorio oficial (Optimizado)

* **Windows (Como Administrador):**
  * Optimizado (recomendado): `.\sync-claude-plugins.ps1`
  * Incluir plugins excluidos: `.\sync-claude-plugins.ps1 -Include "math-olympiad,pyright-lsp"`
  * Eliminar plugin o skill: `.\sync-claude-plugins.ps1 -Remove "science"`
  * Forzar todos: `.\sync-claude-plugins.ps1 -All`
  * Solo limpieza: `.\sync-claude-plugins.ps1 -CleanUnneeded`
* **macOS / Linux:**
  * Optimizado (recomendado): `chmod +x sync-claude-plugins.sh && ./sync-claude-plugins.sh`
  * Incluir plugins excluidos: `./sync-claude-plugins.sh --include "math-olympiad,pyright-lsp"`
  * Eliminar plugin o skill: `./sync-claude-plugins.sh --remove "science"`
  * Forzar todos: `./sync-claude-plugins.sh --all`
  * Solo limpieza: `./sync-claude-plugins.sh --clean`

#### B. Instalar un plugin externo (con escaneo de seguridad)

* **Windows (Como Administrador):** `.\sync-claude-plugins.ps1 -ExternalUrl "https://github.com/usuario/repositorio-plugin.git"`
* **Windows (Omitir escaneo):** `.\sync-claude-plugins.ps1 -ExternalUrl "https://github.com/usuario/repositorio-plugin.git" -SkipScan`
* **macOS / Linux:** `./sync-claude-plugins.sh "https://github.com/usuario/repositorio-plugin.git"`
* **macOS / Linux (Omitir escaneo):** `./sync-claude-plugins.sh "https://github.com/usuario/repositorio-plugin.git" --skip-scan`

---

## 🛡️ Escaneo de Seguridad con NVIDIA SkillSpector

Los scripts incorporan integración predeterminada con **[NVIDIA SkillSpector](https://github.com/nvidia/skillspector)**, el escáner de seguridad diseñado para detectar vulnerabilidades en skills y plugins de agentes de IA (Claude Code, Antigravity, MCP):

* **Instalación Automática:** Si `skillspector` no está instalado en tu sistema, el script lo descargará e instalará automáticamente vía `uv` (o `pip`) en la primera ejecución.
* **Uso a Demanda Ultra Rápido:** Una vez instalado, los análisis posteriores se ejecutan de manera instantánea mediante análisis estático (`--no-llm`), revisando prompt injection, exfiltración de credenciales, patrones de ejecución arbitrarios y supply-chain.
* **Bloqueo Preventivo:** Si el plugin externo supera el umbral de riesgo o presenta amenazas críticas, la instalación se aborta inmediatamente antes de copiar ningún archivo al directorio de configuración del agente (`~/.gemini/config/plugins`).
* **Omisión Opcional:** Puedes omitir la verificación de seguridad pasando el parámetro `-SkipScan` en PowerShell o `--skip-scan` en Bash si confías plenamente en el código.
* **Auditoría Manual a Demanda:** Puedes auditar cualquier plugin o skill ya instalado ejecutando:
  ```bash
  skillspector scan ~/.gemini/config/plugins/<nombre-plugin> --no-llm
  ```

---

### 🧠 Habilidad Automatizada (Skill)

Ambos scripts instalan automáticamente el plugin de administración `claude-plugins-manager`. Una vez instalado, puedes pedirle a tu agente en lenguaje natural que administre tus herramientas en el futuro:

* *"actualizar plugins"*
* *"sincronizar plugins de Claude"*
* *"instala este plugin para el CLI: https://github.com/usuario/repositorio-plugin.git"*
* *"audita la seguridad de la skill X con SkillSpector"*
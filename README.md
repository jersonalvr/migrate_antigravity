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

#### A. Sincronizar repositorio oficial de Claude

Si no especificas nada, se descargarán o actualizarán todos los plugins oficiales.

**Windows (PowerShell):**

> ⚠️ **Importante:** Ejecuta tu terminal de PowerShell **como Administrador** para evitar errores de permisos con Git (`fatal: detected dubious ownership in repository`).

```powershell
irm https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.ps1 | iex
```

**macOS / Linux (Bash):**

```bash
curl -sSf https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.sh | bash
```

#### B. Instalar un plugin externo desde Git

Puedes instalar un repositorio de un desarrollador externo pasando la URL de Git como argumento.

**Windows (PowerShell):**

> ⚠️ **Importante:** Ejecuta tu terminal de PowerShell **como Administrador**.

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.ps1))) -ExternalUrl "https://github.com/usuario/repositorio-plugin.git"
```

**macOS / Linux (Bash):**

```bash
curl -sSf https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.sh | bash -s -- "https://github.com/usuario/repositorio-plugin.git"
```

### Ejecución Local

Si prefieres descargar y ejecutar el proceso usando los scripts locales de este repositorio:

#### A. Sincronizar repositorio oficial

* **Windows (Como Administrador):** `.\sync-claude-plugins.ps1`
* **macOS / Linux:** `chmod +x sync-claude-plugins.sh && ./sync-claude-plugins.sh`

#### B. Instalar un plugin externo

* **Windows (Como Administrador):** `.\sync-claude-plugins.ps1 -ExternalUrl "https://github.com/usuario/repositorio-plugin.git"`
* **macOS / Linux:** `./sync-claude-plugins.sh "https://github.com/usuario/repositorio-plugin.git"`

### 🧠 Habilidad Automatizada (Skill)

Ambos scripts instalan automáticamente el plugin de administración `claude-plugins-manager`. Una vez instalado, puedes pedirle a tu agente en lenguaje natural que administre tus herramientas en el futuro:

* *"actualizar plugins"*
* *"sincronizar plugins de Claude"*
* *"instala este plugin para el CLI: https://github.com/usuario/repositorio-plugin.git"*
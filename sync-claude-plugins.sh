#!/bin/bash
# sync-claude-plugins.sh
# Script to synchronize official Claude Code plugins or install external skills globally

EXTERNAL_URL=""
SILENT=false
SKIP_SCAN=false
INSTALL_ALL=false
CLEAN_UNNEEDED=false
INCLUDE_PLUGINS=()
REMOVE_PLUGINS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --silent|-s)
            SILENT=true
            shift
            ;;
        --skip-scan|--skip-security-scan)
            SKIP_SCAN=true
            shift
            ;;
        --all|-a)
            INSTALL_ALL=true
            shift
            ;;
        --clean|--clean-unneeded)
            CLEAN_UNNEEDED=true
            shift
            ;;
        --include|-i)
            IFS=',' read -ra ADDR <<< "$2"
            for i in "${ADDR[@]}"; do
                trimmed=$(echo "$i" | xargs)
                [ -n "$trimmed" ] && INCLUDE_PLUGINS+=("$trimmed")
            done
            shift 2
            ;;
        --include=*)
            val="${1#*=}"
            IFS=',' read -ra ADDR <<< "$val"
            for i in "${ADDR[@]}"; do
                trimmed=$(echo "$i" | xargs)
                [ -n "$trimmed" ] && INCLUDE_PLUGINS+=("$trimmed")
            done
            shift
            ;;
        --remove|-r|--delete)
            IFS=',' read -ra ADDR <<< "$2"
            for i in "${ADDR[@]}"; do
                trimmed=$(echo "$i" | xargs)
                [ -n "$trimmed" ] && REMOVE_PLUGINS+=("$trimmed")
            done
            shift 2
            ;;
        --remove=*|--delete=*)
            val="${1#*=}"
            IFS=',' read -ra ADDR <<< "$val"
            for i in "${ADDR[@]}"; do
                trimmed=$(echo "$i" | xargs)
                [ -n "$trimmed" ] && REMOVE_PLUGINS+=("$trimmed")
            done
            shift
            ;;
        -*)
            shift
            ;;
        *)
            EXTERNAL_URL="$1"
            shift
            ;;
    esac
done

log() {
    if [ "$SILENT" = false ]; then
        echo "$1"
    fi
}

run_git() {
    if [ "$SILENT" = true ]; then
        "$@" > /dev/null 2>&1
    else
        "$@"
    fi
}

PLUGINS_PATH="$HOME/.gemini/config/plugins"
SKILLS_PATH="$HOME/.gemini/config/skills"
SCRATCH_PATH="$HOME/.gemini/scratch"
REPO_PATH="$SCRATCH_PATH/claude-plugins-official"
REPO_URL="https://github.com/anthropics/claude-plugins-official.git"

# Plugins excluidos por defecto para no saturar la ventana de contexto de Antigravity:
# 1. LSPs (Antigravity IDE ya tiene soporte nativo de lenguaje vía su editor VS Code).
# 2. Herramientas exclusivas del CLI de Claude (incompatibles o que leen carpetas inexistentes ~/.claude).
# 3. Puentes de mensajería externa (añaden skills persistentes en cada turno de chat).
# 4. Plugins de nicho extremo (hardware Cardputer, olimpiadas/demostraciones matemáticas).
# 5. Conectores externos sin configurar o wrappers de formato de salida.
DEFAULT_EXCLUDED_PLUGINS=(
    # LSPs redundantes (Antigravity tiene LSPs nativos)
    "clangd-lsp" "csharp-lsp" "gopls-lsp" "jdtls-lsp" "kotlin-lsp"
    "lua-lsp" "php-lsp" "pyright-lsp" "ruby-lsp" "rust-analyzer-lsp"
    "swift-lsp" "typescript-lsp"

    # Exclusivos de Claude Code CLI / Incompatibles
    "example-plugin" "claude-code-setup" "claude-md-management"
    "receipts" "session-report" "claude-security"

    # Puentes de mensajería (skills access/configure consumen tokens innecesarios)
    "discord" "imessage" "telegram"

    # Nicho / Hardware / Matemáticas de concurso
    "cwc-makers" "math-olympiad" "math-proof"

    # Servicios externos no configurados / estilos de salida CLI
    "asana" "linear" "gitlab" "laravel-boost" "fakechat"
    "explanatory-output-style" "learning-output-style"
)

is_excluded_plugin() {
    local target="$1"
    for item in "${DEFAULT_EXCLUDED_PLUGINS[@]}"; do
        if [ "$item" = "$target" ]; then
            return 0
        fi
    done
    return 1
}

is_included_plugin() {
    local target="$1"
    for item in "${INCLUDE_PLUGINS[@]}"; do
        if [ "$item" = "$target" ]; then
            return 0
        fi
    done
    return 1
}

# Ensure ~/.local/bin is in PATH (standard path for uv tools)
if [ -d "$HOME/.local/bin" ]; then
    export PATH="$HOME/.local/bin:$PATH"
fi

test_skillspector_installed() {
    command -v skillspector >/dev/null 2>&1
}

ensure_skillspector() {
    if test_skillspector_installed; then
        return 0
    fi

    log "SkillSpector no está instalado. Instalándolo automáticamente para garantizar la seguridad..."
    if command -v uv >/dev/null 2>&1; then
        log "Instalando NVIDIA SkillSpector vía 'uv tool install'..."
        if [ "$SILENT" = true ]; then
            uv tool install git+https://github.com/NVIDIA/skillspector.git >/dev/null 2>&1
        else
            uv tool install git+https://github.com/NVIDIA/skillspector.git
        fi
    elif command -v pip >/dev/null 2>&1 || command -v pip3 >/dev/null 2>&1; then
        local pip_cmd="pip"
        command -v pip3 >/dev/null 2>&1 && pip_cmd="pip3"
        log "Instalando NVIDIA SkillSpector vía '$pip_cmd install'..."
        if [ "$SILENT" = true ]; then
            $pip_cmd install git+https://github.com/NVIDIA/skillspector.git >/dev/null 2>&1
        else
            $pip_cmd install git+https://github.com/NVIDIA/skillspector.git
        fi
    else
        log "Aviso: No se encontró 'uv' ni 'pip' para instalar SkillSpector. Se continuará la instalación sin escaneo."
        return 1
    fi

    if [ -d "$HOME/.local/bin" ]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi

    if test_skillspector_installed; then
        log "SkillSpector se instaló con éxito."
        return 0
    else
        log "Aviso: No se pudo verificar la instalación de SkillSpector."
        return 1
    fi
}

invoke_skill_security_scan() {
    local target_folder="$1"
    if [ "$SKIP_SCAN" = true ]; then
        log "Escaneo de seguridad omitido por el usuario (--skip-scan)."
        return 0
    fi

    if ! ensure_skillspector; then
        log "Continuando sin escaneo de seguridad (SkillSpector no disponible)."
        return 0
    fi

    log "Ejecutando escaneo de seguridad con NVIDIA SkillSpector (modo estático ultra rápido)..."
    local report_file="$SCRATCH_PATH/skillspector_scan.json"
    rm -f "$report_file"

    skillspector scan "$target_folder" --no-llm --format json --output "$report_file"
    local scan_exit_code=$?

    # Extraer y desglosar archivos comprometidos / señalados para análisis del usuario y del agente
    if [ -f "$report_file" ]; then
        local py_cmd="python3"
        command -v python3 >/dev/null 2>&1 || py_cmd="python"
        if command -v "$py_cmd" >/dev/null 2>&1; then
            "$py_cmd" -c '
import sys, json
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)
    risk = data.get("risk_assessment", {})
    issues = data.get("issues", [])
    if issues:
        sev = risk.get("severity", "UNKNOWN")
        score = risk.get("score", "N/A")
        rec = risk.get("recommendation", "N/A")
        print("\n--- DETALLE DE SEGURIDAD (NVIDIA SkillSpector) ---")
        print(f"Nivel de Riesgo: {sev} (Score: {score}/100) - Recomendación: {rec}")
        print(f"Archivos comprometidos / señalados ({len(issues)} hallazgos detectados):")
        by_file = {}
        for iss in issues:
            fn = iss.get("location", {}).get("file", "desconocido")
            by_file.setdefault(fn, []).append(iss)
        for fn, f_issues in sorted(by_file.items()):
            print(f"  • Archivo: {fn}")
            for iss in f_issues[:3]:
                line = iss.get("location", {}).get("start_line")
                line_str = f" (línea {line})" if line else ""
                s = iss.get("severity", "INFO")
                c = iss.get("category", "General")
                p = iss.get("pattern", iss.get("id", ""))
                print(f"      - [{s}] {c}: {p}{line_str}")
            if len(f_issues) > 3:
                print(f"      - ... (+ {len(f_issues) - 3} observaciones adicionales en este archivo)")
        print("--------------------------------------------------\n")
except Exception:
    pass
' "$report_file" 2>/dev/null
        fi
    fi

    if [ $scan_exit_code -ne 0 ]; then
        log "❌ ALERTA DE SEGURIDAD: SkillSpector detectó un nivel de riesgo crítico o elevado en el plugin (Exit Code: $scan_exit_code)."
        log "La instalación se ha cancelado automáticamente para proteger tu entorno."
        log "Si confías plenamente en este código y deseas forzar su instalación, ejecuta el script agregando: --skip-scan"
        return 1
    fi

    log "✅ Escaneo completado: No se detectaron riesgos críticos en el plugin."
    return 0
}

# 1. Ensure paths exist
mkdir -p "$SCRATCH_PATH"
mkdir -p "$PLUGINS_PATH"

# 2. Function to remove a specific plugin or skill
remove_target_plugin_or_skill() {
    local target="$1"
    [ -z "$target" ] && return
    local found=false

    # 1. Plugin folder
    if [ -d "$PLUGINS_PATH/$target" ]; then
        log "Removiendo plugin: $PLUGINS_PATH/$target..."
        rm -rf "$PLUGINS_PATH/$target"
        log "✅ Plugin '$target' eliminado con éxito."
        found=true
    fi

    # 2. Global skill
    if [ -d "$SKILLS_PATH/$target" ]; then
        log "Removiendo skill global: $SKILLS_PATH/$target..."
        rm -rf "$SKILLS_PATH/$target"
        log "✅ Skill global '$target' eliminada con éxito."
        found=true
    fi

    # 3. Nested skill in plugins
    while IFS= read -r nested; do
        if [ -n "$nested" ] && [ -d "$nested" ]; then
            log "Removiendo skill anidada: $nested..."
            rm -rf "$nested"
            log "✅ Skill anidada '$target' eliminada con éxito."
            found=true
        fi
    done < <(find "$PLUGINS_PATH" -type d -name "$target" 2>/dev/null)

    if [ "$found" = false ]; then
        log "⚠️ No se encontró ningún plugin o skill con el nombre '$target'."
    fi
}

# 3. Function to install/update a plugin directory
install_plugin() {
    local src_folder="$1"
    local force="${2:-false}"
    local plugin_name=$(basename "$src_folder")

    # Exclude non-essential, redundant, or boilerplate plugins
    if [ "$force" = false ] && [ "$INSTALL_ALL" = false ] && is_excluded_plugin "$plugin_name"; then
        if is_included_plugin "$plugin_name"; then
            log "  [Incluido explícitamente vía --include] $plugin_name..."
        else
            log "  [Omitido] $plugin_name (no esencial / redundante con Antigravity). Usa --include o --all para forzar."
            return
        fi
    fi

    local dest_folder="$PLUGINS_PATH/$plugin_name"
    log "Syncing plugin: $plugin_name..."
    mkdir -p "$dest_folder"

    # Copy files/folders excluding hidden/git folders
    for item in "$src_folder"/*; do
        [ -e "$item" ] || continue
        local name=$(basename "$item")
        if [ "$name" != ".git" ] && [ "$name" != ".github" ] && [ "$name" != ".gitignore" ]; then
            cp -R "$item" "$dest_folder/"
        fi
    done

    # Find manifest
    local manifest_path=""
    if [ -f "$src_folder/.claude-plugin/plugin.json" ]; then manifest_path="$src_folder/.claude-plugin/plugin.json"
    elif [ -f "$src_folder/.gemini-plugin/plugin.json" ]; then manifest_path="$src_folder/.gemini-plugin/plugin.json"
    elif [ -f "$src_folder/plugin.json" ]; then manifest_path="$src_folder/plugin.json"
    fi

    if [ -n "$manifest_path" ]; then
        cp "$manifest_path" "$dest_folder/plugin.json"
    else
        echo "{\"name\": \"$plugin_name\"}" > "$dest_folder/plugin.json"
    fi

    # A. Restructure root-level SKILL.md if found
    if [ -f "$dest_folder/SKILL.md" ]; then
        local target_skill_folder="$dest_folder/skills/$plugin_name"
        mkdir -p "$target_skill_folder"
        mv "$dest_folder/SKILL.md" "$target_skill_folder/SKILL.md"
        
        # Move related resource folders if they exist at root
        for folder in references scripts examples; do
            if [ -d "$dest_folder/$folder" ]; then
                mv "$dest_folder/$folder" "$target_skill_folder/"
            fi
        done
    fi

    # B. Scan for SKILL.md files and rename conflicting names
    find "$dest_folder" -name "SKILL.md" | while read -r skill_file; do
        if [ -f "$skill_file" ]; then
            python3 -c "
import sys, os, re
path = sys.argv[1]
plugin_name = sys.argv[2]

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

parts = content.split('---', 2)
if len(parts) >= 3:
    frontmatter = parts[1]
    
    # 1. Check if name exists
    name_match = re.search(r'^name:\s*[\'\"]?([^\'\"]+)[\'\"]?\s*$', frontmatter, re.M)
    if not name_match:
        skill_name = os.path.basename(os.path.dirname(path))
        frontmatter = f'\nname: {skill_name}' + frontmatter
    else:
        skill_name = name_match.group(1).strip()
    
    # 2. Rename if it is generic
    if skill_name in ['access', 'configure']:
        new_skill_name = f'{plugin_name}-{skill_name}'
        frontmatter = re.sub(r'^name:\s*.*$', f'name: {new_skill_name}', frontmatter, flags=re.M)
        
    parts[1] = frontmatter
    new_content = '---'.join(parts)
    if new_content != content:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(new_content)
" "$skill_file" "$plugin_name" 2>/dev/null || sed -i "s/^name:[[:space:]]*access[[:space:]]*$/name: ${plugin_name}-access/g; s/^name:[[:space:]]*configure[[:space:]]*$/name: ${plugin_name}-configure/g" "$skill_file"
        fi
    done
}

# 4. Handle Removal of Specific Plugins or Skills
if [ ${#REMOVE_PLUGINS[@]} -gt 0 ]; then
    log "Procesando eliminación de plugins o skills solicitados..."
    for item in "${REMOVE_PLUGINS[@]}"; do
        remove_target_plugin_or_skill "$item"
    done
    if [ -z "$EXTERNAL_URL" ] && [ "$INSTALL_ALL" = false ] && [ "$CLEAN_UNNEEDED" = false ] && [ ${#INCLUDE_PLUGINS[@]} -eq 0 ]; then
        log "Operación de eliminación completada."
        exit 0
    fi
fi

# 5. Handle External Plugin Installation
if [ -n "$EXTERNAL_URL" ]; then
    PLUGIN_NAME=$(basename "$EXTERNAL_URL" .git)
    TEMP_PATH="$SCRATCH_PATH/$PLUGIN_NAME"
    
    log "Cloning external plugin from $EXTERNAL_URL..."
    rm -rf "$TEMP_PATH"
    run_git git clone --depth 1 "$EXTERNAL_URL" "$TEMP_PATH"
    
    if [ -d "$TEMP_PATH" ]; then
        # Validar seguridad con SkillSpector antes de proceder a la instalación
        if ! invoke_skill_security_scan "$TEMP_PATH"; then
            rm -rf "$TEMP_PATH"
            exit 1
        fi

        has_nested=false
        if [ -d "$TEMP_PATH/plugins" ]; then
            for nested_dir in "$TEMP_PATH/plugins"/*; do
                if [ -d "$nested_dir" ]; then
                    install_plugin "$nested_dir" true
                    has_nested=true
                fi
            done
        fi
        if [ -d "$TEMP_PATH/external_plugins" ]; then
            for nested_dir in "$TEMP_PATH/external_plugins"/*; do
                if [ -d "$nested_dir" ]; then
                    install_plugin "$nested_dir" true
                    has_nested=true
                fi
            done
        fi
        if [ "$has_nested" = false ]; then
            install_plugin "$TEMP_PATH" true
        fi
        log "External plugin installed successfully!"
    else
        log "Failed to clone external repository."
    fi
    
    # Copy script before exiting
    if [ -f "$0" ] && [[ "$0" == /* ]]; then
        cp "$0" "$PLUGINS_PATH/sync-claude-plugins.sh"
    fi
    exit 0
fi

# 6. Clean unneeded / non-essential plugins if requested or during standard sync
if [ "$INSTALL_ALL" = false ]; then
    log "Optimizando ventana de contexto: verificando y removiendo plugins no esenciales..."
    removed_count=0
    for excluded in "${DEFAULT_EXCLUDED_PLUGINS[@]}"; do
        if is_included_plugin "$excluded"; then
            continue
        fi
        installed_dir="$PLUGINS_PATH/$excluded"
        if [ -d "$installed_dir" ]; then
            log "  Removiendo plugin no esencial para liberar contexto: $excluded..."
            rm -rf "$installed_dir"
            removed_count=$((removed_count + 1))
        fi
    done
    if [ $removed_count -gt 0 ]; then
        log "✅ Se removieron $removed_count plugins no esenciales para liberar presupuesto de tokens de contexto."
    fi
fi

if [ "$CLEAN_UNNEEDED" = true ]; then
    log "Limpieza de plugins no esenciales finalizada."
    exit 0
fi

# 7. Regular Official Repo Sync
if [ -d "$REPO_PATH" ]; then
    log "Updating local repository..."
    pushd "$REPO_PATH" > /dev/null
    run_git git pull
    popd > /dev/null
else
    log "Cloning official Claude plugins repository..."
    run_git git clone --depth 1 "$REPO_URL" "$REPO_PATH"
fi

if [ -d "$REPO_PATH/plugins" ]; then
    for dir in "$REPO_PATH/plugins"/*; do
        if [ -d "$dir" ]; then install_plugin "$dir"; fi
    done
fi

if [ -d "$REPO_PATH/external_plugins" ]; then
    for dir in "$REPO_PATH/external_plugins"/*; do
        if [ -d "$dir" ]; then install_plugin "$dir"; fi
    done
fi

# 6. Write/generate the claude-plugins-manager plugin and skill
MANAGER_FOLDER="$PLUGINS_PATH/claude-plugins-manager"
MANAGER_SKILLS_FOLDER="$MANAGER_FOLDER/skills/sync-plugins"
mkdir -p "$MANAGER_SKILLS_FOLDER"

cat << 'EOF' > "$MANAGER_FOLDER/plugin.json"
{
  "name": "claude-plugins-manager",
  "version": "1.3.0",
  "description": "Manage, sync, and install official and third-party Claude plugins globally for Antigravity with context optimization",
  "author": {
    "name": "jersonalvr"
  }
}
EOF

cat << 'EOF' > "$MANAGER_SKILLS_FOLDER/SKILL.md"
---
name: sync-plugins
description: Sync official Claude plugins or install third-party plugins globally in the .gemini configuration directory with automatic context token budget optimization. Use when the user asks to update plugins, sync plugins, clean unneeded plugins, or install a skill/plugin from an external URL.
---

# Sync and Install Claude Plugins

You are an agent with a skill to manage and install plugins into the global configuration directory.

To perform the action:
1. Proactively run the appropriate command depending on the OS and the user's request. Do not use the Silent flag so you can read the output.

   **A. To Sync Official Plugins (Optimized for Context Tokens - Recommended):**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1`
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh`
   *(Omits redundant LSPs, chat bridges, and Claude CLI-only tools to avoid exceeding customization token budget)*

   **B. To Force Install ALL Plugins (Including redundant LSPs and niche math/hardware):**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1 -All`
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh --all`

   **C. To Include Specific Plugins Otherwise Excluded by Default:**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1 -Include "math-olympiad,pyright-lsp"`
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh --include "math-olympiad,pyright-lsp"`

   **D. To Remove a Specific Plugin or Skill:**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1 -Remove "NOMBRE_PLUGIN_O_SKILL"`
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh --remove "NOMBRE_PLUGIN_O_SKILL"`

   **E. To Clean / Remove Unneeded Plugins Only:**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1 -CleanUnneeded`
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh --clean`

   **F. To Install an External Plugin (User provides a Git URL):**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1 -ExternalUrl "URL_HERE"`
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh "URL_HERE"`
   *(Note: External plugins are automatically scanned with NVIDIA SkillSpector. Pass -SkipScan or --skip-scan to bypass)*

   **G. To Audit Any Plugin or Skill On-Demand:**
   - On Windows/macOS/Linux: `skillspector scan "PATH_TO_SKILL" --no-llm`

2. Report the output of the execution to the user:
   - If SkillSpector detects risks and blocks installation, the output will list the specific compromised/flagged files, categories, and line numbers.
   - You MUST review each reported file and finding to provide an informed, reasoned security audit to the user instead of a generic error message:
     * Explain whether the findings are true malicious risks (e.g. credential theft, unauthorized file access, rogue scripts) or common structural/prompting false positives (e.g. strict anti-laziness rules, HTML placeholder comments, unpinned MCP/npx packages).
     * Advise the user that if they review the code and trust the repository, they can bypass the block by re-running with -SkipScan or --skip-scan.
3. If successful, tell the user that the plugin(s) are now ready to be used.
EOF

# 6. Save a copy of the sync script locally for future updates
LOCAL_SCRIPT_PATH="$PLUGINS_PATH/sync-claude-plugins.sh"
SCRIPT_URL="https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.sh"

# If running script exists, copy it. Else curl it.
if [ -f "$0" ] && [[ "$0" == /* ]]; then
    cp "$0" "$LOCAL_SCRIPT_PATH"
else
    curl -sSf "$SCRIPT_URL" -o "$LOCAL_SCRIPT_PATH" 2>/dev/null
fi

log "Sync completed successfully!"
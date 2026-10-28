#!/bin/bash
# sync-claude-plugins.sh
# Script to synchronize official Claude Code plugins or install external skills globally

EXTERNAL_URL=""
SILENT=false
SKIP_SCAN=false
INSTALL_ALL=false
CLEAN_UNNEEDED=false
INTERACTIVE=false
FIND_DUPLICATES=false
FIX_DUPLICATES=false
SCIENCE=false
PLUGIN_DEV=false
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
        --interactive|-m|--menu)
            INTERACTIVE=true
            shift
            ;;
        --find-duplicates)
            FIND_DUPLICATES=true
            shift
            ;;
        --fix-duplicates)
            FIX_DUPLICATES=true
            shift
            ;;
        --science)
            SCIENCE=true
            shift
            ;;
        --plugin-dev)
            PLUGIN_DEV=true
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
    "receipts" "session-report" "claude-security" "full-output-enforcement"

    # Puentes de mensajería (skills access/configure consumen tokens innecesarios)
    "discord" "imessage" "telegram"

    # Nicho / Hardware / Matemáticas de concurso / Marca
    "cwc-makers" "math-olympiad" "math-proof" "brandkit"

    # Servicios externos no configurados / estilos de salida CLI
    "asana" "linear" "gitlab" "laravel-boost" "fakechat"
    "explanatory-output-style" "learning-output-style"

    # Módulos masivos opcionales (gestionables vía menú interactivo o flags)
    "science" "plugin-dev" "taste-skill"
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

# 2. Functions to manage Antigravity config.json
update_antigravity_plugin_config() {
    local config_file="$HOME/.gemini/config/config.json"
    [ ! -f "$config_file" ] && return 0

    local py_cmd="python3"
    command -v python3 >/dev/null 2>&1 || py_cmd="python"
    if ! command -v "$py_cmd" >/dev/null 2>&1; then return 0; fi

    "$py_cmd" -c '
import sys, json, os

config_file = sys.argv[1]
all_flag = sys.argv[2] == "true"
excluded = sys.argv[3].split(",")
includes = [x.strip() for x in sys.argv[4].split(",") if x.strip()]

if not os.path.exists(config_file):
    sys.exit(0)

try:
    with open(config_file, "r", encoding="utf-8") as f:
        data = json.load(f)
    
    plugins = data.get("plugins", {})
    modified = False
    
    for name, info in plugins.items():
        if name in excluded and name not in includes and not all_flag:
            if info.get("enabled", True) is not False:
                info["enabled"] = False
                modified = True
                print(f"  [Desactivado en config.json] {name}")
                
    if modified:
        with open(config_file, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=4)
        print("Configuracion de plugins en config.json actualizada con exito.")
except Exception:
    pass
' "$config_file" "$INSTALL_ALL" "$(IFS=,; echo "${DEFAULT_EXCLUDED_PLUGINS[*]}")" "$(IFS=,; echo "${INCLUDE_PLUGINS[*]}")"
}

update_plugin_config_entry() {
    local plugin_name="$1"
    local enabled="$2"
    local config_file="$HOME/.gemini/config/config.json"
    [ ! -f "$config_file" ] && return 0

    local py_cmd="python3"
    command -v python3 >/dev/null 2>&1 || py_cmd="python"
    if ! command -v "$py_cmd" >/dev/null 2>&1; then return 0; fi

    "$py_cmd" -c '
import sys, json, os
config_file, name, enabled = sys.argv[1], sys.argv[2], sys.argv[3] == "true"
try:
    with open(config_file, "r", encoding="utf-8") as f:
        data = json.load(f)
    if "plugins" not in data:
        data["plugins"] = {}
    if name not in data["plugins"]:
        data["plugins"][name] = {}
    data["plugins"][name]["enabled"] = enabled
    with open(config_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4)
    print(f"  Plugin {name} configurado como enabled={enabled} en config.json.")
except Exception:
    pass
' "$config_file" "$plugin_name" "$enabled"
}

# 3. Function to remove a specific plugin or skill
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

    # 4. Scratch folder
    if [ -d "$SCRATCH_PATH/$target" ]; then
        log "Removiendo datos en scratch: $SCRATCH_PATH/$target..."
        rm -rf "$SCRATCH_PATH/$target"
        found=true
    fi

    # 5. Disable in config.json
    update_plugin_config_entry "$target" false

    if [ "$found" = false ]; then
        log "⚠️ Plugin o skill '$target' desactivado en configuración."
    fi
}

# 4. Functions for Duplicate Detection and Resolution
find_duplicate_skills() {
    local auto_fix="${1:-false}"
    local py_cmd="python3"
    command -v python3 >/dev/null 2>&1 || py_cmd="python"
    if ! command -v "$py_cmd" >/dev/null 2>&1; then
        log "Se requiere python3 para la detección de duplicados."
        return 1
    fi

    "$py_cmd" -c '
import os, sys, re, shutil
from collections import defaultdict

home = os.path.expanduser("~")
legacy_skills_dir = os.path.join(home, ".gemini", "antigravity", "skills")
legacy_dirs = []
if os.path.exists(legacy_skills_dir):
    legacy_dirs = [d for d in os.listdir(legacy_skills_dir) if os.path.isdir(os.path.join(legacy_skills_dir, d))]

roots = [
    ("Config Skills (~/.gemini/config/skills)", os.path.join(home, ".gemini", "config", "skills")),
    ("Antigravity Legacy Skills (~/.gemini/antigravity/skills)", legacy_skills_dir),
    ("Installed Plugins (~/.gemini/config/plugins)", os.path.join(home, ".gemini", "config", "plugins")),
]

auto_fix = sys.argv[1] == "true"
skills = defaultdict(list)

for source_name, root_path in roots:
    if not os.path.exists(root_path):
        continue
    for dirpath, _, filenames in os.walk(root_path):
        if "SKILL.md" in filenames:
            skill_file = os.path.join(dirpath, "SKILL.md")
            skill_name = ""
            try:
                with open(skill_file, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()
                m = re.search(r"^name:\s*[\x27\"]?([^\x27\"\r\n]+)[\x27\"]?\s*$", content, re.M)
                if m:
                    skill_name = m.group(1).strip()
                else:
                    skill_name = os.path.basename(dirpath)
            except Exception:
                skill_name = os.path.basename(dirpath)
            
            skills[skill_name].append({
                "source": source_name,
                "file": skill_file,
                "folder": dirpath
            })

duplicates = {k: v for k, v in skills.items() if len(v) > 1}
has_issues = bool(duplicates) or bool(legacy_dirs)

print("\n--- ESCANEO DE SKILLS DUPLICADAS Y LEGACY EN ANTIGRAVITY ---")
if not has_issues:
    print("[OK] Excelente: No se encontraron skills duplicadas ni legacy en tu entorno.")
    sys.exit(0)

if duplicates:
    print(f"[AVISO] Se encontraron {len(duplicates)} skills con definiciones duplicadas:\n")
    for name, entries in duplicates.items():
        print(f"  * Skill: \x27{name}\x27 ({len(entries)} copias encontradas)")
        for ent in entries:
            print(f"      - [{ent[\x27source\x27]}] {ent[\x27file\x27]}")
    print("")

if legacy_dirs:
    print(f"[AVISO] Se detectaron {len(legacy_dirs)} skills legacy obsoletas en {legacy_skills_dir}:\n")
    for ldir in legacy_dirs:
        print(f"  * Legacy Skill obsoleta: \x27{ldir}\x27")
    print("  (Nota: Las skills actuales residen en ~/.gemini/config/skills. Estas copias legacy consumen tokens innecesarios).\n")

if auto_fix:
    print("Resolviendo duplicados y purgando skills legacy obsoletas...")
    fixed = 0
    for name, entries in duplicates.items():
        legacy = [e for e in entries if "Antigravity Legacy Skills" in e["source"]]
        config = [e for e in entries if "Config Skills" in e["source"]]
        plugins = [e for e in entries if "Installed Plugins" in e["source"]]
        
        if legacy and config:
            for leg in legacy:
                if os.path.exists(leg["folder"]):
                    print(f"  Eliminando copia legacy duplicada: {leg[\x27folder\x27]}...")
                    shutil.rmtree(leg["folder"], ignore_errors=True)
                    fixed += 1
        elif config and plugins:
            for plg in plugins:
                if os.path.exists(plg["folder"]):
                    print(f"  Eliminando copia redundante en plugin: {plg[\x27folder\x27]}...")
                    shutil.rmtree(plg["folder"], ignore_errors=True)
                    fixed += 1

    if os.path.exists(legacy_skills_dir):
        for rem in os.listdir(legacy_skills_dir):
            full_rem = os.path.join(legacy_skills_dir, rem)
            if os.path.isdir(full_rem):
                print(f"  Eliminando skill legacy obsoleta: {full_rem}...")
                shutil.rmtree(full_rem, ignore_errors=True)
                fixed += 1
        old_manifest = os.path.join(legacy_skills_dir, ".datacloud_skills_manifest")
        if os.path.exists(old_manifest):
            os.remove(old_manifest)

    if fixed > 0:
        print(f"[OK] Se eliminaron {fixed} copias duplicadas / skills legacy. Reinicia Antigravity IDE.")
else:
    print("[INFO] Para resolver automáticamente y liberar tokens, ejecuta:")
    print("   bash sync-claude-plugins.sh --fix-duplicates")
' "$auto_fix"
}

# 5. Function to Install Science Skills
install_science_skills() {
    local science_url="https://github.com/google-deepmind/science-skills.git"
    local science_temp="$SCRATCH_PATH/science-skills"
    log "Clonando repositorio oficial de DeepMind Science Skills..."
    rm -rf "$science_temp"
    run_git git clone --depth 1 "$science_url" "$science_temp"
    if [ -d "$science_temp" ]; then
        if ! invoke_skill_security_scan "$science_temp"; then
            rm -rf "$science_temp"
            return 1
        fi
        install_plugin "$science_temp" true
        update_plugin_config_entry "science" true
        log "✅ Paquete de ciencias (science) instalado con éxito (37 skills)."
    else
        log "❌ Error al clonar el repositorio de science-skills."
    fi
}

pause_menu() {
    echo -e "\nPresiona Enter para continuar..."
    read -r
}

select_interactive_option() {
    local -n _titles=$1
    local -n _descs=$2
    local selected="${3:-0}"
    local total=${#_titles[@]}

    # Check if stdin is a terminal
    if [ ! -t 0 ]; then
        clear 2>/dev/null || echo ""
        echo "=========================================================="
        echo "     Antigravity Plugins & Skills Manager v1.5.0          "
        echo "=========================================================="
        for i in "${!_titles[@]}"; do
            echo "$((i+1))) ${_titles[$i]}"
            if [ -n "${_descs[$i]}" ]; then
                echo "      ${_descs[$i]}"
            fi
        done
        echo "=========================================================="
        read -p "Selecciona una opción [1-$total]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$total" ]; then
            SELECTED_INDEX=$((choice - 1))
            return 0
        fi
        SELECTED_INDEX="$selected"
        return 0
    fi

    # Hide cursor
    tput civis 2>/dev/null || true

    while true; do
        clear 2>/dev/null || echo -e "\033[H\033[J"
        echo "=========================================================="
        echo "     Antigravity Plugins & Skills Manager v1.5.0          "
        echo "=========================================================="
        echo -e " Usa las flechas [↑/↓] para navegar y [Enter] para seleccionar.\n"

        for i in "${!_titles[@]}"; do
            local num=$((i + 1))
            if [ "$i" -eq "$selected" ]; then
                echo -e "\033[1;36m > $num) ${_titles[$i]}\033[0m"
                if [ -n "${_descs[$i]}" ]; then
                    echo -e "\033[0;33m      ${_descs[$i]}\033[0m"
                fi
            else
                echo -e "   $num) ${_titles[$i]}"
                if [ -n "${_descs[$i]}" ]; then
                    echo -e "\033[0;90m      ${_descs[$i]}\033[0m"
                fi
            fi
        done

        echo -e "\n=========================================================="
        echo -e " [Enter] Seleccionar   [1-$total] Atajo numérico   [Q/Esc] Salir"

        # Read key
        IFS= read -rsn1 key 2>/dev/null
        if [ "$key" = $'\x1b' ]; then
            read -rsn2 -t 0.1 seq 2>/dev/null
            if [ "$seq" = "[A" ]; then
                # Up arrow
                selected=$(( (selected - 1 + total) % total ))
            elif [ "$seq" = "[B" ]; then
                # Down arrow
                selected=$(( (selected + 1) % total ))
            elif [ -z "$seq" ]; then
                # Esc
                tput cnorm 2>/dev/null || true
                SELECTED_INDEX=-1
                return 0
            fi
        elif [ -z "$key" ]; then
            # Enter
            tput cnorm 2>/dev/null || true
            SELECTED_INDEX="$selected"
            return 0
        elif [ "$key" = "q" ] || [ "$key" = "Q" ]; then
            tput cnorm 2>/dev/null || true
            SELECTED_INDEX=-1
            return 0
        elif [[ "$key" =~ ^[1-9]$ ]] && [ "$key" -le "$total" ]; then
            tput cnorm 2>/dev/null || true
            SELECTED_INDEX=$((key - 1))
            return 0
        fi
    done
}

show_interactive_menu() {
    local current_idx=0
    while true; do
        local legacy_skills_dir="$HOME/.gemini/antigravity/skills"
        local dupe_warning=""
        if [ -d "$legacy_skills_dir" ]; then
            local count=$(find "$legacy_skills_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
            if [ "$count" -gt 0 ]; then
                dupe_warning=" -- AVISO: ($count skills legacy detectadas)"
            fi
        fi

        local sci_status="[DESACTIVADO]"
        if [ -d "$PLUGINS_PATH/science" ]; then sci_status="[HABILITADO - 37 skills]"; fi

        local pdev_status="[DESACTIVADO]"
        if [ -d "$PLUGINS_PATH/plugin-dev" ]; then pdev_status="[HABILITADO - 7 skills]"; fi

        local taste_status="[DESACTIVADO]"
        if [ -d "$PLUGINS_PATH/taste-skill" ] || [ -d "$SCRATCH_PATH/taste-skill" ]; then taste_status="[HABILITADO - 13 skills]"; fi

        local menu_titles=(
            "[SYNC]  Sincronización Estándar Optimizada (Recomendado)"
            "[SCAN]  Buscar y Resolver Skills Duplicadas$dupe_warning"
            "[BIO]   Gestionar Plugins de Ciencia (DeepMind Science) $sci_status"
            "[DEV]   Gestionar Herramientas de Creación de Plugins (plugin-dev) $pdev_status"
            "[UI]    Gestionar Plugins de Frontend (taste-skill) $taste_status"
            "[CLEAN] Limpiar todos los plugins no esenciales (Liberar tokens inmediatamente)"
            "[GIT]   Instalar Plugin Externo desde URL de Git (con SkillSpector)"
            "[ALL]   Sincronizar TODO sin filtros (--all - instala todos los plugins oficiales)"
            "[SALIR] Salir"
        )

        local menu_descs=(
            "Instala plugins esenciales para desarrollo omitiendo redundantes y LSPs."
            "Detecta skills clonadas (~/.gemini/antigravity vs ~/.gemini/config) y libera tokens."
            "AlphaFold, ChemBL, PDB, Genomica (consume ~5.500 tokens de contexto)."
            "Skills para crear plugins, hooks y commands de Claude (consume ~1.200 tokens)."
            "13 estilos de frontend (brutalist, minimalist, etc. - consume ~1.800 tokens)."
            "Desactiva en config.json plugins innecesarios y elimina carpetas residuales."
            "Clona e instala un repositorio validando previamente la seguridad con NVIDIA SkillSpector."
            "Instala toda la colección oficial sin exclusiones (puede exceder presupuesto)."
            "Cerrar el gestor de plugins y regresar a la terminal."
        )

        select_interactive_option menu_titles menu_descs "$current_idx"
        local choice_idx="$SELECTED_INDEX"

        if [ "$choice_idx" -eq -1 ] || [ "$choice_idx" -eq 8 ]; then
            echo -e "\nOperación cancelada."
            exit 0
        fi

        current_idx="$choice_idx"
        case "$choice_idx" in
            0)
                echo -e "\nIniciando sincronización optimizada..."
                return 0
                ;;
            1)
                find_duplicate_skills false
                read -p $'\n¿Deseas resolver automáticamente las duplicaciones eliminando copias redundantes? [S/n]: ' fix_resp
                if [ "$fix_resp" != "n" ] && [ "$fix_resp" != "N" ]; then
                    find_duplicate_skills true
                fi
                pause_menu
                ;;
            2)
                if [ "$sci_status" != "[DESACTIVADO]" ]; then
                    read -p $'\nEl paquete \'science\' está habilitado. ¿Deseas DESACTIVARLO para liberar contexto? [S/n]: ' sci_resp
                    if [ "$sci_resp" != "n" ] && [ "$sci_resp" != "N" ]; then
                        remove_target_plugin_or_skill "science"
                    fi
                else
                    read -p $'\n¿Deseas HABILITAR / INSTALAR el paquete \'science\' (DeepMind Science Skills - 37 skills)? [s/N]: ' sci_resp
                    if [ "$sci_resp" = "s" ] || [ "$sci_resp" = "S" ]; then
                        install_science_skills
                    fi
                fi
                pause_menu
                ;;
            3)
                if [ "$pdev_status" != "[DESACTIVADO]" ]; then
                    read -p $'\nEl paquete \'plugin-dev\' está habilitado. ¿Deseas DESACTIVARLO para liberar contexto? [S/n]: ' pdev_resp
                    if [ "$pdev_resp" != "n" ] && [ "$pdev_resp" != "N" ]; then
                        remove_target_plugin_or_skill "plugin-dev"
                    fi
                else
                    read -p $'\n¿Deseas HABILITAR / INSTALAR \'plugin-dev\' (herramientas para crear plugins de Claude)? [s/N]: ' pdev_resp
                    if [ "$pdev_resp" = "s" ] || [ "$pdev_resp" = "S" ]; then
                        INCLUDE_PLUGINS+=("plugin-dev")
                        update_plugin_config_entry "plugin-dev" true
                        echo "Se incluirá 'plugin-dev' en la sincronización..."
                        return 0
                    fi
                fi
                pause_menu
                ;;
            4)
                if [ "$taste_status" != "[DESACTIVADO]" ]; then
                    read -p $'\nEl plugin \'taste-skill\' está habilitado. ¿Deseas DESACTIVARLO para liberar contexto? [S/n]: ' taste_resp
                    if [ "$taste_resp" != "n" ] && [ "$taste_resp" != "N" ]; then
                        remove_target_plugin_or_skill "taste-skill"
                    fi
                else
                    echo -e "\nEl plugin taste-skill no está activo."
                fi
                pause_menu
                ;;
            5)
                CLEAN_UNNEEDED=true
                return 0
                ;;
            6)
                read -p $'\nIntroduce la URL del repositorio Git del plugin: ' ext_url
                if [ -n "$ext_url" ]; then
                    EXTERNAL_URL=$(echo "$ext_url" | xargs)
                    return 0
                fi
                ;;
            7)
                INSTALL_ALL=true
                return 0
                ;;
        esac
    done
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

# Handle standalone flags first
if [ "$FIND_DUPLICATES" = true ]; then
    find_duplicate_skills false
    exit 0
fi
if [ "$FIX_DUPLICATES" = true ]; then
    find_duplicate_skills true
    exit 0
fi
if [ "$SCIENCE" = true ]; then
    install_science_skills
    exit 0
fi
if [ "$PLUGIN_DEV" = true ]; then
    INCLUDE_PLUGINS+=("plugin-dev")
    update_plugin_config_entry "plugin-dev" true
fi

# Check if interactive mode is triggered
has_explicit_action=false
if [ -n "$EXTERNAL_URL" ] || [ ${#INCLUDE_PLUGINS[@]} -gt 0 ] || [ ${#REMOVE_PLUGINS[@]} -gt 0 ] || [ "$INSTALL_ALL" = true ] || [ "$CLEAN_UNNEEDED" = true ] || [ "$PLUGIN_DEV" = true ]; then
    has_explicit_action=true
fi

if [ "$INTERACTIVE" = true ] || { [ "$has_explicit_action" = false ] && [ "$SILENT" = false ] && [ -t 0 ]; }; then
    show_interactive_menu
fi

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
    update_antigravity_plugin_config
    if [ $removed_count -gt 0 ]; then
        log "✅ Se removieron $removed_count plugins no esenciales para liberar presupuesto de tokens de contexto."
    fi
fi

if [ "$CLEAN_UNNEEDED" = true ]; then
    update_antigravity_plugin_config
    log "Limpieza de plugins no esenciales finalizada. Reinicia Antigravity IDE para aplicar los cambios de contexto."
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

# 8. Write/generate the claude-plugins-manager plugin and skill
MANAGER_FOLDER="$PLUGINS_PATH/claude-plugins-manager"
MANAGER_SKILLS_FOLDER="$MANAGER_FOLDER/skills/sync-plugins"
mkdir -p "$MANAGER_SKILLS_FOLDER"

cat << 'EOF' > "$MANAGER_FOLDER/plugin.json"
{
  "name": "claude-plugins-manager",
  "version": "1.5.0",
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

   **A. To Open the Interactive Menu:**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1 -Interactive`
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh --interactive`

   **B. To Sync Official Plugins (Optimized for Context Tokens - Recommended):**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1`
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh`
   *(Omits redundant LSPs, chat bridges, and Claude CLI-only tools to avoid exceeding customization token budget)*

   **C. To Find Duplicate Skills & Plugins:**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1 -FindDuplicates`
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh --find-duplicates`

   **D. To Automatically Fix / Deduplicate Skills:**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1 -FixDuplicates`
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh --fix-duplicates`

   **E. To Include or Install Science / Plugin-Dev:**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1 -Science` (or `-PluginDev`)
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh --science` (or `--plugin-dev`)

   **F. To Include Specific Plugins Otherwise Excluded by Default:**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1 -Include "math-olympiad,pyright-lsp"`
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh --include "math-olympiad,pyright-lsp"`

   **G. To Remove a Specific Plugin or Skill:**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1 -Remove "NOMBRE_PLUGIN_O_SKILL"`
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh --remove "NOMBRE_PLUGIN_O_SKILL"`

   **H. To Clean / Remove Unneeded Plugins Only:**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1 -CleanUnneeded`
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh --clean`

   **I. To Install an External Plugin (User provides a Git URL):**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1 -ExternalUrl "URL_HERE"`
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh "URL_HERE"`
   *(Note: External plugins are automatically scanned with NVIDIA SkillSpector. Pass -SkipScan or --skip-scan to bypass)*

   **J. To Audit Any Plugin or Skill On-Demand:**
   - On Windows/macOS/Linux: `skillspector scan "PATH_TO_SKILL" --no-llm`

2. Report the output of the execution to the user:
   - If SkillSpector detects risks and blocks installation, the output will list the specific compromised/flagged files, categories, and line numbers.
   - You MUST review each reported file and finding to provide an informed, reasoned security audit to the user instead of a generic error message:
     * Explain whether the findings are true malicious risks (e.g. credential theft, unauthorized file access, rogue scripts) or common structural/prompting false positives (e.g. strict anti-laziness rules, HTML placeholder comments, unpinned MCP/npx packages).
     * Advise the user that if they review the code and trust the repository, they can bypass the block by re-running with -SkipScan or --skip-scan.
3. If successful, tell the user that the plugin(s) are now ready to be used.
EOF

# 9. Save a copy of the sync script locally for future updates
LOCAL_SCRIPT_PATH="$PLUGINS_PATH/sync-claude-plugins.sh"
SCRIPT_URL="https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.sh"

# If running script exists, copy it. Else curl it.
if [ -f "$0" ] && [[ "$0" == /* ]]; then
    cp "$0" "$LOCAL_SCRIPT_PATH"
else
    curl -sSf "$SCRIPT_URL" -o "$LOCAL_SCRIPT_PATH" 2>/dev/null
fi

update_antigravity_plugin_config

log "Sync completed successfully!"
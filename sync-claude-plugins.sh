#!/bin/bash
# sync-claude-plugins.sh
# Script to synchronize official Claude Code plugins or install external skills globally

EXTERNAL_URL=""
SILENT=false

# Parse arguments
for arg in "$@"; do
    if [ "$arg" = "--silent" ] || [ "$arg" = "-s" ]; then
        SILENT=true
    elif [ -n "$arg" ] && [[ "$arg" != -* ]]; then
        EXTERNAL_URL="$arg"
    fi
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
SCRATCH_PATH="$HOME/.gemini/scratch"
REPO_PATH="$SCRATCH_PATH/claude-plugins-official"
REPO_URL="https://github.com/anthropics/claude-plugins-official.git"

# 1. Ensure paths exist
mkdir -p "$SCRATCH_PATH"
mkdir -p "$PLUGINS_PATH"

# 2. Function to install/update a plugin directory
install_plugin() {
    local src_folder="$1"
    local plugin_name=$(basename "$src_folder")

    # Exclude boilerplate or setup plugins
    if [ "$plugin_name" = "example-plugin" ] || [ "$plugin_name" = "claude-code-setup" ]; then return; fi

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
}

# 3. Handle External Plugin Installation
if [ -n "$EXTERNAL_URL" ]; then
    PLUGIN_NAME=$(basename "$EXTERNAL_URL" .git)
    TEMP_PATH="$SCRATCH_PATH/$PLUGIN_NAME"
    
    log "Cloning external plugin from $EXTERNAL_URL..."
    rm -rf "$TEMP_PATH"
    run_git git clone --depth 1 "$EXTERNAL_URL" "$TEMP_PATH"
    
    if [ -d "$TEMP_PATH" ]; then
        install_plugin "$TEMP_PATH"
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

# 4. Regular Official Repo Sync
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

# 5. Write/generate the claude-plugins-manager plugin and skill
MANAGER_FOLDER="$PLUGINS_PATH/claude-plugins-manager"
MANAGER_SKILLS_FOLDER="$MANAGER_FOLDER/skills/sync-plugins"
mkdir -p "$MANAGER_SKILLS_FOLDER"

cat << 'EOF' > "$MANAGER_FOLDER/plugin.json"
{
  "name": "claude-plugins-manager",
  "version": "1.2.0",
  "description": "Manage, sync, and install official and third-party Claude plugins globally for Antigravity",
  "author": {
    "name": "jersonalvr"
  }
}
EOF

cat << 'EOF' > "$MANAGER_SKILLS_FOLDER/SKILL.md"
---
name: sync-plugins
description: Sync official Claude plugins or install third-party plugins globally in the .gemini configuration directory. Use when the user asks to update plugins, sync plugins, or install a skill/plugin from an external URL.
---

# Sync and Install Claude Plugins

You are an agent with a skill to manage and install plugins into the global configuration directory.

To perform the action:
1. Proactively run the appropriate command depending on the OS and the user's request. Do not use the Silent flag so you can read the output.

   **A. To Sync Official Plugins (No URL provided):**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1`
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh`

   **B. To Install an External Plugin (User provides a Git URL):**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1 -ExternalUrl "URL_HERE"`
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh "URL_HERE"`

2. Report the output of the execution to the user.
3. Tell the user that the plugin(s) are now ready to be used.
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
#!/bin/bash
# sync-claude-plugins.sh
# Script to synchronize official Claude Code plugins with Antigravity CLI

REPO_URL="https://github.com/anthropics/claude-plugins-official.git"
REPO_PATH="$HOME/.gemini/antigravity-cli/scratch/claude-plugins-official"
PLUGINS_PATH="$HOME/.gemini/config/plugins"

# 1. Ensure the clone path exists
mkdir -p "$HOME/.gemini/antigravity-cli/scratch"

# 2. Ensure the repository is cloned and updated
if [ -d "$REPO_PATH" ]; then
    echo "Updating local repository..."
    pushd "$REPO_PATH" > /dev/null
    git pull
    popd > /dev/null
else
    echo "Cloning official Claude plugins repository..."
    git clone --depth 1 "$REPO_URL" "$REPO_PATH"
fi

# 3. Ensure destination plugins folder exists
mkdir -p "$PLUGINS_PATH"

# 4. Function to install/update a plugin directory
install_plugin() {
    local src_folder="$1"
    local plugin_name=$(basename "$src_folder")

    # Exclude boilerplate or setup plugins that might not be needed
    if [ "$plugin_name" = "example-plugin" ] || [ "$plugin_name" = "claude-code-setup" ]; then
        return
    fi

    local dest_folder="$PLUGINS_PATH/$plugin_name"
    echo "Syncing plugin: $plugin_name..."

    # Create destination folder
    mkdir -p "$dest_folder"

    # Copy files/folders excluding hidden/git folders
    for item in "$src_folder"/*; do
        [ -e "$item" ] || continue
        local name=$(basename "$item")
        if [ "$name" != ".git" ] && [ "$name" != ".github" ] && [ "$name" != ".gitignore" ]; then
            cp -R "$item" "$dest_folder/"
        fi
    done

    # Find manifest (plugin.json)
    local manifest_path=""
    if [ -f "$src_folder/.claude-plugin/plugin.json" ]; then
        manifest_path="$src_folder/.claude-plugin/plugin.json"
    elif [ -f "$src_folder/.gemini-plugin/plugin.json" ]; then
        manifest_path="$src_folder/.gemini-plugin/plugin.json"
    elif [ -f "$src_folder/plugin.json" ]; then
        manifest_path="$src_folder/plugin.json"
    fi

    if [ -n "$manifest_path" ]; then
        cp "$manifest_path" "$dest_folder/plugin.json"
    else
        echo "{\"name\": \"$plugin_name\"}" > "$dest_folder/plugin.json"
    fi
}

# 5. Process official plugins
if [ -d "$REPO_PATH/plugins" ]; then
    for dir in "$REPO_PATH/plugins"/*; do
        if [ -d "$dir" ]; then
            install_plugin "$dir"
        fi
    done
fi

# 6. Process external/partner plugins
if [ -d "$REPO_PATH/external_plugins" ]; then
    for dir in "$REPO_PATH/external_plugins"/*; do
        if [ -d "$dir" ]; then
            install_plugin "$dir"
        fi
    done
fi

# 7. Write/generate the claude-plugins-manager plugin and skill
MANAGER_FOLDER="$PLUGINS_PATH/claude-plugins-manager"
MANAGER_SKILLS_FOLDER="$MANAGER_FOLDER/skills/sync-plugins"
mkdir -p "$MANAGER_SKILLS_FOLDER"

cat << 'EOF' > "$MANAGER_FOLDER/plugin.json"
{
  "name": "claude-plugins-manager",
  "version": "1.0.0",
  "description": "Manage and sync official Claude plugins for Antigravity",
  "author": {
    "name": "Jerson"
  }
}
EOF

cat << 'EOF' > "$MANAGER_SKILLS_FOLDER/SKILL.md"
---
name: sync-plugins
description: Sync, update, or refresh official Claude plugins in the Antigravity configuration directory. Use when the user asks to update the plugins, sync the plugins, run the sync script, or similar.
---

# Sync Claude Plugins

You are an agent with a skill to synchronize the official Claude Code plugins into the Antigravity CLI configuration directory.

To perform the synchronization:
1. Proactively run the appropriate command depending on the OS:
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1` (expand $Home to the user's home folder).
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh`
2. Report the output of the execution to the user.
3. Tell the user that the plugins are now updated and ready to be used.
EOF

# 8. Save a copy of the sync script locally for future updates
LOCAL_SCRIPT_PATH="$PLUGINS_PATH/sync-claude-plugins.sh"
SCRIPT_URL="https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.sh"

# If running script exists, copy it. Else curl it.
if [ -f "$0" ] && [[ "$0" == /* ]]; then
    cp "$0" "$LOCAL_SCRIPT_PATH"
else
    curl -sSf "$SCRIPT_URL" -o "$LOCAL_SCRIPT_PATH" 2>/dev/null
fi

echo "Sync completed successfully!"

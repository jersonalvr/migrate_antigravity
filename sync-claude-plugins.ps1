# sync-claude-plugins.ps1
# Script to synchronize official Claude Code plugins with Antigravity CLI

$RepoUrl = "https://github.com/anthropics/claude-plugins-official.git"
$RepoPath = Join-Path $Home ".gemini\antigravity-cli\scratch\claude-plugins-official"
$PluginsPath = Join-Path $Home ".gemini\config\plugins"

# 1. Ensure the clone path exists
$ScratchPath = Join-Path $Home ".gemini\antigravity-cli\scratch"
if (-not (Test-Path $ScratchPath)) {
    New-Item -ItemType Directory -Path $ScratchPath -Force | Out-Null
}

# 2. Ensure the repository is cloned and updated
if (Test-Path $RepoPath) {
    Write-Host "Updating local repository..." -ForegroundColor Cyan
    Push-Location $RepoPath
    git pull
    Pop-Location
} else {
    Write-Host "Cloning official Claude plugins repository..." -ForegroundColor Cyan
    git clone --depth 1 $RepoUrl $RepoPath
}

# 3. Ensure destination plugins folder exists
if (-not (Test-Path $PluginsPath)) {
    New-Item -ItemType Directory -Path $PluginsPath -Force | Out-Null
}

# 4. Function to install/update a plugin directory
function Install-Plugin($SrcFolder) {
    $PluginName = Split-Path $SrcFolder -Leaf
    
    # Exclude boilerplate or setup plugins that might not be needed
    if ($PluginName -eq "example-plugin" -or $PluginName -eq "claude-code-setup") {
        return
    }

    $DestFolder = Join-Path $PluginsPath $PluginName

    Write-Host "Syncing plugin: $PluginName..." -ForegroundColor Yellow

    # Create destination folder if not exists
    if (-not (Test-Path $DestFolder)) {
        New-Item -ItemType Directory -Path $DestFolder -Force | Out-Null
    }

    # Copy files/folders excluding hidden/git folders
    Get-ChildItem -Path $SrcFolder -Exclude ".git", ".github", ".gitignore" | ForEach-Object {
        $SrcItem = $_.FullName
        $DestItem = Join-Path $DestFolder $_.Name
        if ($_.PsIsContainer) {
            if (-not (Test-Path $DestItem)) {
                New-Item -ItemType Directory -Path $DestItem -Force | Out-Null
            }
            Copy-Item -Path "$SrcItem\*" -Destination $DestItem -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Copy-Item -Path $SrcItem -Destination $DestItem -Force
        }
    }

    # Find manifest (plugin.json) in .claude-plugin or .gemini-plugin or root
    $ManifestPath = ""
    $ClaudePluginJson = Join-Path $SrcFolder ".claude-plugin\plugin.json"
    $GeminiPluginJson = Join-Path $SrcFolder ".gemini-plugin\plugin.json"
    $RootPluginJson = Join-Path $SrcFolder "plugin.json"

    if (Test-Path $ClaudePluginJson) {
        $ManifestPath = $ClaudePluginJson
    } elseif (Test-Path $GeminiPluginJson) {
        $ManifestPath = $GeminiPluginJson
    } elseif (Test-Path $RootPluginJson) {
        $ManifestPath = $RootPluginJson
    }

    if ($ManifestPath -ne "") {
        Copy-Item -Path $ManifestPath -Destination (Join-Path $DestFolder "plugin.json") -Force
    } else {
        $BasicJson = @{ name = $PluginName } | ConvertTo-Json
        [System.IO.File]::WriteAllText((Join-Path $DestFolder "plugin.json"), $BasicJson)
    }
}

# 5. Process official plugins
if (Test-Path (Join-Path $RepoPath "plugins")) {
    Get-ChildItem -Path (Join-Path $RepoPath "plugins") -Directory | ForEach-Object {
        Install-Plugin $_.FullName
    }
}

# 6. Process external/partner plugins
if (Test-Path (Join-Path $RepoPath "external_plugins")) {
    Get-ChildItem -Path (Join-Path $RepoPath "external_plugins") -Directory | ForEach-Object {
        Install-Plugin $_.FullName
    }
}

# 7. Write/generate the claude-plugins-manager plugin and skill
$ManagerFolder = Join-Path $PluginsPath "claude-plugins-manager"
$ManagerSkillsFolder = Join-Path $ManagerFolder "skills\sync-plugins"

if (-not (Test-Path $ManagerSkillsFolder)) {
    New-Item -ItemType Directory -Path $ManagerSkillsFolder -Force | Out-Null
}

$ManagerJson = @{
    name = "claude-plugins-manager"
    version = "1.0.0"
    description = "Manage and sync official Claude plugins for Antigravity"
    author = @{ name = "Jerson" }
} | ConvertTo-Json

[System.IO.File]::WriteAllText((Join-Path $ManagerFolder "plugin.json"), $ManagerJson)

$SkillMd = @'
---
name: sync-plugins
description: Sync, update, or refresh official Claude plugins in the Antigravity configuration directory. Use when the user asks to update the plugins, sync the plugins, run the sync script, or similar.
---

# Sync Claude Plugins

You are an agent with a skill to synchronize the official Claude Code plugins into the Antigravity CLI configuration directory.

To perform the synchronization:
1. Proactively run the appropriate command depending on the OS:
   - On Windows: powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1
   - On macOS/Linux: bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh
2. Report the output of the execution to the user.
3. Tell the user that the plugins are now updated and ready to be used.
'@

[System.IO.File]::WriteAllText((Join-Path $ManagerSkillsFolder "SKILL.md"), $SkillMd)

# 8. Save a copy of the sync script locally for future updates
$ScriptUrl = "https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.ps1"
$LocalScriptPath = Join-Path $PluginsPath "sync-claude-plugins.ps1"

if ($MyInvocation.MyCommand.Path -and (Test-Path $MyInvocation.MyCommand.Path)) {
    Copy-Item -Path $MyInvocation.MyCommand.Path -Destination $LocalScriptPath -Force -ErrorAction SilentlyContinue
} else {
    Invoke-WebRequest -Uri $ScriptUrl -OutFile $LocalScriptPath -UseBasicParsing -ErrorAction SilentlyContinue
}

Write-Host "Sync completed successfully!" -ForegroundColor Green

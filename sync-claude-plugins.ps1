# sync-claude-plugins.ps1
# Script to synchronize official Claude Code plugins or install external skills globally

param(
    [string]$ExternalUrl = "",
    [switch]$Silent
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    if (-not $Silent) {
        Write-Host $Message -ForegroundColor $Color
    }
}

$PluginsPath = Join-Path $Home ".gemini\config\plugins"
$ScratchPath = Join-Path $Home ".gemini\scratch"
$RepoPath = Join-Path $ScratchPath "claude-plugins-official"
$RepoUrl = "https://github.com/anthropics/claude-plugins-official.git"

# 1. Ensure paths exist
if (-not (Test-Path $ScratchPath)) {
    New-Item -ItemType Directory -Path $ScratchPath -Force | Out-Null
}
if (-not (Test-Path $PluginsPath)) {
    New-Item -ItemType Directory -Path $PluginsPath -Force | Out-Null
}

# 2. Function to install/update a plugin directory
function Install-Plugin($SrcFolder) {
    $PluginName = Split-Path $SrcFolder -Leaf
    
    # Exclude boilerplate or setup plugins
    if ($PluginName -eq "example-plugin" -or $PluginName -eq "claude-code-setup") { return }

    $DestFolder = Join-Path $PluginsPath $PluginName
    Write-Log "Syncing plugin: $PluginName..." -Color Yellow

    if (-not (Test-Path $DestFolder)) {
        New-Item -ItemType Directory -Path $DestFolder -Force | Out-Null
    }

    Get-ChildItem -Path $SrcFolder -Exclude ".git", ".github", ".gitignore" | ForEach-Object {
        $SrcItem = $_.FullName
        $DestItem = Join-Path $DestFolder $_.Name
        if ($_.PsIsContainer) {
            if (-not (Test-Path $DestItem)) { New-Item -ItemType Directory -Path $DestItem -Force | Out-Null }
            Copy-Item -Path "$SrcItem\*" -Destination $DestItem -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Copy-Item -Path $SrcItem -Destination $DestItem -Force
        }
    }

    # Find manifest
    $ManifestPath = ""
    $ClaudePluginJson = Join-Path $SrcFolder ".claude-plugin\plugin.json"
    $GeminiPluginJson = Join-Path $SrcFolder ".gemini-plugin\plugin.json"
    $RootPluginJson = Join-Path $SrcFolder "plugin.json"

    if (Test-Path $ClaudePluginJson) { $ManifestPath = $ClaudePluginJson }
    elseif (Test-Path $GeminiPluginJson) { $ManifestPath = $GeminiPluginJson }
    elseif (Test-Path $RootPluginJson) { $ManifestPath = $RootPluginJson }

    if ($ManifestPath -ne "") {
        Copy-Item -Path $ManifestPath -Destination (Join-Path $DestFolder "plugin.json") -Force
    } else {
        $BasicJson = @{ name = $PluginName } | ConvertTo-Json
        [System.IO.File]::WriteAllText((Join-Path $DestFolder "plugin.json"), $BasicJson)
    }
}

# 3. Handle External Plugin Installation (if URL is provided)
if ($ExternalUrl -ne "") {
    $PluginName = ($ExternalUrl -split '/')[-1] -replace '\.git$',''
    $TempPath = Join-Path $ScratchPath $PluginName
    
    Write-Log "Cloning external plugin from $ExternalUrl..." -Color Cyan
    if (Test-Path $TempPath) { Remove-Item -Recurse -Force $TempPath }
    
    if ($Silent) {
        git clone --depth 1 $ExternalUrl $TempPath *>$null
    } else {
        git clone --depth 1 $ExternalUrl $TempPath
    }
    
    if (Test-Path $TempPath) {
        Install-Plugin $TempPath
        Write-Log "External plugin installed successfully!" -Color Green
    } else {
        Write-Log "Failed to clone external repository." -Color Red
    }
    
    # Copy script before returning
    $LocalScriptPath = Join-Path $PluginsPath "sync-claude-plugins.ps1"
    if ($MyInvocation.MyCommand.Path -and (Test-Path $MyInvocation.MyCommand.Path)) {
        Copy-Item -Path $MyInvocation.MyCommand.Path -Destination $LocalScriptPath -Force -ErrorAction SilentlyContinue
    }
    return
}

# 4. Regular Official Repo Sync
if (Test-Path $RepoPath) {
    Write-Log "Updating local repository..." -Color Cyan
    Push-Location $RepoPath
    if ($Silent) { git pull *>$null } else { git pull }
    Pop-Location
} else {
    Write-Log "Cloning official Claude plugins repository..." -Color Cyan
    if ($Silent) {
        git clone --depth 1 $RepoUrl $RepoPath *>$null
    } else {
        git clone --depth 1 $RepoUrl $RepoPath
    }
}

if (Test-Path (Join-Path $RepoPath "plugins")) {
    Get-ChildItem -Path (Join-Path $RepoPath "plugins") -Directory | ForEach-Object { Install-Plugin $_.FullName }
}

if (Test-Path (Join-Path $RepoPath "external_plugins")) {
    Get-ChildItem -Path (Join-Path $RepoPath "external_plugins") -Directory | ForEach-Object { Install-Plugin $_.FullName }
}

# 5. Write/generate the claude-plugins-manager plugin and skill
$ManagerFolder = Join-Path $PluginsPath "claude-plugins-manager"
$ManagerSkillsFolder = Join-Path $ManagerFolder "skills\sync-plugins"

if (-not (Test-Path $ManagerSkillsFolder)) { New-Item -ItemType Directory -Path $ManagerSkillsFolder -Force | Out-Null }

$ManagerJson = @{
    name = "claude-plugins-manager"
    version = "1.2.0"
    description = "Manage, sync, and install official and third-party Claude plugins globally for Antigravity"
    author = @{ name = "jersonalvr" }
} | ConvertTo-Json

[System.IO.File]::WriteAllText((Join-Path $ManagerFolder "plugin.json"), $ManagerJson)

$SkillMd = @'
---
name: sync-plugins
description: Sync official Claude plugins or install third-party plugins globally in the .gemini configuration directory. Use when the user asks to update plugins, sync plugins, or install a skill/plugin from an external URL.
---

# Sync and Install Claude Plugins

You are an agent with a skill to manage and install plugins into the global configuration directory.

To perform the action:
1. Proactively run the appropriate command depending on the OS and the user's request. Do not use the Silent flag so you can read the output.

   **A. To Sync Official Plugins (No URL provided):**
   - On Windows: powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1
   - On macOS/Linux: bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh

   **B. To Install an External Plugin (User provides a Git URL):**
   - On Windows: powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1 -ExternalUrl "URL_HERE"
   - On macOS/Linux: bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh "URL_HERE"

2. Report the output of the execution to the user.
3. Tell the user that the plugin(s) are now ready to be used.
'@

[System.IO.File]::WriteAllText((Join-Path $ManagerSkillsFolder "SKILL.md"), $SkillMd)

# 6. Save a copy of the sync script locally for future updates
$ScriptUrl = "https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.ps1"
$LocalScriptPath = Join-Path $PluginsPath "sync-claude-plugins.ps1"

if ($MyInvocation.MyCommand.Path -and (Test-Path $MyInvocation.MyCommand.Path)) {
    Copy-Item -Path $MyInvocation.MyCommand.Path -Destination $LocalScriptPath -Force -ErrorAction SilentlyContinue
} else {
    Invoke-WebRequest -Uri $ScriptUrl -OutFile $LocalScriptPath -UseBasicParsing -ErrorAction SilentlyContinue
}

Write-Log "Sync completed successfully!" -Color Green
# sync-claude-plugins.ps1
# Script to synchronize official Claude Code plugins or install external skills

param(
    [string]$ExternalUrl = ""
)

$RepoUrl = "https://github.com/anthropics/claude-plugins-official.git"
$RepoPath = Join-Path $Home ".gemini\antigravity-cli\scratch\claude-plugins-official"
$PluginsPath = Join-Path $Home ".gemini\config\plugins"
$ScratchPath = Join-Path $Home ".gemini\antigravity-cli\scratch"

# 1. Ensure the clone path exists
if (-not (Test-Path $ScratchPath)) {
    New-Item -ItemType Directory -Path $ScratchPath -Force | Out-Null
}

# 2. Ensure destination plugins folder exists
if (-not (Test-Path $PluginsPath)) {
    New-Item -ItemType Directory -Path $PluginsPath -Force | Out-Null
}

# 3. Function to install/update a plugin directory
function Install-Plugin($SrcFolder) {
    $PluginName = Split-Path $SrcFolder -Leaf
    
    # Exclude boilerplate or setup plugins
    if ($PluginName -eq "example-plugin" -or $PluginName -eq "claude-code-setup") { return }

    $DestFolder = Join-Path $PluginsPath $PluginName
    Write-Host "Syncing plugin: $PluginName..." -ForegroundColor Yellow

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

# 4. Handle External Plugin Installation (if URL is provided)
if ($ExternalUrl -ne "") {
    $PluginName = ($ExternalUrl -split '/')[-1] -replace '\.git$',''
    $TempPath = Join-Path $ScratchPath $PluginName
    
    Write-Host "Cloning external plugin from $ExternalUrl..." -ForegroundColor Cyan
    if (Test-Path $TempPath) { Remove-Item -Recurse -Force $TempPath }
    git clone --depth 1 $ExternalUrl $TempPath
    
    if (Test-Path $TempPath) {
        Install-Plugin $TempPath
        Write-Host "External plugin installed successfully!" -ForegroundColor Green
    } else {
        Write-Host "Failed to clone external repository." -ForegroundColor Red
    }
    
    # Copy script before exiting
    $LocalScriptPath = Join-Path $PluginsPath "sync-claude-plugins.ps1"
    if ($MyInvocation.MyCommand.Path -and (Test-Path $MyInvocation.MyCommand.Path)) {
        Copy-Item -Path $MyInvocation.MyCommand.Path -Destination $LocalScriptPath -Force -ErrorAction SilentlyContinue
    }
    exit
}

# 5. Regular Official Repo Sync
if (Test-Path $RepoPath) {
    Write-Host "Updating local repository..." -ForegroundColor Cyan
    Push-Location $RepoPath
    git pull
    Pop-Location
} else {
    Write-Host "Cloning official Claude plugins repository..." -ForegroundColor Cyan
    git clone --depth 1 $RepoUrl $RepoPath
}

if (Test-Path (Join-Path $RepoPath "plugins")) {
    Get-ChildItem -Path (Join-Path $RepoPath "plugins") -Directory | ForEach-Object { Install-Plugin $_.FullName }
}

if (Test-Path (Join-Path $RepoPath "external_plugins")) {
    Get-ChildItem -Path (Join-Path $RepoPath "external_plugins") -Directory | ForEach-Object { Install-Plugin $_.FullName }
}

# 6. Write/generate the claude-plugins-manager plugin and skill
$ManagerFolder = Join-Path $PluginsPath "claude-plugins-manager"
$ManagerSkillsFolder = Join-Path $ManagerFolder "skills\sync-plugins"

if (-not (Test-Path $ManagerSkillsFolder)) { New-Item -ItemType Directory -Path $ManagerSkillsFolder -Force | Out-Null }

$ManagerJson = @{
    name = "claude-plugins-manager"
    version = "1.1.0"
    description = "Manage, sync, and install official and third-party Claude plugins for Antigravity"
    author = @{ name = "jersonalvr" }
} | ConvertTo-Json

[System.IO.File]::WriteAllText((Join-Path $ManagerFolder "plugin.json"), $ManagerJson)

$SkillMd = @'
---
name: sync-plugins
description: Sync official Claude plugins or install third-party plugins in the Antigravity configuration directory. Use when the user asks to update plugins, sync plugins, or install a skill/plugin from an external URL.
---

# Sync and Install Claude Plugins

You are an agent with a skill to manage and install plugins into the Antigravity CLI configuration directory.

To perform the action:
1. Proactively run the appropriate command depending on the OS and the user's request:

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

# 7. Save a copy of the sync script locally for future updates
$ScriptUrl = "https://raw.githubusercontent.com/jersonalvr/migrate_antigravity/main/sync-claude-plugins.ps1"
$LocalScriptPath = Join-Path $PluginsPath "sync-claude-plugins.ps1"

if ($MyInvocation.MyCommand.Path -and (Test-Path $MyInvocation.MyCommand.Path)) {
    Copy-Item -Path $MyInvocation.MyCommand.Path -Destination $LocalScriptPath -Force -ErrorAction SilentlyContinue
} else {
    Invoke-WebRequest -Uri $ScriptUrl -OutFile $LocalScriptPath -UseBasicParsing -ErrorAction SilentlyContinue
}

Write-Host "Sync completed successfully!" -ForegroundColor Green
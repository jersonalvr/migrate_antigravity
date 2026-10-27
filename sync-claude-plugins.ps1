# sync-claude-plugins.ps1
# Script to synchronize official Claude Code plugins or install external skills globally

param(
    [string]$ExternalUrl = "",
    [switch]$Silent,
    [switch]$SkipScan,
    [switch]$All,
    [switch]$CleanUnneeded
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

# Plugins excluidos por defecto para no saturar la ventana de contexto de Antigravity:
# 1. LSPs (Antigravity IDE ya tiene soporte nativo de lenguaje vía su editor VS Code).
# 2. Herramientas exclusivas del CLI de Claude (incompatibles o que leen carpetas inexistentes ~/.claude).
# 3. Puentes de mensajería externa (añaden skills persistentes en cada turno de chat).
# 4. Plugins de nicho extremo (hardware Cardputer, olimpiadas/demostraciones matemáticas).
# 5. Conectores externos sin configurar o wrappers de formato de salida.
$DefaultExcludedPlugins = @(
    # LSPs redundantes (Antigravity tiene LSPs nativos)
    "clangd-lsp", "csharp-lsp", "gopls-lsp", "jdtls-lsp", "kotlin-lsp",
    "lua-lsp", "php-lsp", "pyright-lsp", "ruby-lsp", "rust-analyzer-lsp",
    "swift-lsp", "typescript-lsp",

    # Exclusivos de Claude Code CLI / Incompatibles
    "example-plugin", "claude-code-setup", "claude-md-management",
    "receipts", "session-report", "claude-security",

    # Puentes de mensajería (skills access/configure consumen tokens innecesarios)
    "discord", "imessage", "telegram",

    # Nicho / Hardware / Matemáticas de concurso
    "cwc-makers", "math-olympiad", "math-proof",

    # Servicios externos no configurados / estilos de salida CLI
    "asana", "linear", "gitlab", "laravel-boost", "fakechat",
    "explanatory-output-style", "learning-output-style"
)

# Ensure ~/.local/bin is in PATH (standard path for uv tools)
$LocalBin = Join-Path $Home ".local\bin"
if (Test-Path $LocalBin) {
    if ($env:PATH -notlike "*$LocalBin*") {
        $env:PATH = "$LocalBin;$env:PATH"
    }
}

function Test-SkillSpectorInstalled {
    if (Get-Command "skillspector" -ErrorAction SilentlyContinue) {
        return $true
    }
    $LocalExe = Join-Path $LocalBin "skillspector.exe"
    if (Test-Path $LocalExe) {
        $env:PATH = "$LocalBin;$env:PATH"
        return $true
    }
    return $false
}

function Ensure-SkillSpector {
    if (Test-SkillSpectorInstalled) {
        return $true
    }

    Write-Log "SkillSpector no está instalado. Instalándolo automáticamente para garantizar la seguridad..." -Color Yellow

    if (Get-Command "uv" -ErrorAction SilentlyContinue) {
        Write-Log "Instalando NVIDIA SkillSpector vía 'uv tool install'..." -Color Cyan
        if ($Silent) {
            uv tool install git+https://github.com/NVIDIA/skillspector.git *>$null
        } else {
            uv tool install git+https://github.com/NVIDIA/skillspector.git
        }
    } elseif (Get-Command "pip" -ErrorAction SilentlyContinue) {
        Write-Log "Instalando NVIDIA SkillSpector vía 'pip install'..." -Color Cyan
        if ($Silent) {
            pip install git+https://github.com/NVIDIA/skillspector.git *>$null
        } else {
            pip install git+https://github.com/NVIDIA/skillspector.git
        }
    } else {
        Write-Log "Aviso: No se encontró 'uv' ni 'pip' para instalar SkillSpector. Se continuará sin escaneo." -Color Yellow
        return $false
    }

    if (Test-Path (Join-Path $LocalBin "skillspector.exe")) {
        $env:PATH = "$LocalBin;$env:PATH"
    }

    if (Test-SkillSpectorInstalled) {
        Write-Log "SkillSpector instalado con éxito." -Color Green
        return $true
    } else {
        Write-Log "Aviso: No se pudo verificar la instalación de SkillSpector." -Color Yellow
        return $false
    }
}

function Invoke-SkillSecurityScan($TargetFolder) {
    if ($SkipScan) {
        Write-Log "Escaneo de seguridad omitido por el usuario (-SkipScan)." -Color DarkGray
        return $true
    }

    $Installed = Ensure-SkillSpector
    if (-not $Installed) {
        Write-Log "Continuando sin escaneo de seguridad (SkillSpector no disponible)." -Color Yellow
        return $true
    }

    Write-Log "Ejecutando escaneo de seguridad con NVIDIA SkillSpector (modo estático ultra rápido)..." -Color Cyan

    $ReportFile = Join-Path $ScratchPath "skillspector_scan.json"
    if (Test-Path $ReportFile) { Remove-Item -Force $ReportFile }

    & skillspector scan $TargetFolder --no-llm --format json --output $ReportFile
    $ScanExitCode = $LASTEXITCODE

    # Extraer y desglosar archivos comprometidos / señalados para análisis del usuario y del agente
    if (Test-Path $ReportFile) {
        try {
            $JsonContent = Get-Content $ReportFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $Risk = $JsonContent.risk_assessment
            $Issues = $JsonContent.issues

            if ($Issues -and $Issues.Count -gt 0) {
                $RiskSeverity = if ($Risk -and $Risk.severity) { $Risk.severity } else { "UNKNOWN" }
                $RiskScore = if ($Risk -and $Risk.score -ne $null) { $Risk.score } else { "N/A" }
                $RiskRec = if ($Risk -and $Risk.recommendation) { $Risk.recommendation } else { "N/A" }

                Write-Log "`n--- DETALLE DE SEGURIDAD (NVIDIA SkillSpector) ---" -Color Yellow
                Write-Log "Nivel de Riesgo: $RiskSeverity (Score: $RiskScore/100) - Recomendación: $RiskRec" -Color $(if ($RiskSeverity -eq "CRITICAL" -or $RiskSeverity -eq "HIGH") { "Red" } else { "Yellow" })
                Write-Log "Archivos comprometidos / señalados ($($Issues.Count) hallazgos detectados):" -Color Yellow

                $FilesGroup = $Issues | Group-Object { $_.location.file }
                foreach ($Group in $FilesGroup) {
                    Write-Log "  • Archivo: $($Group.Name)" -Color Cyan
                    foreach ($Iss in ($Group.Group | Select-Object -First 3)) {
                        $LineInfo = if ($Iss.location.start_line) { " (línea $($Iss.location.start_line))" } else { "" }
                        $Pat = if ($Iss.pattern) { $Iss.pattern } else { $Iss.id }
                        $Cat = if ($Iss.category) { $Iss.category } else { "General" }
                        $SevCol = if ($Iss.severity -eq "HIGH" -or $Iss.severity -eq "CRITICAL") { "Red" } else { "White" }
                        Write-Log "      - [$($Iss.severity)] $($Cat): $Pat$LineInfo" -Color $SevCol
                    }
                    if ($Group.Group.Count -gt 3) {
                        Write-Log "      - ... (+ $($Group.Group.Count - 3) observaciones adicionales en este archivo)" -Color DarkGray
                    }
                }
                Write-Log "--------------------------------------------------`n" -Color Yellow
            }
        } catch {
            Write-Log "Aviso: No se pudo formatear el detalle del reporte JSON: $_" -Color DarkGray
        }
    }

    if ($ScanExitCode -ne 0) {
        Write-Log "❌ ALERTA DE SEGURIDAD: SkillSpector detectó un nivel de riesgo crítico o elevado en el plugin (Exit Code: $ScanExitCode)." -Color Red
        Write-Log "La instalación ha sido cancelada para proteger tu entorno." -Color Red
        Write-Log "Si confías plenamente en este código y deseas forzar la instalación, ejecuta el script agregando: -SkipScan" -Color Yellow
        return $false
    }

    Write-Log "✅ Escaneo completado: No se detectaron riesgos críticos en el plugin." -Color Green
    return $true
}

# 1. Ensure paths exist
if (-not (Test-Path $ScratchPath)) {
    New-Item -ItemType Directory -Path $ScratchPath -Force | Out-Null
}
if (-not (Test-Path $PluginsPath)) {
    New-Item -ItemType Directory -Path $PluginsPath -Force | Out-Null
}

# 2. Function to install/update a plugin directory
function Install-Plugin($SrcFolder, [switch]$Force) {
    $PluginName = Split-Path $SrcFolder -Leaf
    
    # Exclude non-essential, redundant, or boilerplate plugins
    if (-not $Force -and -not $All -and ($DefaultExcludedPlugins -contains $PluginName)) {
        Write-Log "  [Omitido] $PluginName (no esencial / redundante con Antigravity). Usa -All para forzar." -Color DarkGray
        return
    }

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

    # A. Restructure root-level SKILL.md if found
    $RootSkill = Join-Path $DestFolder "SKILL.md"
    if (Test-Path $RootSkill) {
        $TargetSkillFolder = Join-Path $DestFolder "skills\$PluginName"
        if (-not (Test-Path $TargetSkillFolder)) {
            New-Item -ItemType Directory -Path $TargetSkillFolder -Force | Out-Null
        }
        Move-Item -Path $RootSkill -Destination (Join-Path $TargetSkillFolder "SKILL.md") -Force
        
        # Move related resource folders if they exist at root
        foreach ($Folder in @("references", "scripts", "examples")) {
            $RootFolder = Join-Path $DestFolder $Folder
            if (Test-Path $RootFolder) {
                Move-Item -Path $RootFolder -Destination $TargetSkillFolder -Force
            }
        }
    }

    # B. Scan for SKILL.md files and rename conflicting names
    Get-ChildItem -Path $DestFolder -Filter "SKILL.md" -Recurse | ForEach-Object {
        $SkillFile = $_.FullName
        $ParentDir = Split-Path (Split-Path $SkillFile -Parent) -Leaf
        $Content = [System.IO.File]::ReadAllText($SkillFile, [System.Text.Encoding]::UTF8)
        
        # Split content by '---' to isolate frontmatter
        $Parts = $Content -split '---', 3
        if ($Parts.Length -ge 3) {
            $Frontmatter = $Parts[1]
            
            # 1. Check if name exists
            if ($Frontmatter -notmatch '(?m)^name\s*:') {
                $Frontmatter = "`nname: $ParentDir" + $Frontmatter
                $SkillName = $ParentDir
            } else {
                # Extract name
                if ($Frontmatter -match '(?m)^name:\s*[''"]?([^\''"\r\n]+)[''"]?\s*$') {
                    $SkillName = $Matches[1].Trim()
                } else {
                    $SkillName = $ParentDir
                }
            }
            
            # 2. Rename if it is generic
            if ($SkillName -eq "access" -or $SkillName -eq "configure") {
                $NewSkillName = "$PluginName-$SkillName"
                $Frontmatter = $Frontmatter -replace '(?m)^name:\s*.*$', "name: $NewSkillName"
            }
            
            $Parts[1] = $Frontmatter
            $NewContent = $Parts -join '---'
            if ($Content -ne $NewContent) {
                [System.IO.File]::WriteAllText($SkillFile, $NewContent, [System.Text.Encoding]::UTF8)
            }
        }
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
        # Validar seguridad con SkillSpector antes de proceder a la instalación
        $ScanPassed = Invoke-SkillSecurityScan $TempPath
        if (-not $ScanPassed) {
            Remove-Item -Recurse -Force $TempPath
            return
        }

        $HasNested = $false
        $PluginsDir = Join-Path $TempPath "plugins"
        $ExtPluginsDir = Join-Path $TempPath "external_plugins"
        
        if (Test-Path $PluginsDir) {
            Get-ChildItem -Path $PluginsDir -Directory | ForEach-Object {
                Install-Plugin $_.FullName -Force
                $HasNested = $true
            }
        }
        if (Test-Path $ExtPluginsDir) {
            Get-ChildItem -Path $ExtPluginsDir -Directory | ForEach-Object {
                Install-Plugin $_.FullName -Force
                $HasNested = $true
            }
        }
        if (-not $HasNested) {
            Install-Plugin $TempPath -Force
        }
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

# 4. Clean unneeded / non-essential plugins if requested or during standard sync
if (-not $All) {
    Write-Log "Optimizando ventana de contexto: verificando y removiendo plugins no esenciales..." -Color Cyan
    $RemovedCount = 0
    foreach ($Excluded in $DefaultExcludedPlugins) {
        $InstalledDir = Join-Path $PluginsPath $Excluded
        if (Test-Path $InstalledDir) {
            Write-Log "  Removiendo plugin no esencial para liberar contexto: $Excluded..." -Color Yellow
            Remove-Item -Recurse -Force $InstalledDir -ErrorAction SilentlyContinue
            $RemovedCount++
        }
    }
    if ($RemovedCount -gt 0) {
        Write-Log "✅ Se removieron $RemovedCount plugins no esenciales para liberar presupuesto de tokens de contexto." -Color Green
    }
}

if ($CleanUnneeded) {
    Write-Log "Limpieza de plugins no esenciales finalizada." -Color Green
    return
}

# 5. Regular Official Repo Sync
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

# 6. Write/generate the claude-plugins-manager plugin and skill
$ManagerFolder = Join-Path $PluginsPath "claude-plugins-manager"
$ManagerSkillsFolder = Join-Path $ManagerFolder "skills\sync-plugins"

if (-not (Test-Path $ManagerSkillsFolder)) { New-Item -ItemType Directory -Path $ManagerSkillsFolder -Force | Out-Null }

$ManagerJson = @{
    name = "claude-plugins-manager"
    version = "1.3.0"
    description = "Manage, sync, and install official and third-party Claude plugins globally for Antigravity with context optimization"
    author = @{ name = "jersonalvr" }
} | ConvertTo-Json

[System.IO.File]::WriteAllText((Join-Path $ManagerFolder "plugin.json"), $ManagerJson)

$SkillMd = @'
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

   **C. To Clean / Remove Unneeded Plugins Only:**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1 -CleanUnneeded`
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh --clean`

   **D. To Install an External Plugin (User provides a Git URL):**
   - On Windows: `powershell -ExecutionPolicy Bypass -File $Home\.gemini\config\plugins\sync-claude-plugins.ps1 -ExternalUrl "URL_HERE"`
   - On macOS/Linux: `bash $HOME/.gemini/config/plugins/sync-claude-plugins.sh "URL_HERE"`
   *(Note: External plugins are automatically scanned with NVIDIA SkillSpector. Pass -SkipScan or --skip-scan to bypass)*

   **E. To Audit Any Plugin or Skill On-Demand:**
   - On Windows/macOS/Linux: `skillspector scan "PATH_TO_SKILL" --no-llm`

2. Report the output of the execution to the user:
   - If SkillSpector detects risks and blocks installation, the output will list the specific compromised/flagged files, categories, and line numbers.
   - You MUST review each reported file and finding to provide an informed, reasoned security audit to the user instead of a generic error message:
     * Explain whether the findings are true malicious risks (e.g. credential theft, unauthorized file access, rogue scripts) or common structural/prompting false positives (e.g. strict anti-laziness rules, HTML placeholder comments, unpinned MCP/npx packages).
     * Advise the user that if they review the code and trust the repository, they can bypass the block by re-running with -SkipScan or --skip-scan.
3. If successful, tell the user that the plugin(s) are now ready to be used.
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
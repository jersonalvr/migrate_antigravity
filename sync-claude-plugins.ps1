# sync-claude-plugins.ps1
# Script to synchronize official Claude Code plugins or install external skills globally

param(
    [string]$ExternalUrl = "",
    [string[]]$Include = @(),
    [string[]]$Remove = @(),
    [switch]$Interactive,
    [switch]$FindDuplicates,
    [switch]$FixDuplicates,
    [switch]$Science,
    [switch]$PluginDev,
    [switch]$Silent,
    [switch]$SkipScan,
    [switch]$All,
    [switch]$CleanUnneeded
)

$IncludeList = @()
if ($Include) {
    foreach ($item in $Include) {
        $IncludeList += ($item -split ',').ForEach({ $_.Trim() }) | Where-Object { $_ -ne "" }
    }
}

$RemoveList = @()
if ($Remove) {
    foreach ($item in $Remove) {
        $RemoveList += ($item -split ',').ForEach({ $_.Trim() }) | Where-Object { $_ -ne "" }
    }
}

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    if (-not $Silent) {
        Write-Host $Message -ForegroundColor $Color
    }
}

$PluginsPath = Join-Path $Home ".gemini\config\plugins"
$SkillsPath = Join-Path $Home ".gemini\config\skills"
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
    "receipts", "session-report", "claude-security", "full-output-enforcement",

    # Puentes de mensajería (skills access/configure consumen tokens innecesarios)
    "discord", "imessage", "telegram",

    # Nicho / Hardware / Matemáticas de concurso / Marca
    "cwc-makers", "math-olympiad", "math-proof", "brandkit",

    # Servicios externos no configurados / estilos de salida CLI
    "asana", "linear", "gitlab", "laravel-boost", "fakechat",
    "explanatory-output-style", "learning-output-style",

    # Módulos masivos opcionales (gestionables vía menú interactivo o flags)
    "science", "plugin-dev", "taste-skill"
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
        Write-Log "[ALERTA DE SEGURIDAD] SkillSpector detecto un nivel de riesgo critico o elevado en el plugin (Exit Code: $ScanExitCode)." -Color Red
        Write-Log "La instalacion ha sido cancelada para proteger tu entorno." -Color Red
        Write-Log "Si confias plenamente en este codigo y deseas forzar la instalacion, ejecuta el script agregando: -SkipScan" -Color Yellow
        return $false
    }

    Write-Log "[OK] Escaneo completado: No se detectaron riesgos criticos en el plugin." -Color Green
    return $true
}

# 1. Ensure paths exist
if (-not (Test-Path $ScratchPath)) {
    New-Item -ItemType Directory -Path $ScratchPath -Force | Out-Null
}
if (-not (Test-Path $PluginsPath)) {
    New-Item -ItemType Directory -Path $PluginsPath -Force | Out-Null
}

# 2. Functions to manage Antigravity config.json
function Update-AntigravityPluginConfig {
    $ConfigJsonPath = Join-Path (Join-Path $Home ".gemini") "config\config.json"
    if (-not (Test-Path $ConfigJsonPath)) { return }

    try {
        $ConfigRaw = [System.IO.File]::ReadAllText($ConfigJsonPath, [System.Text.Encoding]::UTF8)
        $ConfigObj = $ConfigRaw | ConvertFrom-Json
        
        if ($ConfigObj.plugins) {
            $Modified = $false
            foreach ($Prop in $ConfigObj.plugins.PSObject.Properties) {
                $PName = $Prop.Name
                # If plugin is in excluded list and not explicitly included or all
                if ($DefaultExcludedPlugins -contains $PName -and ($IncludeList -notcontains $PName) -and -not $All) {
                    if ($Prop.Value.enabled -ne $false) {
                        $Prop.Value.enabled = $false
                        $Modified = $true
                        Write-Log "  [Desactivado en config.json] $PName (liberando tokens de contexto)" -Color DarkGray
                    }
                }
            }

            if ($Modified) {
                $NewJson = $ConfigObj | ConvertTo-Json -Depth 10
                [System.IO.File]::WriteAllText($ConfigJsonPath, $NewJson, [System.Text.Encoding]::UTF8)
                Write-Log "Configuracion de plugins en config.json actualizada con exito." -Color Green
            }
        }
    } catch {
        Write-Log "Aviso: No se pudo actualizar config.json: $_" -Color DarkGray
    }
}

function Update-PluginConfigEntry([string]$PluginName, [bool]$Enabled) {
    $ConfigJsonPath = Join-Path (Join-Path $Home ".gemini") "config\config.json"
    if (-not (Test-Path $ConfigJsonPath)) { return }

    try {
        $ConfigRaw = [System.IO.File]::ReadAllText($ConfigJsonPath, [System.Text.Encoding]::UTF8)
        $ConfigObj = $ConfigRaw | ConvertFrom-Json
        
        if ($ConfigObj.plugins) {
            if ($ConfigObj.plugins.PSObject.Properties[$PluginName]) {
                $ConfigObj.plugins.$PluginName.enabled = $Enabled
            } else {
                $ConfigObj.plugins | Add-Member -MemberType NoteProperty -Name $PluginName -Value ([PSCustomObject]@{ enabled = $Enabled })
            }
            $NewJson = $ConfigObj | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($ConfigJsonPath, $NewJson, [System.Text.Encoding]::UTF8)
            Write-Log "  Plugin '$PluginName' configurado como enabled=$Enabled en config.json." -Color Green
        }
    } catch {
        Write-Log "Aviso: Error al actualizar '$PluginName' en config.json: $_" -Color DarkGray
    }
}

# 3. Function to remove a specific plugin or skill
function Remove-TargetPluginOrSkill([string]$Target) {
    $Target = $Target.Trim()
    if ([string]::IsNullOrWhiteSpace($Target)) { return }
    $Found = $false

    # 1. Plugin folder in ~/.gemini/config/plugins/<Target>
    $PluginDir = Join-Path $PluginsPath $Target
    if (Test-Path $PluginDir) {
        Write-Log "Removiendo plugin: $PluginDir..." -Color Yellow
        Remove-Item -Recurse -Force $PluginDir -ErrorAction SilentlyContinue
        Write-Log "Plugin '$Target' eliminado con exito." -Color Green
        $Found = $true
    }

    # 2. Global skill folder in ~/.gemini/config/skills/<Target>
    $SkillDir = Join-Path $SkillsPath $Target
    if (Test-Path $SkillDir) {
        Write-Log "Removiendo skill global: $SkillDir..." -Color Yellow
        Remove-Item -Recurse -Force $SkillDir -ErrorAction SilentlyContinue
        Write-Log "Skill global '$Target' eliminada con exito." -Color Green
        $Found = $true
    }

    # 3. Nested skill directory with that name inside any plugin
    $NestedSkills = Get-ChildItem -Path $PluginsPath -Directory -Recurse -Filter $Target -ErrorAction SilentlyContinue | Where-Object {
        (Test-Path (Join-Path $_.FullName "SKILL.md")) -or ($_.Parent.Name -eq "skills")
    }
    foreach ($Nested in $NestedSkills) {
        Write-Log "Removiendo skill anidada: $($Nested.FullName)..." -Color Yellow
        Remove-Item -Recurse -Force $Nested.FullName -ErrorAction SilentlyContinue
        Write-Log "Skill anidada '$Target' en plugin '$($Nested.Parent.Parent.Name)' eliminada con exito." -Color Green
        $Found = $true
    }

    # 4. Scratch folder
    $ScratchDir = Join-Path $ScratchPath $Target
    if (Test-Path $ScratchDir) {
        Write-Log "Removiendo datos en scratch: $ScratchDir..." -Color Yellow
        Remove-Item -Recurse -Force $ScratchDir -ErrorAction SilentlyContinue
        $Found = $true
    }

    # 5. Disable in Antigravity config.json
    Update-PluginConfigEntry -PluginName $Target -Enabled $false

    if (-not $Found) {
        Write-Log "Plugin o skill '$Target' desactivado en config.json." -Color Yellow
    }
}

# 3. Functions for Duplicate Detection and Resolution
function Find-DuplicateSkills([switch]$AutoFix) {
    Write-Log "`n--- ESCANEO DE SKILLS DUPLICADAS EN ANTIGRAVITY ---" -Color Cyan
    
    $Roots = @(
        @{ Name = "Config Skills (~/.gemini/config/skills)"; Path = $SkillsPath },
        @{ Name = "Antigravity Legacy Skills (~/.gemini/antigravity/skills)"; Path = (Join-Path $Home ".gemini\antigravity\skills") },
        @{ Name = "Installed Plugins (~/.gemini/config/plugins)"; Path = $PluginsPath }
    )

    $SkillEntries = @()
    foreach ($Root in $Roots) {
        if (Test-Path $Root.Path) {
            Get-ChildItem -Path $Root.Path -Filter "SKILL.md" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                $Content = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
                $SkillName = ""
                if ($Content -match '(?m)^name:\s*[''"]?([^\''"\r\n]+)[''"]?\s*$') {
                    $SkillName = $Matches[1].Trim()
                } else {
                    $SkillName = Split-Path (Split-Path $_.FullName -Parent) -Leaf
                }
                
                $SkillEntries += [PSCustomObject]@{
                    Name = $SkillName
                    File = $_.FullName
                    Folder = Split-Path $_.FullName -Parent
                    Source = $Root.Name
                    SourcePath = $Root.Path
                }
            }
        }
    }

    $Duplicates = $SkillEntries | Group-Object Name | Where-Object { $_.Count -gt 1 }

    if (-not $Duplicates -or $Duplicates.Count -eq 0) {
        Write-Log "[OK] Excelente: No se encontraron skills duplicadas en tu entorno." -Color Green
        return
    }

    Write-Log "[AVISO] Se encontraron $($Duplicates.Count) skills con definiciones duplicadas:`n" -Color Yellow
    
    foreach ($Dup in $Duplicates) {
        Write-Log "  * Skill: '$($Dup.Name)' ($($Dup.Count) copias encontradas)" -Color Yellow
        foreach ($Inst in $Dup.Group) {
            Write-Log "      - [$($Inst.Source)] $($Inst.File)" -Color DarkGray
        }
    }
    Write-Log ""

    if ($AutoFix -or $FixDuplicates) {
        Resolve-DuplicateSkills -Duplicates $Duplicates
    } else {
        Write-Log "[INFO] Para resolver automaticamente estas duplicaciones y liberar tokens, ejecuta:" -Color Cyan
        Write-Log "   .\sync-claude-plugins.ps1 -FixDuplicates" -Color White
    }
}

function Resolve-DuplicateSkills($Duplicates) {
    Write-Log "Resolviendo duplicados para liberar el presupuesto de tokens de contexto..." -Color Cyan
    $FixedCount = 0
    
    foreach ($Dup in $Duplicates) {
        $LegacyCopies = $Dup.Group | Where-Object { $_.Source -like "*Antigravity Legacy Skills*" }
        $ConfigCopies = $Dup.Group | Where-Object { $_.Source -like "*Config Skills*" }
        
        # Caso 1: Duplicado entre Antigravity Legacy y Config Skills
        if ($LegacyCopies -and $ConfigCopies) {
            foreach ($Leg in $LegacyCopies) {
                Write-Log "  Eliminando copia legacy duplicada: $($Leg.Folder)..." -Color Yellow
                Remove-Item -Recurse -Force $Leg.Folder -ErrorAction SilentlyContinue
                $FixedCount++
            }
        }
        # Caso 2: Duplicado entre un Plugin y Config Skills
        else {
            $PluginCopies = $Dup.Group | Where-Object { $_.Source -like "*Installed Plugins*" }
            if ($ConfigCopies -and $PluginCopies) {
                foreach ($Plg in $PluginCopies) {
                    Write-Log "  Eliminando copia redundante en plugin: $($Plg.Folder)..." -Color Yellow
                    Remove-Item -Recurse -Force $Plg.Folder -ErrorAction SilentlyContinue
                    $FixedCount++
                }
            }
        }
    }
    
    if ($FixedCount -gt 0) {
        Write-Log "[OK] Se eliminaron $FixedCount copias duplicadas de skills. Reinicia Antigravity IDE para ver el presupuesto en verde." -Color Green
    } else {
        Write-Log "No se requirieron cambios adicionales." -Color DarkGray
    }
}

function Install-ScienceSkills {
    $ScienceUrl = "https://github.com/google-deepmind/science-skills.git"
    $ScienceTemp = Join-Path $ScratchPath "science-skills"
    Write-Log "Clonando repositorio oficial de DeepMind Science Skills..." -Color Cyan
    if (Test-Path $ScienceTemp) { Remove-Item -Recurse -Force $ScienceTemp }
    
    git clone --depth 1 $ScienceUrl $ScienceTemp
    if (Test-Path $ScienceTemp) {
        $ScanPassed = Invoke-SkillSecurityScan $ScienceTemp
        if (-not $ScanPassed) {
            Remove-Item -Recurse -Force $ScienceTemp
            return
        }
        Install-Plugin $ScienceTemp -Force
        Write-Log "[OK] Paquete de ciencias (science) instalado con exito (37 skills)." -Color Green
    } else {
        Write-Log "[ERROR] Error al clonar el repositorio de science-skills." -Color Red
    }
}

function Pause-Menu {
    Write-Host "`nPresiona Enter para continuar..." -ForegroundColor DarkGray
    [void][Console]::ReadLine()
}

function Show-InteractiveMenu {
    do {
        Clear-Host
        Write-Host "==========================================================" -ForegroundColor Cyan
        Write-Host "     Antigravity Plugins & Skills Manager v1.5.0          " -ForegroundColor Yellow
        Write-Host "==========================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "1) [SYNC]  Sincronizacion Estandar Optimizada (Recomendado)" -ForegroundColor White
        Write-Host "   Instala plugins esenciales para desarrollo omitiendo redundantes y LSPs." -ForegroundColor DarkGray
        Write-Host ""
        
        $LegacySkillsDir = Join-Path $Home ".gemini\antigravity\skills"
        $DupeWarning = ""
        if (Test-Path $LegacySkillsDir) {
            $DupeCount = (Get-ChildItem -Path $LegacySkillsDir -Directory -ErrorAction SilentlyContinue).Count
            if ($DupeCount -gt 0) { $DupeWarning = " -- AVISO: ($DupeCount skills legacy detectadas)" }
        }
        Write-Host "2) [SCAN]  Buscar y Resolver Skills Duplicadas$DupeWarning" -ForegroundColor White
        Write-Host "   Detecta skills clonadas (~/.gemini/antigravity vs ~/.gemini/config) y libera tokens." -ForegroundColor DarkGray
        Write-Host ""

        $ConfigJsonPath = Join-Path (Join-Path $Home ".gemini") "config\config.json"
        $ConfigObj = $null
        if (Test-Path $ConfigJsonPath) {
            try { $ConfigObj = (Get-Content $ConfigJsonPath -Raw -Encoding UTF8) | ConvertFrom-Json } catch {}
        }

        $ScienceInstalled = ((Test-Path (Join-Path $PluginsPath "science")) -or ($ConfigObj -and $ConfigObj.plugins.science.enabled -eq $true))
        $SciStatus = if ($ScienceInstalled) { "[INSTALADO / HABILITADO - 37 skills]" } else { "[DESACTIVADO]" }
        $SciColor = if ($ScienceInstalled) { "Yellow" } else { "DarkGray" }
        Write-Host "3) [BIO]   Gestionar Plugins de Ciencia (DeepMind Science) $SciStatus" -ForegroundColor White
        Write-Host "   AlphaFold, ChemBL, PDB, Genomica (consume ~5.500 tokens de contexto)" -ForegroundColor $SciColor
        Write-Host ""

        $PluginDevInstalled = ((Test-Path (Join-Path $PluginsPath "plugin-dev")) -or ($ConfigObj -and $ConfigObj.plugins.'plugin-dev'.enabled -eq $true))
        $PDevStatus = if ($PluginDevInstalled) { "[INSTALADO / HABILITADO - 7 skills]" } else { "[DESACTIVADO]" }
        $PDevColor = if ($PluginDevInstalled) { "Yellow" } else { "DarkGray" }
        Write-Host "4) [DEV]   Gestionar Herramientas de Creacion de Plugins (plugin-dev) $PDevStatus" -ForegroundColor White
        Write-Host "   Skills para crear plugins, hooks y commands de Claude (consume ~1.200 tokens)" -ForegroundColor $PDevColor
        Write-Host ""

        $TasteInstalled = ((Test-Path (Join-Path $PluginsPath "taste-skill")) -or (Test-Path (Join-Path $ScratchPath "taste-skill")) -or ($ConfigObj -and $ConfigObj.plugins.'taste-skill'.enabled -eq $true))
        $TasteStatus = if ($TasteInstalled) { "[INSTALADO / HABILITADO - 13 skills]" } else { "[DESACTIVADO]" }
        $TasteColor = if ($TasteInstalled) { "Yellow" } else { "DarkGray" }
        Write-Host "5) [UI]    Gestionar Plugins de Frontend (taste-skill) $TasteStatus" -ForegroundColor White
        Write-Host "   13 estilos de frontend (brutalist, minimalist, etc. - consume ~1.800 tokens)" -ForegroundColor $TasteColor
        Write-Host ""

        Write-Host "6) [CLEAN] Limpiar todos los plugins no esenciales (Liberar tokens inmediatamente)" -ForegroundColor White
        Write-Host "7) [GIT]   Instalar Plugin Externo desde URL de Git (con SkillSpector)" -ForegroundColor White
        Write-Host "8) [ALL]   Sincronizar TODO sin filtros (-All - instala todos los plugins oficiales)" -ForegroundColor White
        Write-Host "9) [SALIR] Salir" -ForegroundColor Red
        Write-Host "==========================================================" -ForegroundColor Cyan
        
        $Choice = Read-Host "Selecciona una opcion [1-9]"
        switch ($Choice) {
            "1" {
                Write-Host "`nIniciando sincronizacion optimizada..." -ForegroundColor Cyan
                return "Sync"
            }
            "2" {
                Write-Host "`nEscaneando skills duplicadas..." -ForegroundColor Cyan
                Find-DuplicateSkills
                $Fix = Read-Host "`nDeseas resolver automaticamente las duplicaciones eliminando copias redundantes? [S/n]"
                if ($Fix -ne "n" -and $Fix -ne "N") {
                    Find-DuplicateSkills -AutoFix
                }
                Pause-Menu
            }
            "3" {
                if ($ScienceInstalled) {
                    $Resp = Read-Host "`nEl paquete 'science' esta instalado (37 skills / ~5.500 tokens). Deseas DESINSTALARLO para liberar contexto? [S/n]"
                    if ($Resp -ne "n" -and $Resp -ne "N") {
                        Remove-TargetPluginOrSkill "science"
                    }
                } else {
                    $Resp = Read-Host "`nDeseas INSTALAR el paquete 'science' (DeepMind Science Skills - 37 skills)? [s/N]"
                    if ($Resp -eq "s" -or $Resp -eq "S") {
                        Install-ScienceSkills
                        Update-PluginConfigEntry -PluginName "science" -Enabled $true
                    }
                }
                Pause-Menu
            }
            "4" {
                if ($PluginDevInstalled) {
                    $Resp = Read-Host "`nEl paquete 'plugin-dev' esta instalado (7 skills / ~1.200 tokens). Deseas DESINSTALARLO para liberar contexto? [S/n]"
                    if ($Resp -ne "n" -and $Resp -ne "N") {
                        Remove-TargetPluginOrSkill "plugin-dev"
                    }
                } else {
                    $Resp = Read-Host "`nDeseas INSTALAR 'plugin-dev' (herramientas para crear plugins de Claude)? [s/N]"
                    if ($Resp -eq "s" -or $Resp -eq "S") {
                        $script:IncludeList += "plugin-dev"
                        Write-Host "Se incluira 'plugin-dev' en la sincronizacion..." -ForegroundColor Green
                        return "Sync"
                    }
                }
                Pause-Menu
            }
            "5" {
                if ($TasteInstalled) {
                    $Resp = Read-Host "`nEl plugin 'taste-skill' esta instalado (13 skills / ~1.800 tokens). Deseas DESINSTALARLO para liberar contexto? [S/n]"
                    if ($Resp -ne "n" -and $Resp -ne "N") {
                        Remove-TargetPluginOrSkill "taste-skill"
                    }
                } else {
                    Write-Host "`nEl plugin taste-skill no esta instalado." -ForegroundColor Gray
                }
                Pause-Menu
            }
            "6" {
                $script:CleanUnneeded = $true
                return "Clean"
            }
            "7" {
                $Url = Read-Host "`nIntroduce la URL del repositorio Git del plugin"
                if (-not [string]::IsNullOrWhiteSpace($Url)) {
                    $script:ExternalUrl = $Url.Trim()
                    return "External"
                }
            }
            "8" {
                $script:All = $true
                return "SyncAll"
            }
            "9" {
                Write-Host "Operacion cancelada." -ForegroundColor Yellow
                exit 0
            }
            default {
                Write-Host "Opcion invalida. Presiona Enter para continuar..." -ForegroundColor Red
                [void][Console]::ReadLine()
            }
        }
    } while ($true)
}

# 4. Function to install/update a plugin directory
function Install-Plugin($SrcFolder, [switch]$Force) {
    $PluginName = Split-Path $SrcFolder -Leaf
    
    # Exclude non-essential, redundant, or boilerplate plugins
    if (-not $Force -and -not $All -and ($DefaultExcludedPlugins -contains $PluginName)) {
        if ($IncludeList -contains $PluginName) {
            Write-Log "  [Incluido explícitamente vía -Include] $PluginName..." -Color Cyan
        } else {
            Write-Log "  [Omitido] $PluginName (no esencial / redundante con Antigravity). Usa -Include o -All para forzar." -Color DarkGray
            return
        }
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

# Handle standalone flags first
if ($FindDuplicates) {
    Find-DuplicateSkills
    return
}
if ($FixDuplicates) {
    Find-DuplicateSkills -AutoFix
    return
}
if ($Science) {
    Install-ScienceSkills
    return
}
if ($PluginDev) {
    $IncludeList += "plugin-dev"
}

# Check if interactive mode is triggered
$HasExplicitAction = ($ExternalUrl -ne "") -or ($Include.Count -gt 0) -or ($Remove.Count -gt 0) -or $All -or $CleanUnneeded -or $PluginDev

$IsPiped = $false
try {
    $IsPiped = [Console]::IsInputRedirected
} catch {
    $IsPiped = $false
}

if ($Interactive -or (-not $HasExplicitAction -and -not $Silent -and -not $IsPiped)) {
    $MenuAction = Show-InteractiveMenu
    if ($MenuAction -eq "External") {
        # Continúa con $ExternalUrl
    } elseif ($MenuAction -eq "Clean") {
        $CleanUnneeded = $true
    } elseif ($MenuAction -eq "SyncAll") {
        $All = $true
    } elseif ($MenuAction -eq "Sync") {
        # Continúa con sincronización estándar
    } else {
        return
    }
}

# 4. Handle Removal of Specific Plugins or Skills
if ($RemoveList.Count -gt 0) {
    Write-Log "Procesando eliminación de plugins o skills solicitados..." -Color Cyan
    foreach ($Item in $RemoveList) {
        Remove-TargetPluginOrSkill $Item
    }
    if ($ExternalUrl -eq "" -and -not $All -and -not $CleanUnneeded -and $IncludeList.Count -eq 0) {
        Write-Log "Operación de eliminación completada." -Color Green
        return
    }
}

# 5. Handle External Plugin Installation (if URL is provided)
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

# 6. Clean unneeded / non-essential plugins if requested or during standard sync
if (-not $All) {
    Write-Log "Optimizando ventana de contexto: verificando y removiendo plugins no esenciales..." -Color Cyan
    $RemovedCount = 0
    foreach ($Excluded in $DefaultExcludedPlugins) {
        if ($IncludeList -contains $Excluded) {
            continue
        }
        $InstalledDir = Join-Path $PluginsPath $Excluded
        if (Test-Path $InstalledDir) {
            Write-Log "  Removiendo plugin no esencial para liberar contexto: $Excluded..." -Color Yellow
            Remove-Item -Recurse -Force $InstalledDir -ErrorAction SilentlyContinue
            $RemovedCount++
        }
    }
    # Desactivar en config.json
    Update-AntigravityPluginConfig

    if ($RemovedCount -gt 0) {
        Write-Log "Se removieron $RemovedCount plugins no esenciales para liberar presupuesto de tokens de contexto." -Color Green
    }
}

if ($CleanUnneeded) {
    Update-AntigravityPluginConfig
    Write-Log "Limpieza de plugins no esenciales finalizada. Reinicia Antigravity IDE para aplicar los cambios de contexto." -Color Green
    return
}

# 7. Regular Official Repo Sync
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
    version = "1.5.0"
    description = "Manage, sync, and install official and third-party Claude plugins globally for Antigravity with context optimization"
    author = @{ name = "jersonalvr" }
} | ConvertTo-Json

[System.IO.File]::WriteAllText((Join-Path $ManagerFolder "plugin.json"), $ManagerJson)

$SkillMd = @'
---
name: sync-plugins
description: Sync official Claude plugins, clean unneeded plugins, scan for duplicates, or install a skill/plugin globally in Antigravity. Use when the user asks to update plugins, sync plugins, clean unneeded plugins, find duplicates, or install a skill/plugin from an external URL.
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

Update-AntigravityPluginConfig

Write-Log "Sync completed successfully!" -Color Green
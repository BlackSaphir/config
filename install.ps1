<#
.SYNOPSIS
    Sets up the terminal environment from github.com/BlackSaphir/config on Windows.

.DESCRIPTION
    Run in a normal (non-admin) PowerShell window:

        irm https://raw.githubusercontent.com/BlackSaphir/config/main/install.ps1 | iex

    or, inside a clone of the repo:

        powershell -ExecutionPolicy Bypass -File .\install.ps1

    Works in Windows PowerShell 5.1 and PowerShell 7. Safe to run again: steps
    that are already done are skipped. Every file it changes is backed up first
    (*.bak-<timestamp>). See TROUBLESHOOTING.md if something fails.

    Environment variables to change what it does:
        CONFIG_DOCKER=1   install Docker Desktop without asking
        CONFIG_DOCKER=0   skip Docker Desktop without asking
#>

function Install-Config {
    $ErrorActionPreference = 'Continue'
    $ProgressPreference    = 'SilentlyContinue'   # makes downloads in PowerShell 5.1 much faster
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $RepoRaw   = 'https://raw.githubusercontent.com/BlackSaphir/config/main'
    $Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
    $Failures  = New-Object System.Collections.Generic.List[string]
    $Notes     = New-Object System.Collections.Generic.List[string]
    $LocalRepo = $null
    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'starship\starship.toml'))) { $LocalRepo = $PSScriptRoot }

    # ---------------------------------------------------------------- helpers

    function Write-Step($text) { Write-Host ''; Write-Host "==> $text" -ForegroundColor Cyan }
    function Write-Ok($text)   { Write-Host "    ok    $text" -ForegroundColor Green }
    function Write-Skip($text) { Write-Host "    skip  $text" -ForegroundColor DarkGray }
    function Write-Warn($text) { Write-Host "    warn  $text" -ForegroundColor Yellow }
    function Write-Fail($text) { Write-Host "    FAIL  $text" -ForegroundColor Red; $Failures.Add($text) }

    function Update-SessionPath {
        $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path = "$machine;$user"
    }

    function Test-Command($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }

    function Backup-File($path) {
        if (Test-Path $path) {
            $bak = "$path.bak-$Stamp"
            Copy-Item $path $bak -Force
            return $bak
        }
    }

    function Write-Utf8NoBom($path, $text) {
        $dir = Split-Path $path -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
        [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $false))
    }

    # Reads a JSON file that may contain // comment lines and trailing commas
    # (winget and Windows Terminal settings). Returns $null if it can't be parsed.
    function Read-JsonWithComments($path) {
        $raw = Get-Content $path -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]@{} }
        $clean = ($raw -split "`r?`n" | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
        $clean = [regex]::Replace($clean, ',(\s*[}\]])', '$1')
        try { return $clean | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    }

    function Set-JsonProperty($obj, $name, $value) {
        if ($obj.PSObject.Properties[$name]) { $obj.$name = $value }
        else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
    }

    function Get-RepoFile($relPath, $dest) {
        if ($LocalRepo) {
            Copy-Item (Join-Path $LocalRepo $relPath) $dest -Force
        } else {
            Save-Url "$RepoRaw/$($relPath -replace '\\','/')" $dest
        }
    }

    # Waits until DNS works again (for example after a VPN or Tailscale changed
    # the network). Returns $false if it still fails after $seconds.
    function Wait-Network($seconds = 60) {
        $deadline = (Get-Date).AddSeconds($seconds)
        while ((Get-Date) -lt $deadline) {
            try { [Net.Dns]::GetHostAddresses('github.com') | Out-Null; return $true } catch { Start-Sleep -Seconds 3 }
        }
        return $false
    }

    # Every download is tried twice. Before the second try the script waits for
    # the network, so a short outage doesn't fail the whole run.
    $Attempts = 2

    function Install-WingetPackage($id) {
        winget list --id $id --exact --accept-source-agreements --disable-interactivity *> $null
        if ($LASTEXITCODE -eq 0) { Write-Skip "$id (already installed)"; return }
        for ($i = 1; $i -le $Attempts; $i++) {
            Write-Host "    ...   installing $id"
            winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
            $code = $LASTEXITCODE
            if ($code -eq 0) { Write-Ok $id; return }
            if ($i -lt $Attempts) { Write-Warn "$id failed (winget exit code $code); waiting for the network, then trying again"; Wait-Network | Out-Null }
        }
        Write-Fail "$id (winget exit code $code)"
    }

    function Save-Url($url, $outFile) {
        for ($i = 1; $i -le $Attempts; $i++) {
            try { Invoke-WebRequest $url -OutFile $outFile -UseBasicParsing -ErrorAction Stop; return }
            catch {
                if ($i -ge $Attempts) { throw }
                Write-Warn "Download failed ($($_.Exception.Message)); waiting for the network, then trying again"
                Wait-Network | Out-Null
            }
        }
    }

    # Runs PowerShell code in a separate process. The code is passed base64-encoded
    # because Windows PowerShell 5.1 mangles quotes in arguments to programs.
    # Hiding progress and using text output keeps the child from writing CLIXML
    # when the output is redirected.
    function Invoke-Encoded($exe, $code) {
        $code = "`$ProgressPreference = 'SilentlyContinue'`n" + $code
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
        & $exe -NoProfile -ExecutionPolicy Bypass -OutputFormat Text -EncodedCommand $encoded
    }

    # Runs a vendor install script in a separate process, so an `exit` inside it
    # can't close this window.
    function Invoke-RemoteInstaller($name, $url) {
        for ($i = 1; $i -le $Attempts; $i++) {
            Write-Host "    ...   installing $name"
            Invoke-Encoded 'powershell' "irm '$url' | iex"
            $code = $LASTEXITCODE
            if ($code -eq 0) { Write-Ok $name; return }
            if ($i -lt $Attempts) { Write-Warn "$name failed (exit code $code); waiting for the network, then trying again"; Wait-Network | Out-Null }
        }
        Write-Fail "$name (installer exit code $code)"
    }

    # herdr installs `hc` (its CLI) and a Start menu shortcut; `herdr` may not be on PATH.
    function Test-Herdr {
        if ((Test-Command 'herdr') -or (Test-Command 'hc')) { return $true }
        [bool](Get-ChildItem (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs') -Recurse -Filter '*herdr*' -ErrorAction SilentlyContinue)
    }

    # True if a font file is both registered (per-user or system-wide) and present.
    # A file without a registry entry is not usable by Windows Terminal.
    function Test-FontRegistered($fileName) {
        $keys = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts', 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
        foreach ($key in $keys) {
            $props = Get-ItemProperty $key -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -in 'PSPath','PSParentPath','PSChildName','PSDrive','PSProvider') { continue }
                $data = [string]$p.Value
                if (-not $data -or (Split-Path $data -Leaf) -ne $fileName) { continue }
                $full = if ([IO.Path]::IsPathRooted($data)) { $data } else { Join-Path $env:WINDIR "Fonts\$data" }
                if (Test-Path $full) { return $true }
            }
        }
        return $false
    }

    # ConvertTo-Json in Windows PowerShell 5.1 indents oddly. This re-indents
    # compact JSON with 4 spaces, like Windows Terminal writes it.
    function Format-Json($json) {
        $sb = New-Object Text.StringBuilder
        $level = 0; $inString = $false; $escaped = $false
        $chars = $json.ToCharArray()
        for ($i = 0; $i -lt $chars.Length; $i++) {
            $c = $chars[$i]
            if ($inString) {
                [void]$sb.Append($c)
                if ($escaped) { $escaped = $false }
                elseif ($c -eq [char]'\') { $escaped = $true }
                elseif ($c -eq [char]'"') { $inString = $false }
                continue
            }
            if ($c -eq [char]'"') { $inString = $true; [void]$sb.Append($c) }
            elseif ($c -eq [char]'{' -or $c -eq [char]'[') {
                $next = if ($i + 1 -lt $chars.Length) { $chars[$i + 1] } else { [char]0 }
                if (($c -eq [char]'{' -and $next -eq [char]'}') -or ($c -eq [char]'[' -and $next -eq [char]']')) {
                    [void]$sb.Append($c).Append($next); $i++
                } else {
                    $level++
                    [void]$sb.Append($c).Append("`n").Append('    ' * $level)
                }
            }
            elseif ($c -eq [char]'}' -or $c -eq [char]']') {
                $level--
                [void]$sb.Append("`n").Append('    ' * $level).Append($c)
            }
            elseif ($c -eq [char]',') { [void]$sb.Append(",`n").Append('    ' * $level) }
            elseif ($c -eq [char]':') { [void]$sb.Append(': ') }
            elseif (-not [char]::IsWhiteSpace($c)) { [void]$sb.Append($c) }
        }
        return $sb.ToString() + "`n"
    }

    function Write-Json($path, $obj) {
        Write-Utf8NoBom $path (Format-Json ($obj | ConvertTo-Json -Depth 32 -Compress))
    }

    # ---------------------------------------------------------------- checks

    Write-Host ''
    Write-Host 'BlackSaphir/config - Windows setup' -ForegroundColor Cyan
    if ($LocalRepo) { Write-Host "Using config files from $LocalRepo" } else { Write-Host 'Downloading config files from GitHub' }

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Host ''
        Write-Host 'This window runs as administrator. Please run the script in a normal PowerShell window.' -ForegroundColor Red
        Write-Host 'User settings (PATH, fonts, profile) would otherwise end up in the wrong place.' -ForegroundColor Red
        return
    }
    if (-not (Test-Command 'winget')) {
        Write-Host ''
        Write-Host 'winget was not found. Install "App Installer" from the Microsoft Store, then run this script again.' -ForegroundColor Red
        return
    }

    try { $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() }
    catch { $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE } }
    if ($arch -eq 'AMD64') { $arch = 'X64' }

    # ---------------------------------------------------------------- 1. execution policy

    Write-Step 'Execution policy'
    try {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
        Write-Ok 'CurrentUser = RemoteSigned'
    } catch {
        if ((Get-ExecutionPolicy -Scope CurrentUser) -eq 'RemoteSigned') { Write-Ok 'CurrentUser = RemoteSigned (a more specific scope overrides it in this window; that is fine)' }
        else { Write-Fail "Could not set execution policy: $($_.Exception.Message)" }
    }

    # ---------------------------------------------------------------- 2. winget: extract zips with tar

    Write-Step 'winget: extract zip packages with tar'
    $wgSettings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json'
    $wg = if (Test-Path $wgSettings) { Read-JsonWithComments $wgSettings } else { [pscustomobject]@{} }
    if ($null -eq $wg) {
        $bak = Backup-File $wgSettings
        Write-Warn "Could not read winget settings; replaced them (backup: $bak)"
        $wg = [pscustomobject]@{}
    }
    if ($wg.PSObject.Properties['installBehavior'] -and $wg.installBehavior.PSObject.Properties['archiveExtractionMethod'] -and $wg.installBehavior.archiveExtractionMethod -eq 'tar') {
        Write-Skip 'already set'
    } else {
        if (Test-Path $wgSettings) { Backup-File $wgSettings | Out-Null }
        Set-JsonProperty $wg '$schema' 'https://aka.ms/winget-settings.schema.json'
        if (-not $wg.PSObject.Properties['installBehavior']) { Set-JsonProperty $wg 'installBehavior' ([pscustomobject]@{}) }
        Set-JsonProperty $wg.installBehavior 'archiveExtractionMethod' 'tar'
        Write-Json $wgSettings $wg
        Write-Ok 'archiveExtractionMethod = tar'
    }

    # ---------------------------------------------------------------- 3. winget packages

    # Tailscale is installed at the very end: installing it briefly interrupts
    # the network, which made every download after it fail.
    Write-Step 'Installing packages with winget'
    $packages = @(
        'Microsoft.PowerShell',
        'Microsoft.WindowsTerminal',
        'Git.Git',
        'GitHub.cli',
        'OpenJS.NodeJS.LTS',
        'Gitleaks.Gitleaks',
        'Starship.Starship',
        'eza-community.eza',
        'lsd-rs.lsd',
        'sharkdp.bat',
        'junegunn.fzf',
        'jdx.mise',
        'ajeetdsouza.zoxide',
        'sxyazi.yazi',
        'sharkdp.fd',
        'BurntSushi.ripgrep.MSVC'
    )
    foreach ($p in $packages) { Install-WingetPackage $p }

    $docker = $env:CONFIG_DOCKER
    if ($docker -ne '0' -and $docker -ne '1') {
        $answer = Read-Host '    Install Docker Desktop? It needs WSL2 and a restart afterwards. [y/N]'
        $docker = if ($answer -match '^(y|j)') { '1' } else { '0' }
    }
    if ($docker -eq '1') {
        Install-WingetPackage 'Docker.DockerDesktop'
        $Notes.Add('Docker Desktop: restart Windows, then start Docker Desktop once to finish its setup.')
    } else {
        Write-Skip 'Docker.DockerDesktop (not selected)'
    }

    Update-SessionPath

    # ---------------------------------------------------------------- 4. environment

    Write-Step 'Environment variables'
    $fileExe = Join-Path $env:ProgramFiles 'Git\usr\bin\file.exe'
    if (Test-Path $fileExe) {
        if ([Environment]::GetEnvironmentVariable('YAZI_FILE_ONE', 'User') -eq $fileExe) { Write-Skip 'YAZI_FILE_ONE already set' }
        else { [Environment]::SetEnvironmentVariable('YAZI_FILE_ONE', $fileExe, 'User'); Write-Ok "YAZI_FILE_ONE = $fileExe" }
        $env:YAZI_FILE_ONE = $fileExe
    } else {
        Write-Fail "file.exe not found at $fileExe (is Git for Windows installed?)"
    }

    # ---------------------------------------------------------------- 5. npm + agent-browser

    Write-Step 'agent-browser (npm)'
    if (-not (Test-Command 'npm')) {
        Write-Fail 'npm not found (Node.js install failed?). Skipping agent-browser.'
    } else {
        $npmPrefix = (& npm prefix -g 2>$null | Select-Object -First 1)
        if ($npmPrefix) {
            $npmPrefix = $npmPrefix.Trim()
            $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
            if (($userPath -split ';') -notcontains $npmPrefix) {
                [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ";$npmPrefix"), 'User')
                Write-Ok "Added npm global folder to PATH: $npmPrefix"
                Update-SessionPath
            } else {
                Write-Skip "npm global folder already on PATH"
            }
        }
        if (Test-Command 'agent-browser') {
            Write-Skip 'agent-browser (already installed)'
        } else {
            & npm install -g agent-browser
            Update-SessionPath
            if (Test-Command 'agent-browser') { Write-Ok 'agent-browser' } else { Write-Fail 'agent-browser (npm install failed)' }
        }
    }

    # ---------------------------------------------------------------- 6. Claude Code + herdr

    Write-Step 'Claude Code and herdr'
    if (Test-Command 'claude') { Write-Skip 'Claude Code (already installed)' }
    else { Invoke-RemoteInstaller 'Claude Code' 'https://claude.ai/install.ps1'; Update-SessionPath }

    if ($arch -ne 'X64') {
        Write-Skip "herdr (needs an x86_64 PC; this one is $arch)"
    } elseif (Test-Herdr) {
        Write-Skip 'herdr (already installed)'
    } else {
        Invoke-RemoteInstaller 'herdr' 'https://releases.herdr.dev/app/install.ps1'
    }

    # ---------------------------------------------------------------- 7. Nerd Font

    Write-Step 'Hack Nerd Font'
    $userFonts = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    if (Test-FontRegistered 'HackNerdFont-Regular.ttf') {
        Write-Skip 'already installed'
    } else {
        $tmp = Join-Path $env:TEMP "hack-nerd-font-$Stamp"
        try {
            New-Item -ItemType Directory -Force $tmp | Out-Null
            Save-Url 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip' "$tmp\Hack.zip"
            Expand-Archive "$tmp\Hack.zip" -DestinationPath "$tmp\Hack" -Force -ErrorAction Stop
            New-Item -ItemType Directory -Force $userFonts | Out-Null
            $regKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
            if (-not (Test-Path $regKey)) { New-Item -Path $regKey -Force | Out-Null }
            $fonts = Get-ChildItem "$tmp\Hack" -Filter 'HackNerdFont-*.ttf'
            foreach ($f in $fonts) {
                $target = Join-Path $userFonts $f.Name
                # A file that is already there may be in use; then only the registry entry is missing.
                if (-not (Test-Path $target)) { Copy-Item $f.FullName $target -Force -ErrorAction Stop }
                New-ItemProperty -Path $regKey -Name "$($f.BaseName) (TrueType)" -Value $target -PropertyType String -Force | Out-Null
            }
            Write-Ok "$($fonts.Count) font files installed for this user"
        } catch {
            Write-Fail "Hack Nerd Font: $($_.Exception.Message)"
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # ---------------------------------------------------------------- 8. Windows Terminal

    Write-Step 'Windows Terminal settings'
    $wtSettings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    if (-not (Test-Path $wtSettings)) {
        Write-Warn 'Windows Terminal has no settings file yet. Open Windows Terminal once, close it, and run this script again.'
        $Notes.Add('Windows Terminal: open it once, then run this script again to set the font and default profile.')
    } else {
        $wt = Read-JsonWithComments $wtSettings
        if ($null -eq $wt) {
            Write-Fail 'Could not read Windows Terminal settings.json; set the font and default profile by hand (see README).'
        } else {
            $changed = $false
            if (-not $wt.PSObject.Properties['profiles']) { Set-JsonProperty $wt 'profiles' ([pscustomobject]@{}) }
            if ($wt.profiles -is [array]) {
                Write-Warn 'Old settings.json layout; set the font by hand (Settings > Profiles > Defaults > Appearance).'
            } else {
                if (-not $wt.profiles.PSObject.Properties['defaults']) { Set-JsonProperty $wt.profiles 'defaults' ([pscustomobject]@{}) }
                $defaults = $wt.profiles.defaults
                if (-not $defaults.PSObject.Properties['font']) { Set-JsonProperty $defaults 'font' ([pscustomobject]@{}) }
                if ($defaults.font.PSObject.Properties['face'] -and $defaults.font.face -eq 'Hack Nerd Font') {
                    Write-Skip 'font already Hack Nerd Font'
                } else {
                    Set-JsonProperty $defaults.font 'face' 'Hack Nerd Font'; $changed = $true
                    Write-Ok 'font = Hack Nerd Font'
                }

                $pwshProfile = $null
                if ($wt.profiles.PSObject.Properties['list']) {
                    $pwshProfile = $wt.profiles.list | Where-Object { $_.PSObject.Properties['source'] -and $_.source -eq 'Windows.Terminal.PowershellCore' } | Select-Object -First 1
                }
                if ($pwshProfile) {
                    if ($wt.PSObject.Properties['defaultProfile'] -and $wt.defaultProfile -eq $pwshProfile.guid) {
                        Write-Skip 'default profile already PowerShell 7'
                    } else {
                        Set-JsonProperty $wt 'defaultProfile' $pwshProfile.guid; $changed = $true
                        Write-Ok 'default profile = PowerShell 7'
                    }
                } else {
                    Write-Warn 'Windows Terminal has not detected PowerShell 7 yet. Open Windows Terminal once and run this script again.'
                }
            }
            if ($changed) {
                $bak = Backup-File $wtSettings
                Write-Json $wtSettings $wt
                Write-Host "          backup: $bak" -ForegroundColor DarkGray
            }
        }
    }

    # ---------------------------------------------------------------- 9. config files

    Write-Step 'Config files (Starship, yazi)'
    $targets = @(
        @{ Src = 'starship\starship.toml'; Dest = Join-Path $env:USERPROFILE '.config\starship.toml' },
        @{ Src = 'yazi\theme.toml';        Dest = Join-Path $env:APPDATA 'yazi\config\theme.toml' }
    )
    foreach ($t in $targets) {
        try {
            $dir = Split-Path $t.Dest -Parent
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
            $tmpFile = "$($t.Dest).new"
            Get-RepoFile $t.Src $tmpFile
            if ((Test-Path $t.Dest) -and ((Get-FileHash $t.Dest).Hash -eq (Get-FileHash $tmpFile).Hash)) {
                Remove-Item $tmpFile -Force
                Write-Skip "$($t.Dest) (up to date)"
            } else {
                $bak = Backup-File $t.Dest
                Move-Item $tmpFile $t.Dest -Force
                if ($bak) { Write-Ok "$($t.Dest) (backup: $bak)" } else { Write-Ok $t.Dest }
            }
        } catch {
            Write-Fail "$($t.Src): $($_.Exception.Message)"
        }
    }

    # ---------------------------------------------------------------- 10. PowerShell 7 modules + profile

    Write-Step 'PowerShell 7 modules and profile'
    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwsh) {
        $candidate = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
        if (Test-Path $candidate) { $pwsh = $candidate }
    }
    if (-not $pwsh) {
        Write-Fail 'pwsh (PowerShell 7) not found; skipping modules and profile.'
    } else {
        $moduleCode = @'
$failed = $false
foreach ($m in 'PSFzf', 'Terminal-Icons') {
    if (Get-Module -ListAvailable $m) { Write-Host "    skip  $m (already installed)" -ForegroundColor DarkGray; continue }
    for ($i = 1; $i -le 2; $i++) {
        try {
            Install-Module $m -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Write-Host "    ok    $m" -ForegroundColor Green
            break
        } catch {
            if ($i -lt 2) {
                Write-Host "    warn  $m failed; trying again in 20 seconds" -ForegroundColor Yellow
                Start-Sleep -Seconds 20
            } else {
                Write-Host "    FAIL  $m : $($_.Exception.Message)" -ForegroundColor Red
                $failed = $true
            }
        }
    }
}
if ($failed) { exit 1 }
'@
        Invoke-Encoded $pwsh $moduleCode
        if ($LASTEXITCODE -ne 0) { $Failures.Add('Installing PSFzf / Terminal-Icons failed') }

        $profilePath = (& $pwsh -NoProfile -Command '$PROFILE' | Select-Object -First 1).Trim()
        $begin = '# >>> BlackSaphir/config >>>'
        $end   = '# <<< BlackSaphir/config <<<'
        $block = @'
# >>> BlackSaphir/config >>>
# Managed by install.ps1 from github.com/BlackSaphir/config.
# Running the script again replaces everything between these two markers.

function Test-Cmd($n) { [bool](Get-Command $n -ErrorAction SilentlyContinue) }

# Autosuggestions from history; syntax highlighting is built into PSReadLine
try {
    Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView -ErrorAction Stop
} catch { }
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

# fzf: Ctrl+T file search, Ctrl+R history search
if ((Test-Cmd fzf) -and (Get-Module -ListAvailable PSFzf)) {
    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}

if (Get-Module -ListAvailable Terminal-Icons) { Import-Module Terminal-Icons }
if (Test-Cmd mise)     { mise activate pwsh | Out-String | Invoke-Expression }
if (Test-Cmd starship) { Invoke-Expression (& starship init powershell) }
if (Test-Cmd zoxide)   { Invoke-Expression (& { (zoxide init powershell | Out-String) }) }   # z, zi

# yazi: start with `y`; `q` quits and changes to the folder you were in
function y {
    $tmp = (New-TemporaryFile).FullName
    yazi $args --cwd-file="$tmp"
    $cwd = Get-Content -Path $tmp -Encoding UTF8
    if (-not [String]::IsNullOrEmpty($cwd) -and $cwd -ne $PWD.Path) {
        Set-Location -LiteralPath (Resolve-Path -LiteralPath $cwd).Path
    }
    Remove-Item -Path $tmp
}

# Aliases (same as macOS)
if (Test-Cmd lsd) {
    Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
    function ls  { lsd @args }
    function l   { lsd -l @args }
    function la  { lsd -a @args }
    function lsa { lsd -a @args }
    function lla { lsd -la @args }
    function lt  { lsd --tree @args }
}
if (Test-Cmd bat) {
    Remove-Item Alias:cat -Force -ErrorAction SilentlyContinue
    function cat { bat --paging=never @args }
}
# <<< BlackSaphir/config <<<
'@
        try {
            $existing = if (Test-Path $profilePath) { Get-Content $profilePath -Raw } else { '' }
            if ($null -eq $existing) { $existing = '' }
            $pattern = '(?s)' + [regex]::Escape($begin) + '.*?' + [regex]::Escape($end)
            if ($existing -match $pattern) {
                $replacement = $block.TrimEnd()
                $new = [regex]::Replace($existing, $pattern, { param($m) $replacement }.GetNewClosure())
            } else {
                $new = $existing.TrimEnd() + $(if ($existing.Trim()) { "`r`n`r`n" } else { '' }) + $block.TrimEnd() + "`r`n"
            }
            if ($new -eq $existing) {
                Write-Skip "$profilePath (up to date)"
            } else {
                $bak = Backup-File $profilePath
                Write-Utf8NoBom $profilePath $new
                if ($bak) { Write-Ok "$profilePath (backup: $bak)" } else { Write-Ok $profilePath }
            }
        } catch {
            Write-Fail "Writing the PowerShell profile: $($_.Exception.Message)"
        }
    }

    # ---------------------------------------------------------------- 11. Tailscale (last)

    Write-Step 'Tailscale (installed last because it briefly interrupts the network)'
    Install-WingetPackage 'Tailscale.Tailscale'

    # ---------------------------------------------------------------- 12. check

    Write-Step 'Check'
    Update-SessionPath
    $tools = 'pwsh','git','gh','node','npm','gitleaks','starship','tailscale','eza','lsd','bat','fzf','mise','zoxide','yazi','fd','rg','agent-browser','claude'
    foreach ($t in $tools) {
        if (Test-Command $t) { Write-Ok $t } else { Write-Fail "$t not found on PATH" }
    }
    if ($arch -eq 'X64') {
        if (Test-Herdr) { Write-Ok 'herdr' } else { Write-Fail 'herdr not found (no hc command or Start menu shortcut)' }
    }

    # ---------------------------------------------------------------- summary

    Write-Host ''
    if ($Failures.Count -eq 0) {
        Write-Host 'Done. Close this window and open Windows Terminal.' -ForegroundColor Green
    } else {
        Write-Host "Done with $($Failures.Count) problem(s):" -ForegroundColor Yellow
        $Failures | Select-Object -Unique | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        Write-Host 'See TROUBLESHOOTING.md: https://github.com/BlackSaphir/config/blob/main/TROUBLESHOOTING.md' -ForegroundColor Yellow
        Write-Host 'You can run this script again after fixing them; finished steps are skipped.'
    }
    foreach ($n in $Notes) { Write-Host "Note: $n" -ForegroundColor Cyan }
}

Install-Config

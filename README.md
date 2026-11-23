# config

Terminal and CLI setup for macOS and Windows.

## macOS

Requires [Homebrew](https://brew.sh).

```sh
git clone https://github.com/BlackSaphir/config.git
cd config
brew bundle --file=Brewfile
```

This also installs **iTerm2** and **Hack Nerd Font**, which provides the icons used by `lsd`.

If iTerm2 "already exists", see
[TROUBLESHOOTING.md](TROUBLESHOOTING.md#brew-bundle-iterm2-already-exists).

### iTerm2 profile

`iterm2/profile.json` is an iTerm2
[Dynamic Profile](https://iterm2.com/documentation-dynamic-profiles.html) named
**config**. It sets colours, Hack Nerd Font 12, an 80×40 window and so on.
Link it into iTerm2's dynamic profiles folder:

```sh
mkdir -p ~/Library/Application\ Support/iTerm2/DynamicProfiles
ln -sf "$PWD/iterm2/profile.json" ~/Library/Application\ Support/iTerm2/DynamicProfiles/config.json
```

iTerm2 loads it immediately. To make it the default, go to Settings → Profiles,
select **config**, then choose **Other Actions… → Set as Default**.

**Double-tap Control** opens a hotkey window. This needs the **Accessibility**
permission for iTerm2 (System Settings → Privacy & Security → Accessibility),
then a restart of iTerm2. If it doesn't work, see
[TROUBLESHOOTING.md](TROUBLESHOOTING.md#double-tap-control-doesnt-open-the-iterm2-hotkey-window).

Changes you make in the iTerm2 settings UI are not written back to this file.
To update the repo, edit `iterm2/profile.json` directly. Because it's a symlink,
iTerm2 picks up the edits right away.

### Starship prompt

`starship/starship.toml` is the prompt config (based on the `gruvbox-rainbow`
preset). Link it into place:

```sh
mkdir -p ~/.config
ln -sf "$PWD/starship/starship.toml" ~/.config/starship.toml
```

The next prompt picks it up; no restart needed.

### yazi theme

`yazi/theme.toml` shows folders in a light blue instead of the terminal's dark
ANSI blue. Link it into yazi's config folder:

```sh
mkdir -p ~/.config/yazi
ln -sf "$PWD/yazi/theme.toml" ~/.config/yazi/theme.toml
```

### Terminal.app (if not using iTerm2)

Settings → Profiles → (your profile) → Text → Font → Change… → `Hack Nerd Font`.

### Configure zsh

Add to `~/.zshrc`:

```zsh
# mise (tool version manager)
eval "$(mise activate zsh)"

# Autosuggestions
source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# Prompt
eval "$(starship init zsh)"

# zoxide: `z <part of path>` jumps to a folder, `zi` opens an interactive picker
eval "$(zoxide init zsh)"

# yazi: start with `y`; when you quit with `q`, the shell changes to the
# folder you were in (`Q` quits without changing folder)
function y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd < "$tmp"
  [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
  rm -f -- "$tmp"
}

# Aliases
alias ls='lsd'
alias l='lsd -l'
alias la='lsd -a'
alias lsa='lsd -a'
alias lla='lsd -la'
alias lt='lsd --tree'
alias cat='bat --paging=never'

# Syntax highlighting (must be sourced last)
source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
```

Then reload the shell with `exec zsh`.

## Windows (Windows Terminal)

Run everything in a **normal (non-admin)** PowerShell 7 window, and reopen the
terminal after each step so `PATH` updates. If something fails, see
[TROUBLESHOOTING.md](TROUBLESHOOTING.md#windows).

### 1. PowerShell 7 and script policy

```powershell
winget install Microsoft.PowerShell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

In Windows Terminal: **Settings → Startup → Default profile → PowerShell** (black
icon, not "Windows PowerShell").

### 2. Let winget extract zips with `tar`

Run `winget settings` and save:

```json
{
  "$schema": "https://aka.ms/winget-settings.schema.json",
  "installBehavior": { "archiveExtractionMethod": "tar" }
}
```

Without this, zip-based tools fail on some PCs
([details](TROUBLESHOOTING.md#zip-packages-fail-with-failed-to-extract-archive)).

### 3. Install the tools

```powershell
winget install Git.Git GitHub.cli OpenJS.NodeJS.LTS Gitleaks.Gitleaks Starship.Starship Tailscale.Tailscale Docker.DockerDesktop
winget install eza-community.eza lsd-rs.lsd sharkdp.bat junegunn.fzf jdx.mise ajeetdsouza.zoxide sxyazi.yazi sharkdp.fd BurntSushi.ripgrep.MSVC

[Environment]::SetEnvironmentVariable("YAZI_FILE_ONE", "C:\Program Files\Git\usr\bin\file.exe", "User")
```

Docker Desktop provides docker, buildx and compose (replaces colima). Git for
Windows includes git-lfs and the `file.exe` yazi needs.

In a new terminal:

```powershell
npm install -g agent-browser
irm https://claude.ai/install.ps1 | iex                # Claude Code
irm https://releases.herdr.dev/app/install.ps1 | iex   # herdr (x86_64 only)
```

Apply the Starship prompt and yazi theme (inside the cloned `config` folder):

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.config", "$env:APPDATA\yazi\config" | Out-Null
Copy-Item .\starship\starship.toml "$env:USERPROFILE\.config\starship.toml"
Copy-Item .\yazi\theme.toml "$env:APPDATA\yazi\config\theme.toml"
```

### 4. Nerd Font

Download `Hack.zip` from
<https://github.com/ryanoasis/nerd-fonts/releases/latest>, extract it, select the
`HackNerdFont-*.ttf` files, right-click → **Install**. Then in Windows Terminal:
**Settings → Profiles → Defaults → Appearance → Font face → `Hack Nerd Font`**.

### 5. PowerShell profile

```powershell
Install-Module PSFzf, Terminal-Icons -Scope CurrentUser
New-Item -Path $PROFILE -ItemType File -Force   # only if it doesn't exist yet
notepad $PROFILE
```

Add:

```powershell
# Autosuggestions from history; syntax highlighting is built into PSReadLine
Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

# fzf: Ctrl+T file search, Ctrl+R history search
Import-Module PSFzf
Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'

Import-Module Terminal-Icons
mise activate pwsh | Out-String | Invoke-Expression
Invoke-Expression (&starship init powershell)
Invoke-Expression (& { (zoxide init powershell | Out-String) })   # z, zi

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
Remove-Item Alias:ls, Alias:cat -Force -ErrorAction SilentlyContinue
function ls  { lsd @args }
function l   { lsd -l @args }
function la  { lsd -a @args }
function lsa { lsd -a @args }
function lla { lsd -la @args }
function lt  { lsd --tree @args }
function cat { bat --paging=never @args }
```

Reload with `. $PROFILE`. To check every tool, see
[Check everything](TROUBLESHOOTING.md#check-everything).

### Not available on Windows

| macOS tool | Windows alternative |
|---|---|
| colima | Docker Desktop |
| mole | none |
| zsh-autosuggestions / zsh-syntax-highlighting | PSReadLine (step 5), or zsh inside WSL |

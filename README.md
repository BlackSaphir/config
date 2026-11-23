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

> If iTerm2 is already installed outside Homebrew, `brew bundle` will report that the
> app already exists. Either skip it or let Homebrew take it over with
> `brew install --cask --force iterm2`.

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

The profile opens a hotkey window when you **double-tap Control**. For this,
iTerm2 needs the **Accessibility** permission:

1. System Settings → Privacy & Security → **Accessibility**: add iTerm and turn it on.
   If iTerm is already listed (for example after reinstalling it), remove it
   with **−** and add it again; the old entry may no longer be valid.
2. Quit iTerm2 completely (⌘Q) and start it again. Hotkeys are only registered
   at launch.

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
alias lla='lsd -la'
alias lt='lsd --tree'
alias cat='bat --paging=never'

# Syntax highlighting (must be sourced last)
source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
```

Then reload the shell with `exec zsh`.

## Windows (Windows Terminal)

Run the commands below in a regular (non-admin) PowerShell window unless noted.
Package IDs can change, so if one fails, look it up with `winget search <name>`.

### 1. Install PowerShell 7 and make it the default

```powershell
winget install Microsoft.PowerShell
```

In Windows Terminal: **Settings → Startup → Default profile → PowerShell** (the
one with the black icon, not "Windows PowerShell"). Do all of the following steps in PowerShell 7.

### 2. Install the tools

```powershell
winget install Git.Git            # includes git-lfs
winget install GitHub.cli
winget install sharkdp.bat
winget install eza-community.eza
winget install lsd-rs.lsd
winget install junegunn.fzf
winget install jdx.mise
winget install Tailscale.Tailscale
winget install Docker.DockerDesktop   # provides docker, buildx and compose (replaces colima)
winget install ajeetdsouza.zoxide
winget install sxyazi.yazi
winget install sharkdp.fd
winget install BurntSushi.ripgrep.MSVC
winget install Starship.Starship
```

yazi uses `file.exe` from Git for Windows to detect file types. Point it there
once:

```powershell
[Environment]::SetEnvironmentVariable("YAZI_FILE_ONE", "C:\Program Files\Git\usr\bin\file.exe", "User")
```

Tools that are not on winget:

```powershell
# Scoop (package manager), needed for gitleaks and the font
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
irm https://get.scoop.sh | iex
scoop install gitleaks

# agent-browser (requires Node.js: winget install OpenJS.NodeJS.LTS)
npm install -g agent-browser

# Claude Code
irm https://claude.ai/install.ps1 | iex

# herdr (x86_64 only; adds a Start menu entry)
irm https://releases.herdr.dev/app/install.ps1 | iex
```

Close and reopen the terminal afterwards so the new `PATH` entries take effect.

Apply the Starship prompt and yazi theme from this repo (run inside the cloned
`config` folder):

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.config" | Out-Null
Copy-Item .\starship\starship.toml "$env:USERPROFILE\.config\starship.toml"

New-Item -ItemType Directory -Force "$env:APPDATA\yazi\config" | Out-Null
Copy-Item .\yazi\theme.toml "$env:APPDATA\yazi\config\theme.toml"
```

### 3. Install a Nerd Font

```powershell
scoop bucket add nerd-fonts
scoop install Hack-NF
```

In Windows Terminal: **Settings → Profiles → Defaults → Appearance → Font face →
`Hack Nerd Font`**. Or set it in `settings.json`:

```json
"profiles": {
  "defaults": {
    "font": { "face": "Hack Nerd Font" }
  }
}
```

### 4. Configure the PowerShell profile

Install the optional modules:

```powershell
Install-Module PSFzf -Scope CurrentUser
Install-Module Terminal-Icons -Scope CurrentUser
```

Open the profile (`notepad $PROFILE`, creating it first with
`New-Item -Path $PROFILE -ItemType File -Force` if it doesn't exist) and add:

```powershell
# Autosuggestions from history (zsh-autosuggestions equivalent).
# Syntax highlighting is built into PSReadLine.
Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

# fzf: Ctrl+T file search, Ctrl+R history search
Import-Module PSFzf
Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'

# File icons
Import-Module Terminal-Icons

# mise
mise activate pwsh | Out-String | Invoke-Expression

# Prompt
Invoke-Expression (&starship init powershell)

# zoxide: `z <part of path>` jumps to a folder, `zi` opens an interactive picker
Invoke-Expression (& { (zoxide init powershell | Out-String) })

# yazi: start with `y`; quitting with `q` changes to the folder you were in
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
function lla { lsd -la @args }
function lt  { lsd --tree @args }
function cat { bat --paging=never @args }

```

Reload it with `. $PROFILE`.

### Not available on Windows

| macOS tool | Windows alternative |
|---|---|
| colima | Docker Desktop (step 2) |
| mole | none |
| zsh-autosuggestions / zsh-syntax-highlighting | PSReadLine (step 4), or zsh inside WSL |

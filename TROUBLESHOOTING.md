# Troubleshooting

Problems found while installing this setup, and how to fix them. For the normal
install steps, see the [README](README.md).

- [macOS](#macos)
  - [`brew bundle`: iTerm2 "already exists"](#brew-bundle-iterm2-already-exists)
  - [Double-tap Control doesn't open the iTerm2 hotkey window](#double-tap-control-doesnt-open-the-iterm2-hotkey-window)
- [Ubuntu](#ubuntu)
  - [`chsh`: "user … does not exist in /etc/passwd"](#chsh-user--does-not-exist-in-etcpasswd)
  - [Starship: "Unknown key" warnings](#starship-unknown-key-warnings)
  - [Claude Code doesn't install](#claude-code-doesnt-install)
  - [ld.so: "… from LD_PRELOAD cannot be preloaded"](#ldso--from-ld_preload-cannot-be-preloaded)
  - [gsettings: "No schemas installed"](#gsettings-no-schemas-installed)
  - [zsh start: "command not found: brew"](#zsh-start-command-not-found-brew)
  - [setopt: "Command 'setopt' not found"](#setopt-command-setopt-not-found)
- [Windows](#windows)
  - [Prerequisites](#prerequisites)
  - [zip packages fail with "Failed to extract archive"](#zip-packages-fail-with-failed-to-extract-archive)
  - [`agent-browser` is "not recognized" after `npm install -g`](#agent-browser-is-not-recognized-after-npm-install--g)
  - [Install scripts fail](#install-scripts-fail)
  - [Downloads fail with 0x80072EE7 ("server name could not be resolved")](#downloads-fail-with-0x80072ee7-server-name-could-not-be-resolved)
  - [Installing without Scoop](#installing-without-scoop)
  - [`Set-ExecutionPolicy`: "overridden by a policy defined at a more specific scope"](#set-executionpolicy-overridden-by-a-policy-defined-at-a-more-specific-scope)
  - [PSReadLine: "The predictive suggestion feature cannot be enabled…"](#psreadline-the-predictive-suggestion-feature-cannot-be-enabled)
  - [Check everything](#check-everything)

## macOS

### `brew bundle`: iTerm2 "already exists"

iTerm2 was installed outside Homebrew (for example from the website). Either skip
it, or let Homebrew take it over. Your settings in
`~/Library/Preferences/com.googlecode.iterm2.plist` are kept.

```sh
osascript -e 'quit app "iTerm2"'   # quit iTerm2 first
brew install --cask --force iterm2
```

If this fails with `sudo: a password is required` and leaves an empty
`/Applications/iTerm.app` behind, run it in a terminal where you can type your
password:

```sh
sudo rm -rf /Applications/iTerm.app && brew install --cask iterm2
```

Never run `brew uninstall --zap iterm2`: it deletes your iTerm2 settings.

### Double-tap Control doesn't open the iTerm2 hotkey window

To detect a double-tap, iTerm2 has to read key presses system-wide, which needs
the **Accessibility** permission. A normal hotkey like ⌃A works without it, so
this is easy to miss.

1. System Settings → Privacy & Security → **Accessibility**: add iTerm and turn it on.
2. If iTerm is already listed (for example after reinstalling it), remove it with
   **−** and add it again. The old entry may no longer be valid even though the
   switch looks on.
3. Do the same under **Input Monitoring** if iTerm is listed there.
4. Quit iTerm2 completely (⌘Q) and start it again. Hotkeys are only registered at
   launch.

Also check that the **config** profile is the default and no other profile has a
hotkey window: Settings → Profiles → (profile) → Keys → Configure Hotkey Window.

## Ubuntu

### `chsh`: "user … does not exist in /etc/passwd"

**Cause:** you sign in with a domain account (LDAP or Active Directory, user
names like `DOMAIN\user`). Those accounts aren't in `/etc/passwd`, so `chsh`
can't change their login shell.

**Fix:** `install.sh` detects this and adds a block to the top of `~/.bashrc`
that switches interactive bash sessions to zsh. To get a plain bash anyway, run
`CONFIG_NO_ZSH=1 bash`.

### Starship: "Unknown key" warnings

For example `Error in 'StarshipRoot' at 'jj_bookmark': Unknown key`.

**Cause:** an older Starship runs instead of the one from Homebrew. Often mise
installed its own copy, and mise's tools come first on `PATH`. Check with:

```sh
type -a starship; starship --version
```

**Fix:** let Homebrew manage it, then open a new terminal:

```sh
mise unuse -g starship
```

The check at the end of `install.sh` warns about every tool that mise also
manages.

### Claude Code doesn't install

Some managed machines block it. `install.sh` only warns about it and sets up
everything else. Skip it entirely with:

```sh
curl -fsSL https://raw.githubusercontent.com/BlackSaphir/config/main/install.sh | CONFIG_CLAUDE=0 bash
```

### ld.so: "… from LD_PRELOAD cannot be preloaded"

```
ERROR: ld.so: object '/usr/$LIB/<library>.so' from LD_PRELOAD cannot be preloaded (cannot open shared object file): ignored.
```

**Problem:** appears for every Homebrew program. `LD_PRELOAD` contains a path
with `$LIB`. Homebrew sometimes brings its own glibc
(`/home/linuxbrew/.linuxbrew/opt/glibc`), whose loader resolves `$LIB` to a
different folder than Ubuntu's and doesn't find the file.

**Fix:** the `~/.zshrc` block from `install.sh` removes the `LD_PRELOAD` entries
that contain `$LIB`, before anything from Homebrew runs.

### gsettings: "No schemas installed"

**Cause:** Homebrew installed its own `gsettings` (as a dependency), which is
first on `PATH` and only knows Homebrew's schemas.

**Fix:** use the system one: `/usr/bin/gsettings`. `install.sh` does this.

### zsh start: "command not found: brew"

Often followed by `no such file or directory: /share/zsh-autosuggestions/...`.

**Cause:** `~/.zshrc` still has the macOS lines copied from the README above the
block that `install.sh` wrote. They run before Homebrew is loaded.

**Fix:** remove them; the block already does the same. `install.sh` lists them
with their line numbers.

### setopt: "Command 'setopt' not found"

The zsh lines from the README were run in bash, or put in `~/.bashrc`. They
belong in `~/.zshrc`.

## Windows

Found on Windows 10 Pro 22H2 (build 19045) with winget 1.30.

### Prerequisites

| Prerequisite | Needed for | Install |
|---|---|---|
| PowerShell 7 | everything, the profile | `winget install Microsoft.PowerShell` |
| `RemoteSigned` execution policy | Scoop, herdr, Claude Code, the profile | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| winget extracting zips with `tar` | every tool winget ships as a `.zip` | [see below](#zip-packages-fail-with-failed-to-extract-archive) |
| Git for Windows | `git`, and the `file.exe` that yazi uses | `winget install Git.Git` |
| Node.js LTS (provides `npm`) | agent-browser | `winget install OpenJS.NodeJS.LTS` |
| Visual C++ Redistributable 2015+ (x64) | fd, ripgrep and other Rust tools | installed by winget as a dependency; otherwise `winget install Microsoft.VCRedist.2015+.x64` |
| An x86_64 (Intel/AMD) PC | herdr (no ARM build) | — |

Close and reopen the terminal after installing anything, so the new `PATH` loads.

### zip packages fail with "Failed to extract archive"

**Affected:** eza, lsd, bat, fzf, mise, zoxide, yazi, fd, ripgrep: every package
winget ships as a `.zip`. Packages with an MSI/EXE installer (Git, Starship,
Tailscale, Docker Desktop) install fine.

**Symptom:** the console says *"Extracting archive… Failed to extract archive"*
(German: *"Archiv wird extrahiert… Fehler beim Extrahieren der Inhalte des
Archivs"*). The winget log in
`%LOCALAPPDATA%\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir`
shows:

```
[FAIL] ...\AppInstallerCommonCore\Archive.cpp(30) ... 80004005
Failed to extract archive with code -2147467259
Terminating context: 0x8a15005c
```

**Cause:** by default winget unpacks zips with Windows' built-in zip support
("Compressed Folders", `zipfldr.dll`), and that is broken. This often happens after
installing 7-Zip or using a "remove Windows zip support" tweak. Check it with:

```powershell
(New-Object -ComObject Shell.Application).NameSpace("C:\path\to\any.zip").Items().Count
```

If this throws `E_FAIL`, winget's default extraction fails too.

**Fix:** tell winget to use `tar`. Run `winget settings` and save:

```json
{
  "$schema": "https://aka.ms/winget-settings.schema.json",
  "installBehavior": {
    "archiveExtractionMethod": "tar"
  }
}
```

Then install the packages again:

```powershell
winget install eza-community.eza lsd-rs.lsd sharkdp.bat junegunn.fzf jdx.mise ajeetdsouza.zoxide sxyazi.yazi sharkdp.fd BurntSushi.ripgrep.MSVC
```

A missing registry key, `HKCR\CompressedFolder\CLSID`, is often part of the
damage. Restoring it does **not** fix winget on its own, but it's a standard
Windows setting, so it's worth putting back:

```powershell
New-Item -Path 'HKCU:\Software\Classes\CompressedFolder\CLSID' -Force |
  Set-ItemProperty -Name '(default)' -Value '{E88DCCE0-B7B3-11d1-A9F0-00AA0060FA31}'
```

### `agent-browser` is "not recognized" after `npm install -g`

**Cause:** npm puts global packages in a folder that isn't on `PATH`, for example
a custom prefix like `C:\npm-global`. Check yours with:

```powershell
npm prefix -g
```

**Fix:** add that folder to your user `PATH`, then reopen the terminal:

```powershell
$g = npm prefix -g
$u = [Environment]::GetEnvironmentVariable('Path','User')
if (($u -split ';') -notcontains $g) {
  [Environment]::SetEnvironmentVariable('Path', $u.TrimEnd(';') + ";$g", 'User')
}
```

npm may also warn that it skipped agent-browser's `postinstall` script
(`npm warn install-scripts …`). That's harmless: the script only links the native
binary, and agent-browser does the same on its first run. If Chrome isn't
installed, run `agent-browser install` once.

### Install scripts fail

Scoop, herdr and Claude Code install with `irm <url> | iex`, which downloads a
script and runs it immediately. They need:

- PowerShell 7
- the `RemoteSigned` execution policy (see [Prerequisites](#prerequisites))
- a **normal (non-admin)** PowerShell window. Scoop refuses to install from an
  admin shell.
- herdr only: an x86_64 PC

### Downloads fail with 0x80072EE7 ("server name could not be resolved")

**Cause:** installing Tailscale can briefly cut the internet connection. Every
download after that point fails.

**Fix:** `install.ps1` installs Tailscale last and retries each download once
after the network is back. If something still fails, run the script again; it
only installs what's missing.

### Installing without Scoop

Scoop is optional. Both things it was used for work without it:

- gitleaks: `winget install Gitleaks.Gitleaks`
- Hack Nerd Font: download `Hack.zip` from
  <https://github.com/ryanoasis/nerd-fonts/releases/latest>, extract it, select the
  `HackNerdFont-*.ttf` files, then right-click → **Install**.

### `Set-ExecutionPolicy`: "overridden by a policy defined at a more specific scope"

Harmless if it happens inside a tool or script that runs PowerShell with its own
`-ExecutionPolicy Bypass`. The `CurrentUser` setting is still saved. Check it in a
normal terminal:

```powershell
Get-ExecutionPolicy -List
```

### PSReadLine: "The predictive suggestion feature cannot be enabled…"

Appears only when the profile is loaded with redirected output, for example from a
script. In a real Windows Terminal window, `-PredictionSource History` works.

### Check everything

In a new terminal:

```powershell
eza --version; lsd --version; bat --version; fzf --version; mise --version
zoxide --version; yazi --version; fd --version; rg --version; starship --version
gitleaks version; agent-browser --version; gh --version; git --version
$env:YAZI_FILE_ONE          # should be C:\Program Files\Git\usr\bin\file.exe
Get-Module -ListAvailable PSFzf, Terminal-Icons
```

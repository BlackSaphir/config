#!/usr/bin/env bash
# Sets up the terminal environment from github.com/BlackSaphir/config on Ubuntu.
#
# Run as your normal user (not root):
#
#     curl -fsSL https://raw.githubusercontent.com/BlackSaphir/config/main/install.sh | bash
#
# or, inside a clone of the repo:
#
#     ./install.sh
#
# Safe to run again: steps that are already done are skipped. Every file it
# changes is backed up first (*.bak-<timestamp>). See TROUBLESHOOTING.md if
# something fails.
#
# Environment variables to change what it does:
#     CONFIG_DOCKER=1   install Docker Engine without asking
#     CONFIG_DOCKER=0   skip Docker Engine without asking
#     CONFIG_DIR=...    where to clone the repo (default: ~/config)

# Everything is inside main(), so a partly downloaded script never runs.
main() {
    set -uo pipefail

    local repo_url='https://github.com/BlackSaphir/config.git'
    local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
    local failures=() notes=()

    # ------------------------------------------------------------ helpers

    step() { printf '\n\033[36m==> %s\033[0m\n' "$1"; }
    ok()   { printf '    \033[32mok\033[0m    %s\n' "$1"; }
    skip() { printf '    \033[90mskip  %s\033[0m\n' "$1"; }
    warn() { printf '    \033[33mwarn\033[0m  %s\n' "$1"; }
    fail() { printf '    \033[31mFAIL\033[0m  %s\n' "$1"; failures+=("$1"); }
    have() { command -v "$1" >/dev/null 2>&1; }

    backup() {
        if [ -e "$1" ] || [ -L "$1" ]; then
            mv "$1" "$1.bak-$stamp"
            echo "$1.bak-$stamp"
        fi
    }

    # Waits up to 60 seconds until DNS works again.
    wait_network() {
        local i
        for i in $(seq 20); do
            getent hosts github.com >/dev/null 2>&1 && return 0
            sleep 3
        done
        return 1
    }

    # Runs a command, and once more after waiting for the network if it fails.
    retry() {
        "$@" && return 0
        warn "failed; waiting for the network, then trying again"
        wait_network
        "$@"
    }

    # Downloads a vendor install script and runs it with the given command.
    run_remote() {
        local url="$1"; shift
        local tmp rc
        tmp="$(mktemp)"
        curl -fsSL "$url" -o "$tmp" && "$@" "$tmp"
        rc=$?
        rm -f "$tmp"
        return $rc
    }

    # Asks a yes/no question. Reads from the terminal, because stdin is the
    # script itself when it runs via `curl | bash`.
    ask() {
        local answer=''
        if [ -r /dev/tty ]; then read -r -p "    $1 [y/N] " answer < /dev/tty; fi
        [[ "$answer" =~ ^[yYjJ] ]]
    }

    # Symlinks a repo file into place; an existing file is backed up first.
    link() {
        local src="$1" dest="$2" bak
        if [ "$(readlink "$dest" 2>/dev/null)" = "$src" ]; then skip "$dest (already linked)"; return; fi
        mkdir -p "$(dirname "$dest")"
        bak="$(backup "$dest")"
        if ln -s "$src" "$dest"; then
            if [ -n "$bak" ]; then ok "$dest -> $src (backup: $bak)"; else ok "$dest -> $src"; fi
        else
            fail "Could not link $dest"
        fi
    }

    load_brew() {
        local b
        for b in /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do
            if [ -x "$b" ]; then eval "$("$b" shellenv)"; return 0; fi
        done
        return 1
    }

    # ------------------------------------------------------------ checks

    printf '\n\033[36mBlackSaphir/config - Ubuntu setup\033[0m\n'

    if [ "$(uname -s)" != Linux ]; then
        echo 'This script is for Ubuntu. On macOS, follow the README.' >&2; return 1
    fi
    if [ "$(id -u)" -eq 0 ]; then
        echo 'Please run this script as your normal user, not as root or with sudo.' >&2; return 1
    fi
    if ! have apt-get; then
        echo 'apt-get was not found. This script needs Ubuntu or another Debian-based system.' >&2; return 1
    fi
    if ! grep -qiE '^(ID|ID_LIKE)=.*ubuntu' /etc/os-release 2>/dev/null; then
        warn 'This is not Ubuntu. Continuing, but only Ubuntu is tested.'
    fi

    echo 'Some steps need sudo; enter your password once:'
    sudo -v || { echo 'sudo is required.' >&2; return 1; }
    # Keep sudo alive while the script runs (brew bundle can take a while).
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done ) 2>/dev/null &
    SUDO_KEEPER=$!
    trap 'kill "$SUDO_KEEPER" 2>/dev/null' EXIT

    local docker="${CONFIG_DOCKER:-}"
    if [ "$docker" != 0 ] && [ "$docker" != 1 ]; then
        if have docker; then docker=0
        elif ask 'Install Docker Engine (docker, buildx, compose)?'; then docker=1
        else docker=0; fi
    fi

    # ------------------------------------------------------------ 1. apt packages

    step 'apt packages (build tools for Homebrew, zsh, fonts)'
    local apt_pkgs=(build-essential procps curl file git zsh unzip fontconfig) missing=() p
    for p in "${apt_pkgs[@]}"; do
        dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    if [ ${#missing[@]} -eq 0 ]; then
        skip 'all installed'
    elif retry sudo apt-get update -qq && retry sudo apt-get install -y -qq "${missing[@]}"; then
        ok "${missing[*]}"
    else
        fail "apt install ${missing[*]}"
    fi

    # ------------------------------------------------------------ 2. repo

    step 'config repo'
    local repo=''
    local script_dir=''
    if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
    if [ -n "$script_dir" ] && [ -f "$script_dir/starship/starship.toml" ]; then
        repo="$script_dir"
        skip "using $repo"
    else
        repo="${CONFIG_DIR:-$HOME/config}"
        if [ -d "$repo/.git" ]; then
            if [[ "$(git -C "$repo" remote get-url origin 2>/dev/null)" == *BlackSaphir/config* ]]; then
                if retry git -C "$repo" pull --ff-only -q; then ok "updated $repo"; else warn "could not update $repo; using it as it is"; fi
            else
                fail "$repo is a different git repo; set CONFIG_DIR to another folder"; repo=''
            fi
        elif [ -e "$repo" ]; then
            fail "$repo already exists and is not the config repo; set CONFIG_DIR to another folder"; repo=''
        elif retry git clone -q "$repo_url" "$repo"; then
            ok "cloned to $repo"
        else
            fail "git clone $repo_url"; repo=''
        fi
    fi
    if [ -z "$repo" ]; then
        printf '\n\033[31mStopped: the config repo is needed for the next steps.\033[0m\n'
        return 1
    fi

    # ------------------------------------------------------------ 3. Homebrew

    step 'Homebrew'
    if load_brew; then
        skip "already installed ($(brew --prefix))"
    elif retry run_remote https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh env NONINTERACTIVE=1 bash && load_brew; then
        ok "installed ($(brew --prefix))"
    else
        fail 'Homebrew install'
    fi

    # ------------------------------------------------------------ 4. brew bundle

    step 'Tools from the Brewfile (brew bundle)'
    if ! have brew; then
        fail 'skipped: Homebrew is missing'
    elif brew bundle check --file="$repo/Brewfile" >/dev/null 2>&1; then
        skip 'everything installed'
    elif retry brew bundle --file="$repo/Brewfile"; then
        ok 'brew bundle'
    else
        fail 'brew bundle (run it again to see which formula failed)'
    fi

    # ------------------------------------------------------------ 5. Claude Code

    step 'Claude Code'
    if have claude || [ -x "$HOME/.local/bin/claude" ]; then
        skip 'already installed'
    elif retry run_remote https://claude.ai/install.sh bash; then
        ok 'Claude Code'
    else
        fail 'Claude Code install'
    fi

    # ------------------------------------------------------------ 6. Docker Engine

    step 'Docker Engine'
    if have docker; then
        skip 'already installed'
    elif [ "$docker" = 1 ]; then
        if retry run_remote https://get.docker.com sudo sh; then
            sudo usermod -aG docker "$USER" && ok "Docker Engine; added $USER to the docker group"
            notes+=('Docker: log out and back in so you can run docker without sudo.')
        else
            fail 'Docker Engine install'
        fi
    else
        skip 'not selected'
    fi

    # ------------------------------------------------------------ 7. Nerd Font

    step 'Hack Nerd Font'
    local font_dir="$HOME/.local/share/fonts/HackNerdFont"
    if [[ "$(fc-list : family 2>/dev/null)" == *"Hack Nerd Font"* ]]; then
        skip 'already installed'
    else
        local tmp; tmp="$(mktemp -d)"
        if retry curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip -o "$tmp/Hack.zip" \
            && mkdir -p "$font_dir" \
            && unzip -oq "$tmp/Hack.zip" 'HackNerdFont-*.ttf' -d "$font_dir" \
            && fc-cache -f "$font_dir" >/dev/null; then
            ok "installed to $font_dir"
        else
            fail 'Hack Nerd Font'
        fi
        rm -rf "$tmp"
    fi

    # ------------------------------------------------------------ 8. terminal font

    step 'Terminal font (Ptyxis / GNOME Terminal)'
    local font='Hack Nerd Font 12' configured=0
    if ! have gsettings || ! gsettings list-schemas >/dev/null 2>&1; then
        warn 'gsettings is not available (no desktop session, e.g. over SSH). Run the script again in the desktop.'
        notes+=('Terminal font: run the script again inside the Ubuntu desktop to set it.')
    else
        local schemas; schemas="$(gsettings list-schemas 2>/dev/null)"
        if grep -qx 'org.gnome.Ptyxis' <<< "$schemas"; then
            configured=1
            if [ "$(gsettings get org.gnome.Ptyxis font-name)" = "'$font'" ] && [ "$(gsettings get org.gnome.Ptyxis use-system-font)" = false ]; then
                skip 'Ptyxis already uses Hack Nerd Font'
            else
                gsettings set org.gnome.Ptyxis use-system-font false \
                    && gsettings set org.gnome.Ptyxis font-name "$font" \
                    && ok "Ptyxis font = $font" || fail 'Setting the Ptyxis font'
            fi
        fi
        if grep -qx 'org.gnome.Terminal.ProfilesList' <<< "$schemas"; then
            configured=1
            local uuid path
            uuid="$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'")"
            path="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$uuid/"
            if [ "$(gsettings get "$path" font)" = "'$font'" ] && [ "$(gsettings get "$path" use-system-font)" = false ]; then
                skip 'GNOME Terminal already uses Hack Nerd Font'
            else
                gsettings set "$path" use-system-font false \
                    && gsettings set "$path" font "$font" \
                    && ok "GNOME Terminal font = $font" || fail 'Setting the GNOME Terminal font'
            fi
        fi
        [ "$configured" = 1 ] || warn 'Neither Ptyxis nor GNOME Terminal found; set the font to "Hack Nerd Font" in your terminal by hand.'
    fi

    # ------------------------------------------------------------ 9. config files

    step 'Config files (Starship, yazi)'
    link "$repo/starship/starship.toml" "$HOME/.config/starship.toml"
    link "$repo/yazi/theme.toml" "$HOME/.config/yazi/theme.toml"

    # ------------------------------------------------------------ 10. zsh

    step 'zsh'
    local zshrc="$HOME/.zshrc" block new
    IFS= read -r -d '' block <<'EOF'
# >>> BlackSaphir/config >>>
# Managed by install.sh from github.com/BlackSaphir/config.
# Running the script again replaces everything between these two markers.

# Homebrew, and ~/.local/bin (Claude Code)
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x "$HOME/.linuxbrew/bin/brew" ]; then
  eval "$("$HOME/.linuxbrew/bin/brew" shellenv)"
fi
export PATH="$HOME/.local/bin:$PATH"

# History and completion (macOS sets these in /etc/zshrc; Ubuntu doesn't)
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt share_history hist_ignore_dups
bindkey -e
autoload -Uz compinit && compinit

# mise (tool version manager)
command -v mise >/dev/null && eval "$(mise activate zsh)"

# Autosuggestions
[ -f "${HOMEBREW_PREFIX:-}/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ] &&
  source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"

# Prompt
command -v starship >/dev/null && eval "$(starship init zsh)"

# zoxide: `z <part of path>` jumps to a folder, `zi` opens an interactive picker
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# yazi: start with `y`; when you quit with `q`, the shell changes to the
# folder you were in (`Q` quits without changing folder)
function y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd < "$tmp"
  [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
  rm -f -- "$tmp"
}

# Aliases (same as macOS)
alias ls='lsd'
alias l='lsd -l'
alias la='lsd -a'
alias lsa='lsd -a'
alias lla='lsd -la'
alias lt='lsd --tree'
alias cat='bat --paging=never'

# Syntax highlighting (must be sourced last)
[ -f "${HOMEBREW_PREFIX:-}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ] &&
  source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
# <<< BlackSaphir/config <<<
EOF
    block="${block%$'\n'}"
    new="$(mktemp)"
    if [ -f "$zshrc" ]; then
        # Keep everything outside the markers, then append the new block.
        awk '/^# >>> BlackSaphir\/config >>>$/{skip=1} !skip{print} /^# <<< BlackSaphir\/config <<<$/{skip=0}' "$zshrc" \
            | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' > "$new"
        [ -s "$new" ] && echo >> "$new"
    fi
    printf '%s\n' "$block" >> "$new"
    if [ -f "$zshrc" ] && cmp -s "$new" "$zshrc"; then
        skip "$zshrc (up to date)"
        rm -f "$new"
    else
        local bak=''
        if [ -f "$zshrc" ]; then bak="$zshrc.bak-$stamp"; cp "$zshrc" "$bak"; fi
        mv "$new" "$zshrc"
        if [ -n "$bak" ]; then ok "$zshrc (backup: $bak)"; else ok "$zshrc"; fi
    fi

    local zsh_path; zsh_path="$(command -v zsh || true)"
    if [ -z "$zsh_path" ]; then
        fail 'zsh not found'
    elif [ "$(getent passwd "$USER" | cut -d: -f7)" = "$zsh_path" ]; then
        skip 'zsh is already the login shell'
    elif sudo chsh -s "$zsh_path" "$USER"; then
        ok "login shell = $zsh_path"
        notes+=('zsh: log out and back in to make it your default shell (or run `exec zsh` now).')
    else
        fail 'Could not make zsh the login shell (chsh)'
    fi

    # ------------------------------------------------------------ 11. Tailscale (last)

    step 'Tailscale (installed last because it can briefly cut the internet connection)'
    if have tailscale; then
        skip 'already installed'
    elif retry run_remote https://tailscale.com/install.sh sh; then
        ok 'Tailscale'
        notes+=('Tailscale: run `sudo tailscale up` to sign in.')
        wait_network || warn 'The internet connection has not come back yet.'
    else
        fail 'Tailscale install'
    fi

    # ------------------------------------------------------------ 12. check

    step 'Check'
    load_brew >/dev/null 2>&1
    export PATH="$HOME/.local/bin:$PATH"
    local tools=(zsh git gh git-lfs gitleaks starship eza lsd bat fd rg mise zoxide yazi agent-browser herdr claude tailscale) t
    [ "$docker" = 1 ] && tools+=(docker)
    for t in "${tools[@]}"; do
        if have "$t"; then ok "$t"; else fail "$t not found on PATH"; fi
    done

    # ------------------------------------------------------------ summary

    echo
    if [ ${#failures[@]} -eq 0 ]; then
        printf '\033[32mDone. Log out and back in (or run `exec zsh`) to start using the new shell.\033[0m\n'
    else
        printf '\033[33mDone with %d problem(s):\033[0m\n' "${#failures[@]}"
        printf '\033[33m  - %s\033[0m\n' "${failures[@]}"
        printf '\033[33mSee TROUBLESHOOTING.md: https://github.com/BlackSaphir/config/blob/main/TROUBLESHOOTING.md\033[0m\n'
        echo 'You can run this script again after fixing them; finished steps are skipped.'
    fi
    local n
    for n in "${notes[@]+"${notes[@]}"}"; do printf '\033[36mNote: %s\033[0m\n' "$n"; done
}

main "$@"

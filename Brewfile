# Install with: brew bundle --file=Brewfile
# Works on macOS and on Linux (Homebrew on Linux, used by install.sh).

# Formulae (macOS and Linux)
brew "agent-browser"
brew "awscli"
brew "bat"
brew "eza"
brew "fd"
brew "gh"
brew "git"
brew "git-lfs"
brew "gitleaks"
brew "herdr"
brew "htop"
brew "lazygit"
brew "lsd"
brew "mise"
brew "ripgrep"
brew "starship"
brew "yazi"
brew "zoxide"
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"

# macOS only. On Linux, install.sh installs Docker Engine, Tailscale and
# Claude Code with their official installers, Bitwarden with snap, and the
# font by hand.
if OS.mac?
  brew "colima"
  brew "docker"
  brew "docker-buildx"
  brew "docker-compose"
  brew "mole"
  brew "tailscale"

  cask "bitwarden"
  cask "claude-code"
  cask "font-hack-nerd-font"
  cask "iterm2"
end

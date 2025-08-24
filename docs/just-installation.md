# Installing Just Command Runner

[Just](https://github.com/casey/just) is a handy command runner used by PyPgFlow for development automation.

## Installation

### macOS

```bash
# Using Homebrew
brew install just

# Using MacPorts  
sudo port install just
```

### Linux

```bash
# Using cargo (Rust package manager)
cargo install just

# On Ubuntu/Debian
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
cargo install just

# Using snap
sudo snap install --edge just

# Using pre-built binaries
wget -qO - 'https://proget.makedeb.org/debian-feeds/prebuilt-mpr/public-key.gpg' | gpg --dearmor | sudo tee /usr/share/keyrings/prebuilt-mpr-archive-keyring.gpg 1> /dev/null
echo "deb [arch=all,amd64,arm64,armhf signed-by=/usr/share/keyrings/prebuilt-mpr-archive-keyring.gpg] https://proget.makedeb.org prebuilt-mpr main" | sudo tee /etc/apt/sources.list.d/prebuilt-mpr.list
sudo apt update
sudo apt install just
```

### Windows

```powershell
# Using Scoop
scoop install just

# Using Chocolatey
choco install just

# Using cargo
cargo install just
```

### Using GitHub Releases

Download pre-built binaries from the [releases page](https://github.com/casey/just/releases).

## Verification

After installation, verify just is working:

```bash
just --version
```

## Usage in PyPgFlow

Once installed, you can use just commands in the PyPgFlow project:

```bash
# Show all available commands
just

# Start development environment
just dev

# Quick setup
just setup

# Run tests
just test
```

## Alternative: Using Make

If you prefer not to install Just, you can create a simple Makefile as an alternative:

```makefile
dev:
	just dev

test:
	just test

clean:
	just clean
```

This allows you to use `make dev` instead of `just dev`.
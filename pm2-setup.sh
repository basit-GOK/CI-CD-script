#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# pm2-setup.sh
# Clones a GitHub repo, sets up environment, installs, builds, and starts
# the app with PM2
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ─────────────────────────────────────────────
# Colours
# ─────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}  ➜${RESET}  $*"; }
success() { echo -e "${GREEN}${BOLD}  ✔${RESET}  $*"; }
warn()    { echo -e "${YELLOW}${BOLD}  ⚠${RESET}  $*"; }
err()     { echo -e "${RED}${BOLD}  ✖  ERROR:${RESET} $*" >&2; exit 1; }
divider() { echo -e "${CYAN}──────────────────────────────────────────────────${RESET}"; }

# ─────────────────────────────────────────────
# Preflight checks
# ─────────────────────────────────────────────
divider
echo -e "${BOLD}  PM2 App Setup${RESET}"
divider

command -v git  &>/dev/null || err "'git' is not installed. Run: sudo apt install git"
command -v pm2  &>/dev/null || err "'pm2' is not installed. Run: npm install -g pm2"
command -v node &>/dev/null || err "'node' is not installed. Run: sudo apt install nodejs"

# ─────────────────────────────────────────────
# Collect inputs
# ─────────────────────────────────────────────
echo ""
info "Let's collect a few details. Press Enter to accept defaults where shown."
echo ""

# GitHub repo URL
read -rp "  GitHub repo URL (e.g. https://github.com/user/repo): " GITHUB_REPO
[[ -z "$GITHUB_REPO" ]] && err "GitHub repo URL cannot be empty."

# GitHub username
read -rp "  GitHub username: " GITHUB_USER
[[ -z "$GITHUB_USER" ]] && err "GitHub username cannot be empty."

# GitHub password / token (hidden input)
read -rsp "  GitHub password or token (input hidden): " GITHUB_PASS
echo ""
[[ -z "$GITHUB_PASS" ]] && err "GitHub password/token cannot be empty."

# .env file contents
echo ""
info "Paste your .env file contents below (press Ctrl+D when done):"
echo -e "  Example: KEY1=value1"
echo -e "           KEY2=value2"
echo "  -------------------------------------"
ENV_CONTENT=$(cat)
echo ""

# Package manager
echo ""
read -rp "  Package manager (npm / yarn / pnpm) [npm]: " PKG_INPUT
PKG="${PKG_INPUT:-npm}"

# Derive default commands based on package manager
case "$PKG" in
    yarn)
        DEFAULT_INSTALL="yarn"
        DEFAULT_BUILD="yarn build"
        DEFAULT_START="yarn start"
        ;;
    pnpm)
        DEFAULT_INSTALL="pnpm install"
        DEFAULT_BUILD="pnpm run build"
        DEFAULT_START="pnpm run start"
        ;;
    *)
        DEFAULT_INSTALL="npm install"
        DEFAULT_BUILD="npm run build"
        DEFAULT_START="npm run start"
        ;;
esac

# Install command
read -rp "  Install command [${DEFAULT_INSTALL}]: " INSTALL_INPUT
INSTALL_CMD="${INSTALL_INPUT:-$DEFAULT_INSTALL}"

# Build command
read -rp "  Build command [${DEFAULT_BUILD}]: " BUILD_INPUT
BUILD_CMD="${BUILD_INPUT:-$DEFAULT_BUILD}"

# Start command
echo ""
echo -e "  ${CYAN}Start command options:${RESET}"
echo -e "  1) ${DEFAULT_START}"
echo -e "  2) serve -s build -l PORT  (for static React/Vue builds)"
echo -e "  3) Custom command"
echo ""
read -rp "  Start command [${DEFAULT_START}]: " START_INPUT
START_CMD="${START_INPUT:-$DEFAULT_START}"

# If using serve, check it is installed
if [[ "$START_CMD" == serve* ]]; then
    if ! command -v serve &>/dev/null; then
        warn "'serve' is not installed. Installing globally..."
        npm install -g serve
        success "serve installed"
    fi
fi

# Auto-detect repo name from URL
REPO_NAME=$(basename "${GITHUB_REPO%/}" .git)
info "Detected repo name: ${BOLD}${REPO_NAME}${RESET}"

# PM2 process name
read -rp "  PM2 process name [${REPO_NAME}]: " PM2_INPUT
PM2_NAME="${PM2_INPUT:-$REPO_NAME}"

# App directory — auto-derived from repo name, no need to ask
APP_DIR="$(pwd)/${REPO_NAME}"
info "App will be cloned into: ${BOLD}${APP_DIR}${RESET}"

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
echo ""
divider
echo -e "${BOLD}  Configuration summary${RESET}"
divider
echo -e "  Repo URL     : ${BOLD}${GITHUB_REPO}${RESET}"
echo -e "  GitHub user  : ${BOLD}${GITHUB_USER}${RESET}"
echo -e "  Clone dir    : ${BOLD}${APP_DIR}${RESET}"
echo -e "  Package mgr  : ${BOLD}${PKG}${RESET}"
echo -e "  Install cmd  : ${BOLD}${INSTALL_CMD}${RESET}"
echo -e "  Build cmd    : ${BOLD}${BUILD_CMD}${RESET}"
echo -e "  Start cmd    : ${BOLD}${START_CMD}${RESET}"
echo -e "  PM2 name     : ${BOLD}${PM2_NAME}${RESET}"
echo -e "  .env content : ${BOLD}$(echo "$ENV_CONTENT" | wc -l) line(s) provided${RESET}"
divider
echo ""

read -rp "  Proceed? [y/N] " CONFIRM
[[ "${CONFIRM,,}" != "y" ]] && err "Aborted by user."

# ─────────────────────────────────────────────
# Build authenticated clone URL
# ─────────────────────────────────────────────
# Inject credentials into the URL
# https://github.com/user/repo → https://user:token@github.com/user/repo
PROTO="https://"
REPO_PATH="${GITHUB_REPO#https://}"
AUTH_URL="${PROTO}${GITHUB_USER}:${GITHUB_PASS}@${REPO_PATH}"

# ─────────────────────────────────────────────
# Clone the repository
# ─────────────────────────────────────────────
echo ""
info "Cloning repository..."

if [[ -d "$APP_DIR" ]]; then
    warn "Directory '$APP_DIR' already exists."
    read -rp "  Delete and re-clone? [y/N] " RECLONE
    if [[ "${RECLONE,,}" == "y" ]]; then
        rm -rf "$APP_DIR"
        git clone "$AUTH_URL" "$APP_DIR" || err "Git clone failed. Check your credentials and repo URL."
    else
        info "Skipping clone — using existing directory."
    fi
else
    git clone "$AUTH_URL" "$APP_DIR" || err "Git clone failed. Check your credentials and repo URL."
fi

success "Repository cloned to $APP_DIR"

# ─────────────────────────────────────────────
# Navigate into app directory
# ─────────────────────────────────────────────
cd "$APP_DIR" || err "Could not enter directory '$APP_DIR'."

# ─────────────────────────────────────────────
# Write .env file
# ─────────────────────────────────────────────
if [[ -n "$ENV_CONTENT" ]]; then
    info "Writing .env file..."
    echo "$ENV_CONTENT" > .env
    success ".env file written ($(echo "$ENV_CONTENT" | wc -l) lines)"
else
    warn "No .env content provided — skipping .env creation."
fi

# ─────────────────────────────────────────────
# Install dependencies
# ─────────────────────────────────────────────
echo ""
info "Installing dependencies with: ${BOLD}${INSTALL_CMD}${RESET}"
$INSTALL_CMD || err "Dependency installation failed."
success "Dependencies installed"

# ─────────────────────────────────────────────
# Build the project
# ─────────────────────────────────────────────
echo ""
info "Building project with: ${BOLD}${BUILD_CMD}${RESET}"
$BUILD_CMD || err "Build failed."
success "Build complete"

# ─────────────────────────────────────────────
# Start with PM2
# ─────────────────────────────────────────────
echo ""
info "Starting app with PM2..."

# Stop existing process if running
if pm2 list | grep -q "$PM2_NAME"; then
    warn "PM2 process '$PM2_NAME' already exists — stopping it first..."
    pm2 delete "$PM2_NAME" || true
fi

# Start the app
pm2 start $START_CMD --name "$PM2_NAME" || err "PM2 failed to start the application."
pm2 save
success "App started under PM2 as '${PM2_NAME}'"

# ─────────────────────────────────────────────
# Setup PM2 startup on reboot
# ─────────────────────────────────────────────
echo ""
info "Configuring PM2 to restart on system reboot..."
STARTUP_CMD=$(pm2 startup | grep -oP 'sudo .*' | head -1)
if [[ -n "$STARTUP_CMD" ]]; then
    eval "$STARTUP_CMD" || warn "Startup hook failed — run 'pm2 startup' manually if needed."
    success "PM2 startup configured"
else
    warn "Could not extract pm2 startup command — run 'pm2 startup' manually."
fi
pm2 save

# ─────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────
echo ""
divider
success "All done! '${PM2_NAME}' is live and managed by PM2."
info  "Useful PM2 commands:"
echo ""
echo -e "  pm2 list                  — see all running apps"
echo -e "  pm2 logs ${PM2_NAME}           — view live logs"
echo -e "  pm2 restart ${PM2_NAME}        — restart the app"
echo -e "  pm2 stop ${PM2_NAME}           — stop the app"
echo -e "  pm2 delete ${PM2_NAME}         — remove from PM2"
echo ""
divider

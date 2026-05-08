#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# setup-cicd.sh
# Interactively sets GitHub Actions secrets and generates a deploy workflow
# Requirements: gh (GitHub CLI), git
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
echo -e "${BOLD}  GitHub CI/CD Setup${RESET}"
divider
 
command -v gh  &>/dev/null || err "'gh' (GitHub CLI) is not installed. Install from https://cli.github.com"
command -v git &>/dev/null || err "'git' is not installed."
 
# Must be authenticated with gh
gh auth status &>/dev/null || err "Not logged in to GitHub CLI. Run: gh auth login"
 
# Must be inside a git repo
git rev-parse --is-inside-work-tree &>/dev/null || err "This script must be run from inside a git repository."
 
# Detect the GitHub repo (owner/name) from the remote
DETECTED_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || true
 
# ─────────────────────────────────────────────
# Collect inputs
# ─────────────────────────────────────────────
echo ""
info "Let's collect a few details. Press Enter to accept defaults where shown."
echo ""
 
# GitHub repo
if [[ -n "$DETECTED_REPO" ]]; then
    read -rp "  GitHub repo [${DETECTED_REPO}]: " REPO_INPUT
    REPO="${REPO_INPUT:-$DETECTED_REPO}"
else
    read -rp "  GitHub repo (owner/name, e.g. acme/my-app): " REPO
    [[ -z "$REPO" ]] && err "Repository cannot be empty."
fi
 
# Branch name
read -rp "  Branch to deploy from [main]: " BRANCH_INPUT
BRANCH="${BRANCH_INPUT:-main}"
 
# EC2 host
read -rp "  Production server host (IP or domain): " PROD_HOST
[[ -z "$PROD_HOST" ]] && err "Host cannot be empty."
 
# EC2 SSH user
read -rp "  SSH username [ubuntu]: " USER_INPUT
PROD_USER="${USER_INPUT:-ubuntu}"
 
# SSH private key — accept file path
while true; do
    read -rp "  Path to your SSH private key [~/.ssh/id_rsa]: " KEY_PATH_INPUT
    KEY_PATH="${KEY_PATH_INPUT:-$HOME/.ssh/id_rsa}"
    KEY_PATH="${KEY_PATH/#\~/$HOME}"      # expand tilde manually
    if [[ -f "$KEY_PATH" ]]; then
        break
    else
        warn "File not found: $KEY_PATH — please try again."
    fi
done
 
# App directory on the server
read -rp "  App directory on server [/home/${PROD_USER}/app]: " APP_DIR_INPUT
APP_DIR="${APP_DIR_INPUT:-/home/${PROD_USER}/app}"
 
# Package manager
read -rp "  Package manager (npm / yarn / pnpm) [yarn]: " PKG_INPUT
PKG="${PKG_INPUT:-yarn}"
 
# Derive install / build commands
case "$PKG" in
    npm)  INSTALL_CMD="npm install";    BUILD_CMD="npm run build";  START_CMD="npm run start:prod" ;;
    pnpm) INSTALL_CMD="pnpm install";   BUILD_CMD="pnpm run build"; START_CMD="pnpm run start:prod" ;;
    *)    INSTALL_CMD="yarn";           BUILD_CMD="yarn run build"; START_CMD="yarn start:prod" ;;
esac
 
# Allow user to override start command
read -rp "  PM2 start command [${START_CMD}]: " START_INPUT
START_CMD="${START_INPUT:-$START_CMD}"
 
# PM2 process name
DEFAULT_PM2=$(basename "$REPO")
read -rp "  PM2 process name [${DEFAULT_PM2}]: " PM2_INPUT
PM2_NAME="${PM2_INPUT:-$DEFAULT_PM2}"
 
# Health-check port
read -rp "  App port for health check [3000]: " PORT_INPUT
APP_PORT="${PORT_INPUT:-3000}"
 
# Gitleaks paid licence (optional)
read -rp "  Gitleaks licence key (leave blank to skip — free on public repos): " GITLEAKS_KEY
 
echo ""
divider
echo -e "${BOLD}  Configuration summary${RESET}"
divider
echo -e "  Repo         : ${BOLD}${REPO}${RESET}"
echo -e "  Branch       : ${BOLD}${BRANCH}${RESET}"
echo -e "  Server host  : ${BOLD}${PROD_HOST}${RESET}"
echo -e "  SSH user     : ${BOLD}${PROD_USER}${RESET}"
echo -e "  SSH key file : ${BOLD}${KEY_PATH}${RESET}"
echo -e "  App dir      : ${BOLD}${APP_DIR}${RESET}"
echo -e "  Package mgr  : ${BOLD}${PKG}${RESET}"
echo -e "  Build cmd    : ${BOLD}${BUILD_CMD}${RESET}"
echo -e "  Start cmd    : ${BOLD}${START_CMD}${RESET}"
echo -e "  PM2 name     : ${BOLD}${PM2_NAME}${RESET}"
echo -e "  Health port  : ${BOLD}${APP_PORT}${RESET}"
[[ -n "$GITLEAKS_KEY" ]] && echo -e "  Gitleaks key : ${BOLD}[provided]${RESET}" || echo -e "  Gitleaks key : ${YELLOW}skipped${RESET}"
divider
echo ""
 
read -rp "  Proceed? [y/N] " CONFIRM
[[ "${CONFIRM,,}" != "y" ]] && err "Aborted by user."
 
# ─────────────────────────────────────────────
# Set GitHub Actions secrets
# ─────────────────────────────────────────────
echo ""
info "Setting GitHub Actions secrets on ${BOLD}${REPO}${RESET}..."
 
gh secret set PROD_HOST    --body "$PROD_HOST"                    --repo "$REPO"
success "PROD_HOST set"
 
gh secret set PROD_USER    --body "$PROD_USER"                    --repo "$REPO"
success "PROD_USER set"
 
gh secret set PROD_SSH_KEY --body "$(cat "$KEY_PATH")"            --repo "$REPO"
success "PROD_SSH_KEY set"
 
if [[ -n "$GITLEAKS_KEY" ]]; then
    gh secret set GITLEAKS_LICENSE --body "$GITLEAKS_KEY"         --repo "$REPO"
    success "GITLEAKS_LICENSE set"
else
    warn "GITLEAKS_LICENSE skipped — Gitleaks step will be skipped in the workflow too."
fi
 
# ─────────────────────────────────────────────
# Generate the workflow file
# ─────────────────────────────────────────────
echo ""
info "Generating .github/workflows/deploy.yml..."
 
WORKFLOW_DIR=".github/workflows"
mkdir -p "$WORKFLOW_DIR"
 
# Build gitleaks block conditionally
if [[ -n "$GITLEAKS_KEY" ]]; then
    GITLEAKS_BLOCK=$(cat <<'EOF'
  # ─── Job 1: Secret scanning ───────────────────────────────────────────────
  gitleaks:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
 
      - name: Run Gitleaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}
 
EOF
)
    NEEDS_CLAUSE="    needs: gitleaks"
else
    GITLEAKS_BLOCK=""
    NEEDS_CLAUSE=""
fi
 
cat > "${WORKFLOW_DIR}/deploy.yml" <<WORKFLOW
name: Deploy to Production
 
on:
  push:
    branches:
      - ${BRANCH}
 
jobs:
${GITLEAKS_BLOCK}
  # ─── Job 2: Deploy ────────────────────────────────────────────────────────
  deploy:
    runs-on: ubuntu-latest
${NEEDS_CLAUSE}
    permissions:
      contents: read
 
    steps:
      # ─── 1. Checkout ────────────────────────────────────────────────────
      - name: Checkout repository
        uses: actions/checkout@v4
 
      # ─── 2. Deploy to EC2 ───────────────────────────────────────────────
      - name: Deploy to EC2
        uses: appleboy/ssh-action@v1.0.3
        env:
          GH_TOKEN: \${{ secrets.GITHUB_TOKEN }}
        with:
          host: \${{ secrets.PROD_HOST }}
          username: \${{ secrets.PROD_USER }}
          key: \${{ secrets.PROD_SSH_KEY }}
          envs: GH_TOKEN
          command_timeout: 10m
          script: |
            set -euo pipefail
            cd ${APP_DIR}
 
            # ── Auth ──────────────────────────────────────────────────────
            git config --local credential.helper \\
              '!f() { echo "username=x-access-token"; echo "password='"\$GH_TOKEN"'"; }; f'
 
            # ── Pull latest ───────────────────────────────────────────────
            git fetch origin
            git reset --hard origin/${BRANCH}
            git clean -fd
 
            # ── Install & build ───────────────────────────────────────────
            ${INSTALL_CMD}
            ${BUILD_CMD}
 
            # ── Graceful restart ──────────────────────────────────────────
            pm2 reload ${PM2_NAME} || pm2 start "${START_CMD}" --name ${PM2_NAME}
            pm2 save
 
            # ── Cleanup ───────────────────────────────────────────────────
            git config --local --unset credential.helper
 
            # ── Health check ──────────────────────────────────────────────
            echo "Running health check..."
            MAX_RETRIES=4
            RETRY_INTERVAL=5
            HEALTH_URL="http://localhost:${APP_PORT}"
            SUCCESS=false
 
            for i in \$(seq 1 \$MAX_RETRIES); do
              STATUS=\$(curl -s -o /dev/null -w "%{http_code}" "\$HEALTH_URL" 2>/dev/null) || STATUS="000"
              if [ "\$STATUS" = "200" ]; then
                echo "Health check passed (attempt \$i) — app is live"
                SUCCESS=true
                break
              fi
              echo "Attempt \$i/\$MAX_RETRIES — got HTTP \$STATUS, retrying in \${RETRY_INTERVAL}s..."
              sleep \$RETRY_INTERVAL
            done
 
            if [ "\$SUCCESS" != "true" ]; then
              echo "Health check failed after \$MAX_RETRIES attempts — rolling back..."
              pm2 stop ${PM2_NAME}
              git reset --hard HEAD~1
              ${INSTALL_CMD}
              ${BUILD_CMD}
              pm2 start ${PM2_NAME} --update-env
              pm2 save
              echo "::error::Deploy failed — rolled back to previous version"
              exit 1
            fi
 
      # ─── 3. Notify on failure ─────────────────────────────────────────────
      - name: Notify on failure
        if: failure()
        run: echo "::error::Deployment failed on \$(date -u). Check deploy logs."
WORKFLOW
 
success "Workflow file written to ${WORKFLOW_DIR}/deploy.yml"
 
# ─────────────────────────────────────────────
# Optionally commit & push
# ─────────────────────────────────────────────
echo ""
read -rp "  Commit and push the workflow file now? [y/N] " PUSH_CONFIRM
 
if [[ "${PUSH_CONFIRM,,}" == "y" ]]; then
    git add "${WORKFLOW_DIR}/deploy.yml"
    git commit -m "ci: add production deploy workflow"
    git push origin "$BRANCH"
    success "Workflow committed and pushed to ${BRANCH}."
    echo ""
    info "Your next push to '${BRANCH}' will trigger the pipeline."
    info "Monitor it at: https://github.com/${REPO}/actions"
else
    warn "Workflow file was NOT pushed. When ready, run:"
    echo ""
    echo "    git add .github/workflows/deploy.yml"
    echo "    git commit -m 'ci: add production deploy workflow'"
    echo "    git push origin ${BRANCH}"
    echo ""
fi
 
divider
success "All done! Secrets are set and your workflow is ready."
divider

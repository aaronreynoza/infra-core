#!/usr/bin/env bash
# install-runner.sh
# Installs and registers a self-hosted GitHub Actions runner as a systemd service.
# Run as root on the VM that will act as the runner.

set -euo pipefail

# -----------------------------
# Configurable variables
# -----------------------------
# Required: set these via environment variables or you will be prompted.
REPO_URL="${REPO_URL:-}"
REG_TOKEN="${REG_TOKEN:-}"

# Optional settings (can override via env)
RUNNER_NAME="${RUNNER_NAME:-gh-runner-1}"
RUNNER_USER="${RUNNER_USER:-github}"
RUNNER_DIR="${RUNNER_DIR:-/opt/actions-runner}"
LABELS="${LABELS:-self-hosted,proxmox,talos,terraform}"
INSTALL_DOCKER="${INSTALL_DOCKER:-true}"   # set to false to skip Docker
RUNNER_VERSION="${RUNNER_VERSION:-}"       # leave empty to auto-detect latest

# -----------------------------
# Helpers
# -----------------------------
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Please run as root (sudo)."
  fi
}

prompt_if_empty() {
  local var="$1"
  local msg="$2"
  if [[ -z "${!var:-}" ]]; then
    read -rp "$msg: " val
    export "$var"="$val"
  fi
}

latest_runner_version() {
  # Try GitHub API first; fallback to a pinned version if API not reachable.
  local v
  v="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | grep -oE '\"tag_name\":\s*\"v[0-9.]+' | head -1 | grep -oE '[0-9.]+' )" || true
  if [[ -z "$v" ]]; then
    v="2.319.1"  # fallback pin
  fi
  echo "$v"
}

ensure_user() {
  local user="$1"
  if ! id -u "$user" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -U "$user"
  fi
}

install_deps() {
  apt-get update -y
  apt-get install -y curl jq tar unzip git ca-certificates
  if [[ "${INSTALL_DOCKER}" == "true" ]]; then
    apt-get install -y docker.io
    systemctl enable --now docker
    usermod -aG docker "$RUNNER_USER" || true
  fi
}

download_runner() {
  mkdir -p "$RUNNER_DIR"
  chown -R "$RUNNER_USER":"$RUNNER_USER" "$RUNNER_DIR"
  cd "$RUNNER_DIR"

  if [[ -z "$RUNNER_VERSION" ]]; then
    RUNNER_VERSION="$(latest_runner_version)"
  fi
  echo "Using GitHub Actions Runner version: $RUNNER_VERSION"

  local tgz="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
  local url="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${tgz}"

  sudo -u "$RUNNER_USER" bash -lc "curl -fL -o '${tgz}' '${url}'"
  sudo -u "$RUNNER_USER" bash -lc "tar xzf '${tgz}' && rm -f '${tgz}'"

  # Install additional dependencies required by the runner
  sudo -u "$RUNNER_USER" bash -lc "./bin/installdependencies.sh || true"
}

configure_runner() {
  cd "$RUNNER_DIR"
  # Remove any previous stale service (safe if first run)
  if systemctl list-units --full -all | grep -q 'actions.runner'; then
    ./svc.sh stop || true
    ./svc.sh uninstall || true
  fi

  # Configure unattended
  sudo -u "$RUNNER_USER" bash -lc "./config.sh --unattended     --url '${REPO_URL}'     --token '${REG_TOKEN}'     --name '${RUNNER_NAME}'     --labels '${LABELS}'     --work '${RUNNER_DIR}/_work'     --replace"

  # Install & start as a service
  ./svc.sh install "$RUNNER_USER"
  ./svc.sh start
}

install_aws() {
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  sudo /tmp/aws/install
}

post_info() {
  echo
  echo "==================== Summary ===================="
  echo "Runner name:     ${RUNNER_NAME}"
  echo "Runner user:     ${RUNNER_USER}"
  echo "Runner dir:      ${RUNNER_DIR}"
  echo "Labels:          ${LABELS}"
  echo "Repo URL:        ${REPO_URL}"
  echo "Service status:  $(systemctl is-active actions.runner.*.service || true)"
  echo "Logs:            journalctl -u actions.runner* -f"
  echo "Diag logs:       ${RUNNER_DIR}/_diag"
  echo "================================================="
}

main() {
  need_root
  prompt_if_empty REPO_URL "Enter GitHub repo/org URL (e.g. https://github.com/your-org/your-repo)"
  prompt_if_empty REG_TOKEN "Enter runner registration token"

  ensure_user "$RUNNER_USER"
  install_deps
  download_runner
  configure_runner
  install_aws
  post_info
}

main "$@"

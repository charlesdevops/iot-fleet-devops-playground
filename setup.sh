#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Fleet Registry — bootstrap script for Ubuntu (native or WSL2)
# Installs: Python 3.12, Poetry, Docker CE, Terraform, Helm, kubectl
# ---------------------------------------------------------------------------

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

print_step() { echo -e "\n${CYAN}${BOLD}==> $*${RESET}"; }
print_ok()   { echo -e "${GREEN}✓ $*${RESET}"; }
print_skip() { echo -e "${YELLOW}⏭ $*${RESET}"; }
print_warn() { echo -e "${YELLOW}⚠ $*${RESET}"; }
die()        { echo -e "${RED}✗ $*${RESET}" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Refuse to run as root
# ---------------------------------------------------------------------------
if [[ "$EUID" -eq 0 ]]; then
    die "Do not run this script as root or with sudo. Run it as your regular user — sudo is used internally where needed."
fi

# ---------------------------------------------------------------------------
# 1. Verify Ubuntu
# ---------------------------------------------------------------------------
print_step "Checking operating system"
if [[ ! -f /etc/os-release ]]; then
    die "Cannot determine the operating system (/etc/os-release not found)."
fi
# shellcheck source=/dev/null
source /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
    die "This script only supports Ubuntu (detected: ${PRETTY_NAME:-$ID})."
fi
print_ok "Ubuntu detected: ${PRETTY_NAME}"

CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
[[ -z "$CODENAME" ]] && die "Cannot determine Ubuntu codename."

# ---------------------------------------------------------------------------
# 2. System prerequisites
# ---------------------------------------------------------------------------
print_step "Installing system prerequisites"

# If the Trivy apt repo is present, always refresh its GPG key and ensure
# the sources entry uses the modern signed-by format (handles both a missing
# keyring and a stale/corrupt one from a previous apt-key-based install).
TRIVY_SOURCES="/etc/apt/sources.list.d/trivy.list"
TRIVY_KEYRING="/etc/apt/keyrings/trivy.gpg"
if [[ -f "$TRIVY_SOURCES" ]]; then
    print_warn "Trivy repo detected — refreshing GPG key..."
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key \
        | gpg --dearmor \
        | sudo tee "$TRIVY_KEYRING" > /dev/null
    sudo chmod a+r "$TRIVY_KEYRING"
    # Rewrite the sources entry with the correct signed-by reference
    echo "deb [signed-by=${TRIVY_KEYRING}] https://aquasecurity.github.io/trivy-repo/deb generic main" \
        | sudo tee "$TRIVY_SOURCES" > /dev/null
    print_ok "Trivy GPG key and sources entry updated"
fi

sudo apt-get update -qq
sudo apt-get install -y -qq \
    curl \
    gnupg \
    ca-certificates \
    software-properties-common \
    lsb-release \
    unzip \
    apt-transport-https
print_ok "System prerequisites installed"

# ---------------------------------------------------------------------------
# 3. Python 3.12
# ---------------------------------------------------------------------------
print_step "Python 3.12"
if command -v python3.12 &>/dev/null; then
    print_skip "python3.12 already present: $(python3.12 --version)"
else
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    sudo apt-get update -qq
    sudo apt-get install -y -qq python3.12 python3.12-venv python3.12-dev
    print_ok "Python 3.12 installed: $(python3.12 --version)"
fi

# ---------------------------------------------------------------------------
# 4. Poetry
# ---------------------------------------------------------------------------
print_step "Poetry"
export PATH="$HOME/.local/bin:$PATH"
if command -v poetry &>/dev/null; then
    print_skip "Poetry already present: $(poetry --version)"
else
    curl -sSL https://install.python-poetry.org | python3.12 -
    print_ok "Poetry installed: $(poetry --version)"
fi

# ---------------------------------------------------------------------------
# 5. Docker CE + Compose plugin
# ---------------------------------------------------------------------------
print_step "Docker CE"
if command -v docker &>/dev/null; then
    print_skip "Docker already present: $(docker --version)"
else
    # Remove any conflicting packages
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        sudo apt-get remove -y -qq "$pkg" 2>/dev/null || true
    done

    # Add the official Docker GPG key and apt repository
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    # Add current user to the docker group
    sudo usermod -aG docker "$USER"
    print_ok "Docker installed: $(docker --version)"
    print_warn "Run 'newgrp docker' or log out and back in to use Docker without sudo."

    # WSL-specific note
    if grep -qi microsoft /proc/version 2>/dev/null; then
        print_warn "WSL detected: start the service with 'sudo service docker start' or use Docker Desktop."
    fi
fi

# ---------------------------------------------------------------------------
# 5b. Docker Buildx plugin
# ---------------------------------------------------------------------------
print_step "Docker Buildx plugin"
# Remove a broken user-level binary (wrong arch) that shadows the system plugin
USER_BUILDX="$HOME/.docker/cli-plugins/docker-buildx"
if [[ -f "$USER_BUILDX" ]] && ! "$USER_BUILDX" version &>/dev/null 2>&1; then
    print_warn "Removing broken user-level buildx binary..."
    rm -f "$USER_BUILDX"
fi
if docker buildx version &>/dev/null 2>&1; then
    print_skip "docker-buildx already working: $(docker buildx version)"
else
    sudo apt-get install -y -qq docker-buildx-plugin
    print_ok "docker-buildx-plugin installed: $(docker buildx version)"
fi

# ---------------------------------------------------------------------------
# 6. Terraform
# ---------------------------------------------------------------------------
print_step "Terraform"
if command -v terraform &>/dev/null; then
    print_skip "Terraform already present: $(terraform --version | head -1)"
else
    curl -fsSL "https://apt.releases.hashicorp.com/gpg" \
        | sudo gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
    sudo chmod a+r /etc/apt/keyrings/hashicorp.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/hashicorp.gpg] \
https://apt.releases.hashicorp.com ${CODENAME} main" \
        | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

    sudo apt-get update -qq
    sudo apt-get install -y -qq terraform
    print_ok "Terraform installed: $(terraform --version | head -1)"
fi

# ---------------------------------------------------------------------------
# 7. Helm
# ---------------------------------------------------------------------------
print_step "Helm"
if command -v helm &>/dev/null; then
    print_skip "Helm already present: $(helm version --short)"
else
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    print_ok "Helm installed: $(helm version --short)"
fi

# ---------------------------------------------------------------------------
# 8. kubectl
# ---------------------------------------------------------------------------
print_step "kubectl"
if command -v kubectl &>/dev/null; then
    print_skip "kubectl already present: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
else
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key" \
        | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    sudo chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    echo \
        "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
        | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

    sudo apt-get update -qq
    sudo apt-get install -y -qq kubectl
    print_ok "kubectl installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
fi

# ---------------------------------------------------------------------------
# 9. minikube
# ---------------------------------------------------------------------------
print_step "minikube"
if command -v minikube &>/dev/null; then
    print_skip "minikube already present: $(minikube version --short)"
else
    curl -LO "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64"
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    rm minikube-linux-amd64
    print_ok "minikube installed: $(minikube version --short)"
fi

# ---------------------------------------------------------------------------
# 10. Python project dependencies (Poetry install)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_step "Installing Python project dependencies"
(cd "$SCRIPT_DIR/app" && poetry lock --no-update 2>/dev/null || poetry lock) && \
(cd "$SCRIPT_DIR/app" && poetry install)
print_ok "Python dependencies installed"

# ---------------------------------------------------------------------------
# 11. Local .env setup
# ---------------------------------------------------------------------------
print_step "Setting up .env"
ENV_FILE="$SCRIPT_DIR/app/.env"
ENV_EXAMPLE="$SCRIPT_DIR/app/.env-example"

if [[ -f "$ENV_FILE" ]]; then
    print_skip ".env already exists — not overwritten"
else
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    print_ok ".env created from .env-example"
    print_warn "The defaults in app/.env are ready for LocalStack. Edit the file only if targeting real AWS."
fi

# ---------------------------------------------------------------------------
# 12. Summary
# ---------------------------------------------------------------------------
echo -e "\n${BOLD}${GREEN}════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  Setup completed successfully!${RESET}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════${RESET}\n"

echo -e "${BOLD}Installed tools:${RESET}"
printf "  %-18s %s\n" "Python:"         "$(python3.12 --version 2>&1)"
printf "  %-18s %s\n" "Poetry:"         "$(poetry --version 2>&1)"
printf "  %-18s %s\n" "Docker:"         "$(docker --version 2>/dev/null || echo 'restart your session to use without sudo')"
printf "  %-18s %s\n" "Docker Compose:" "$(docker compose version 2>/dev/null)"
printf "  %-18s %s\n" "Terraform:"      "$(terraform --version 2>/dev/null | head -1)"
printf "  %-18s %s\n" "Helm:"           "$(helm version --short 2>/dev/null)"
printf "  %-18s %s\n" "kubectl:"        "$(kubectl version --client 2>/dev/null | grep 'Client Version')"
printf "  %-18s %s\n" "minikube:"       "$(minikube version --short 2>/dev/null)"

echo -e "\n${BOLD}Next steps:${RESET}"
echo "  1. Review and configure app/.env (defaults are ready for LocalStack)"
echo "  2. make up          # start LocalStack + app"
echo "  3. make infra-init  # download Terraform providers (first time only)"
echo "  4. make infra-apply # provision DynamoDB and S3 on LocalStack"
echo "  5. make test        # run the test suite"

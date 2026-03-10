#!/bin/bash
set -e

echo "=========================================="
echo "Tau2-Bench Setup Script"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Detect OS
OS_TYPE=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]; then
        OS_TYPE="debian"
        print_info "Detected Ubuntu/Debian system"
    else
        OS_TYPE="linux-other"
        print_warning "Non-Ubuntu/Debian Linux detected."
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
    print_info "Detected macOS system"
else
    OS_TYPE="unknown"
    print_warning "Cannot detect OS. Will attempt to continue."
fi

# Install system dependencies based on OS
if [ "$OS_TYPE" = "debian" ]; then
    # Ubuntu/Debian (GCP VM)
    print_info "Updating package lists..."
    apt-get update -qq
    
    print_info "Installing system dependencies..."
    apt-get install -y -qq \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        git \
        curl \
        build-essential \
        libffi-dev \
        libssl-dev \
        2>/dev/null || {
        print_error "Failed to install system dependencies"
        exit 1
    }
    print_success "System dependencies installed"
elif [ "$OS_TYPE" = "macos" ]; then
    # macOS - check if dependencies are available
    print_info "Checking macOS dependencies..."
    
    if ! command -v git &> /dev/null; then
        print_error "git is not installed. Please install Xcode Command Line Tools: xcode-select --install"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        print_error "curl is not installed. Please install it."
        exit 1
    fi
    
    print_success "macOS dependencies check passed"
    print_info "Note: On macOS, please ensure Python 3.10+ is installed (e.g., via brew: brew install python@3.10)"
else
    # Unknown OS - just check if Python is available
    print_warning "Unknown OS. Skipping system package installation."
    print_info "Please ensure Python 3.10+, git, and curl are installed."
fi

# Check Python version (requires 3.10+)
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
REQUIRED_VERSION="3.10"
if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$PYTHON_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then 
    print_error "Python 3.10+ is required. Found: $PYTHON_VERSION"
    exit 1
fi
print_success "Python version check passed: $PYTHON_VERSION"

# Install PDM (Python Dependency Manager)
print_info "Installing PDM..."
pip3 install -q pdm
print_success "PDM installed: $(pdm --version)"

# Clone tau2-bench repository if not already present
REPO_DIR="${SCRIPT_DIR}/tau2-bench-repo"
if [ ! -d "${REPO_DIR}" ]; then
    print_info "Cloning tau2-bench repository..."
    git clone https://github.com/sierra-research/tau-bench.git "${REPO_DIR}" 2>/dev/null || {
        print_warning "Failed to clone from GitHub. Checking for local copy..."
        if [ -d "${SCRIPT_DIR}/src" ] && [ -f "${SCRIPT_DIR}/pyproject.toml" ]; then
            print_info "Using local source files"
            mkdir -p "${REPO_DIR}"
            cp -r "${SCRIPT_DIR}/src" "${REPO_DIR}/"
            cp -r "${SCRIPT_DIR}/data" "${REPO_DIR}/" 2>/dev/null || true
            cp "${SCRIPT_DIR}/pyproject.toml" "${REPO_DIR}/" 2>/dev/null || true
            cp "${SCRIPT_DIR}/pdm.lock" "${REPO_DIR}/" 2>/dev/null || true
            cp "${SCRIPT_DIR}/README.md" "${REPO_DIR}/" 2>/dev/null || true
        else
            print_error "No repository or local files found"
            exit 1
        fi
    }
else
    print_info "Repository already exists at ${REPO_DIR}"
fi

# Create virtual environment using PDM
print_info "Setting up Python virtual environment..."
cd "${REPO_DIR}"

# Initialize PDM if not already initialized
if [ ! -f "pdm.lock" ]; then
    print_info "Initializing PDM project..."
    pdm init -n 2>/dev/null || true
fi

# Install dependencies
print_info "Installing Python dependencies (this may take a few minutes)..."
pdm install --prod -q || {
    print_warning "Production install failed, trying dev install..."
    pdm install -q
}

# Install the package in editable mode to get CLI
print_info "Installing tau2 package..."
pdm run pip install -e . -q

print_success "Dependencies installed"

# Create results directory
RESULTS_DIR="${SCRIPT_DIR}/results"
mkdir -p "${RESULTS_DIR}"
print_success "Results directory created: ${RESULTS_DIR}"

# Create data directory symlink if needed
if [ ! -d "${SCRIPT_DIR}/data" ] && [ -d "${REPO_DIR}/data" ]; then
    ln -sf "${REPO_DIR}/data" "${SCRIPT_DIR}/data"
    print_success "Data directory linked"
fi

# Verify installation
print_info "Verifying installation..."
if pdm run tau2 --help > /dev/null 2>&1; then
    print_success "tau2 CLI is working"
else
    print_error "tau2 CLI verification failed"
    exit 1
fi

# Show available domains
print_info "Available domains:"
pdm run tau2 run --help 2>&1 | grep -A 20 "domain" | head -10 || true

echo ""
echo "=========================================="
print_success "Setup Complete!"
echo "=========================================="
echo ""
echo "Repository: ${REPO_DIR}"
echo "Results: ${RESULTS_DIR}"
echo ""
echo "Next steps:"
echo "  1. Create a config.json file with your settings"
echo "  2. Run: ./run.sh --config config.json"
echo ""
echo "Or run directly with CLI arguments:"
echo "  ./run.sh --api-url <url> --api-key <key> --model <model> --domain mock"
echo ""

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
    sudo apt-get update -qq
    
    print_info "Installing system dependencies..."
    sudo apt-get install -y -qq \
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

# Clone tau2-bench repository if not already present
REPO_DIR="${SCRIPT_DIR}/tau2-bench-repo"
if [ ! -d "${REPO_DIR}" ]; then
    print_info "Cloning tau2-bench repository..."
    git clone https://github.com/sierra-research/tau2-bench.git "${REPO_DIR}" 2>/dev/null || {
        print_error "Failed to clone repository"
        exit 1
    }
else
    print_info "Repository already exists at ${REPO_DIR}"
fi

# Create virtual environment
print_info "Setting up Python virtual environment..."
cd "${REPO_DIR}"

# Remove old venv if it exists
if [ -d ".venv" ]; then
    print_warning "Removing old virtual environment..."
    rm -rf .venv
fi

# Create new venv
print_info "Creating virtual environment..."
python3 -m venv .venv

# Activate and upgrade pip
print_info "Upgrading pip..."
.venv/bin/pip install --upgrade pip -q

# Install PDM in the virtual environment (required for building)
print_info "Installing PDM in virtual environment..."
.venv/bin/pip install pdm -q
print_info "PDM version: $(.venv/bin/pdm --version)"

# Fix pyproject.toml if it has invalid email
if [ -f "pyproject.toml" ]; then
    print_info "Fixing pyproject.toml if needed..."
    # Fix empty email field in authors
    sed -i 's/email = ""/email = "author@example.com"/g' pyproject.toml 2>/dev/null || \
    sed -i '' 's/email = ""/email = "author@example.com"/g' pyproject.toml 2>/dev/null || true
fi

# Install dependencies using PDM (this installs the package too)
print_info "Installing Python dependencies with PDM..."
print_info "Running: .venv/bin/pdm install"
.venv/bin/pdm install 2>&1

# Check if tau2 CLI exists
print_info "Checking for tau2 CLI..."
if [ -f ".venv/bin/tau2" ]; then
    print_success "tau2 CLI found at .venv/bin/tau2"
else
    print_warning "tau2 CLI not found in .venv/bin/"
    print_info "Contents of .venv/bin/:"
    ls -la .venv/bin/ 2>/dev/null || true
    
    # Try using pdm run to execute tau2
    print_info "Trying 'pdm run tau2 --help'..."
    if .venv/bin/pdm run tau2 --help > /dev/null 2>&1; then
        print_success "tau2 works via 'pdm run tau2'"
        # Create a wrapper script
        cat > .venv/bin/tau2 << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."
exec .venv/bin/pdm run tau2 "$@"
EOF
        chmod +x .venv/bin/tau2
        print_success "Created tau2 wrapper script"
    else
        print_error "tau2 CLI not available via pdm run either"
        print_info "Checking site-packages for tau2 module..."
        find .venv/lib -name "tau2*" -type d 2>/dev/null || true
        print_info "Checking for entry_points.txt..."
        find .venv/lib -name "entry_points.txt" -exec cat {} \; 2>/dev/null || true
    fi
fi

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
if .venv/bin/tau2 --help > /dev/null 2>&1; then
    print_success "tau2 CLI is working"
    print_info "tau2 help:"
    .venv/bin/tau2 --help 2>&1 | head -20 || true
else
    print_error "tau2 CLI verification failed"
    exit 1
fi

# Show available domains
print_info "Available domains:"
.venv/bin/tau2 run --help 2>&1 | grep -A 20 "domain" | head -10 || true

echo ""
echo "=========================================="
print_success "Setup Complete!"
echo "=========================================="
echo ""
echo "Repository: ${REPO_DIR}"
echo "Results: ${RESULTS_DIR}"
echo ""
echo "Next steps:"
echo "  1. Run: ./run.sh --api-url <url> --api-key <key> --model <model> --domain mock"
echo ""

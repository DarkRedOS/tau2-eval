#!/bin/bash
set -e

echo "=========================================="
echo "Tau2-Bench Runner"
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

# Default values
CONFIG_FILE=""
API_URL=""
API_KEY=""
MODEL_NAME=""
DOMAIN="mock"
MAX_CONCURRENCY=3
NUM_TRIALS=1
MAX_STEPS=200
TASK_IDS=""
SAVE_TO=""
AGENT_LLM_ARGS='{"temperature": 0.0}'
USER_LLM_ARGS='{"temperature": 0.0}'

# Show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Run Tau2-Bench benchmark on a GCP VM.

Options:
  --config, -c FILE          JSON config file with all settings
  --api-url, -u URL          API base URL (e.g., https://grid.ai.juspay.net/v1)
  --api-key, -k KEY          API key for authentication
  --model, -m MODEL          Model name (e.g., glm-latest, gpt-4)
  --domain, -d DOMAIN        Domain to run (mock, airline, retail, telecom) [default: mock]
  --concurrency, -n NUM      Max concurrent simulations [default: 3]
  --trials, -t NUM           Number of trials per task [default: 1]
  --max-steps NUM            Max steps per simulation [default: 200]
  --task-ids ID1 ID2 ...     Specific task IDs to run (space-separated)
  --save-to NAME             Custom name for results file
  --help, -h                 Show this help message

Examples:
  # Using config file
  $0 --config config.json

  # Using CLI arguments
  $0 --api-url https://api.example.com/v1 --api-key sk-xxx --model glm-latest --domain mock

  # Run specific tasks
  $0 --config config.json --task-ids task_001 task_002

Config file format (config.json):
{
  "api_url": "https://grid.ai.juspay.net/v1",
  "api_key": "your-api-key",
  "model": "glm-latest",
  "domain": "mock",
  "max_concurrency": 3,
  "num_trials": 1,
  "max_steps": 200,
  "agent_llm_args": {"temperature": 0.0},
  "user_llm_args": {"temperature": 0.0}
}

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config|-c)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --api-url|-u)
            API_URL="$2"
            shift 2
            ;;
        --api-key|-k)
            API_KEY="$2"
            shift 2
            ;;
        --model|-m)
            MODEL_NAME="$2"
            shift 2
            ;;
        --domain|-d)
            DOMAIN="$2"
            shift 2
            ;;
        --concurrency|-n)
            MAX_CONCURRENCY="$2"
            shift 2
            ;;
        --trials|-t)
            NUM_TRIALS="$2"
            shift 2
            ;;
        --max-steps)
            MAX_STEPS="$2"
            shift 2
            ;;
        --task-ids)
            shift
            TASK_IDS=""
            while [[ $# -gt 0 ]] && [[ "$1" != --* ]]; do
                TASK_IDS="$TASK_IDS $1"
                shift
            done
            ;;
        --save-to)
            SAVE_TO="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Load from config file if provided
if [ -n "$CONFIG_FILE" ]; then
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi
    
    print_info "Loading configuration from: $CONFIG_FILE"
    
    # Parse JSON config using Python
    CONFIG_JSON=$(cat "$CONFIG_FILE")
    
    # Extract values from config (only if not already set via CLI)
    [ -z "$API_URL" ] && API_URL=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('api_url', ''))" 2>/dev/null || true)
    [ -z "$API_KEY" ] && API_KEY=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('api_key', ''))" 2>/dev/null || true)
    [ -z "$MODEL_NAME" ] && MODEL_NAME=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('model', ''))" 2>/dev/null || true)
    [ -z "$DOMAIN" ] && DOMAIN=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('domain', 'mock'))" 2>/dev/null || true)
    [ "$MAX_CONCURRENCY" = "3" ] && MAX_CONCURRENCY=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('max_concurrency', 3))" 2>/dev/null || true)
    [ "$NUM_TRIALS" = "1" ] && NUM_TRIALS=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('num_trials', 1))" 2>/dev/null || true)
    [ "$MAX_STEPS" = "200" ] && MAX_STEPS=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('max_steps', 200))" 2>/dev/null || true)
    
    # Get LLM args from config
    AGENT_ARGS_FROM_CONFIG=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; d=json.load(sys.stdin).get('agent_llm_args', {}); print(json.dumps(d))" 2>/dev/null || echo '{"temperature": 0.0}')
    USER_ARGS_FROM_CONFIG=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; d=json.load(sys.stdin).get('user_llm_args', {}); print(json.dumps(d))" 2>/dev/null || echo '{"temperature": 0.0}')
    
    [ "$AGENT_LLM_ARGS" = '{"temperature": 0.0}' ] && AGENT_LLM_ARGS="$AGENT_ARGS_FROM_CONFIG"
    [ "$USER_LLM_ARGS" = '{"temperature": 0.0}' ] && USER_LLM_ARGS="$USER_ARGS_FROM_CONFIG"
fi

# Validate required arguments
if [ -z "$API_URL" ]; then
    print_error "API URL is required. Use --api-url or config file."
    exit 1
fi

if [ -z "$API_KEY" ]; then
    print_error "API key is required. Use --api-key or config file."
    exit 1
fi

if [ -z "$MODEL_NAME" ]; then
    print_error "Model name is required. Use --model or config file."
    exit 1
fi

# Check if setup has been run
REPO_DIR="${SCRIPT_DIR}/tau2-bench-repo"
if [ ! -d "${REPO_DIR}" ]; then
    print_error "tau2-bench repository not found. Please run ./setup.sh first."
    exit 1
fi

# Create results directory
RESULTS_DIR="${SCRIPT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

# Set up Python environment
VENV_BIN="${REPO_DIR}/.venv/bin"
if [ -f "${VENV_BIN}/python" ]; then
    PYTHON_CMD="${VENV_BIN}/python"
    TAU2_CMD="${VENV_BIN}/tau2"
else
    print_error "Virtual environment not found. Please run ./setup.sh first."
    exit 1
fi

# Verify tau2 is available
if [ ! -x "$TAU2_CMD" ]; then
    print_error "tau2 CLI not found in virtual environment. Please run ./setup.sh first."
    exit 1
fi

print_info "Using Python: $PYTHON_CMD"
print_info "Using tau2: $TAU2_CMD"

# Generate run ID
RUN_ID=$(date +%Y%m%d_%H%M%S)
if [ -z "$SAVE_TO" ]; then
    SAVE_TO="${DOMAIN}_${MODEL_NAME//\//_}_${RUN_ID}"
fi

# Display configuration
echo ""
echo "=========================================="
echo "Configuration"
echo "=========================================="
echo "API URL: $API_URL"
echo "Model: $MODEL_NAME"
echo "Domain: $DOMAIN"
echo "Max Concurrency: $MAX_CONCURRENCY"
echo "Num Trials: $NUM_TRIALS"
echo "Max Steps: $MAX_STEPS"
echo "Results: ${RESULTS_DIR}/${SAVE_TO}.json"
if [ -n "$TASK_IDS" ]; then
    echo "Task IDs: $TASK_IDS"
fi
echo "=========================================="
echo ""

# Add API credentials to LLM args
# The api_base and api_key are passed via environment variables for LiteLLM
AGENT_LLM_ARGS_WITH_AUTH=$(echo "$AGENT_LLM_ARGS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
d['api_base'] = '$API_URL'
d['api_key'] = '$API_KEY'
print(json.dumps(d))
")

USER_LLM_ARGS_WITH_AUTH=$(echo "$USER_LLM_ARGS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
d['api_base'] = '$API_URL'
d['api_key'] = '$API_KEY'
print(json.dumps(d))
")

# Format model name for LiteLLM (add openai/ prefix if not present)
if [[ ! "$MODEL_NAME" =~ ^openai/ ]]; then
    MODEL_NAME="openai/$MODEL_NAME"
fi

# Export environment variables for LiteLLM
export OPENAI_API_BASE="$API_URL"
export OPENAI_API_KEY="$API_KEY"

# Build the command using tau2 directly
CMD="cd \"${REPO_DIR}\" && \"${TAU2_CMD}\" run \
    --domain \"$DOMAIN\" \
    --agent-llm \"$MODEL_NAME\" \
    --user-llm \"$MODEL_NAME\" \
    --max-concurrency $MAX_CONCURRENCY \
    --num-trials $NUM_TRIALS \
    --max-steps $MAX_STEPS \
    --agent-llm-args '$AGENT_LLM_ARGS_WITH_AUTH' \
    --user-llm-args '$USER_LLM_ARGS_WITH_AUTH' \
    --save-to \"$SAVE_TO\""

# Add task IDs if specified
if [ -n "$TASK_IDS" ]; then
    CMD="$CMD --task-ids $TASK_IDS"
fi

# Run the benchmark
print_info "Starting Tau2-Bench..."
print_info "Command: $CMD"
echo ""

# Execute and capture output
OUTPUT_FILE="${RESULTS_DIR}/${SAVE_TO}.log"
eval "$CMD" 2>&1 | tee "$OUTPUT_FILE"

EXIT_CODE=${PIPESTATUS[0]}

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    print_success "Benchmark completed successfully!"
    
    # Find the results file
    RESULTS_FILE="${REPO_DIR}/data/simulations/${SAVE_TO}.json"
    if [ -f "$RESULTS_FILE" ]; then
        # Copy to results directory
        cp "$RESULTS_FILE" "${RESULTS_DIR}/"
        print_success "Results saved to: ${RESULTS_DIR}/${SAVE_TO}.json"
        
        # Display summary and create result.json
        echo ""
        echo "=========================================="
        echo "Results Summary"
        echo "=========================================="
        export RESULTS_FILE="$RESULTS_FILE"
        export SCRIPT_DIR="${SCRIPT_DIR}"
        export DOMAIN="$DOMAIN"
        export MODEL_NAME="$MODEL_NAME"
        python3 << 'PYTHON_EOF'
import json
import os

results_file = os.environ.get("RESULTS_FILE", "")
script_dir = os.environ.get("SCRIPT_DIR", "")
domain = os.environ.get("DOMAIN", "mock")
model = os.environ.get("MODEL_NAME", "unknown")

try:
    with open(results_file, "r") as f:
        data = json.load(f)
    
    # Handle tau2-bench results format (dict with 'simulations' key)
    if isinstance(data, dict) and "simulations" in data:
        simulations = data.get("simulations", [])
        total = len(simulations)
        
        rewards = []
        task_results = {}
        termination_reasons = {}
        total_steps = 0
        
        for sim in simulations:
            task_id = sim.get("task_id", "unknown")
            reward_info = sim.get("reward_info", {})
            reward = reward_info.get("reward", 0) if isinstance(reward_info, dict) else 0
            rewards.append(reward)
            task_results[task_id] = reward
            
            reason = sim.get("termination_reason", "unknown")
            termination_reasons[reason] = termination_reasons.get(reason, 0) + 1
            
            messages = sim.get("messages", [])
            total_steps += len(messages)
        
        successful = sum(1 for r in rewards if r > 0)
        failed = total - successful
        avg_reward = sum(rewards) / total if total > 0 else 0
        avg_steps = total_steps / total if total > 0 else 0
        
        print(f"Total Tasks: {total}")
        print(f"Successful: {successful}")
        print(f"Failed: {failed}")
        print(f"Success Rate: {successful/total*100:.1f}%")
        print(f"Average Reward: {avg_reward:.3f}")
        
        # Create result.json with standardized format
        result_json = {
            "metrics": {
                "main": {
                    "name": "pass@1",
                    "value": round(avg_reward, 4)
                },
                "secondary": {
                    "success_rate": round(successful / total, 4),
                    "failure_rate": round(failed / total, 4)
                },
                "additional": {
                    "total_tasks": total,
                    "successful_tasks": successful,
                    "failed_tasks": failed,
                    "average_steps": round(avg_steps, 2),
                    "domain": domain,
                    "model": model,
                    "termination_reasons": termination_reasons,
                    "task_results": task_results
                }
            }
        }
        
        # Write result.json
        result_json_path = os.path.join(script_dir, "result.json")
        with open(result_json_path, "w") as f:
            json.dump(result_json, f, indent=2)
        print(f"\nResult JSON saved to: {result_json_path}")
        
    elif isinstance(data, list) and len(data) > 0:
        total = len(data)
        successful = sum(1 for r in data if r.get("reward", 0) > 0)
        failed = total - successful
        avg_reward = sum(r.get("reward", 0) for r in data) / total if total > 0 else 0
        
        print(f"Total Tasks: {total}")
        print(f"Successful: {successful}")
        print(f"Failed: {failed}")
        print(f"Success Rate: {successful/total*100:.1f}%")
        print(f"Average Reward: {avg_reward:.3f}")
        
        # Calculate per-task results
        task_results = {}
        for r in data:
            task_id = r.get("task_id", "unknown")
            reward = r.get("reward", 0)
            task_results[task_id] = reward
        
        # Count termination reasons
        termination_reasons = {}
        total_steps = 0
        for r in data:
            reason = r.get("termination_reason", "unknown")
            termination_reasons[reason] = termination_reasons.get(reason, 0) + 1
            total_steps += len(r.get("trajectory", []))
        
        avg_steps = total_steps / total if total > 0 else 0
        
        # Create result.json with standardized format
        result_json = {
            "metrics": {
                "main": {
                    "name": "pass@1",
                    "value": round(avg_reward, 4)
                },
                "secondary": {
                    "success_rate": round(successful / total, 4),
                    "failure_rate": round(failed / total, 4)
                },
                "additional": {
                    "total_tasks": total,
                    "successful_tasks": successful,
                    "failed_tasks": failed,
                    "average_steps": round(avg_steps, 2),
                    "domain": domain,
                    "model": model,
                    "termination_reasons": termination_reasons,
                    "task_results": task_results
                }
            }
        }
        
        # Write result.json
        result_json_path = os.path.join(script_dir, "result.json")
        with open(result_json_path, "w") as f:
            json.dump(result_json, f, indent=2)
        print(f"\nResult JSON saved to: {result_json_path}")
        
    else:
        print("Results format: single simulation or unknown format")
        reward = data.get("reward", 0) if isinstance(data, dict) else 0
        print(f"Reward: {reward}")
        
        result_json = {
            "metrics": {
                "main": {
                    "name": "pass@1",
                    "value": reward
                },
                "secondary": {},
                "additional": {
                    "domain": domain,
                    "model": model
                }
            }
        }
        
        result_json_path = os.path.join(script_dir, "result.json")
        with open(result_json_path, "w") as f:
            json.dump(result_json, f, indent=2)
        print(f"\nResult JSON saved to: {result_json_path}")
        
except Exception as e:
    print(f"Could not parse results: {e}")
    import traceback
    traceback.print_exc()
PYTHON_EOF
        echo "=========================================="
    else
        print_warning "Results file not found at expected location: $RESULTS_FILE"
        # Try to find it
        FOUND_FILE=$(find "${REPO_DIR}/data/simulations" -name "*${SAVE_TO}*.json" -type f 2>/dev/null | head -1)
        if [ -n "$FOUND_FILE" ]; then
            print_info "Found results at: $FOUND_FILE"
            cp "$FOUND_FILE" "${RESULTS_DIR}/"
        fi
    fi
    
    print_success "Log saved to: $OUTPUT_FILE"
else
    print_error "Benchmark failed with exit code $EXIT_CODE"
    print_info "Partial log saved to: $OUTPUT_FILE"
    exit $EXIT_CODE
fi

echo ""
print_success "All done!"

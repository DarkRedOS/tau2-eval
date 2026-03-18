# Tau2-Bench

Next-generation benchmark for Tool-Agent-User Interaction with multiple domains (mock, airline, retail, telecom).

## Quick Start

```bash
./setup.sh                                          # First time only
./run.sh --api-url <url> --api-key <key> --model <model>
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--api-url`, `-u` | API base URL | required |
| `--api-key`, `-k` | API key for authentication | required |
| `--model`, `-m` | Model name (e.g., glm-latest, gpt-4o) | required |
| `--domain`, `-d` | Domain (mock, airline, retail, telecom) | mock |
| `--concurrency`, `-n` | Max concurrent simulations | 3 |
| `--trials`, `-t` | Number of trials per task | 1 |
| `--max-steps` | Max steps per simulation | 200 |
| `--task-ids` | Specific task IDs to run (space-separated) | all |
| `--save-to` | Custom name for results file | auto-generated |

## Config File

```bash
./run.sh --config config.json
```

```json
{
  "api_url": "https://api.example.com/v1",
  "api_key": "your-api-key",
  "model": "glm-latest",
  "domain": "mock",
  "max_concurrency": 3,
  "num_trials": 1,
  "max_steps": 200,
  "agent_llm_args": {"temperature": 0.0},
  "user_llm_args": {"temperature": 0.0}
}
```

## Domains

| Domain | Description |
|--------|-------------|
| `mock` | Simplified test environment (fastest) |
| `airline` | Airline booking and customer service |
| `retail` | E-commerce and retail operations |
| `telecom` | Telecommunications customer support |

## Requirements

- Python 3.10+
- Git
- PDM (auto-installed via setup.sh)

## Output

Results saved to `results/<domain>_<model>_<timestamp>.json`:

```json
[
  {
    "task_id": "task_001",
    "reward": 1.0,
    "success": true,
    "steps": 15
  }
]
```

Summary metrics:
- Total tasks
- Successful/Failed count
- Success rate percentage
- Average reward

## Examples

```bash
# Basic run with mock domain (fastest for testing)
./run.sh --api-url https://api.example.com/v1 --api-key sk-xxx --model glm-latest --domain mock

# Run retail domain with higher concurrency
./run.sh --config config.json --domain retail --concurrency 5

# Run specific tasks only
./run.sh --config config.json --task-ids task_001 task_002 task_003

# Run with multiple trials for reliability testing
./run.sh --config config.json --trials 3

# Save results with custom name
./run.sh --config config.json --save-to my_experiment

# Run with higher step limit for complex tasks
./run.sh --config config.json --max-steps 500
```

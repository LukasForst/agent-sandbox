# Agentic sandbox

Sandboxes coding agent in docker container and mounts local directory to it.

Simple tooling for JavaScript, Python and Go is installed, modify `Dockerfile.agents` to add more.

## Installation

```bash
mkdir -p "${HOME}/.local/bin"
ln -s "$(pwd)/agent.sh" "${HOME}/.local/bin/agent"
```

## Usage

```bash
Usage: agent.sh [OPTIONS] [COMMAND]

Run an AI coding agent inside a Docker container mounted to the current project.

Options:
  --build         Build the Docker image before running
  --force-build   Build the Docker image without cache and exit
  --join-net NET  Connect the container to Docker network NET
  --help, -h      Show this help message and exit

Commands (mutually exclusive):
  --claude        Run Claude agent (default when no command is given)
  --copilot       Run GitHub Copilot agent
  --bedrock       Run Claude via Amazon Bedrock (requires AWS_BEARER_TOKEN_BEDROCK)
  --bash          Open a bash shell inside the container
  [other args]    Pass arguments directly to the container entrypoint

Environment:
  AWS_BEARER_TOKEN_BEDROCK  Bearer token for Bedrock (required for --bedrock)
  AWS_REGION                AWS region for Bedrock (default: eu-central-1)
  ANTHROPIC_MODEL           Override the default Bedrock model ARN
  .env.agents               If present in the current directory, loaded automatically

Examples:
  agent.sh                  Run Claude agent in the current project
  agent.sh --build --claude Build image then run Claude agent
  agent.sh --bedrock        Run Claude via Amazon Bedrock
  agent.sh --bash           Open a shell inside the container
  agent.sh --join-net mynet Run agent connected to Docker network 'mynet'
```
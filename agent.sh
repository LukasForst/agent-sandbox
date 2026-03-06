#!/bin/bash
set -e

# resolve the directory where this script actually lives (follows symlinks)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# project name as the name of the current directory
PROJECT_PATH="$(pwd)"
PROJECT_NAME="$(basename $(pwd))"

IMAGE_NAME="code-agent"
CONTAINER_NAME="code-agent-${PROJECT_NAME}"
DOCKERFILE="${SCRIPT_DIR}/Dockerfile"
USER_NAME="agent"
NETWORK_NAME=""
FORCE_BUILD=0
BUILD=0

# load .env.agents from the current working directory if it exists
ENV_FILE="$(pwd)/.env.agents"
ENV_ARGS=()
if [ -f "${ENV_FILE}" ]; then
  echo "Loading ${ENV_FILE}"
  ENV_ARGS=("--env-file" "${ENV_FILE}")
fi


build() {
  docker build \
    -f "${DOCKERFILE}" \
    -t "${IMAGE_NAME}" \
    --build-arg USER_ID=$(id -u) \
    --build-arg USER_NAME="${USER_NAME}" \
    .
}

force_build() {
  docker build \
    --no-cache \
    -f "${DOCKERFILE}" \
    -t "${IMAGE_NAME}" \
    --build-arg USER_ID=$(id -u) \
    --build-arg USER_NAME="${USER_NAME}" \
    .
}

check_network() {
  if [ -n "${NETWORK_NAME}" ]; then
    echo "--network ${NETWORK_NAME}"
  fi
}

# generate -v /dev/null:<path> or -v <emptydir>:<path> flags for every entry in .gitignore
# skips: blank lines, comments, node_modules, wildcards/patterns with * ? [ ]
# uses /dev/null for files, an empty tmpdir for directories
_GITIGNORE_EMPTY_DIR=""
gitignore_null_mounts() {
  local gitignore="${PROJECT_PATH}/.gitignore"
  if [ ! -f "${gitignore}" ]; then
    return
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    # skip blank lines, comments, and negation patterns
    [[ -z "$line" || "$line" == \#* || "$line" == \!* ]] && continue
    # skip node_modules
    [[ "$line" == "node_modules" || "$line" == "node_modules/" ]] && continue
    # skip glob patterns (contain * ? [ ])
    [[ "$line" == *[\*\?\[]* ]] && continue
    # remember if the original line had a trailing slash (explicit directory marker)
    local is_dir_hint=0
    [[ "$line" == */ ]] && is_dir_hint=1
    # strip a leading slash if present
    local entry="${line#/}"
    # strip a trailing slash if present
    entry="${entry%/}"
    local target="${PROJECT_PATH}/${entry}"
    # determine whether to treat as directory or file:
    # 1. trailing slash in .gitignore  2. existing directory on host
    if [ "${is_dir_hint}" -eq 1 ] || [ -d "${target}" ]; then
      # only mount if the directory actually exists on the host
      [ ! -d "${target}" ] && continue
      # lazily create one shared empty tmpdir for all directory mounts
      if [ -z "${_GITIGNORE_EMPTY_DIR}" ]; then
        _GITIGNORE_EMPTY_DIR="$(mktemp -d)"
      fi
      echo "-v ${_GITIGNORE_EMPTY_DIR}:${target}"
    else
      # only mount if the file actually exists on the host
      [ ! -f "${target}" ] && continue
      echo "-v /dev/null:${target}"
    fi
  done < "${gitignore}"
}

run() {
  # --user ensures that all created / modified files are owned by the host user
  docker run --rm -it \
    --name "${CONTAINER_NAME}" \
    --hostname "${CONTAINER_NAME}" \
    $(check_network) \
    "${ENV_ARGS[@]}" \
    -v "${HOME}/.claude.json:/home/${USER_NAME}/.claude.json" \
    -v "${HOME}/.claude:/home/${USER_NAME}/.claude" \
    -v "${HOME}/.copilot:/home/${USER_NAME}/.copilot" \
    -v "$(pwd):${PROJECT_PATH}" \
    $(gitignore_null_mounts) \
    --workdir "${PROJECT_PATH}" \
    --user $(id -u):$(id -g) \
    "${IMAGE_NAME}" \
    "$@"
}

run_bedrock() {
  # setup models for bedrock
  model="${ANTHROPIC_MODEL}"
  if [ -z "${model}" ]; then
    model="arn:aws:bedrock:eu-central-1:730335612892:inference-profile/global.anthropic.claude-sonnet-4-5-20250929-v1:0"
  fi

  region="${AWS_REGION}"
  if [ -z "${region}" ]; then
    region="eu-central-1"
  fi

  # caller must set the bearer token
  if [ -z "${AWS_BEARER_TOKEN_BEDROCK}" ]; then
    echo "Error: AWS_BEARER_TOKEN_BEDROCK is not set, set it for your environment"
    exit 1
  fi

  # for claude_code_max_output_tokens ->
  # https://builder.aws.com/content/2tXkZKrZzlrlu0KfH8gST5Dkppq/claude-code-on-amazon-bedrock-quick-setup-guide
  docker run --rm -it \
    --name "${CONTAINER_NAME}" \
    --hostname "${CONTAINER_NAME}" \
    $(check_network) \
    "${ENV_ARGS[@]}" \
    -e "AWS_BEARER_TOKEN_BEDROCK=${AWS_BEARER_TOKEN_BEDROCK}" \
    -e "ANTHROPIC_MODEL=${model}" \
    -e "AWS_REGION=${region}" \
    -e "CLAUDE_CODE_USE_BEDROCK=1" \
    -e "CLAUDE_CODE_MAX_OUTPUT_TOKENS=8192" \
    -e "MAX_THINKING_TOKENS=1024" \
    -v "${HOME}/.claude.json:/home/${USER_NAME}/.claude.json" \
    -v "${HOME}/.claude:/home/${USER_NAME}/.claude" \
    -v "$(pwd):${PROJECT_PATH}" \
    $(gitignore_null_mounts) \
    --workdir "${PROJECT_PATH}" \
    --user $(id -u):$(id -g) \
    "${IMAGE_NAME}" \
    "${@}"
}

# Parse arguments
FILTERED_ARGS=()
i=1
while [ $i -le $# ]; do
  arg="${!i}"
  if [ "$arg" == "--join-net" ]; then
    i=$((i + 1))
    NETWORK_NAME="${!i}"
  elif [ "$arg" == "--force-build" ]; then
    FORCE_BUILD=1
  elif [ "$arg" == "--build" ]; then
    BUILD=1
  else
    FILTERED_ARGS+=("$arg")
  fi
  i=$((i + 1))
done

# Restore positional parameters without flag args
set -- "${FILTERED_ARGS[@]}"

# if --force-build is supplied, build with --no-cache and exit
if [ "${FORCE_BUILD}" -eq 1 ]; then
  force_build
  exit 0
fi

# if --build is supplied, build the image before running the agent
if [ "${BUILD}" -eq 1 ]; then
  build
fi

# --help
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
  cat <<EOF
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
EOF
  exit 0
fi

# if no agent flag is given and no other args, default to claude
if [ "$1" == "--bash" ]; then
  run bash
fi

# copilot
if [ "$1" == "--copilot" ]; then
  run copilot --allow-all-tools --allow-all-paths --allow-all-urls --yolo
fi

# claude bedrock
if [ "$1" == "--bedrock" ]; then
  run_bedrock claude --dangerously-skip-permissions
fi

# otherwise we run it with claude
if [ "$1" == "--claude" ] || [ -z "$1" ]; then
  run claude --dangerously-skip-permissions
fi


# if there's some parameter pass it directly to the container
if [ "$1" != "--bash" ] && [ "$1" != "--bedrock" ] && [ "$1" != "--claude" ]; then
  run "$@"
fi

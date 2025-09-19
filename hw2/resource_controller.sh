#!/bin/bash
CGRP_MOUNTPOINT="/sys/fs/cgroup"
PREFIX="controller_"

if [ ! -f "$CGRP_MOUNTPOINT/cgroup.controllers" ]; then
  echo "Error: enable cgroups v2 to use this utility." >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "bash: cgroup interaction: Permission denied." >&2
  exit 1
fi

show_help() {
  echo "resource_controller limits CPU and RAM used by processes."
  echo ""
  echo "Usage: $(basename "$0") <command> [options]"
  echo ""
  echo "Commands:"
  echo "  exec       Start a new process in cgroup."
  echo "  limit      Add an existing process to cgroup."
  echo "  list       List available cgroups, created by this utility."
  echo "  clean      Delete all empty cgroups created by this utility."
  echo "  help       Get more information about a given command."
  echo ""
  echo "Options for 'exec':"
  echo "  --cpu PERCENT          CPU limit in percent (e.g., 50)."
  echo "  --mem-max SIZE         memory.max limit. (K,M,G)"
  echo "  --mem-high SIZE        memory.high limit. (K,M,G)"
  echo "  --swap-max SIZE        swap.max limit. (K,M,G)"
  echo "  --swap-high SIZE       swap.high limit. (K,M,G)"
  echo ""
  echo "Options for 'limit':"
  echo "  --cpu PERCENT          CPU limit in percent (e.g., 50)."
  echo "  --mem-high SIZE        memory.high limit. (K,M,G)"
  echo "  --mem-max SIZE         memory.max limit. (K,M,G)"
  echo "  --swap-high SIZE       swap.high limit. (K,M,G)"
  echo "  --swap-max SIZE        swap.max limit. (K,M,G)"
  echo ""
  echo "Usage examples:"
  echo "  $(basename "$0") exec --cpu 50 --mem-high 50M --swap-high 20M stress --cpu 1 -t 10"
  echo "  $(basename "$0") limit --cpu 30 --mem-max 1G 1234"
  echo "  $(basename "$0") list"
  echo "  $(basename "$0") clean"
}

generate_random_name() {
  local length=16
  tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c $length
}

cgroup_exists() {
  local CGROUP_PATH="$CGRP_MOUNTPOINT/$1"
  [ -d "$CGROUP_PATH" ]
}

is_valid_size_format() {
  [[ $1 =~ ^[0-9]+([KMG])?$ ]]
}

set_cgroup_limits() {
  local CGROUP_NAME="$1"
  local CPU_LIMIT="$2"
  local MEM_MAX="$3"
  local MEM_HIGH="$4"
  local SWAP_MAX="$5"
  local SWAP_HIGH="$6"
  local CGROUP_PATH="$CGRP_MOUNTPOINT/$1"
  
  if [ -n "$CPU_LIMIT" ]; then
    local CPU_PERIOD=100000
    local CPU_QUOTA=$((CPU_PERIOD * CPU_LIMIT / 100))
    echo "$CPU_QUOTA $CPU_PERIOD" > "$CGROUP_PATH/cpu.max"
  fi
  
  if [ -n "$MEM_HIGH" ]; then
    if is_valid_size_format "$MEM_HIGH"; then
      echo "$MEM_HIGH" > "$CGROUP_PATH/memory.high"
    else
      echo "Invalid size format: $MEM_HIGH"
      exit 1
    fi
  fi

  if [ -n "$MEM_MAX" ]; then
    if is_valid_size_format "$MEM_MAX"; then
      echo "$MEM_MAX" > "$CGROUP_PATH/memory.max"
    else
      echo "Invalid size format: $MEM_MAX"
      exit 1
    fi
  fi

  if [ -n "$SWAP_HIGH" ]; then
    if is_valid_size_format "$SWAP_HIGH"; then
      echo "$SWAP_HIGH" > "$CGROUP_PATH/memory.swap.high"
    else
      echo "Invalid size format: $SWAP_HIGH"
      exit 1
    fi
  fi

  if [ -n "$SWAP_MAX" ]; then
    if is_valid_size_format "$SWAP_MAX"; then
      echo "$SWAP_MAX" > "$CGROUP_PATH/memory.swap.max"
    else
      echo "Invalid size format: $SWAP_MAX"
      exit 1
    fi
  fi
}

cmd_exec() {
  local CPU_LIMIT=""
  local MEM_MAX=""
  local MEM_HIGH=""
  local SWAP_MAX=""
  local SWAP_HIGH=""
  local COMMAND_TO_RUN=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cpu) CPU_LIMIT="$2"; shift 2 ;;
      --mem-max) MEM_MAX="$2"; shift 2 ;;
      --mem-high) MEM_HIGH="$2"; shift 2 ;;
      --swap-max) SWAP_MAX="$2"; shift 2 ;;
      --swap-high) SWAP_HIGH="$2"; shift 2 ;;
      --*)
        echo "Error: Unknown argument: $1" >&2
        exit 1
        ;;
      *)
        COMMAND_TO_RUN="$@"
        break
        ;;
    esac
  done
  
  if [ -z "$COMMAND_TO_RUN" ]; then
    echo "Error: Command to exec must be set." >&2
    exit 1
  fi

  local RANDOM_NAME=$(generate_random_name)
  local CGROUP_NAME="$PREFIX$RANDOM_NAME"
  
  if ! cgroup_exists "$CGROUP_NAME"; then
    cgcreate -g "cpu,memory:$CGROUP_NAME"
  else
    echo "Error: Failed to create cgroup: cgroup with this name already exists." >&2
    exit 1
  fi
  
  set_cgroup_limits "$CGROUP_NAME" "$CPU_LIMIT" "$MEM_MAX" "$MEM_HIGH" "$SWAP_MAX" "$SWAP_HIGH"
  
  cgexec -g "cpu,memory:$CGROUP_NAME" $COMMAND_TO_RUN
  local exit_code=$?
  
  cgdelete -g "cpu,memory:$CGROUP_NAME" 2>/dev/null || echo "Error: Could not remove cgroup (process still running?)" >&2
  
  exit $exit_code
}

cmd_limit() {
  local CPU_LIMIT=""
  local MEM_MAX=""
  local MEM_HIGH=""
  local SWAP_MAX=""
  local SWAP_HIGH=""
  local PID=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cpu) CPU_LIMIT="$2"; shift 2 ;;
      --mem-max) MEM_MAX="$2"; shift 2 ;;
      --mem-high) MEM_HIGH="$2"; shift 2 ;;
      --swap-max) SWAP_MAX="$2"; shift 2 ;;
      --swap-high) SWAP_HIGH="$2"; shift 2 ;;
      --*)
        echo "Error: Unknown argument: $1" >&2
        exit 1
        ;;
      [0-9]*)
        PID="$1"
        shift
        ;;
      *)
        echo "Error: Invalid argument: $1" >&2
        exit 1
        ;;
    esac
  done
  
  if [ -z "$PID" ]; then
    echo "Error: Process PID must be specified." >&2
    exit 1
  fi
  
  if ! ps -p "$PID" > /dev/null 2>&1; then
    echo "Error: Process with PID $PID doesn't exist." >&2
    exit 1
  fi

  local RANDOM_NAME=$(generate_random_name)
  local CGROUP_NAME="$PREFIX$RANDOM_NAME"
  
  if ! cgroup_exists "$CGROUP_NAME"; then
		cgcreate -g "cpu,memory:$CGROUP_NAME"
	else
		echo "Error: Failed to create cgroup: cgroup with this name already exists." >&2
		exit 1
	fi
  
  set_cgroup_limits "$CGROUP_NAME" "$CPU_LIMIT" "$MEM_MAX" "$MEM_HIGH" "$SWAP_MAX" "$SWAP_HIGH"
  
  cgclassify -g "cpu,memory:$CGROUP_NAME" "$PID"
  
  if [ $? -eq 0 ]; then
    echo "Successfully limited process $PID resources."
  else
    echo "Error: Failed to add process $PID to cgroup" >&2
    cgdelete -g "cpu,memory:$CGROUP_NAME" 2>/dev/null
    exit 1
  fi
}

cmd_list() {
  local found=0
  while IFS= read -r -d '' cgroup_path; do
    found=1
    if [[ -f "$cgroup_path/cgroup.procs" ]]; then
      local pid
      pid=$(tr '\n' ' ' < "$cgroup_path/cgroup.procs")
      echo "Running process: ${pid:-null}"
      echo "Process limits:"
    fi
    
    if [ -f "$cgroup_path/cpu.max" ]; then
      local cpu_limits=$(cat "$cgroup_path/cpu.max")
      echo "  CPU limits: $cpu_limits"
    fi
    
    if [ -f "$cgroup_path/memory.max" ]; then
      local mem_max=$(cat "$cgroup_path/memory.max")
      echo "  Memory.max: $mem_max"
    fi
    
    if [ -f "$cgroup_path/memory.high" ]; then
      local mem_high=$(cat "$cgroup_path/memory.high")
      echo "  Memory.high: $mem_high"
    fi
    
    if [ -f "$cgroup_path/memory.swap.max" ]; then
      local swap_max=$(cat "$cgroup_path/memory.swap.max")
      echo "  Swap.max: $swap_max"
    fi
    
    if [ -f "$cgroup_path/memory.swap.high" ]; then
      local swap_high=$(cat "$cgroup_path/memory.swap.high")
      echo "  Swap.high: $swap_high"
    fi
    
    echo "---" 
  done < <(find "$CGRP_MOUNTPOINT" -mindepth 1 -maxdepth 1 -type d -name "$PREFIX*" -print0)

  if [[ $found -eq 0 ]]; then
    echo "No active cgroups found."
  fi
}

cmd_clean() {
  echo "Cleaning up empty cgroups created by this utility..."
  
  find "$CGRP_MOUNTPOINT" -mindepth 1 -maxdepth 1 -type d -name "$PREFIX*" | while read -r cgroup_path; do
    local cgroup_name=$(basename "$cgroup_path")
    
    if [ -f "$cgroup_path/cgroup.procs" ]; then
      local process_count=$(cat "$cgroup_path/cgroup.procs" | wc -l)
      if [ "$process_count" -gt 0 ]; then
        continue
      fi
    fi
    
    cgdelete -g "cpu,memory:$cgroup_name" 2>/dev/null || echo "Error: Could not remove cgroup (process still running?)" >&2
  done
}

case "$1" in
  exec) shift; cmd_exec "$@" ;;
  limit) shift; cmd_limit "$@" ;;
  list) cmd_list ;;
  clean) cmd_clean ;;
  help|--help|-h) show_help ;;
  "") echo "Error: Command must be specified." >&2; show_help; exit 1 ;;
  *) echo "Error: Unknown command '$1'." >&2; show_help; exit 1 ;;
esac


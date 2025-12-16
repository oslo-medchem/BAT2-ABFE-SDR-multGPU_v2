#!/bin/bash
#==============================================================================
# SDR Equilibration GPU Runner
# Version: 2.0
# Purpose: Run equilibration for all ligands with intelligent GPU management
#==============================================================================

set -euo pipefail

#==============================================================================
# CONFIGURATION
#==============================================================================
USE_GPU=true             # true = GPU mode, false = CPU mode (safer for large systems)
MAX_JOBS=8               # Number of concurrent jobs
EQUIL_DIR="./equil"
LOG_DIR="./equil_logs"
CHECKPOINT_FILE="./equil_progress.txt"
REQUIRED_FREE_MEMORY=8000  # MB of free GPU memory required

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#==============================================================================
# Functions
#==============================================================================

print_header() {
    echo -e "${BLUE}=========================================="
    echo "$1"
    echo -e "==========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

get_available_gpu() {
    # Returns GPU ID with enough free memory, or -1 if none available
    if [ "$USE_GPU" = false ]; then
        echo "-1"
        return 0
    fi
    
    for gpu_id in $(seq 0 $((MAX_JOBS - 1))); do
        # Check if GPU is already in use
        if ! grep -q "^GPU${gpu_id}:" "$LOG_DIR/active_jobs.txt" 2>/dev/null; then
            # Check GPU free memory
            local free_mem=$(nvidia-smi -i $gpu_id --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null || echo "0")
            if [ "$free_mem" -ge "$REQUIRED_FREE_MEMORY" ]; then
                echo "$gpu_id"
                return 0
            fi
        fi
    done
    echo "-1"
}

wait_for_slot() {
    # Wait for an available job slot (GPU or CPU)
    while true; do
        local active_jobs=$(jobs -r | wc -l)
        
        if [ "$USE_GPU" = true ]; then
            local gpu_id=$(get_available_gpu)
            if [ "$gpu_id" != "-1" ]; then
                return 0
            fi
        else
            if [ $active_jobs -lt $MAX_JOBS ]; then
                return 0
            fi
        fi
        
        sleep 5
    done
}

is_completed() {
    local ligand="$1"
    grep -q "^COMPLETED:$ligand$" "$CHECKPOINT_FILE" 2>/dev/null
    return $?
}

mark_completed() {
    local ligand="$1"
    echo "COMPLETED:$ligand" >> "$CHECKPOINT_FILE"
}

check_completion() {
    # Check if equilibration completed successfully
    local lig_dir="$1"
    local ligand=$(basename "$lig_dir")
    
    # Look for md-03.out (final equilibration step)
    if [ -f "$lig_dir/md-03.out" ]; then
        if grep -q "TIMINGS" "$lig_dir/md-03.out" && \
           grep -q "Total wall time:" "$lig_dir/md-03.out"; then
            return 0  # Completed
        fi
    fi
    return 1  # Not completed
}

run_ligand() {
    local lig_dir="$1"
    local job_num="$2"
    local ligand=$(basename "$lig_dir")
    local log_file="${LOG_DIR}/${ligand}.log"
    
    # Skip if already completed
    if check_completion "$lig_dir"; then
        echo "[$(date '+%H:%M:%S')] ✓ Already completed: $ligand"
        return 0
    fi
    
    if [ "$USE_GPU" = true ]; then
        local gpu_id=$(get_available_gpu)
        echo "GPU${gpu_id}:$ligand" >> "$LOG_DIR/active_jobs.txt"
        echo "[$(date '+%H:%M:%S')] Starting $ligand on GPU $gpu_id"
    else
        echo "[$(date '+%H:%M:%S')] Starting $ligand on CPU"
    fi
    
    (
        cd "$lig_dir" || exit 1
        
        if [ "$USE_GPU" = true ]; then
            export CUDA_VISIBLE_DEVICES=$gpu_id
        else
            unset CUDA_VISIBLE_DEVICES
        fi
        
        echo "=== Started: $(date) ===" > "$log_file"
        echo "Ligand: $ligand" >> "$log_file"
        echo "Mode: $([ "$USE_GPU" = true ] && echo "GPU $CUDA_VISIBLE_DEVICES" || echo "CPU")" >> "$log_file"
        echo "" >> "$log_file"
        
        bash run-local.bash >> "$log_file" 2>&1
        exit_code=$?
        
        echo "" >> "$log_file"
        echo "=== Finished: $(date) ===" >> "$log_file"
        echo "Exit code: $exit_code" >> "$log_file"
        
        # Remove from active jobs
        if [ "$USE_GPU" = true ]; then
            sed -i "/^GPU${gpu_id}:$ligand$/d" "$LOG_DIR/active_jobs.txt" 2>/dev/null || true
        fi
        
        if [ $exit_code -eq 0 ]; then
            mark_completed "$ligand"
            echo "[$(date '+%H:%M:%S')] ✓ Completed: $ligand"
        else
            echo "[$(date '+%H:%M:%S')] ✗ FAILED: $ligand (exit $exit_code)"
        fi
    ) &
}

#==============================================================================
# Main
#==============================================================================

print_header "SDR Equilibration Runner"

# Create directories
mkdir -p "$LOG_DIR"
touch "$LOG_DIR/active_jobs.txt"
touch "$CHECKPOINT_FILE"

# Configuration
echo "Configuration:"
echo "  Mode: $([ "$USE_GPU" = true ] && echo "GPU" || echo "CPU")"
echo "  Max concurrent jobs: $MAX_JOBS"
echo "  Working directory: $(pwd)"
echo "  Equilibration directory: $EQUIL_DIR"
echo ""

# Check directory exists
if [ ! -d "$EQUIL_DIR" ]; then
    print_error "Equilibration directory not found: $EQUIL_DIR"
    exit 1
fi

# Find ligand folders
shopt -s nullglob nocaseglob
lig_folders=("$EQUIL_DIR"/lig-*)
shopt -u nullglob nocaseglob

if [ ${#lig_folders[@]} -eq 0 ]; then
    print_error "No lig-* folders found in $EQUIL_DIR"
    exit 1
fi

print_success "Found ${#lig_folders[@]} ligand folders"

if [ "$USE_GPU" = false ]; then
    print_warning "Running in CPU mode (recommended for large systems)"
fi

echo ""

# Process each ligand
job_num=0
for lig_dir in "${lig_folders[@]}"; do
    ligand=$(basename "$lig_dir")
    
    if [ ! -f "$lig_dir/run-local.bash" ]; then
        print_warning "SKIP: $ligand (no run-local.bash)"
        continue
    fi
    
    wait_for_slot
    run_ligand "$lig_dir" "$job_num"
    ((job_num++))
    sleep 1
done

echo ""
echo "All jobs submitted. Waiting for completion..."

# Wait for all background jobs
wait

print_header "Equilibration Complete"

# Summary
total=${#lig_folders[@]}
completed=$(grep -c "^COMPLETED:" "$CHECKPOINT_FILE" 2>/dev/null || echo "0")
failed=$((total - completed))

echo "Summary:"
echo "  Total: $total"
print_success "Completed: $completed"
if [ $failed -gt 0 ]; then
    print_error "Failed: $failed"
fi

exit 0

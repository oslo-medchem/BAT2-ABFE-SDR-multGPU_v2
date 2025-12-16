#!/bin/bash
#==============================================================================
# SDR FEP GPU Runner
# Version: 2.0
# Purpose: Run all REST and SDR method windows with intelligent GPU management
#==============================================================================

set -euo pipefail

#==============================================================================
# CONFIGURATION
#==============================================================================
FE_DIR="./fe"
LOG_DIR="./fe_logs"
NUM_GPUS=8
REQUIRED_FREE_MEMORY=8000  # MB
CHECK_INTERVAL=3

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

is_window_completed() {
    # Check if window has completed successfully
    local window_dir="$1"
    
    # Look for md-02.out (final production step)
    if [ -f "$window_dir/md-02.out" ]; then
        if grep -q "TIMINGS" "$window_dir/md-02.out" && \
           grep -q "Total wall time:" "$window_dir/md-02.out"; then
            return 0  # Completed
        fi
    fi
    return 1  # Not completed
}

get_available_gpu() {
    # Returns GPU ID with enough free memory
    for gpu_id in $(seq 0 $((NUM_GPUS - 1))); do
        # Check if GPU is busy
        if ! grep -q "|${gpu_id}|" "$LOG_DIR/active_gpus.txt" 2>/dev/null; then
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

wait_for_gpu() {
    # Wait until a GPU becomes available
    while true; do
        local gpu_id=$(get_available_gpu)
        if [ "$gpu_id" != "-1" ]; then
            echo "$gpu_id"
            return 0
        fi
        sleep $CHECK_INTERVAL
    done
}

scan_windows() {
    # Scan for all REST and SDR windows
    local all_windows=()
    
    print_header "Scanning for windows..."
    
    shopt -s nullglob nocaseglob
    for lig_dir in "$FE_DIR"/lig-*/; do
        [ ! -d "$lig_dir" ] && continue
        local ligand=$(basename "$lig_dir")
        
        echo "Scanning $ligand..."
        
        # Scan REST windows
        if [ -d "${lig_dir}rest" ]; then
            for window in "${lig_dir}rest"/*/; do
                [ ! -d "$window" ] && continue
                if [ -f "${window}run-local.bash" ]; then
                    all_windows+=("$window")
                    echo "  ✓ Found: rest/$(basename $window)"
                fi
            done
        fi
        
        # Scan SDR windows
        if [ -d "${lig_dir}sdr" ]; then
            for window in "${lig_dir}sdr"/*/; do
                [ ! -d "$window" ] && continue
                if [ -f "${window}run-local.bash" ]; then
                    all_windows+=("$window")
                    echo "  ✓ Found: sdr/$(basename $window)"
                fi
            done
        fi
    done
    shopt -u nullglob nocaseglob
    
    echo ""
    printf '%s\n' "${all_windows[@]}"
}

run_window() {
    local window_path="$1"
    local gpu_id="$2"
    
    # Extract window info
    local ligand=$(basename $(dirname $(dirname "$window_path")))
    local method=$(basename $(dirname "$window_path"))
    local window=$(basename "$window_path")
    local log_file="${LOG_DIR}/${ligand}_${method}_${window}_gpu${gpu_id}.log"
    
    # Mark GPU as busy
    echo "$window_path|$gpu_id|$$|$(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_DIR/active_gpus.txt"
    
    echo "[$(date '+%H:%M:%S')] Starting $ligand/$method/$window on GPU $gpu_id"
    
    (
        cd "$window_path" || exit 1
        
        export CUDA_VISIBLE_DEVICES="$gpu_id"
        
        echo "=== Job Started: $(date) ===" > "$log_file"
        echo "Window: $window_path" >> "$log_file"
        echo "GPU: $gpu_id" >> "$log_file"
        echo "" >> "$log_file"
        
        bash run-local.bash >> "$log_file" 2>&1
        exit_code=$?
        
        echo "" >> "$log_file"
        echo "=== Job Finished: $(date) ===" >> "$log_file"
        echo "Exit Code: $exit_code" >> "$log_file"
        
        # Remove from active GPUs
        sed -i "\|^$window_path|$gpu_id|d" "$LOG_DIR/active_gpus.txt" 2>/dev/null || true
        
        if [ $exit_code -eq 0 ]; then
            echo "$window_path" >> "$LOG_DIR/completed.txt"
            echo "[$(date '+%H:%M:%S')] ✓ Completed: $ligand/$method/$window"
        else
            echo "$window_path" >> "$LOG_DIR/failed.txt"
            echo "[$(date '+%H:%M:%S')] ✗ Failed: $ligand/$method/$window"
        fi
    ) &
}

#==============================================================================
# Main
#==============================================================================

print_header "SDR FEP Simulation Runner"

# Create directories
mkdir -p "$LOG_DIR"
touch "$LOG_DIR/active_gpus.txt"
touch "$LOG_DIR/completed.txt"
touch "$LOG_DIR/failed.txt"

echo "Configuration:"
echo "  FE directory: $FE_DIR"
echo "  Log directory: $LOG_DIR"
echo "  Number of GPUs: $NUM_GPUS"
echo "  Required free memory: ${REQUIRED_FREE_MEMORY} MB"
echo ""

# Check FE directory exists
if [ ! -d "$FE_DIR" ]; then
    print_error "FE directory not found: $FE_DIR"
    exit 1
fi

# Scan for windows
mapfile -t ALL_WINDOWS < <(scan_windows)

if [ ${#ALL_WINDOWS[@]} -eq 0 ]; then
    print_error "No windows found!"
    exit 1
fi

print_success "Found ${#ALL_WINDOWS[@]} total windows"

# Count by type
rest_count=$(printf '%s\n' "${ALL_WINDOWS[@]}" | grep -c "/rest/" || echo "0")
sdr_count=$(printf '%s\n' "${ALL_WINDOWS[@]}" | grep -c "/sdr/" || echo "0")

echo "  REST windows: $rest_count"
echo "  SDR windows: $sdr_count"
echo ""

# Ask for confirmation
echo "Estimated time: ~$((${#ALL_WINDOWS[@]} * 15 / NUM_GPUS)) minutes"
echo ""
read -p "Start simulations? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Make all run-local.bash executable
print_header "Preparing scripts..."
find "$FE_DIR" -name "run-local.bash" -exec chmod +x {} \;
print_success "Made all run-local.bash scripts executable"

# Process all windows
print_header "Starting simulations..."

processed=0
for window in "${ALL_WINDOWS[@]}"; do
    # Skip if already completed
    if is_window_completed "$window"; then
        echo "[$(date '+%H:%M:%S')] ⊙ Skipping: $(basename $(dirname $(dirname $window)))/$(basename $(dirname $window))/$(basename $window) (already completed)"
        continue
    fi
    
    # Wait for available GPU
    gpu_id=$(wait_for_gpu)
    
    # Launch job
    run_window "$window" "$gpu_id"
    ((processed++))
    
    # Brief delay
    sleep 1
done

# Wait for all jobs
print_header "Waiting for all jobs to complete..."

while [ $(jobs -r | wc -l) -gt 0 ]; do
    sleep 10
    running=$(wc -l < "$LOG_DIR/active_gpus.txt" 2>/dev/null || echo "0")
    echo -ne "\rJobs still running: $running   "
done

echo ""
print_header "All Simulations Complete!"

# Summary
total=${#ALL_WINDOWS[@]}
completed=$(wc -l < "$LOG_DIR/completed.txt" 2>/dev/null || echo "0")
failed=$(wc -l < "$LOG_DIR/failed.txt" 2>/dev/null || echo "0")
skipped=$((total - processed))

echo "Results:"
echo "  Total windows: $total"
print_success "Completed: $completed"
if [ $skipped -gt 0 ]; then
    echo "  Skipped (already done): $skipped"
fi
if [ $failed -gt 0 ]; then
    print_error "Failed: $failed"
    echo ""
    echo "Failed windows:"
    cat "$LOG_DIR/failed.txt"
fi

exit 0

#!/bin/bash
#==============================================================================
# SDR Simulation Monitor
# Version: 2.0
# Purpose: Monitor progress of SDR equilibration and FEP simulations
#==============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Mode selection
CONTINUOUS_MODE=false
REFRESH_INTERVAL=30

if [ "$1" == "--continuous" ] || [ "$1" == "-c" ]; then
    CONTINUOUS_MODE=true
    REFRESH_INTERVAL=${2:-30}
fi

show_status() {
    clear
    
    echo -e "${BLUE}=========================================="
    echo "SDR Simulation Monitor"
    echo -e "==========================================${NC}"
    echo "Time: $(date)"
    echo ""
    
    # Check what's available
    has_equil=false
    has_fep=false
    
    if [ -d "./equil" ]; then
        has_equil=true
    fi
    
    if [ -d "./fe" ]; then
        has_fep=true
    fi
    
    # GPU Status
    echo "GPU Status:"
    if command -v nvidia-smi &> /dev/null; then
        for gpu_id in {0..7}; do
            local free_mem=$(nvidia-smi -i $gpu_id --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null || echo "N/A")
            if [ "$free_mem" != "N/A" ]; then
                if [ -f "equil_logs/active_jobs.txt" ] && grep -q "^GPU${gpu_id}:" "equil_logs/active_jobs.txt" 2>/dev/null; then
                    echo -e "  GPU $gpu_id: ${GREEN}Busy${NC} (${free_mem} MB free)"
                elif [ -f "fe_logs/active_gpus.txt" ] && grep -q "|${gpu_id}|" "fe_logs/active_gpus.txt" 2>/dev/null; then
                    echo -e "  GPU $gpu_id: ${GREEN}Busy${NC} (${free_mem} MB free)"
                else
                    echo "  GPU $gpu_id: Available (${free_mem} MB free)"
                fi
            fi
        done
    else
        echo "  nvidia-smi not available"
    fi
    echo ""
    
    # Equilibration Status
    if [ "$has_equil" = true ]; then
        echo -e "${BLUE}=== Equilibration Status ===${NC}"
        
        local total_lig=$(find equil -maxdepth 1 -name "lig-*" -type d 2>/dev/null | wc -l)
        local completed=0
        
        if [ -f "equil_progress.txt" ]; then
            completed=$(grep -c "^COMPLETED:" "equil_progress.txt" 2>/dev/null || echo "0")
        else
            # Count by checking md-03.out files
            for lig_dir in equil/lig-*/; do
                if [ -f "${lig_dir}md-03.out" ]; then
                    if grep -q "TIMINGS" "${lig_dir}md-03.out" && \
                       grep -q "Total wall time:" "${lig_dir}md-03.out"; then
                        ((completed++))
                    fi
                fi
            done
        fi
        
        local running=$(jobs -p 2>/dev/null | wc -l)
        local pending=$((total_lig - completed - running))
        
        echo "  Total ligands: $total_lig"
        echo -e "  ${GREEN}Completed: $completed${NC}"
        echo "  Running: $running"
        echo "  Pending: $pending"
        
        if [ $total_lig -gt 0 ]; then
            local percent=$(awk "BEGIN {printf \"%.0f\", ($completed/$total_lig)*100}")
            echo "  Progress: $percent%"
        fi
        
        echo ""
    fi
    
    # FEP Status
    if [ "$has_fep" = true ]; then
        echo -e "${BLUE}=== FEP Status ===${NC}"
        
        # Count windows
        local total_rest=$(find fe/lig-*/rest -name "run-local.bash" 2>/dev/null | wc -l)
        local total_sdr=$(find fe/lig-*/sdr -name "run-local.bash" 2>/dev/null | wc -l)
        local total=$((total_rest + total_sdr))
        
        # Count completed
        local completed=0
        for window in fe/lig-*/rest/*/md-02.out fe/lig-*/sdr/*/md-02.out; do
            if [ -f "$window" ]; then
                if grep -q "TIMINGS" "$window" && \
                   grep -q "Total wall time:" "$window"; then
                    ((completed++))
                fi
            fi
        done 2>/dev/null
        
        # Count running and failed
        local running=0
        local failed=0
        
        if [ -f "fe_logs/active_gpus.txt" ]; then
            running=$(wc -l < "fe_logs/active_gpus.txt")
        fi
        
        if [ -f "fe_logs/failed.txt" ]; then
            failed=$(wc -l < "fe_logs/failed.txt")
        fi
        
        local pending=$((total - completed - running - failed))
        
        echo "  Total windows: $total"
        if [ $total_rest -gt 0 ]; then
            echo "    REST: $total_rest windows"
        fi
        if [ $total_sdr -gt 0 ]; then
            echo "    SDR:  $total_sdr windows"
        fi
        echo -e "  ${GREEN}Completed: $completed${NC}"
        echo "  Running: $running"
        echo "  Pending: $pending"
        if [ $failed -gt 0 ]; then
            echo -e "  ${RED}Failed: $failed${NC}"
        fi
        
        if [ $total -gt 0 ]; then
            local percent=$(awk "BEGIN {printf \"%.0f\", ($completed/$total)*100}")
            echo "  Progress: $percent%"
            
            # Progress bar
            local bar_length=40
            local filled=$((percent * bar_length / 100))
            local empty=$((bar_length - filled))
            echo -n "  ["
            for ((i=0; i<filled; i++)); do echo -n "="; done
            for ((i=0; i<empty; i++)); do echo -n " "; done
            echo "] $percent%"
        fi
        
        echo ""
        
        # Show currently running jobs
        if [ $running -gt 0 ] && [ -f "fe_logs/active_gpus.txt" ]; then
            echo "Currently Running (last 5):"
            tail -5 "fe_logs/active_gpus.txt" | while IFS='|' read -r path gpu pid time; do
                local ligand=$(basename $(dirname $(dirname "$path")))
                local method=$(basename $(dirname "$path"))
                local window=$(basename "$path")
                echo -e "  ${GREEN}►${NC} $ligand/$method/$window (GPU $gpu) - Started: $time"
            done
            echo ""
        fi
        
        # Show recent completions
        if [ -f "fe_logs/completed.txt" ] && [ -s "fe_logs/completed.txt" ]; then
            echo "Recent Completions (last 5):"
            tail -5 "fe_logs/completed.txt" | while read -r window_path; do
                local ligand=$(basename $(dirname $(dirname "$window_path")))
                local method=$(basename $(dirname "$window_path"))
                local window=$(basename "$window_path")
                local comp_time=$(stat -c %y "$window_path/md-02.out" 2>/dev/null | cut -d'.' -f1 || echo "Unknown")
                echo -e "  ${GREEN}✓${NC} $ligand/$method/$window - $comp_time"
            done
            echo ""
        fi
        
        # Show recent failures
        if [ $failed -gt 0 ]; then
            echo "Recent Failures (last 5):"
            tail -5 "fe_logs/failed.txt" | while read -r window_path; do
                local ligand=$(basename $(dirname $(dirname "$window_path")))
                local method=$(basename $(dirname "$window_path"))
                local window=$(basename "$window_path")
                echo -e "  ${RED}✗${NC} $ligand/$method/$window"
            done
            echo ""
        fi
    fi
    
    echo -e "${BLUE}==========================================${NC}"
    
    if [ "$CONTINUOUS_MODE" = false ]; then
        echo "Run with --continuous for auto-refresh"
        echo "Example: $0 --continuous 30"
    fi
}

# Main loop
if [ "$CONTINUOUS_MODE" = true ]; then
    while true; do
        show_status
        sleep $REFRESH_INTERVAL
    done
else
    show_status
fi

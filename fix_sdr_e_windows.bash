#!/bin/bash
#==============================================================================
# Fix SDR E* Windows
# Version: 2.0
# Purpose: Fix electrostatic decoupling windows that have incorrect parameters
#
# Issues Fixed:
#   1. Incorrect crgmask residue numbers
#   2. Time step too large (dt)
#   3. Improper timask1/timask2 for ifsc=0
#   4. ntc/ntf mismatch
#==============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

get_ligand_residue() {
    # Get actual ligand residue number from topology
    local prmtop="$1"
    
    if [ ! -f "$prmtop" ]; then
        echo "0"
        return 1
    fi
    
    # Try to find ligand residue
    local lig_res=$(cpptraj -p "$prmtop" <<EOF 2>/dev/null | grep -E "FMM|LIG|MOL" | head -1 | awk '{print $1}'
parminfo
quit
EOF
)
    
    if [ -z "$lig_res" ]; then
        # Fallback: get last residue number
        lig_res=$(cpptraj -p "$prmtop" <<EOF 2>/dev/null | tail -1 | awk '{print $1}'
parminfo
quit
EOF
)
    fi
    
    echo "${lig_res:-0}"
}

fix_mdin_file() {
    local mdin_file="$1"
    local ligand_res="$2"
    
    if [ ! -f "$mdin_file" ]; then
        return 1
    fi
    
    # Backup original
    cp "$mdin_file" "${mdin_file}.backup"
    
    # Apply fixes
    # 1. Fix crgmask to actual ligand residue
    if [ "$ligand_res" != "0" ]; then
        sed -i "s/crgmask=':[0-9,]*'/crgmask=':${ligand_res}'/" "$mdin_file"
        sed -i "s/crgmask=\":[0-9,]*\"/crgmask=\":${ligand_res}\"/" "$mdin_file"
    fi
    
    # 2. Reduce time step if too large
    sed -i 's/dt = 0\.004/dt = 0.002/' "$mdin_file"
    sed -i 's/dt=0\.004/dt=0.002/' "$mdin_file"
    
    # 3. Remove timask1/timask2 for ifsc=0 windows
    if grep -q "ifsc.*=.*0" "$mdin_file"; then
        sed -i '/timask1=/d' "$mdin_file"
        sed -i '/timask2=/d' "$mdin_file"
    fi
    
    # 4. Ensure ntc=ntf for SHAKE
    if grep -q "ntc.*=.*2" "$mdin_file"; then
        sed -i 's/ntf.*=.*1/ntf=2/' "$mdin_file"
    fi
    
    return 0
}

clean_window_outputs() {
    # Clean corrupted output files
    local window_dir="$1"
    
    rm -f "${window_dir}"/md*.rst7
    rm -f "${window_dir}"/md*.nc
    rm -f "${window_dir}"/mdinfo
    rm -f "${window_dir}"/mden
    rm -f "${window_dir}"/md*.out
}

main() {
    print_header "SDR E* Window Fixer"
    
    # Check we're in the BAT directory
    if [ ! -d "fe" ]; then
        print_error "Please run from the BAT root directory (parent of fe/)"
        exit 1
    fi
    
    cd fe
    
    # Find all e* windows in SDR
    local e_windows=()
    for ligand_dir in lig-*/; do
        [ ! -d "$ligand_dir" ] && continue
        
        if [ -d "${ligand_dir}sdr" ]; then
            for window in "${ligand_dir}sdr"/e[0-9]*/ ; do
                [ ! -d "$window" ] && continue
                e_windows+=("$window")
            done
        fi
    done
    
    if [ ${#e_windows[@]} -eq 0 ]; then
        print_warning "No e* windows found in SDR method"
        exit 0
    fi
    
    print_success "Found ${#e_windows[@]} e* windows"
    
    # Ask for confirmation
    echo ""
    echo "This will:"
    echo "  1. Backup original mdin files"
    echo "  2. Fix crgmask with correct ligand residue"
    echo "  3. Reduce time step (dt → 0.002)"
    echo "  4. Remove timask1/timask2 for ifsc=0"
    echo "  5. Fix ntc/ntf mismatch"
    echo "  6. Clean corrupted output files"
    echo ""
    read -p "Proceed? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
    
    # Process each e* window
    local fixed=0
    local failed=0
    
    print_header "Processing e* windows..."
    
    for window in "${e_windows[@]}"; do
        echo "Processing: $window"
        
        # Get ligand residue number
        local prmtop="${window}full.prmtop"
        if [ ! -f "$prmtop" ]; then
            prmtop="${window}full.hmr.prmtop"
        fi
        
        local lig_res=$(get_ligand_residue "$prmtop")
        echo "  Ligand residue: $lig_res"
        
        # Fix all mdin files
        local success=true
        for mdin in "${window}"*.in; do
            if [ -f "$mdin" ]; then
                if fix_mdin_file "$mdin" "$lig_res"; then
                    echo "  Fixed: $(basename $mdin)"
                else
                    print_warning "  Failed to fix: $(basename $mdin)"
                    success=false
                fi
            fi
        done
        
        # Clean outputs
        clean_window_outputs "$window"
        echo "  Cleaned outputs"
        
        if [ "$success" = true ]; then
            fixed=$((fixed + 1))
            print_success "  Done: $window"
        else
            failed=$((failed + 1))
            print_error "  Failed: $window"
        fi
        
        echo ""
    done
    
    # Final report
    print_header "Fix Complete"
    print_success "Fixed windows: $fixed"
    if [ $failed -gt 0 ]; then
        print_warning "Failed windows: $failed"
    fi
    
    echo ""
    echo "Next steps:"
    echo "  1. Verify fixes: Check mdin files in e* windows"
    echo "  2. Run simulations: Use run_fep_all_gpus.bash"
    echo "  3. Monitor: Use monitor_sdr.bash"
}

main "$@"

#!/bin/bash
#==============================================================================
# BAT.py SDR Automation Scripts - Installation
# Version: 2.0
# Purpose: Install and verify SDR automation scripts
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

check_requirements() {
    print_header "Checking Requirements"
    
    local all_good=true
    
    # Check bash version
    if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
        print_success "Bash version: ${BASH_VERSION}"
    else
        print_error "Bash 4.0+ required, found: ${BASH_VERSION}"
        all_good=false
    fi
    
    # Check for required commands
    for cmd in find grep sed awk wc ps; do
        if command -v "$cmd" &> /dev/null; then
            print_success "Found: $cmd"
        else
            print_error "Missing: $cmd"
            all_good=false
        fi
    done
    
    # Check for nvidia-smi (optional but recommended)
    if command -v nvidia-smi &> /dev/null; then
        local gpu_count=$(nvidia-smi -L 2>/dev/null | wc -l)
        print_success "Found nvidia-smi: $gpu_count GPUs detected"
    else
        print_warning "nvidia-smi not found (GPU monitoring unavailable)"
    fi
    
    # Check for pmemd.cuda
    if command -v pmemd.cuda &> /dev/null; then
        print_success "Found pmemd.cuda: $(which pmemd.cuda)"
    else
        print_warning "pmemd.cuda not found (add to PATH before running)"
    fi
    
    # Check for cpptraj (needed by fixes)
    if command -v cpptraj &> /dev/null; then
        print_success "Found cpptraj: $(which cpptraj)"
    else
        print_warning "cpptraj not found (needed for fix scripts)"
    fi
    
    echo ""
    
    if [ "$all_good" = false ]; then
        print_error "Some requirements not met"
        return 1
    fi
    
    return 0
}

check_directory_structure() {
    print_header "Checking Directory Structure"
    
    # Check for BAT directory structure
    local has_equil=false
    local has_fe=false
    
    if [ -d "equil" ]; then
        has_equil=true
        print_success "Found equil/ directory"
    fi
    
    if [ -d "fe" ]; then
        has_fe=true
        print_success "Found fe/ directory"
    fi
    
    if [ "$has_equil" = false ] && [ "$has_fe" = false ]; then
        print_error "Not in a BAT directory (no equil/ or fe/ found)"
        echo "Please run from BAT root directory"
        return 1
    fi
    
    # Check for ligand directories
    local lig_count=0
    if [ -d "equil" ]; then
        lig_count=$(find equil -maxdepth 1 -name "lig-*" -type d 2>/dev/null | wc -l)
    fi
    
    if [ $lig_count -gt 0 ]; then
        print_success "Found $lig_count ligand directories in equil/"
    else
        print_warning "No ligand directories found in equil/"
    fi
    
    if [ -d "fe" ]; then
        lig_count=$(find fe -maxdepth 1 -name "lig-*" -type d 2>/dev/null | wc -l)
        if [ $lig_count -gt 0 ]; then
            print_success "Found $lig_count ligand directories in fe/"
        else
            print_warning "No ligand directories found in fe/"
        fi
    fi
    
    return 0
}

install_scripts() {
    print_header "Installing Scripts"
    
    # Make all scripts executable
    if [ -d "scripts" ]; then
        find scripts -name "*.bash" -exec chmod +x {} \;
        print_success "Made scripts executable"
    fi
    
    if [ -d "fixes" ]; then
        find fixes -name "*.bash" -exec chmod +x {} \;
        print_success "Made fix scripts executable"
    fi
    
    # Create log directories if they don't exist
    mkdir -p equil_logs
    mkdir -p fe_logs
    print_success "Created log directories"
    
    # Create checkpoint files
    touch equil_progress.txt
    touch fe_logs/active_gpus.txt
    touch fe_logs/completed.txt
    touch fe_logs/failed.txt
    print_success "Created tracking files"
    
    return 0
}

create_symlinks() {
    print_header "Creating Convenience Links"
    
    # Create symlinks for easy access
    if [ -f "scripts/equil/run_equil_all_gpus.bash" ]; then
        ln -sf scripts/equil/run_equil_all_gpus.bash run_equil.bash 2>/dev/null || true
        print_success "Created: run_equil.bash"
    fi
    
    if [ -f "scripts/fep/run_fep_all_gpus.bash" ]; then
        ln -sf scripts/fep/run_fep_all_gpus.bash run_fep.bash 2>/dev/null || true
        print_success "Created: run_fep.bash"
    fi
    
    if [ -f "scripts/monitoring/monitor_sdr.bash" ]; then
        ln -sf scripts/monitoring/monitor_sdr.bash monitor.bash 2>/dev/null || true
        print_success "Created: monitor.bash"
    fi
    
    if [ -f "fixes/fix_sdr_e_windows.bash" ]; then
        ln -sf fixes/fix_sdr_e_windows.bash fix_e_windows.bash 2>/dev/null || true
        print_success "Created: fix_e_windows.bash"
    fi
    
    return 0
}

show_next_steps() {
    print_header "Installation Complete!"
    
    echo ""
    echo "📚 Quick Start:"
    echo ""
    echo "  1. Run equilibration:"
    echo "     cd equil/ && ../scripts/equil/run_equil_all_gpus.bash"
    echo "     OR: ./run_equil.bash  (from BAT root)"
    echo ""
    echo "  2. Fix e* windows:"
    echo "     bash fixes/fix_sdr_e_windows.bash"
    echo "     OR: ./fix_e_windows.bash"
    echo ""
    echo "  3. Run FEP simulations:"
    echo "     cd fe/ && ../scripts/fep/run_fep_all_gpus.bash"
    echo "     OR: ./run_fep.bash  (from BAT root)"
    echo ""
    echo "  4. Monitor progress:"
    echo "     scripts/monitoring/monitor_sdr.bash --continuous"
    echo "     OR: ./monitor.bash --continuous"
    echo ""
    echo "📖 Documentation:"
    echo "     docs/README.md         - Complete guide"
    echo "     docs/QUICKSTART.md     - Quick reference"
    echo ""
    echo "🔗 Convenience scripts (from BAT root):"
    echo "     ./run_equil.bash       - Run equilibration"
    echo "     ./run_fep.bash         - Run FEP simulations"
    echo "     ./monitor.bash         - Monitor progress"
    echo "     ./fix_e_windows.bash   - Fix e* windows"
    echo ""
}

main() {
    print_header "BAT.py SDR Automation - Installer"
    
    echo "Version: 2.0 (SDR-specific)"
    echo "Installation directory: $(pwd)"
    echo ""
    
    # Run checks
    if ! check_requirements; then
        print_error "Requirements check failed"
        exit 1
    fi
    
    if ! check_directory_structure; then
        print_error "Directory structure check failed"
        exit 1
    fi
    
    # Install
    if ! install_scripts; then
        print_error "Installation failed"
        exit 1
    fi
    
    # Create symlinks
    create_symlinks
    
    # Show next steps
    show_next_steps
    
    print_success "Installation successful!"
}

main "$@"

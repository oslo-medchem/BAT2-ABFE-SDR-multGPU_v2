# Quick Start - BAT.py SDR Automation

Get running with SDR simulations in 5 minutes!

## ⚡ Installation (30 seconds)

```bash
# 1. Navigate to BAT directory
cd /path/to/BAT/

# 2. Extract package
unzip SDR_Scripts_Clean.zip

# 3. Run installer
bash install.bash
```

## 🚀 Running Simulations

### Step 1: Equilibration (30 minutes - 3 hours)

```bash
cd equil/
../scripts/equil/run_equil_all_gpus.bash
```

### Step 2: Fix E* Windows (1 minute)

```bash
cd ..
bash fixes/fix_sdr_e_windows.bash
```

###Step 3: FEP Simulations (2-7 days)

```bash
cd fe/
../scripts/fep/run_fep_all_gpus.bash
```

### Step 4: Monitor (continuous)

```bash
# In another terminal
cd /path/to/BAT/
scripts/monitoring/monitor_sdr.bash --continuous
```

## ✅ Expected Timeline

| Task | Time |
|------|------|
| Installation | 30 seconds |
| Equilibration | 3-6 hours |
| Fix e* windows | 1 minute |
| FEP simulations | 2-7 days |

## 📊 Monitor Output

```
========================================
SDR Simulation Monitor
========================================

GPU Status:
  GPU 0: Busy (4500 MB free)
  GPU 1: Busy (4300 MB free)
  ...

=== FEP Status ===
  Total windows: 528
    REST: 240 windows
    SDR:  288 windows
  ✓ Completed: 350
  Running: 8
  Pending: 170
  Progress: 66%
  [=========================               ] 66%
```

## 🔍 Common Commands

```bash
# Check equilibration status
ls equil_logs/*.log | wc -l

# Check FEP completion
grep -l "Total wall time" fe/lig-*/rest/*/md-02.out | wc -l
grep -l "Total wall time" fe/lig-*/sdr/*/md-02.out | wc -l

# Check GPU usage
nvidia-smi

# View specific window log
tail -f fe_logs/lig-fmm_rest_c00_gpu0.log

# Find failures
grep -l "Failed\|ERROR" fe_logs/*.log
```

## 🛑 Stop Everything

```bash
# Kill all jobs
pkill pmemd.cuda

# Verify stopped
ps aux | grep pmemd
```

## 📁 Output Files

```
After running:
├── equil_logs/
│   ├── lig-fmm.log
│   └── ...
├── fe_logs/
│   ├── lig-fmm_rest_c00_gpu0.log
│   ├── lig-fmm_sdr_e00_gpu1.log
│   └── ...
└── fe/
    └── lig-*/
        ├── rest/*/md-02.out  (completed)
        └── sdr/*/md-02.out   (completed)
```

## 🆘 Quick Fixes

### E* windows failing?
```bash
bash fixes/fix_sdr_e_windows.bash
```

### GPU out of memory?
```bash
# Edit scripts/fep/run_fep_all_gpus.bash
NUM_GPUS=4  # Use fewer GPUs
```

### Jobs not starting?
```bash
# Check permissions
find . -name "run-local.bash" -exec chmod +x {} \;

# Check PATH
which pmemd.cuda
```

### Need to restart?
```bash
# Scripts skip completed windows!
# Just rerun the same command
```

## 🎯 Success Criteria

**You're good when:**
- ✅ All 8 GPUs busy
- ✅ Jobs completing
- ✅ Progress increasing
- ✅ No failures (or very few)

**Check logs if:**
- ❌ Many failures (>10%)
- ❌ Jobs finish in seconds
- ❌ GPU OOM errors
- ❌ No progress

## 📚 Need Help?

- Full guide: `docs/README.md`
- Troubleshooting: `docs/TROUBLESHOOTING.md`
- Method details: `docs/SDR_METHOD.md`

---

**That's it! You should be running now.** 🚀

For detailed explanations, see `docs/README.md`

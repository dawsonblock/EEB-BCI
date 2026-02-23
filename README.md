# Boreal Neuro-Core

> **Version 4.1** — Advanced FPGA-based closed-loop neural interface architecture.

The **Boreal Neuro-Core** is a low-latency, highly optimized hardware engine designed for real-time bidirectional Brain-Computer Interfaces (BCI). Built natively in Verilog and targeted for Xilinx Artix-7 FPGAs, it integrates motor intent decoding, robotic inverse kinematics, and therapeutic Vagus Nerve Stimulation (VNS) into a unified, sub-millisecond pipeline.

## 🚀 Key Features

- **Active Inference Engine:** Uses stochastic gradient descent and Hebbian learning rules to dynamically map raw EEG signals to physical robotic states (`μ`). Features multi-stage DSP pipelining, temporal predictive coding (lag compensation), and mathematically saturated boundaries.
- **CORDIC Inverse Kinematics:** A fully unrolled, 16-iteration pipelined `atan2` engine using shift-and-add logic and pre-computed ROM. Calculates required joint angles (`θ1`, `θ2`) continuously without stalling the main pipeline.
- **Therapeutic VNS Bursting:** "Leaky Bucket" duty-cycle timing mechanism for targeted nerve stimulation, locked behind a strict **T-Wave cardiac guardrail** to theoretically eliminate physical risks during vulnerable heartbeat phases.
- **Robust SPI Interfacing:** Glitch-free, edge-detected SPI chain with internal 16-word FIFO buffering to decouple asynchronous biopotential front-ends (like the ADS1299) from the raw processing core.
- **Physical Hardening:** Features structural PWM glitch prevention, a 50ms hardware watchdog timer to recover from sensory disconnects, and a queryable status register file for live debug monitoring.

## 📂 Project Structure

```text
├── src/                # Core Verilog RTL modules (Boreal Core)
├── tb/                 # Icarus Verilog testbenches
├── scripts/            # LUT generation and auxiliary Python scripts
├── constraints/        # Physical XDC pin mappings for Artix-7 FPGAs
├── build/              # Generated simulation waveforms and synth logs
├── Makefile            # Central multi-threaded build system
└── .gitignore
```

## 🛠️ Build System

The project relies on a deeply integrated `Makefile` that handles linting, LUT generation, parallel simulation, and topological structural synthesis.

### Dependencies

- **Icarus Verilog (`iverilog` / `vvp`)**: For structural linting and testbench simulation.
- **Yosys**: Open-source synthesis suite for mapping to Xilinx cell primitives.
- **Python 3**: For generating mathematical look-up tables (`lut_gen.py`).

### Commands

```bash
# Run the full pipeline (Lint -> Synthesize -> Simulate)
make all

# Verify structural correctness and syntax
make lint

# Generate and view the hardware resource utilization report
make synth
make report

# Run all testbenches locally in parallel
make sim

# Clean transient build files
make clean
```

## 🧠 Core Architecture

Data flows into the core asynchronously via SPI. A dedicated `boreal_ad_guard` continuously monitors the real-time Heart-Rate Variability (HRV) and prediction errors (`ε`). If confidence drops below established thresholds, the structural AD-Guard forces the system into a fail-safe idle loop, immediately inhibiting physical movement and prioritizing biological safety over intent inference.

## 📜 License

This project is licensed under the standard repository license. See the `LICENSE` file for full details.

# Boreal Neuro-Core

> **Version 6.0** — Advanced FPGA-based closed-loop neural interface architecture (Layer 3 Expansion).

The **Boreal Neuro-Core** is a low-latency, highly optimized hardware engine designed for real-time bidirectional Brain-Computer Interfaces (BCI). Built natively in Verilog and targeted for Xilinx Artix-7 FPGAs, it integrates motor intent decoding, robotic inverse kinematics, and therapeutic Vagus Nerve Stimulation (VNS) into a unified, sub-millisecond pipeline.

## 🚀 Key Features

- **Advanced Active Inference Engine:** Uses stochastic gradient descent and Hebbian learning rules to dynamically map raw EEG signals to physical robotic states (`μ`). Features multi-stage DSP pipelining, temporal predictive coding (lag compensation), and absolute arithmetic saturation.
- **Deterministic Decision VM:** A 32-bit Micro-Instruction Set ROM providing programmable routing. It intercepts continuous inference signals and enforces safe fixed-coordinate outputs to the kinematics solvers.
- **Structured Safety Escalation:** A hardware-level 4-Tier safety state machine evaluating continuous biological signals (like AD distress) alongside watchdog timers to dynamically restrict motor geometry and force therapeutic timeouts.
- **Hardware Replay Buffer:** A 1024-deep x 48-bit wide telemetry ledger natively mapped to Artix-7 Block RAM to log continuous inference predictions and errors for non-blocking host-side diagnostics.
- **Multi-Channel EEG Fusion:** Parallel 8-channel array of IIR DC-blockers mapped to a spatial filter, enabling spatial signal diversity.
- **CORDIC Inverse Kinematics:** A 16-iteration unrolled pipeline resolving physical joint angles using a natively instantiated cosine lookup RAM to ensure mathematical determinism.
- **Robust SPI Interfacing:** Edge-detected asynchronous dual-clock FIFO buffering bridging continuous high-speed digital ingestion flawlessly with the computational clock domains.

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

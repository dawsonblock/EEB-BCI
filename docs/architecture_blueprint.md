# Deep Extraction — Boreal Neuro-Core (EEB-BCI)

## 1. System Identity

This repository is a hardware-first closed-loop neural interface implemented in Verilog for Artix-7 FPGA. It attempts to fuse:
 • EEG → intent decoding
 • Real-time control / inverse kinematics
 • Biological stimulation (VNS)
 • Hardware safety gating

All inside a deterministic, sub-millisecond pipeline.

This is not a generic BCI. It is a control engine: signal → decision → actuator → feedback.

⸻

## 2. Structural Architecture (Extracted)

### Data Path

```text
SPI (EEG / sensors)
   ↓
AD Guard (safety + confidence)
   ↓
Learning / Active Inference Engine
   ↓
CORDIC IK Solver
   ↓
PWM / Motor Output
   ↓
VNS Control (optional stimulation)
   ↓
Status + Watchdog
```

### Core Modules (from RTL)

| Module | Function |
|--------|----------|
| `boreal_top.v` | System integration / pipeline orchestration |
| `boreal_ad_guard.v` | Confidence + biological safety gate |
| `boreal_apex_core.v` | Active inference / decoding engine |
| `boreal_learning.v` | Hebbian / SGD adaptation |
| `boreal_cordic_ik.v` | Hardware inverse kinematics |
| `boreal_memory.v` | Internal state / weights |
| `boreal_spi_chain.v` + `spi_fifo` | EEG ingestion |
| `boreal_pwm_gen.v` | Motor / actuator output |
| `boreal_vns_control.v` | Vagus nerve stimulation |
| `boreal_watchdog.v` | Hard reset + fault recovery |
| `boreal_status_regs.v` | Telemetry / debug |

This is a fully pipelined hardware brainstem, not a high-level cognitive system.

⸻

## 3. Functional Capabilities

### A. Neural → Control Translation

The core uses predictive / active inference style learning:
 • Maps EEG features → motor state μ
 • Online adaptation via Hebbian + gradient
 • Temporal prediction / lag compensation

This is effectively a low-level brain → actuator decoder.

⸻

### B. Deterministic Hardware IK

CORDIC-based solver:
 • Fully pipelined
 • No floating point
 • Fixed latency
 • Continuous output

This enables direct robotic joint control from neural signals.

⸻

### C. Closed-Loop Neuromodulation

The VNS module:
 • Burst-based duty cycle control
 • Guarded by cardiac phase gate (T-wave)
 • Controlled stimulation timing

This is a neural therapy + control hybrid, rare in FPGA BCI builds.

⸻

### D. Safety Envelope

The AD-Guard enforces:
 • Confidence threshold
 • Error monitoring
 • Hard stop override
 • Biological safety priority

This resembles your hardware Gate philosophy.

⸻

## 4. Engineering Strengths

**Deterministic Latency**
Fully pipelined → no OS, no jitter → real-time control.

**Hardware Learning**
On-device adaptation avoids host CPU dependency.

**Closed-Loop Design**
Not just decode → also modulates nervous system.

**Safety-First Hardware Gate**
Rare in BCI systems; aligns with medical / robotics safety.

**Real Implementation (not theoretical)**
Verilog + testbenches + synthesis path → buildable.

⸻

## 5. Structural Weaknesses

**Limited Cognitive Depth**
This is brainstem-level, not cortex:
 • No symbolic reasoning
 • No planning
 • No memory hierarchy
 • No world model
It decodes signals. It does not think.

⸻

**Primitive Learning Model**
Hebbian + SGD:
 • No probabilistic modeling
 • No uncertainty tracking
 • No long-term adaptation
 • No feature abstraction
Performance ceiling: mid-tier motor decoding.

⸻

**No High-Level Control Loop**
Missing:
 • Planner
 • Decision logic
 • Policy engine
 • Safety reasoning beyond thresholds
It reacts, it does not decide.

⸻

**Fixed Architecture**
Hardwired:
 • IK dimensions fixed
 • Signal model fixed
 • No modular extension layer

⸻

**Biological Safety Claims Not Proven**
Cardiac guard concept exists, but:
 • No validated ECG sync model
 • No clinical fail-safe architecture
 • No redundant gating
Unsafe if used in real human stimulation without redesign.

⸻

## 6. What This System Is Actually Good At

**Strong domains**
 • Deterministic BCI control loop
 • Low-latency neural → actuator translation
 • Hardware neural decoding
 • Closed-loop stimulation experiments
 • Robotics brainstem controller
 • Embedded neural prosthetics prototype

**Weak domains**
 • Intelligence
 • Adaptive cognition
 • Long-term learning
 • Complex behavior
 • Autonomous reasoning

⸻

## 7. Capability Level

| Layer | Level |
|-------|-------|
| Signal decoding | Strong |
| Motor control | Strong |
| Learning | Basic |
| Intelligence | Minimal |
| Autonomy | Low |
| Safety | Structural but incomplete |

Equivalent to: hardware motor cortex + reflex loop, not a brain.

⸻

## 8. What Is Missing (Critical)

**Intelligence Layer**
 • Planner
 • Policy / decision VM
 • Goal modeling
 • State estimation

**Learning Upgrade**
 • Bayesian inference
 • Uncertainty estimation
 • Feature abstraction
 • Long-term plasticity

**System Architecture**
 • Deterministic memory hierarchy
 • Replay / training buffer
 • Sensor fusion
 • Multi-modal input

**Safety Upgrade**
 • Redundant gating
 • Verified stimulation envelope
 • Failure classification
 • Hardware ledger

**Expandability**
 • Modular pipeline
 • Instruction layer
 • External compute interface

⸻

## 9. Comparison to Your RFSN / Boreal Philosophy

This design is compatible with your architecture, but incomplete.

| This Repo | Your RFSN |
|-----------|-----------|
| Signal → action | Full decision stack |
| Reflex intelligence | Cognitive agent |
| Simple learning | Structured learning |
| Safety threshold | Hardware Gate |
| No ledger | Deterministic audit |
| Fixed behavior | Policy-driven |

This repo could become your neural input front-end.

⸻

## 10. Performance Ceiling

**Without upgrades:**
 • Moderate decoding accuracy
 • Stable deterministic latency
 • Limited adaptability
 • Not scalable to complex cognition

**With proper integration into your system:**
 • Could become hardware neural sensorimotor core
 • Feed deterministic agent
 • Enable true neural → AI → actuator loop

⸻

## 11. Risk Profile

**Engineering Risks**
 • Biological stimulation safety incomplete
 • Learning instability possible
 • No fault classification
 • No calibration pipeline

**Architectural Risks**
 • Hard to extend
 • No abstraction layer
 • Tight coupling between modules

⸻

## 12. What This Can Become (If Upgraded)

If merged into your broader architecture, this could serve as:
 • Neural sensor layer
 • Real-time brain → agent interface
 • Deterministic prosthetic controller
 • Closed-loop neuro-robotic core
 • Hybrid biological-AI control substrate

But only after adding intelligence + safety + learning layers.

⸻

---

# Deep Extraction — Layer 2 (RTL-Truth vs README Claims)

You’ve got a real, buildable FPGA pipeline here, but several “safety/biology/math” claims in the README don’t match what the RTL actually does.

### 1) What the top-level actually wires

`boreal_top.v` reality:

- SPI ingests 792 bits per transaction, asserts `spi_data_valid` for 1 cycle.
- Apex core uses only the lowest 24 bits: `raw_eeg_in = spi_data_payload[23:0]`.
- Learning runs whenever `spi_data_valid` is high (every sample).
- VNS triggers on `trigger_reward` from apex.
- PWM runs continuously off `theta_1`/`theta_2`.

**Major consequence:** There is no top-level safety cutout for motion. `ad_guard_active`, `safety_active`, and `wdt_fault` do not inhibit PWM.

### 2) SPI INGESTION

Hard-coded fixed payload size (792) handling only the lowest 24 bits. Silent failure if hardware mismatch occurs.

### 3) APEX CORE MATH

- **DC Blocker:** Coherent 1st-order high-pass.
- **Epsilon:** Observed minus Expected calculation directly uses LUT mapping incorrectly.
- **Temporal Lead (lag_comp):** 16-bit slice of 32-bit product is raw (Note: Fixed in v4.1 via `>>>`).
- **LUT ROM Index:** `mu_t[15:6]` wraps into high index range on negative values.

### 4) AD GUARD

Claim: Pearson correlation. Reality: Windowed covariance sum threshold with hard-coded means mapping directly to False Positives on shifted distributions.

### 5) INVERSE KINEMATICS (IK)

CORDIC `atan2` is real. `theta_2` (Law of Cosines elbow) is a crude placeholder linear expression missing division by `2*L1*L2` and missing the `acos` LUT mapping.

### 6) VNS

`ad_guard_active` input exists but is never used to gate stimulation.

### 7) WATCHDOG

Telemetry only. `wdt_fault` does not trigger system halt/reset in `boreal_top.v`.

⸻

## The Highest-Leverage Fixes (Actionable Layer 2 Plan)

### A) Hard safety cutouts at top level

Add a single `safe_to_move` wire and force PWM duty to 0 when false.

### B) Make watchdog actually reset state

Use `wdt_reset` to:

- reset `mu_t`, `mu_t_minus_1`
- freeze learning
- force PWM low

### C) Fix the AD guard

Implement an online exponential mean estimator (replace hardcoded `50` and `120`).

### D) Fix IK

Add a small LUT for `acos` and actually compute `cos(theta2) = (r^2 - L1^2 - L2^2) / (2 L1 L2)`.

### E) Fix Scaling in the "lead" term

Done (v4.1)

### F) LUT Index Sanitization

Add signed bias `mu_offset = mu_t + 16'sd32768` before indexing to prevent binary wrap.

---

# Layer 3 — Full System Expansion Plan (Hardware-Realistic)

## 1. Deterministic Decision-VM Layer

A micro-ISA Decision VM between Apex and IK.

- Fixed 32-bit instructions (MOV, CMP, JLT, JGT, SET, HALT, SCALE, SAT, REWARD).
- Enforces programmable behavior, goal-conditioned actuation, and policy versioning.

## 2. Multi-Channel EEG Fusion Block

Process 8 channels in parallel using IIR HP + energy accumulators into a weighted fusion sum.

## 3. Hardware Replay Buffer

1024-entry Block RAM circular buffer to record `mu_t`, `epsilon`, and `hrv` for post-hoc/host training.

## 4. Structured Safety Escalation

Replace flat `system_safe` with tiers:

- TIER 0: normal
- TIER 1: reduced speed
- TIER 2: motion freeze
- TIER 3: full halt + VNS disabled

---

# Layer 4 & 5 — Concrete RTL Artifacts

Provides skeletons for the Decision-VM, 8-channel EEG Fusion, Replay BRAM buffer, Fixed-Point Kalman State Estimator, Trajectory Generators, AXI-Lite bridges, and Boot Guard cryptographic hashing hardware.

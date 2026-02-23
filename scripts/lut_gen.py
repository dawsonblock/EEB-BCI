#!/usr/bin/env python3
"""
Boreal Neuro-Core v4.0
Script: lut_gen.py
Description: Generates a Look-Up Table (LUT) for the Sigmoid Activation Function
and its Derivative for the Boreal Active Inference hardware module.
Outputs a memory file suitable for synthesis.
"""

import math


def sigmoid(x: float) -> float:
    """Calculate standard sigmoid, avoiding math domain errors for extreme values."""
    if x < -10.0:
        return 0.0
    if x > 10.0:
        return 1.0
    return 1.0 / (1.0 + math.exp(-x))


def sigmoid_derivative(x: float) -> float:
    """Calculate the derivative of the sigmoid function."""
    s = sigmoid(x)
    return s * (1.0 - s)


def main() -> None:
    # LUT Configuration
    num_entries = 1024
    min_val = -8.0
    max_val = 8.0
    step = (max_val - min_val) / num_entries

    output_file = "sigmoid_lut.mem"

    print(f"Generating LUT: {num_entries} entries, Range [{min_val}, {max_val})")

    with open(output_file, "w") as f:
        # Write header info as Verilog comments
        f.write("// Boreal Neuro-Core v4.0 Sigmoid/Derivative LUT\n")
        f.write("// Format: 32-bit hex (Bits [31:16] = Derivative, [15:0] = Sigmoid)\n")
        f.write("// Value mapped using Q0.15 Fixed-Point notation.\n")

        for i in range(num_entries):
            x = min_val + i * step
            sig = sigmoid(x)
            sig_d = sigmoid_derivative(x)

            # Convert float to Q0.15 fixed-point integers
            sig_fixed = int(sig * 32767.0)
            sig_d_fixed = int(sig_d * 32767.0)

            # Pack: derivative in upper 16, sigmoid in lower 16
            val = (sig_d_fixed << 16) | (sig_fixed & 0xFFFF)

            # Write zero-padded 8-character hexadecimal
            f.write(f"{val:08X}\n")

    print(f"Successfully wrote {output_file}")


if __name__ == "__main__":
    main()

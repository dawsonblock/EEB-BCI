import math
import sys

# Generate a 256-word Look-Up Table for acos(x).
# Input x: cos(theta) mapped from [-1, 1] to [0, 255]
# Output theta: acos(x) in Q2.13 radians (0 to 3.14159 -> 0 to 25735)
try:
    with open("acos_lut.mem", "w") as f:
        for i in range(256):
            # Map index 0-255 back to cos(th) in [-1.0, 1.0]
            val = (i / 127.5) - 1.0
            # Clamp precision jitter to valid acos domain
            val = max(-1.0, min(1.0, val))

            # Compute acos(val) in radians
            theta_rad = math.acos(val)

            # Convert to Q2.13 fixed point
            theta_q13 = int(round(theta_rad * (2**13)))

            f.write(f"{theta_q13:04x}\n")
    print("[LUT] Successfully wrote acos_lut.mem")
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)

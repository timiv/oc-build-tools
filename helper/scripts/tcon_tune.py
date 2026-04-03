#!/usr/bin/env python3
"""
tcon_tune.py - Interactive TCON0 register tuning for Allwinner T113s / R528
Display: TJC3IPS480272 (480x272 RGB parallel panel)

Registers:
  0x05461040  TCON0_CTL   - bit 23: RB swap, bits [8:4]: start_delay
  0x05461088  TCON0_IO_POL - bits [30:28]: dclk_sel, bit 27: DE pol,
                              bit 26: clk_inv, bit 25: HSYNC pol, bit 24: VSYNC pol
  0x0546108C  TCON0_IO_TRI - bit 28: rgb_endian

DCLK phase combinations:
  Phase 0: clk_inv=0, dclk_sel=0  (rising edge, no delay)
  Phase 1: clk_inv=0, dclk_sel=2  (rising edge, 2/3 cycle delay)
  Phase 2: clk_inv=1, dclk_sel=0  (falling edge, no delay)
  Phase 3: clk_inv=1, dclk_sel=2  (falling edge, 2/3 cycle delay)

Keys:
  0-3   Set DCLK phase
  r     Toggle RB swap (CTL bit 23)
  d     Toggle DE polarity (IO_POL bit 27)
  h     Toggle HSYNC polarity (IO_POL bit 25)
  v     Toggle VSYNC polarity (IO_POL bit 24)
  e     Toggle RGB endian (IO_TRI bit 28)
  +/=   Increase start_delay (CTL bits [8:4], max 31)
  -     Decrease start_delay (CTL bits [8:4], min 0)
  p     Print current register state (decoded)
  q     Quit
"""

import sys
import os
import subprocess
import termios
import tty

TCON0_CTL     = 0x05461040
TCON0_IO_POL  = 0x05461088
TCON0_IO_TRI  = 0x0546108C

def devmem_read(addr):
    """Read a 32-bit register using devmem2."""
    try:
        out = subprocess.check_output(
            ["devmem2", hex(addr), "w"],
            stderr=subprocess.DEVNULL
        ).decode()
        # devmem2 output: "Value at address 0x...: 0x..."
        for line in out.splitlines():
            if "Value at address" in line or "Read at address" in line:
                parts = line.split(":")
                if len(parts) >= 2:
                    return int(parts[-1].strip(), 16)
        # fallback: last token
        return int(out.strip().split()[-1], 16)
    except Exception as e:
        print(f"\nERROR reading 0x{addr:08X}: {e}")
        return 0

def devmem_write(addr, value):
    """Write a 32-bit register using devmem2."""
    try:
        subprocess.check_output(
            ["devmem2", hex(addr), "w", hex(value)],
            stderr=subprocess.DEVNULL
        )
    except Exception as e:
        print(f"\nERROR writing 0x{addr:08X} = 0x{value:08X}: {e}")

def get_bits(val, hi, lo):
    mask = (1 << (hi - lo + 1)) - 1
    return (val >> lo) & mask

def set_bits(val, hi, lo, bits):
    mask = ((1 << (hi - lo + 1)) - 1) << lo
    return (val & ~mask) | ((bits << lo) & mask)

def set_bit(val, bit, on):
    if on:
        return val | (1 << bit)
    else:
        return val & ~(1 << bit)

def get_bit(val, bit):
    return (val >> bit) & 1

def decode_phase(clk_inv, dclk_sel):
    if clk_inv == 0 and dclk_sel == 0:
        return 0
    elif clk_inv == 0 and dclk_sel == 2:
        return 1
    elif clk_inv == 1 and dclk_sel == 0:
        return 2
    elif clk_inv == 1 and dclk_sel == 2:
        return 3
    else:
        return f"?(clk_inv={clk_inv}, dclk_sel={dclk_sel})"

PHASE_TABLE = {
    0: (0, 0),  # clk_inv, dclk_sel
    1: (0, 2),
    2: (1, 0),
    3: (1, 2),
}

def print_state(ctl, io_pol, io_tri):
    rb_swap     = get_bit(ctl, 23)
    start_delay = get_bits(ctl, 8, 4)

    dclk_sel    = get_bits(io_pol, 30, 28)
    de_pol      = get_bit(io_pol, 27)
    clk_inv     = get_bit(io_pol, 26)
    hsync_pol   = get_bit(io_pol, 25)
    vsync_pol   = get_bit(io_pol, 24)

    rgb_endian  = get_bit(io_tri, 28)

    phase = decode_phase(clk_inv, dclk_sel)

    print()
    print("=" * 50)
    print(f"  TCON0_CTL    (0x{TCON0_CTL:08X}) = 0x{ctl:08X}")
    print(f"  TCON0_IO_POL (0x{TCON0_IO_POL:08X}) = 0x{io_pol:08X}")
    print(f"  TCON0_IO_TRI (0x{TCON0_IO_TRI:08X}) = 0x{io_tri:08X}")
    print("-" * 50)
    print(f"  DCLK phase   : {phase}  (clk_inv={clk_inv}, dclk_sel={dclk_sel})")
    print(f"  start_delay  : {start_delay}")
    print(f"  RB swap      : {rb_swap}  ({'ON' if rb_swap else 'off'})")
    print(f"  DE polarity  : {de_pol}  ({'active low' if de_pol else 'active high'})")
    print(f"  HSYNC polarity: {hsync_pol}  ({'active low' if hsync_pol else 'active high'})")
    print(f"  VSYNC polarity: {vsync_pol}  ({'active low' if vsync_pol else 'active high'})")
    print(f"  RGB endian   : {rgb_endian}  ({'swapped' if rgb_endian else 'normal'})")
    print("=" * 50)

def print_help():
    print()
    print("Keys:")
    print("  0-3   Set DCLK phase (0=rise/no-delay, 1=rise/2-3delay, 2=fall/no-delay, 3=fall/2-3delay)")
    print("  r     Toggle RB swap (CTL bit 23)")
    print("  d     Toggle DE polarity (IO_POL bit 27)")
    print("  h     Toggle HSYNC polarity (IO_POL bit 25)")
    print("  v     Toggle VSYNC polarity (IO_POL bit 24)")
    print("  e     Toggle RGB endian (IO_TRI bit 28)")
    print("  +/=   Increase start_delay (max 31)")
    print("  -     Decrease start_delay (min 0)")
    print("  p     Print register state")
    print("  ?     This help")
    print("  q     Quit")

def getch():
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        ch = sys.stdin.read(1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
    return ch

def main():
    print("tcon_tune.py — TCON0 interactive register tuner")
    print("Reading current register values...")

    ctl     = devmem_read(TCON0_CTL)
    io_pol  = devmem_read(TCON0_IO_POL)
    io_tri  = devmem_read(TCON0_IO_TRI)

    print_state(ctl, io_pol, io_tri)
    print_help()
    print("\nPress a key (q to quit):")

    while True:
        ch = getch()

        if ch == 'q':
            print("\nBye. Final state:")
            ctl    = devmem_read(TCON0_CTL)
            io_pol = devmem_read(TCON0_IO_POL)
            io_tri = devmem_read(TCON0_IO_TRI)
            print_state(ctl, io_pol, io_tri)
            break

        elif ch in '0123':
            phase = int(ch)
            clk_inv, dclk_sel = PHASE_TABLE[phase]
            io_pol = devmem_read(TCON0_IO_POL)
            io_pol = set_bits(io_pol, 30, 28, dclk_sel)
            io_pol = set_bit(io_pol, 26, clk_inv)
            devmem_write(TCON0_IO_POL, io_pol)
            io_pol = devmem_read(TCON0_IO_POL)
            clk_inv_rb  = get_bit(io_pol, 26)
            dclk_sel_rb = get_bits(io_pol, 30, 28)
            print(f"\n  DCLK phase -> {phase}  (wrote clk_inv={clk_inv}, dclk_sel={dclk_sel}, readback: clk_inv={clk_inv_rb}, dclk_sel={dclk_sel_rb})")

        elif ch == 'r':
            ctl = devmem_read(TCON0_CTL)
            new_val = get_bit(ctl, 23) ^ 1
            ctl = set_bit(ctl, 23, new_val)
            devmem_write(TCON0_CTL, ctl)
            ctl = devmem_read(TCON0_CTL)
            print(f"\n  RB swap -> {get_bit(ctl, 23)}")

        elif ch == 'd':
            io_pol = devmem_read(TCON0_IO_POL)
            new_val = get_bit(io_pol, 27) ^ 1
            io_pol = set_bit(io_pol, 27, new_val)
            devmem_write(TCON0_IO_POL, io_pol)
            io_pol = devmem_read(TCON0_IO_POL)
            print(f"\n  DE polarity -> {get_bit(io_pol, 27)}")

        elif ch == 'h':
            io_pol = devmem_read(TCON0_IO_POL)
            new_val = get_bit(io_pol, 25) ^ 1
            io_pol = set_bit(io_pol, 25, new_val)
            devmem_write(TCON0_IO_POL, io_pol)
            io_pol = devmem_read(TCON0_IO_POL)
            print(f"\n  HSYNC polarity -> {get_bit(io_pol, 25)}")

        elif ch == 'v':
            io_pol = devmem_read(TCON0_IO_POL)
            new_val = get_bit(io_pol, 24) ^ 1
            io_pol = set_bit(io_pol, 24, new_val)
            devmem_write(TCON0_IO_POL, io_pol)
            io_pol = devmem_read(TCON0_IO_POL)
            print(f"\n  VSYNC polarity -> {get_bit(io_pol, 24)}")

        elif ch == 'e':
            io_tri = devmem_read(TCON0_IO_TRI)
            new_val = get_bit(io_tri, 28) ^ 1
            io_tri = set_bit(io_tri, 28, new_val)
            devmem_write(TCON0_IO_TRI, io_tri)
            io_tri = devmem_read(TCON0_IO_TRI)
            print(f"\n  RGB endian -> {get_bit(io_tri, 28)}")

        elif ch in ('+', '='):
            ctl = devmem_read(TCON0_CTL)
            delay = get_bits(ctl, 8, 4)
            if delay < 31:
                delay += 1
                ctl = set_bits(ctl, 8, 4, delay)
                devmem_write(TCON0_CTL, ctl)
                ctl = devmem_read(TCON0_CTL)
            print(f"\n  start_delay -> {get_bits(ctl, 8, 4)}")

        elif ch == '-':
            ctl = devmem_read(TCON0_CTL)
            delay = get_bits(ctl, 8, 4)
            if delay > 0:
                delay -= 1
                ctl = set_bits(ctl, 8, 4, delay)
                devmem_write(TCON0_CTL, ctl)
                ctl = devmem_read(TCON0_CTL)
            print(f"\n  start_delay -> {get_bits(ctl, 8, 4)}")

        elif ch == 'p':
            ctl    = devmem_read(TCON0_CTL)
            io_pol = devmem_read(TCON0_IO_POL)
            io_tri = devmem_read(TCON0_IO_TRI)
            print_state(ctl, io_pol, io_tri)

        elif ch == '?':
            print_help()

        else:
            print(f"\n  Unknown key: {repr(ch)}")

if __name__ == "__main__":
    main()

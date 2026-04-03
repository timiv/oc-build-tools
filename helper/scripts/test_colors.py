#!/usr/bin/env python3
import os
import sys
import mmap
import tty
import termios

FB = '/dev/fb0'

COLORS = {
    'r': ('red', 255, 0, 0),
    'g': ('green', 0, 255, 0),
    'b': ('blue', 0, 0, 255),
    'w': ('white', 255, 255, 255),
    'k': ('black', 0, 0, 0),
    'y': ('yellow', 255, 255, 0),
    'c': ('cyan', 0, 255, 255),
    'm': ('magenta', 255, 0, 255),
}


def read_int(path):
    with open(path, 'r') as f:
        return int(f.read().strip())


def read_wh(path):
    with open(path, 'r') as f:
        a, b = f.read().strip().split(',')
        return int(a), int(b)


def fb_info():
    w, h = read_wh('/sys/class/graphics/fb0/virtual_size')
    bpp = read_int('/sys/class/graphics/fb0/bits_per_pixel')
    stride_path = '/sys/class/graphics/fb0/stride'
    stride = read_int(stride_path) if os.path.exists(stride_path) else w * (bpp // 8)
    return w, h, bpp, stride


def pixel_bytes(r, g, b, bpp):
    if bpp == 16:
        px = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
        return px.to_bytes(2, 'little')
    if bpp == 32:
        px = (r << 16) | (g << 8) | b
        return px.to_bytes(4, 'little')
    raise RuntimeError(f'Unsupported bpp: {bpp}')


def fill_color(mm, stride, h, bpp, r, g, b):
    p = pixel_bytes(r, g, b, bpp)
    line = p * (stride // len(p))
    for y in range(h):
        off = y * stride
        mm[off:off + len(line)] = line
    mm.flush()


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
    if not os.path.exists(FB):
        print(f'Framebuffer not found: {FB}')
        return 1

    w, h, bpp, stride = fb_info()
    size = stride * h

    with open(FB, 'r+b', buffering=0) as f:
        mm = mmap.mmap(f.fileno(), size, access=mmap.ACCESS_WRITE)
        try:
            print(f'fb0: {w}x{h}, {bpp}bpp, stride={stride}')
            print('Keys: R G B W K Y C M   (Q to quit)')
            print('Press a key...')
            while True:
                ch = getch().lower()
                if ch == 'q':
                    print('\nquit')
                    return 0
                if ch in COLORS:
                    name, r, g, b = COLORS[ch]
                    fill_color(mm, stride, h, bpp, r, g, b)
                    print(f'\r{name:<8} RGB=({r:3},{g:3},{b:3})', end='', flush=True)
        finally:
            mm.close()


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print('\ninterrupted')
        raise SystemExit(0)

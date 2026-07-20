"""標準ライブラリのみの最小PNG入出力（8bit RGBA/RGB, 非インターレース）。
Pillow非依存。テスト用画像の生成と、Aseprite出力の検証に使う。"""
import struct
import zlib


def _chunk(typ, data):
    return (struct.pack(">I", len(data)) + typ + data +
            struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff))


def write_rgba(path, w, h, pixels):
    """pixels: (r,g,b,a) タプルの行優先(top-down)リスト、長さ w*h。"""
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)  # 8bit, colortype6=RGBA
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter None
        for x in range(w):
            r, g, b, a = pixels[y * w + x]
            raw += bytes((r & 255, g & 255, b & 255, a & 255))
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(sig + _chunk(b"IHDR", ihdr) + _chunk(b"IDAT", idat) + _chunk(b"IEND", b""))


def read(path):
    """returns (w, h, pixels) ; pixels は (r,g,b,a) の行優先(top-down)リスト。"""
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "PNG署名が不正"
    pos = 8
    w = h = bitd = ct = interlace = None
    idat = bytearray()
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        typ = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b"IHDR":
            w, h, bitd, ct, _comp, _filt, interlace = struct.unpack(">IIBBBBB", chunk)
        elif typ == b"IDAT":
            idat += chunk
        elif typ == b"IEND":
            break
    assert bitd == 8, "8bit深度のみ対応（bitd=%s）" % bitd
    assert interlace == 0, "非インターレースのみ対応"
    channels = {0: 1, 2: 3, 6: 4}.get(ct)
    assert channels, "未対応のカラータイプ %s" % ct
    raw = zlib.decompress(bytes(idat))
    stride = w * channels
    prev = bytearray(stride)
    pix = []
    p = 0
    for _y in range(h):
        ft = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = prev[i]
            c = prev[i - channels] if i >= channels else 0
            x = line[i]
            if ft == 0:
                v = x
            elif ft == 1:
                v = x + a
            elif ft == 2:
                v = x + b
            elif ft == 3:
                v = x + ((a + b) >> 1)
            elif ft == 4:
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                v = x + pr
            else:
                raise ValueError("未知のフィルタ %s" % ft)
            line[i] = v & 0xff
        prev = line
        for x in range(w):
            off = x * channels
            if channels == 4:
                pix.append((line[off], line[off + 1], line[off + 2], line[off + 3]))
            elif channels == 3:
                pix.append((line[off], line[off + 1], line[off + 2], 255))
            else:
                pix.append((line[off], line[off], line[off], 255))
    return w, h, pix

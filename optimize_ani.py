"""Optimize Windows .ani cursor files:
1. Extract a single target resolution (32, 48, or 64) to cut file size.
2. Fix non-premultiplied alpha edge pixels (R/G/B > A) to remove bright halos.
3. Optionally trim long loops (e.g. normal-cycle.ani -> 389 frames).
"""

import argparse
import json
import os
import struct


def fix_premult(img_data: bytes, w: int, h: int) -> bytes:
    hdr = img_data[:40]
    pix_len = w * h * 4
    pix = bytearray(img_data[40 : 40 + pix_len])
    mask = img_data[40 + pix_len :]
    for j in range(0, pix_len, 4):
        b, g, r, a = pix[j], pix[j + 1], pix[j + 2], pix[j + 3]
        if a == 0:
            if b or g or r:
                pix[j] = pix[j + 1] = pix[j + 2] = 0
        elif b > a or g > a or r > a:
            pix[j] = (b * a + 127) // 255
            pix[j + 1] = (g * a + 127) // 255
            pix[j + 2] = (r * a + 127) // 255
    return hdr + bytes(pix) + mask


def extract_and_fix_size(ic_bytes: bytes, target_size: int) -> bytes:
    reserved, itype, count = struct.unpack("<HHH", ic_bytes[:6])
    target_entry = None
    for i in range(count):
        entry = struct.unpack("<BBBBHHII", ic_bytes[6 + i * 16 : 6 + (i + 1) * 16])
        w, h = entry[0] or 256, entry[1] or 256
        if w == target_size and h == target_size:
            target_entry = entry
            break
    if target_entry is None:
        return ic_bytes
    w, h, cc, res, hx, hy, bsz, off = target_entry
    img_data = fix_premult(ic_bytes[off : off + bsz], w, h)
    new_header = struct.pack("<HHH", reserved, itype, 1)
    new_entry = struct.pack("<BBBBHHII", w, h, cc, res, hx, hy, len(img_data), 6 + 16)
    return new_header + new_entry + img_data


def make_chunk(cid: bytes, payload: bytes) -> bytes:
    pad = b"\x00" if (len(payload) & 1) else b""
    return cid + struct.pack("<I", len(payload)) + payload + pad


def optimize_ani(src_path: str, dst_path: str, target_size: int = 64, max_frames: int | None = None) -> None:
    with open(src_path, "rb") as f:
        data = f.read()
    anih = rate = seq = info_chunk = None
    icons = []

    def walk(start: int, end: int) -> None:
        nonlocal anih, rate, seq, info_chunk
        p = start
        while p + 8 <= end:
            cid = data[p : p + 4]
            csz = struct.unpack("<I", data[p + 4 : p + 8])[0]
            if cid == b"LIST":
                ltype = data[p + 8 : p + 12]
                if ltype == b"INFO":
                    info_chunk = data[p : p + 8 + csz + (csz & 1)]
                else:
                    walk(p + 12, min(end, p + 8 + csz))
            elif cid == b"RIFF":
                walk(p + 12, min(end, p + 8 + csz))
            elif cid == b"anih":
                anih = list(struct.unpack("<9I", data[p + 8 : p + 8 + 36]))
            elif cid == b"rate":
                cnt = csz // 4
                rate = list(struct.unpack(f"<{cnt}I", data[p + 8 : p + 8 + cnt * 4]))
            elif cid == b"seq ":
                cnt = csz // 4
                seq = list(struct.unpack(f"<{cnt}I", data[p + 8 : p + 8 + cnt * 4]))
            elif cid == b"icon":
                icons.append(data[p + 8 : p + 8 + csz])
            p += 8 + csz + (csz & 1)

    walk(12, len(data))

    if max_frames and len(icons) > max_frames:
        icons = icons[:max_frames]
        anih[1] = len(icons)
        if seq:
            seq = [s for s in seq if s < len(icons)] or list(range(len(icons)))
            anih[2] = len(seq)
        else:
            anih[2] = len(icons)
        if rate:
            rate = rate[: anih[2]]

    opt_icons = [extract_and_fix_size(ic, target_size) for ic in icons]
    fram_payload = b"fram" + b"".join(make_chunk(b"icon", ic) for ic in opt_icons)
    fram_list = make_chunk(b"LIST", fram_payload)

    body = bytearray()
    if info_chunk:
        body += info_chunk
    body += make_chunk(b"anih", struct.pack("<9I", *anih))
    if rate:
        body += make_chunk(b"rate", struct.pack(f"<{len(rate)}I", *rate))
    if seq:
        body += make_chunk(b"seq ", struct.pack(f"<{len(seq)}I", *seq))
    body += fram_list

    riff = b"RIFF" + struct.pack("<I", 4 + len(body)) + b"ACON" + bytes(body)
    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    with open(dst_path, "wb") as f:
        f.write(riff)


def main() -> None:
    parser = argparse.ArgumentParser(description="Optimize GrokBot .ani cursors")
    parser.add_argument("--src", required=True, help="Source folder containing Scheme.json")
    parser.add_argument("--dst", required=True, help="Output folder")
    parser.add_argument("--size", type=int, default=64, choices=[32, 48, 64], help="Target icon size")
    parser.add_argument("--normal-frames", type=int, default=389, help="Max frames for normal-cycle.ani")
    args = parser.parse_args()

    with open(os.path.join(args.src, "Scheme.json"), "r", encoding="utf-8") as f:
        scheme = json.load(f)

    for role, rel in scheme["Roles"].items():
        sp = os.path.join(args.src, rel)
        dp = os.path.join(args.dst, rel)
        max_f = args.normal_frames if rel.endswith("normal-cycle.ani") else None
        optimize_ani(sp, dp, target_size=args.size, max_frames=max_f)
        print(f"{role:12s}: {os.path.getsize(dp) / 1024:.1f} KB")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Inspect an Android APK/AAB without the Android SDK (docs/release-android.md).

Reports and checks:
  * package files present (manifest, dex, native libs per ABI, packaged client config, no tests);
  * 16 KB page-size readiness of 64-bit native libraries: every ELF LOAD segment aligned to 2**14
    (Google Play requirement for apps targeting API 35+ on 64-bit devices);
  * for APKs, whether 64-bit .so entries are stored uncompressed at 16 KB-aligned offsets (needed for
    direct loading; an AAB is re-packed by Play, so this is not checked for AABs).
Exit 1 when a check fails. Usage: check-artifact.py <file.apk|file.aab>
"""
import struct
import sys
import zipfile

ABIS_64 = ("arm64-v8a", "x86_64")


def load_aligns(data: bytes) -> list[int]:
    if data[:4] != b"\x7fELF":
        return []
    if data[4] == 2:  # 64-bit
        phoff = struct.unpack_from("<Q", data, 0x20)[0]
        phentsize, phnum = struct.unpack_from("<HH", data, 0x36)
        rows = [struct.unpack_from("<IIQQQQQQ", data, phoff + i * phentsize) for i in range(phnum)]
    else:
        phoff = struct.unpack_from("<I", data, 0x1C)[0]
        phentsize, phnum = struct.unpack_from("<HH", data, 0x2A)
        rows = [struct.unpack_from("<IIIIIIII", data, phoff + i * phentsize) for i in range(phnum)]
    return [r[7] for r in rows if r[0] == 1]


def main(path: str) -> int:
    z = zipfile.ZipFile(path)
    aab = path.endswith(".aab")
    prefix = "base/" if aab else ""
    names = z.namelist()
    problems: list[str] = []
    manifest = prefix + ("manifest/AndroidManifest.xml" if aab else "AndroidManifest.xml")
    for required in (manifest, prefix + "assets/config/client.json"):
        if required not in names:
            problems.append(f"missing {required}")
    if not any(n.startswith(prefix + ("dex/" if aab else "classes")) for n in names):
        problems.append("no dex code")
    leaked = [n for n in names if "/tests/" in n or "/tests_ui/" in n or "/tests_e2e/" in n or "addons/" in n]
    if leaked:
        problems.append(f"test/editor files packaged: {leaked[:3]}")
    libs = [i for i in z.infolist() if i.filename.startswith(prefix + "lib/") and i.filename.endswith(".so")]
    abis = sorted({i.filename.split("/")[-2] for i in libs})
    print(f"{path}: {'AAB' if aab else 'APK'}, {len(names)} entries, ABIs {abis}")
    if not any(a in abis for a in ABIS_64):
        problems.append("no 64-bit native libraries (Play requires arm64-v8a)")
    for info in libs:
        abi = info.filename.split("/")[-2]
        aligns = load_aligns(z.read(info.filename))
        ok16 = bool(aligns) and min(aligns) >= 16384
        line = f"  {info.filename}: LOAD align {sorted(set(aligns))} {'16KB-ok' if ok16 else 'NOT 16KB'}"
        if not aab:
            offset = info.header_offset + 30 + len(info.filename.encode()) + len(info.extra)
            stored = info.compress_type == zipfile.ZIP_STORED
            line += f", {'stored' if stored else 'compressed'}" + (f", offset%16384={offset % 16384}" if stored else "")
        print(line)
        if abi in ABIS_64 and not ok16:
            problems.append(f"{info.filename} is not 16 KB aligned (Play: apps targeting API 35+)")
    for p in problems:
        print(f"FAIL {p}")
    print("artifact check:", "FAILED" if problems else "passed")
    return 1 if problems else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))

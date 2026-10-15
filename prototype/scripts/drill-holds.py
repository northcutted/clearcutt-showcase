#!/usr/bin/env python3
"""Apply or release the CVE drill's package holds in the platform manifests.

    drill-holds.py apply|release|show PLATFORM_DIR

The holds (demo-script.md, Act 6), chosen while prototyping (FINDINGS.md W1):

  OpenSSL 3   libcrypto3, libssl3 = 3.6.3-r4 in every run image
              (CVE-2026-14456, High, fixed in 3.6.3-r5; release resolves 3.6.5-r2)
  libxml2     2.13.6-r3 (soname libxml2.so.2) in run-python and build-python,
              instead of libxml2-16 (soname libxml2.so.16, 2.15.x): an "ABI hold"

Each held line carries a "# DRILL hold" marker so the diff reads as a drill.
"""

import pathlib
import sys

MARK = "  # DRILL hold"

EDITS = {
    "images/_shared/run.yaml": [
        ("    - libcrypto3\n", f"    - libcrypto3=3.6.3-r4{MARK}: CVE-2026-14456 (High)\n"),
        ("    - libssl3\n", f"    - libssl3=3.6.3-r4{MARK}: CVE-2026-14456 (High)\n"),
    ],
    "images/run-python/image.yaml": [
        (
            "  packages: [python-3.14, libxml2-16]\n",
            f"  packages: [python-3.14, libxml2=2.13.6-r3]{MARK}: libxml2 2.13 (libxml2.so.2)\n",
        ),
    ],
    "images/build-python/image.yaml": [
        (
            "py3.14-setuptools, build-base, pkgconf, libxml2-dev]\n",
            "py3.14-setuptools, build-base, pkgconf,\n"
            f"             libxml2-dev=2.13.6-r3, libxml2=2.13.6-r3, libxml2-utils=2.13.6-r3]{MARK}: libxml2 2.13\n",
        ),
    ],
}


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in ("apply", "release", "show"):
        print(__doc__, file=sys.stderr)
        return 2
    action, root = sys.argv[1], pathlib.Path(sys.argv[2])
    held = 0
    for rel, edits in EDITS.items():
        p = root / rel
        text = p.read_text()
        for free, hold in edits:
            if action == "show":
                held += hold in text
                continue
            src, dst = (free, hold) if action == "apply" else (hold, free)
            if dst in text:
                continue  # already in the requested state
            if src not in text:
                print(f"{p}: expected text not found:\n{src}", file=sys.stderr)
                return 1
            text = text.replace(src, dst)
        if action != "show":
            p.write_text(text)
    if action == "show":
        total = sum(len(e) for e in EDITS.values())
        print("held" if held == total else "released" if held == 0 else f"partial ({held}/{total})")
    return 0


if __name__ == "__main__":
    sys.exit(main())

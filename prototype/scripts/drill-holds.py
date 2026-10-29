#!/usr/bin/env python3
"""Apply or release the drills' package holds in the platform manifests.

    drill-holds.py apply|release|show PLATFORM_DIR [SET]
    drill-holds.py vex-add|vex-remove|vex-show PLATFORM_DIR

SET picks the holds (default cve):

  cve        the first drill (demo-script.md, Act 6), chosen while
             prototyping (FINDINGS.md W1):
               OpenSSL 3  libcrypto3, libssl3 = 3.6.3-r4 in every run image
                          (CVE-2026-14456, High, fixed in 3.6.3-r5)
               libxml2    2.13.6-r3 (soname libxml2.so.2) in run-python and
                          build-python, instead of libxml2-16: an "ABI hold"
  toolchain  drill 2, act 1 (gap B): Go held at 1.27.2 in build-go, the
             toolchain of stack go:1. Go 1.27.2's standard library has
             GO-2026-6809 (CVE-2026-111943, crypto/x509 denylist; grype
             severity Unknown, so the Critical gate lets it through), fixed
             in 1.27.3. It reaches checkout's binary only by a rebuild.
  critical   drill 2, act 3: brotli held at 1.2.0-r3 in build-node, which
             has CVE-2026-111497 (Critical, fixed in 1.2.0-r7): the gate
             (failOn: critical, onlyFixed) refuses the image until a VEX
             statement (vex-add) covers it.

vex-add writes org/vex/drill.openvex.json, a security-owned statement that
CVE-2026-111497 doesn't affect the build-node image (scoped to that image
and its brotli packages), labelled as a drill statement, and lists it in
org/profile.yaml's vulnerabilities.vex; vex-remove takes both out again.

Each held line carries a "# DRILL hold" marker so the diff reads as a drill.
"""

import json
import pathlib
import sys

MARK = "  # DRILL hold"

SETS = {
    "cve": {
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
    },
    "toolchain": {
        "images/build-go/image.yaml": [
            (
                "  packages: [go-1.27, git]\n",
                f"  packages: [go-1.27=1.27.2-r0, git]{MARK}: Go 1.27.2, GO-2026-6809 (fixed in 1.27.3)\n",
            ),
        ],
    },
    "critical": {
        "images/build-node/image.yaml": [
            (
                "  packages: [nodejs-24, npm]\n",
                "  packages: [nodejs-24, npm,\n"
                "             libbrotlicommon1=1.2.0-r3, libbrotlidec1=1.2.0-r3, libbrotlienc1=1.2.0-r3]"
                f"{MARK}: brotli 1.2.0-r3, CVE-2026-111497 (Critical, fixed in 1.2.0-r7)\n",
            ),
        ],
    },
}

# The images each set holds packages in, and those packages (what
# lock --update-package re-resolves), for drill-github.sh.
IMAGES = {
    "cve": ["run-go", "run-python", "run-node", "build-python"],
    "toolchain": ["build-go"],
    "critical": ["build-node"],
}
PACKAGES = {
    "cve": ["libcrypto3", "libssl3", "libxml2", "libxml2-16", "libxml2-dev", "libxml2-utils"],
    "toolchain": ["go-1.27"],
    "critical": ["libbrotlicommon1", "libbrotlidec1", "libbrotlienc1"],
}

VEX_FILE = "org/vex/drill.openvex.json"
VEX_LIST = ("  vex: [vex/catalog.openvex.json]\n", "  vex: [vex/catalog.openvex.json, vex/drill.openvex.json]\n")
VEX_DOC = {
    "@context": "https://openvex.dev/ns/v0.2.0",
    "@id": "https://github.com/northcutted/clearcutt-showcase-platform/blob/main/org/vex/drill.openvex.json",
    "author": "clearcutt-showcase security (platform repository, org/vex/): DRILL statement, removed when drill 2 ends",
    "timestamp": "2026-10-29T00:00:00Z",
    "version": 1,
    "statements": [
        {
            "vulnerability": {
                "name": "CVE-2026-111497",
                "description": "brotli: a Critical decoder flaw (DRILL: the hold in build-node is deliberate)",
            },
            "products": [
                {
                    "@id": "pkg:oci/build-node?repository_url=ghcr.io/northcutted/clearcutt-showcase/platform/build-node",
                    "subcomponents": [
                        {"@id": "pkg:apk/wolfi/libbrotlicommon1"},
                        {"@id": "pkg:apk/wolfi/libbrotlidec1"},
                        {"@id": "pkg:apk/wolfi/libbrotlienc1"},
                    ],
                }
            ],
            "status": "not_affected",
            "justification": "vulnerable_code_not_in_execute_path",
            "impact_statement": (
                "DRILL (showcase drill 2, act 3; bringup/DRILL-RESULTS.md): not a real triage. "
                "The statement exists to show a Critical that fails the gate, a security-owned "
                "VEX statement that lets one image past it, and that suppression in the "
                "vulnerability attestation, the estate report, and the portal. Scoped to the "
                "build-node image and its brotli packages; every other image still reports "
                "CVE-2026-111497. Removed, with the brotli hold, when the drill ends."
            ),
        }
    ],
}


def holds(action: str, root: pathlib.Path, name: str) -> int:
    edits_by_file = SETS[name]
    held = 0
    for rel, edits in edits_by_file.items():
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
        total = sum(len(e) for e in edits_by_file.values())
        print("held" if held == total else "released" if held == 0 else f"partial ({held}/{total})")
    return 0


def vex(action: str, root: pathlib.Path) -> int:
    doc, profile = root / VEX_FILE, root / "org/profile.yaml"
    text = profile.read_text()
    without, with_drill = VEX_LIST
    if action == "vex-show":
        print("present" if doc.exists() and with_drill in text else "absent" if not doc.exists() and without in text else "partial")
        return 0
    if action == "vex-add":
        doc.write_text(json.dumps(VEX_DOC, indent=2) + "\n")
        src, dst = without, with_drill
    else:
        doc.unlink(missing_ok=True)
        src, dst = with_drill, without
    if dst not in text:
        if src not in text:
            print(f"{profile}: expected text not found:\n{src}", file=sys.stderr)
            return 1
        profile.write_text(text.replace(src, dst))
    return 0


def main() -> int:
    args = sys.argv[1:]
    if len(args) == 2 and args[0] in ("vex-add", "vex-remove", "vex-show"):
        return vex(args[0], pathlib.Path(args[1]))
    if len(args) == 3 and args[0] in ("images", "packages") and args[2] in SETS:
        print(" ".join((IMAGES if args[0] == "images" else PACKAGES)[args[2]]))
        return 0
    if len(args) not in (2, 3) or args[0] not in ("apply", "release", "show") or (len(args) == 3 and args[2] not in SETS):
        print(__doc__, file=sys.stderr)
        return 2
    return holds(args[0], pathlib.Path(args[1]), args[2] if len(args) == 3 else "cve")


if __name__ == "__main__":
    sys.exit(main())

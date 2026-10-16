"""Build catalog._feeds, a C extension linked against the system libxml2.

pyproject.toml carries the metadata; this file only declares the extension,
whose flags come from pkg-config (libxml2-dev in the stack's build image).
"""

import shlex
import subprocess

from setuptools import Extension, setup


def pkg_config(*args: str) -> list[str]:
    out = subprocess.run(["pkg-config", *args, "libxml-2.0"], check=True, capture_output=True, text=True)
    return shlex.split(out.stdout)


cflags = pkg_config("--cflags")
libs = pkg_config("--libs")

setup(
    ext_modules=[
        Extension(
            "catalog._feeds",
            sources=["catalog/_feeds.c"],
            include_dirs=[f[2:] for f in cflags if f.startswith("-I")],
            library_dirs=[f[2:] for f in libs if f.startswith("-L")],
            libraries=[f[2:] for f in libs if f.startswith("-l")],
        )
    ]
)

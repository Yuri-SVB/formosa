#!/usr/bin/env python3
import os
from setuptools import setup

CWD = os.path.dirname(os.path.realpath(__file__))


def read(*path: str) -> str:
    filename = os.path.join(CWD, *path)
    with open(filename, "r", encoding="utf-8") as f:
        return f.read()


setup(
    name="formosa",
    version="0.1.0",
    author="Yuri S Villas Boas, André Fidencio Gonçalves",
    author_email="yurisvb@pm.me",
    description="Formosa: seed encoding by themed mnemonic sentences (BIP-450)",
    long_description=read("README.md"),
    long_description_content_type="text/markdown",
    url="https://github.com/Yuri-SVB/formosa",
    # The package lives under src/, which setuptools is not told by the layout alone
    package_dir={"": "src"},
    packages=["mnemonic"],
    # The themes are the word lists; without them an installed package cannot
    #  build or read a single mnemonic
    package_data={"mnemonic": ["themes/*.json", "py.typed"]},
    include_package_data=True,
    zip_safe=False,
    python_requires=">=3.9",
    license="MIT",
    classifiers=[
        "License :: OSI Approved :: MIT License",
        "Operating System :: POSIX :: Linux",
        "Operating System :: Microsoft :: Windows",
        "Operating System :: MacOS :: MacOS X",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Topic :: Security :: Cryptography",
    ],
)

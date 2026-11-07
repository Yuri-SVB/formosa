#!/usr/bin/env python3
import os
from setuptools import setup
from setuptools.command.build_py import build_py

CWD = os.path.dirname(os.path.realpath(__file__))


def read(*path: str) -> str:
    filename = os.path.join(CWD, *path)
    with open(filename, "r", encoding="utf-8") as f:
        return f.read()


class BuildWithThemes(build_py):
    """ Ships the repository's themes/ folder inside the package, where an installed module looks"""

    def run(self):
        super().run()
        themes = os.path.join(CWD, "..", "themes")
        target = os.path.join(self.build_lib, "mnemonic", "themes")
        self.mkpath(target)
        # The themes only: not their authoring files (edit/) or templates
        for name in sorted(os.listdir(themes)):
            if name.endswith(".json"):
                self.copy_file(os.path.join(themes, name), os.path.join(target, name))


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
    package_data={"mnemonic": ["py.typed"]},
    cmdclass={"build_py": BuildWithThemes},
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

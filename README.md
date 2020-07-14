# my-MSYS2-packages

Package scripts for MSYS2.

To build these, run msys2_shell.cmd then from the bash prompt. Packages from
the msys2-devel and base-devel groups are implicit build time dependencies.
Make sure both are installed before attempting to build any package:

    pacman -S --needed base-devel msys2-devel
    cd ${package-name}
    makepkg

To install the built package(s).

    pacman -U ${package-name}*.pkg.tar.xz

## License

MSYS2-packages is licensed under BSD 3-Clause "New" or "Revised" License.
A full copy of the license is provided in [LICENSE](LICENSE).

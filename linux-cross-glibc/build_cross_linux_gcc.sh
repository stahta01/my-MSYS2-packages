#-------------------------------------------------------------------------------------------
# This script will download packages for, configure, build and install a GCC cross-compiler.
#
# Forked from: https://gist.github.com/preshing/41d5c7248dea16238b60
#-------------------------------------------------------------------------------------------

TARGET=$1
INSTALL_PATH=$2
export PATH=$INSTALL_PATH/bin:$PATH
PARALLEL_MAKE=-j2
CONFIGURATION_OPTIONS="--disable-multilib --enable-shared --enable-threads"
MAJOR_KERNEL_VERSION=5
LINUX_KERNEL_VERSION=linux-$MAJOR_KERNEL_VERSION.5
BINUTILS_VERSION=binutils-2.34
GCC_VERSION=gcc-10.2.0
GLIBC_VERSION=glibc-2.32
MPFR_VERSION=mpfr-3.1.4
GMP_VERSION=gmp-6.1.2
MPC_VERSION=mpc-1.0.3
ISL_VERSION=isl-0.22

extract() {
    local tarfile="$1"
    local extracted="$(echo "$tarfile" | sed 's/\.tar.*$//')"
    if [ ! -d  "src/xscript/$extracted" ]; then
        echo "Extracting ${tarfile}"
        mkdir -p "src/xscript"
        tar -xf $tarfile -C src/xscript
    fi
}

extract_to_gcc_folder() {
    local tarfile="$1"
    local subfolder="$(echo "$tarfile" | sed 's/-.*$//')"
    if [ ! -d  "src/xscript/$GCC_VERSION/$subfolder" ]; then
        echo "Extracting ${tarfile} to src/xscript/$GCC_VERSION/$subfolder"
        mkdir -p "src/xscript/$GCC_VERSION/$subfolder"
        tar -x --strip-components=1 -f "$tarfile" -C "src/xscript/$GCC_VERSION/$subfolder"
    fi
}

# Download packages
export http_proxy=$HTTP_PROXY https_proxy=$HTTP_PROXY ftp_proxy=$HTTP_PROXY
wget -nc https://ftp.gnu.org/gnu/binutils/$BINUTILS_VERSION.tar.gz
wget -nc https://ftp.gnu.org/gnu/gcc/$GCC_VERSION/$GCC_VERSION.tar.gz
wget -nc https://www.kernel.org/pub/linux/kernel/v$MAJOR_KERNEL_VERSION.x/$LINUX_KERNEL_VERSION.tar.xz
wget -nc https://ftp.gnu.org/gnu/glibc/$GLIBC_VERSION.tar.xz
wget -nc https://ftp.gnu.org/gnu/mpfr/$MPFR_VERSION.tar.xz
wget -nc https://ftp.gnu.org/gnu/gmp/$GMP_VERSION.tar.xz
wget -nc https://ftp.gnu.org/gnu/mpc/$MPC_VERSION.tar.gz
wget -nc http://isl.gforge.inria.fr/$ISL_VERSION.tar.bz2

# Extract packages
extract                     $BINUTILS_VERSION.tar.gz
extract                     $GCC_VERSION.tar.gz
extract_to_gcc_folder       $MPFR_VERSION.tar.xz
extract_to_gcc_folder       $GMP_VERSION.tar.xz
extract_to_gcc_folder       $MPC_VERSION.tar.gz
extract_to_gcc_folder       $ISL_VERSION.tar.bz2
extract                     $LINUX_KERNEL_VERSION.tar.xz || true
extract                     $GLIBC_VERSION.tar.xz || true
cp src/xscript/$GLIBC_VERSION/benchtests/strcoll-inputs/filelist#en_US.UTF-8 src/xscript/$GLIBC_VERSION/benchtests/strcoll-inputs/filelist#C

cd src/xscript

# Step 1. Binutils
mkdir -p build-$TARGET-binutils
cd build-$TARGET-binutils
../$BINUTILS_VERSION/configure --prefix=$INSTALL_PATH --target=$TARGET $CONFIGURATION_OPTIONS
make $PARALLEL_MAKE
make install
cd ..

# Step 2. Linux Kernel Headers
_target=$TARGET
if [ "${_target}" = "aarch64-linux-gnu" ]; then
  _target_arch='arm64'
fi
if [ "${_target}" = "riscv64-linux-gnu" ]; then
  _target_arch='riscv'
fi
if [ "${_target}" = "x86_64-pc-linux-gnu" ]; then
  _target_arch='x86_64'
fi
cd $LINUX_KERNEL_VERSION
make ARCH=$_target_arch INSTALL_HDR_PATH=$INSTALL_PATH/$TARGET headers_install
cd ..

# Step 3. C/C++ Compilers
mkdir -p build-$TARGET-gcc
cd build-$TARGET-gcc
../$GCC_VERSION/configure --prefix=$INSTALL_PATH --target=$TARGET --enable-languages=c,c++ --disable-libsanitizer $CONFIGURATION_OPTIONS
make $PARALLEL_MAKE all-gcc
make install-gcc
cd ..

# Step 4. Standard C Library Headers and Startup Files
cd $GLIBC_VERSION
# Replace "oS" with "oZ" to avoid filename clashes
sed -i 's/.oS)/.oZ)/g; s/.oS$/.oZ/g; s/.oS =/.oZ =/g'       Makeconfig
sed -i 's/.oS,/.oZ,/g; s/.oS +=/.oZ +=/g; s/.oS)/.oZ)/g'    Makerules 
sed -i 's/.oS)/.oZ)/g; s/.oS,/.oZ,/g'                       extra-lib.mk        
sed -i 's/.oS)/.oZ)/g'                                      nptl/Makefile
sed -i 's/.oS +=/.oZ +=/g'                                  csu/Makefile
sed -i 's/.oS +=/.oZ +=/g'                                  sysdeps/i386/i686/Makefile
sed -i 's/.oS,/.oZ,/g'                                      sysdeps/ieee754/ldbl-opt/Makefile
sed -i 's/.oS +=/.oZ +=/g'                                  sysdeps/sparc/sparc32/sparcv9/Makefile
sed -i 's/.oS +=/.oZ +=/g'                                  sysdeps/sparc/sparc64/Makefile
sed -i 's/.oS +=/.oZ +=/g'                                  sysdeps/unix/sysv/linux/mips/Makefile
sed -i 's/.oS +=/.oZ +=/g'                                  sysdeps/x86/Makefile
sed -i 's/,oS}/,oZ}/g'                                      scripts/check-local-headers.sh
# use copy because the rellns-sh has issues under msys2
sed -i 's|$(LN_S) `$(..)scripts/rellns-sh -p $< $@` $@|cp -p $< $@|' Makerules
cd ..
mkdir -p build-$TARGET-glibc
cd build-$TARGET-glibc
../$GLIBC_VERSION/configure --prefix=$INSTALL_PATH/$TARGET --build=$MACHTYPE --host=$TARGET --target=$TARGET --with-headers=$INSTALL_PATH/$TARGET/include $CONFIGURATION_OPTIONS libc_cv_forced_unwind=yes
make install-bootstrap-headers=yes install-headers
make $PARALLEL_MAKE csu/subdir_lib
install csu/crt1.o csu/crti.o csu/crtn.o $INSTALL_PATH/$TARGET/lib
$TARGET-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o $INSTALL_PATH/$TARGET/lib/libc.so
touch $INSTALL_PATH/$TARGET/include/gnu/stubs.h
cd ..

# Step 5. Compiler Support Library
cd build-$TARGET-gcc
make $PARALLEL_MAKE all-target-libgcc
make install-target-libgcc
cd ..

# Step 6. Standard C Library & the rest of Glibc
cd build-$TARGET-glibc
make $PARALLEL_MAKE
make install
cd ..

# Step 7. Standard C++ Library & the rest of GCC
cd build-$TARGET-gcc
make $PARALLEL_MAKE all
make install
cd ..

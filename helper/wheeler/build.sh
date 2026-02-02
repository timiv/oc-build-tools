#!/bin/bash
if [ -z $STAGING_DIR ]; then
  echo "STAGING_DIR not set"
  exit -1
fi 

PYTHON_EXE=$STAGING_DIR/hostpkg/bin/python3

# See entware-packages/lang/pyton/python-package.mk
export PATH="$STAGING_DIR/toolchain-arm_cortex-a9_gcc-8.4.0_glibc-2.27_eabi/bin:$STAGING_DIR/hostpkg/bin:$PATH"
export CC="arm-openwrt-linux-gnueabi-gcc"
export CCSHARED="arm-openwrt-linux-gnueabi-gcc -DPIC -fpic"
export CXX="arm-openwrt-linux-gnueabi-g++"
export LD="arm-openwrt-linux-gnueabi-gcc"
export LDSHARED="arm-openwrt-linux-gnueabi-gcc -shared"
export CFLAGS="-O2 -pipe -mtune=cortex-a9 -fno-caller-saves -fhonour-copts -mfloat-abi=soft"
export CPPFLAGS="-I$STAGING_DIR/toolchain-arm_cortex-a9_gcc-8.4.0_glibc-2.27_eabi/usr/include -I$STAGING_DIR/toolchain-arm_cortex-a9_gcc-8.4.0_glibc-2.27_eabi/include -I$STAGING_DIR/target-arm_cortex-a9_glibc-2.27_eabi/opt/include -I$STAGING_DIR/target-arm_cortex-a9_glibc-2.27_eabi/opt/include/python3.11" 
export LDFLAGS="-Wl,--dynamic-linker=/opt/lib/ld-linux.so.3 -Wl,-rpath=/opt/lib -L$STAGING_DIR/toolchain-arm_cortex-a9_gcc-8.4.0_glibc-2.27_eabi/usr/lib -L$STAGING_DIR/toolchain-arm_cortex-a9_gcc-8.4.0_glibc-2.27_eabi/lib -fuse-ld=bfd -L$STAGING_DIR/target-arm_cortex-a9_glibc-2.27_eabi/opt/lib -lpython3.11" 
export _PYTHON_HOST_PLATFORM="linux-armv7l" #"linux-arm" 
export _PYTHON_SYSCONFIGDATA_NAME="_sysconfigdata__linux_arm-linux-gnueabi" 
export PYTHONPATH="$STAGING_DIR/target-arm_cortex-a9_glibc-2.27_eabi/opt/lib/python3.11:$STAGING_DIR/target-arm_cortex-a9_glibc-2.27_eabi/opt/lib/python3.11/site-packages"
export PYTHONDONTWRITEBYTECODE=1 
export _python_sysroot="$STAGING_DIR/target-arm_cortex-a9_glibc-2.27_eabi" 
export _python_prefix="/opt" 
export _python_exec_prefix="/opt" 
export CARGO_HOME=$STAGING_DIR/target-arm_cortex-a9_glibc-2.27_eabi/host/share/cargo 
export CARGO_BUILD_RUSTFLAG="-C relocation-model=static -C link-args=-Wl,-rpath,/opt/lib -C relocation-model=static -C link-args=-Wl,-rpath,/opt/lib" 
export CARGO_BUILD_TARGET=armv7-openwrt-linux-gnueabi 
export CC=arm-openwrt-linux-gnueabi-gcc 
export CXX="arm-openwrt-linux-gnueabi-g++" 
export TARGET_CC="arm-openwrt-linux-gnueabi-gcc"
export TARGET_CXX="arm-openwrt-linux-gnueabi-g++"
export TARGET_CFLAGS="-O2 -pipe -mtune=cortex-a9 -fno-caller-saves -fhonour-copts -mfloat-abi=soft -I$STAGING_DIR/toolchain-arm_cortex-a9_gcc-8.4.0_glibc-2.27_eabi/usr/include -I$STAGING_DIR/toolchain-arm_cortex-a9_gcc-8.4.0_glibc-2.27_eabi/include -I$STAGING_DIR/target-arm_cortex-a9_glibc-2.27_eabi/opt/include -I$STAGING_DIR/target-arm_cortex-a9_glibc-2.27_eabi/opt/include" 
export TARGET_CXXFLAGS="-O2 -pipe -mtune=cortex-a9 -fno-caller-saves -fhonour-copts -mfloat-abi=soft -I$STAGING_DIR/toolchain-arm_cortex-a9_gcc-8.4.0_glibc-2.27_eabi/usr/include -I$STAGING_DIR/toolchain-arm_cortex-a9_gcc-8.4.0_glibc-2.27_eabi/include -I$STAGING_DIR/target-arm_cortex-a9_glibc-2.27_eabi/opt/include -I$STAGING_DIR/target-arm_cortex-a9_glibc-2.27_eabi/opt/include" 
export PYO3_CROSS_LIB_DIR="$STAGING_DIR/target-arm_cortex-a9_glibc-2.27_eabi/opt/lib/python3.11" 
export SETUPTOOLS_RUST_CARGO_PROFILE="sstrip"

#export PYTHONPATH="$PYTHON_PATH:.venv/lib/python3.11/site-packages"


# Builds wheels with pip
# Args: additional parameters to pass to pip wheel, e.g. build_wheels("-r", "requirements.txt")
function build_wheels() {
	$PYTHON_EXE \
		-m pip \
		wheel \
		--wheel-dir wheels \
		--no-build-isolation \
		"$@"
}

#echo "Building meson-python"
#build_wheels "meson-python<1.0.0"

echo "Building numpy"
build_wheels "numpy"

# We need to prebuild pillow as not all libs are available
echo "Building pillow"
build_wheels "pillow<11.0.0" -C lcms=disable -C jpeg2000=disable -C imagequant=disable -C platform-guessing=disable

echo "Building requirements for klippy"
build_wheels -r klippy-requirements.txt

echo "Building requirements for moonraker"
build_wheels -r moonraker-requirements.txt -C lcms=disable -C jpeg2000=disable -C imagequant=disable -C platform-guessing=disable

#echo "Building requirements for Klipper Screen"
#build_wheels -r KlipperScreen-requirements.txt

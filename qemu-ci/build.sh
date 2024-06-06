#!/bin/bash

set -uo pipefail
set -e
set -vx

git clone --depth=1 -b aspeed-9.1 https://github.com/legoater/qemu.git
cd qemu
export CC="ccache gcc"
export CXX="ccache g++"
./configure --target-list=arm-softmmu --prefix=$(pwd)/install
make -j $(grep -c processor /proc/cpuinfo) install
cd ..

./aspeed-boot.sh -q --prefix=qemu/install/

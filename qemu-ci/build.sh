#!/bin/bash

branch="aspeed-9.2"

set -uo pipefail
set -e
set -vx

git clone --depth=1 -b $branch https://github.com/legoater/qemu.git
cd qemu
export CC="ccache gcc"
export CXX="ccache g++"
./configure --target-list=arm-softmmu,aarch64-softmmu --prefix=$(pwd)/install
make -j $(grep -c processor /proc/cpuinfo) install
cd ..

./aspeed-boot.sh -q --prefix=qemu/install/

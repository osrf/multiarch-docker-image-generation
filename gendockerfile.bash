#!/bin/bash

ARCH="${ARCH:-linux/arm64}"
DISTRO="${DISTRO:-ubuntu}"
CODENAME="${CODENAME:-jammy}"
QEMU_STATIC_BIN="${QEMU_STATIC_BIN:-qemu-aarch64-static}"

cat > "${DISTRO}-${CODENAME}-${ARCH#linux/}.dockerfile" <<DOCKERFILE
FROM --platform="$ARCH" $DISTRO:$CODENAME
ADD $QEMU_STATIC_BIN /usr/bin/$QEMU_STATIC_BIN
DOCKERFILE

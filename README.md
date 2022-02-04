Script (derived from https://github.com/docker-32bit/ubuntu) to generate Ubuntu 32bit Docker images.

The generated Docker images are available via [DockerHub](https://hub.docker.com/r/osrf/ubuntu_i386/).

#### Note:
In order to run docker images derived from a different platform architecture than the host (the architecture used to run the docker engine), the host kernel still needs to be configured to enable the binfmt-support for the foreign architecture. This can be done by simply via:  
`$ sudo apt install qemu-user-static`

Additionally, the runtime in the container will need access to qemu-<arch>-static binaries. This can be done two ways; by either mounting those binaries from the host to `user/bin/` inside the container, or baking them into the image itself from the get-go (as done here in this repo's bootstrap setup).
The current version of qemu being bundled is 3.1.

* `qemu-aarch64-static` was taken from the Debian package `qemu-user-static_3.1+dfsg-8+deb10u3_amd64.deb`.
* `qemu-arm-static` was taken from the Debian package `qemu-user-static_3.1+dfsg-8+deb10u3_i386.deb`.

The binary `qemu-arm-static` must be taken from a 32bit architecture (in this case i386) to work around [this bug](https://bugs.launchpad.net/qemu/+bug/1805913).

In order to use the bootstrap tooling, `debootstrap` must be installed. This can be done by simply via: 
`$ sudo apt install debootstrap`

Additionally when building from a different platform architecture than the target image, i.e. the architecture used to run the debootstrap and docker engine vs the architecture inside the source chroot, the host will again need binfmt-support for the kernel. As the debootstrap process downloads and copies in the qemu static binaries for emulation into the chroot before any execution is done inside the chroot, installing the qemu static binaries onto the host is then not essential.

### Building minimal images using the upstream multiarch images as a base.

Docker's native multi-arch image support is available in 20.04 which includes support for using the host's qemu-user-static and binfmt-misc support to run arm-native images on amd64 transparently.
See https://github.com/docker/for-linux/issues/56 and https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=868217
Until our infrastructure is configured to specify platform when building and running cross-platform images we still rely on the osrf/$OS_$ARCH:$CODENAME images.

However, instead of building and maintaining images from scratch we can leverage the default docker images for debian and ubuntu which are now provided for multiple platforms.
Since the native arch information is embedded in the image's metadata a normal docker-run will generate warnings when the platform doesn't match the host platform.
We work around this by exporting and modifying the image's metadata before re-importing it.
I haven't found a more ergonomic way of doing this yet.

The process is as follows

1. Fetch the appropriate base image from Docker Hub
  ```
  docker pull --platform=linux/amd64 ubuntu:jammy
  ```
2. Using the image ID rather than tag (to prevent overriding the official tag and confusing your system later) export the image as a tar archive and extract it to a temporary workspace
  ```
  docker save 0da0201282b7 > ubuntu-jammy-arm64.tar
  mkdir -p tmp/ubuntu-jammy-arm64; tar -C tmp/ubuntu-jammy-arm64 -xf ubuntu-jammy-arm64.tar
  ```
3. Edit the image metadata to set the architecture to amd64. "variant" is not defined by default for amd64 images.
  ```
  sed -e 's/"architecture":"arm64"/"architecture":"amd64"/' -e 's/,"variant":"v8"//' -i tmp/ubuntu-jammy-arm64/*.json
  ```
5. Re-tar the image contents and import them into docker.
  ```
  tar -C tmp/ubuntu-jammy-arm64 -cf ubuntu-jammy-arm64.tar .
  docker load < ubuntu-jammy-arm64.tar
  ```
6. Tag and push the image to Docker Hub
  ```
  docker tag 184ec6725d6517ab94e8ee552f357f787eff4dc8ef1e41c8c2de8ab5d606b19c osrf/ubuntu_arm64:jammy
  docker push osrf/ubuntu_arm64:jammy
  ```

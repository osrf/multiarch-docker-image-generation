Script (derived from https://github.com/docker-32bit/ubuntu) to generate Ubuntu 32bit Docker images.

The generated Docker images are available via [DockerHub](https://hub.docker.com/r/osrf/ubuntu_i386/).

#### Note:
In order to run docker images derived from a different platform architecture than the host (the architecture used to run the docker engine), the host kernel still needs to be configured to enable the binfmt-support for the foreign architecture. This can be done by simply via:  
`$ sudo apt install qemu-user-static`

Additionally, the runtime in the container will need access to qemu-<arch>-static binaries. This can be done two ways; by either mounting those binaries from the host to `user/bin/` inside the container, or baking them into the image itself from the get-go (as done here in this repo's bootstrap setup).
To see what version of qemu is currently being bundled, check the commit history. Updates to the embedded binaries should include their full version and how they were sourced.

In order to use the bootstrap tooling, `debootstrap` must be installed. This can be done by simply via: 
`$ sudo apt install debootstrap`

Additionally when building from a different platform architecture than the target image, i.e. the architecture used to run the debootstrap and docker engine vs the architecture inside the source chroot, the host will again need binfmt-support for the kernel. As the debootstrap process downloads and copies in the qemu static binaries for emulation into the chroot before any execution is done inside the chroot, installing the qemu static binaries onto the host is then not essential.

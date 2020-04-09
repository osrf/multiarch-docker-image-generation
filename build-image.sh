#!/bin/bash -x
### Build a docker image for ubuntu i386.

# Sources:
# https://wiki.debian.org/Debootstrap
# https://wiki.debian.org/EmDebian/CrossDebootstrap
# https://wiki.debian.org/Arm64Qemu

set -e

### settings
if [ "$IMAGE_OS" ]; then
  os=$IMAGE_OS
else
  os=ubuntu
fi

if [ "$IMAGE_ARCH" ]; then
  arch=$IMAGE_ARCH
else
  arch=arm64
fi

if [ "$IMAGE_SUITE" ]; then
  suite=$IMAGE_SUITE
else
  suite=xenial
fi

chroot_dir="/var/chroot/${os}_${arch}_$suite"
docker_image="osrf/${os}_$arch:$suite"

foreign_arches=(armhf arm64)

if [ $os == 'ubuntu' ]; then
  if [ $suite == 'saucy' ] || [ $suite == 'utopic' ] || [ $suite == 'vivid' ] || [ $suite == 'wily' || [ $suite == 'yakkety' || [ $suite == 'zesty' ]; then
    apt_mirror='http://old-releases.ubuntu.com/ubuntu'
  elif [[ ${foreign_arches[*]} =~ $arch ]]; then
    apt_mirror='http://ports.ubuntu.com'
  else
    apt_mirror='http://archive.ubuntu.com/ubuntu'
  fi
elif [ $os == 'debian' ]; then
  apt_mirror='http://httpredir.debian.org/debian'
fi

### make sure that the required tools are installed
# apt-get install -y docker.io debootstrap dchroot


### Clear chroot_dir to make sure the rebuild is clean
# This is tp prevent a corrupted chroot dir to break repeated failed
# rebuilds that have been observed at the deboostrap minbase stage
echo Clear chroot before debootstrap
rm -rf $chroot_dir

### install a minbase system with debootstrap
export DEBIAN_FRONTEND=noninteractive
foreign_arg=''
if [[ ${foreign_arches[*]} =~ $arch ]]; then
  foreign_arg='--foreign'
fi
debootstrap $foreign_arg --variant=minbase --arch=$arch $suite $chroot_dir $apt_mirror

if [[ ${foreign_arches[*]} =~ $arch ]]; then
  if [ $arch == 'armhf' ]; then
    cp qemu-arm-static $chroot_dir/usr/bin/
  elif [ $arch == 'arm64' ]; then
    cp qemu-aarch64-static $chroot_dir/usr/bin/
  fi
  LC_ALL=C LANGUAGE=C LANG=C chroot $chroot_dir /debootstrap/debootstrap --second-stage
  LC_ALL=C LANGUAGE=C LANG=C chroot $chroot_dir dpkg --configure -a
fi
if [ $os == 'ubuntu' ]; then
  repositories='main restricted universe multiverse'
else
  repositories='main'
  additional_components='non-free contrib'
fi

### update the list of package sources
cat <<EOF > $chroot_dir/etc/apt/sources.list
deb $apt_mirror $suite $repositories
EOF

if [ -n "$additional_components" ]; then
	for component in $additional_components; do
		cat <<EOF >> $chroot_dir/etc/apt/sources.list
deb $apt_mirror $suite $component
EOF
	done
fi

if [ $os == 'ubuntu' ]; then
  cat <<EOF >> $chroot_dir/etc/apt/sources.list
deb $apt_mirror $suite-updates $repositories
deb $apt_mirror $suite-backports $repositories
EOF
  if [ ! [ ${foreign_arches[*]} =~ $arch ] ]; then
    cat <<EOF >> $chroot_dir/etc/apt/sources.list
deb http://security.ubuntu.com/ubuntu $suite-security main restricted universe multiverse
EOF
  fi
fi

# if [ "$suite" != "vivid" ]; then
# cat <<EOF >> $chroot_dir/etc/apt/sources.list
# deb http://extras.ubuntu.com/ubuntu $suite main
# EOF
# fi

# a few minor docker-specific tweaks
# see https://github.com/docker/docker/blob/master/contrib/mkimage/debootstrap

# prevent init scripts from running during install/update
echo '#!/bin/sh' > $chroot_dir/usr/sbin/policy-rc.d
echo 'exit 101' >> $chroot_dir/usr/sbin/policy-rc.d
chmod +x $chroot_dir/usr/sbin/policy-rc.d

# force dpkg not to call sync() after package extraction (speeding up installs)
echo 'force-unsafe-io' > $chroot_dir/etc/dpkg/dpkg.cfg.d/docker-apt-speedup

# Install humanity-icon-theme on bionic to work around
# https://github.com/ros-infrastructure/buildfarm_deployment/issues/198
if [ $suite == 'bionic' ]; then
	chroot $chroot_dir sh -c 'apt-get update && apt-get install -y humanity-icon-theme'
fi


# _keep_ us lean by effectively running "apt-get clean" after every install
echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' > $chroot_dir/etc/apt/apt.conf.d/docker-clean
echo 'APT::Update::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' >> $chroot_dir/etc/apt/apt.conf.d/docker-clean
echo 'Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache "";' >> $chroot_dir/etc/apt/apt.conf.d/docker-clean

# remove apt-cache translations for fast "apt-get update"
echo 'Acquire::Languages "none";' > $chroot_dir/etc/apt/apt.conf.d/docker-no-languages

# store Apt lists files gzipped on-disk for smaller size
echo 'Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";' > $chroot_dir/etc/apt/apt.conf.d/docker-gzip-indexes


cp /etc/resolv.conf $chroot_dir/etc/resolv.conf
mount -o bind /proc $chroot_dir/proc
### install ubuntu-minimal
if [ $os == 'ubuntu' ]; then
  chroot $chroot_dir apt-get update
  chroot $chroot_dir apt-get -y install ubuntu-minimal
elif [ $os == 'debian' ]; then
  echo 'TODO debian minimal here'
fi

# https://github.com/docker/docker/issues/1024
chroot $chroot_dir dpkg-divert --local --rename --add /sbin/initctl
chroot $chroot_dir ln -sf /bin/true /sbin/initctl

### Build semop wrapper
cp wrap_semop.c $chroot_dir/tmp/
chroot $chroot_dir apt-get -y install build-essential
chroot $chroot_dir gcc -fPIC -shared -o /opt/libpreload-semop.so /tmp/wrap_semop.c
chroot $chroot_dir echo /opt/libpreload-semop.so > $chroot_dir/etc/ld.so.preload

### cleanup and unmount /proc
chroot $chroot_dir apt-get autoclean
chroot $chroot_dir apt-get clean
chroot $chroot_dir apt-get autoremove
rm $chroot_dir/etc/resolv.conf
umount $chroot_dir/proc

### create a tar archive from the chroot directory
tar cfz $os_$arch_$suite.tgz -C $chroot_dir .

### import this tar archive into a docker image:
cat $os_$arch_$suite.tgz | docker import - $docker_image

# ### cleanup
rm $os_$arch_$suite.tgz
rm -rf $chroot_dir

### push image to Docker Hub
echo "Test the image $docker_image and push it to upstream with 'docker push $docker_image'"

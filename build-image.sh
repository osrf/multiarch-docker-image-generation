#!/bin/bash -x
### Build a docker image for ubuntu i386.

set -e

### settings
arch=i386
suite=trusty
chroot_dir="/var/chroot/ubuntu_32bit_$suite"
apt_mirror='http://archive.ubuntu.com/ubuntu'
docker_image="osrf/ubuntu_32bit:$suite"

### make sure that the required tools are installed
apt-get install -y docker.io debootstrap dchroot

### install a minbase system with debootstrap
export DEBIAN_FRONTEND=noninteractive
debootstrap --variant=minbase --arch=$arch $suite $chroot_dir $apt_mirror

### update the list of package sources
cat <<EOF > $chroot_dir/etc/apt/sources.list
deb $apt_mirror $suite main restricted universe multiverse
deb $apt_mirror $suite-updates main restricted universe multiverse
deb $apt_mirror $suite-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $suite-security main restricted universe multiverse
EOF

if [ "$suite" != "vivid" ]; then
cat <<EOF >> $chroot_dir/etc/apt/sources.list
deb http://extras.ubuntu.com/ubuntu $suite main
EOF
fi

# a few minor docker-specific tweaks
# see https://github.com/docker/docker/blob/master/contrib/mkimage/debootstrap

# prevent init scripts from running during install/update
echo '#!/bin/sh' > $chroot_dir/usr/sbin/policy-rc.d
echo 'exit 101' >> $chroot_dir/usr/sbin/policy-rc.d
chmod +x $chroot_dir/usr/sbin/policy-rc.d

# force dpkg not to call sync() after package extraction (speeding up installs)
echo 'force-unsafe-io' > $chroot_dir/etc/dpkg/dpkg.cfg.d/docker-apt-speedup

# _keep_ us lean by effectively running "apt-get clean" after every install
echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' > $chroot_dir/etc/apt/apt.conf.d/docker-clean
echo 'APT::Update::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' >> $chroot_dir/etc/apt/apt.conf.d/docker-clean
echo 'Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache "";' >> $chroot_dir/etc/apt/apt.conf.d/docker-clean

# remove apt-cache translations for fast "apt-get update"
echo 'Acquire::Languages "none";' > $chroot_dir/etc/apt/apt.conf.d/docker-no-languages

# store Apt lists files gzipped on-disk for smaller size
echo 'Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";' > $chroot_dir/etc/apt/apt.conf.d/docker-gzip-indexes

### install ubuntu-minimal
cp /etc/resolv.conf $chroot_dir/etc/resolv.conf
mount -o bind /proc $chroot_dir/proc
chroot $chroot_dir apt-get update
chroot $chroot_dir apt-get -y install ubuntu-minimal

# https://github.com/docker/docker/issues/1024
chroot $chroot_dir dpkg-divert --local --rename --add /sbin/initctl
chroot $chroot_dir ln -s /bin/true /sbin/initctl

### cleanup and unmount /proc
chroot $chroot_dir apt-get autoclean
chroot $chroot_dir apt-get clean
chroot $chroot_dir apt-get autoremove
rm $chroot_dir/etc/resolv.conf
umount $chroot_dir/proc

### create a tar archive from the chroot directory
tar cfz ubuntu_32bit_$suite.tgz -C $chroot_dir .

### import this tar archive into a docker image:
cat ubuntu_32bit_$suite.tgz | docker import - $docker_image

# ### push image to Docker Hub
docker push $docker_image

# ### cleanup
rm ubuntu_32bit_$suite.tgz
rm -rf $chroot_dir

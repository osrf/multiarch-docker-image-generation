#!/usr/bin/env python3

import argparse
import errno
import os
import subprocess

from datetime import date

ALL_ARCHES = [
    # 'amd64', Use the standard images from docker
    'armhf',
    'arm64',
    'i386',
]

arch_uname_mapping = {
    'arm64': 'aarch64',
    'armhf': 'armv7l',
    'i386': 'x86_64',  # No qemu, just using 32bit support mode
}

SUPPORTED_TARGETS = {
    'debian': {
        'stretch': ['arm64', 'armhf'],
        'buster': ['arm64', 'armhf'],
    },
    'ubuntu': {
        'trusty': ['i386', 'armhf'],
        'xenial': ALL_ARCHES,
        'bionic': ALL_ARCHES,
        'disco' : ALL_ARCHES,
        'focal' : ['arm64', 'armhf'],
    }
}


# Generator to yeild the above tree as tuples
def get_supported_targets():
    for (os_name, os) in SUPPORTED_TARGETS.items():
        for (suite_name, suite) in os.items():
            for arch in suite:
                yield (os_name, suite_name, arch)


def construct_image_name(operating_system, arch, suite):
    return "osrf/%s_%s:%s" % (operating_system, arch, suite)


def image_save_name_encode(image_name):
    image_name = image_name.replace('/', '__')
    image_name = image_name.replace(':', '__')
    return image_name + '-' + date.today().isoformat()


def backup_image(image_name, directory):
    try:
        os.makedirs(directory)
    except OSError as ex:
        if ex.errno == errno.EEXIST and os.path.isdir(directory):
            pass
        else:
            raise

    image_filename = os.path.join(directory,
        image_save_name_encode(image_name) + '.tar')
    if os.path.exists(image_filename):
        print("Backup %s already exists; skipping." % image_filename)
        return True
    try:
        print("Pulling %s for backup" % image_name)
        pull_command = 'docker pull %s' % (image_name)
        subprocess.check_output(pull_command, shell=True, stderr=subprocess.STDOUT)

        backup_command = 'docker save %s -o %s' % (image_name, image_filename)
        print("Saving image %s with command [%s]" % (image_name, backup_command))
        subprocess.check_output(backup_command, shell=True, stderr=subprocess.STDOUT)
        return True
    except subprocess.CalledProcessError as ex:
        print("Failed to backup %s to %s: %s\nContinuing..." %
              (image_name, image_filename, ex))
        return False


parser = argparse.ArgumentParser()
parser.add_argument("--os",
    help="Filter results to a specific OS such as 'ubuntu' or 'debian'")
parser.add_argument("--suite",
    help="Filter results to a specific suite such as 'xenial' or 'jessie'")
parser.add_argument("--arch", help="Filter results to a specific architecture such as 'arm64' or 'armhf'")
parser.add_argument("--backup", help="Backup the previous images to this directory.")
args = parser.parse_args()

failed_backups = []
if args.backup:
    for (o, s, a) in get_supported_targets():
        image_name = construct_image_name(o, a, s)
        backup_success = backup_image(image_name, args.backup)
        if not backup_success:
            failed_backups.append(image_name)

successful_builds = []
failed_builds = []
for (o, s, a) in get_supported_targets():
    image_name = construct_image_name(o, a, s)
    if args.os and args.os != o:
        print("%s does not match os argument %s" % (image_name, args.os))
        continue
    if args.suite and args.suite != s:
        print("%s does not match suite argument %s" % (image_name, args.suite))
        continue
    if args.arch and args.arch != a:
        print("%s does not match arch argument %s" % (image_name, args.arch))
        continue
    print('Processing:', o, s, a)
    env_override = {
        'IMAGE_OS': o,
        'IMAGE_SUITE': s,
        'IMAGE_ARCH': a,
    }
    cmd = 'sudo -E ./build-image.sh'

    try:
        subprocess.check_call(cmd, env=env_override, shell=True, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as ex:
        print("failed to process %s: %s" % (image_name, ex))
        failed_builds.append(image_name)
        continue

    verify_command = 'docker run %s uname -a' % image_name
    try:
        output = subprocess.check_output(verify_command, env=env_override, shell=True, stderr=subprocess.STDOUT)
        str_out = output.decode("utf-8")
        if not arch_uname_mapping[a] in str_out:
            print("Failed to get correct uname result for %s, aborting" % image_name)
            failed_builds.append(image_name)
            continue
    except subprocess.CalledProcessError as ex:
        print("failed to test %s" % image_name)
        failed_builds.append(image_name)
        continue
    print("Successfully detected uname %s in %s" % (arch_uname_mapping[a], image_name))
    successful_builds.append(image_name)

print("Summary:")
if failed_builds:
    print("Failed to build:\n%s" % failed_builds)
if failed_backups:
    print("Failed to backup:\n%s" % failed_backups)

print("Successfully built the following images.")
print("%s " % successful_builds)
print("Please verify and push.")
print("For your convenience the push commands are listed below:")
for im in successful_builds:
    print("docker push %s" % im)

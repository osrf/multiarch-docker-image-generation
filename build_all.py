#!/usr/bin/env python3

import argparse
import subprocess

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
        'jessie': ['arm64', 'armhf']
    },
    'ubuntu': {
        'xenial': ALL_ARCHES,
        'wily': ALL_ARCHES,
    }
}


# Generator to yeild the above tree as tuples
def get_supported_targets():
    for (os_name, os) in SUPPORTED_TARGETS.items():
        for (suite_name, suite) in os.items():
            for arch in suite:
                yield (os_name, suite_name, arch)


parser = argparse.ArgumentParser()
parser.add_argument("--os",
    help="Filter results to a specific OS such as 'ubuntu' or 'debian'")
parser.add_argument("--suite",
    help="Filter results to a specific suite such as 'xenial' or 'jessie'")
parser.add_argument("--arch", help="Filter results to a specific architecture such as 'arm64' or 'armhf'")
args = parser.parse_args()

successful_builds = []
failed_builds = []
for (o, s, a) in get_supported_targets():
    image_name = "osrf/%s_%s:%s" % (o, a, s)
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
        print("failed to process %s" % image_name)
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
print("Failed to build:\n%s" % failed_builds)

print("Successfully built the following images.")
print("%s " % successful_builds)
print("Please verify and push.")
print("For your convenience the push commands are listed below:")
for im in successful_builds:
    print("docker push %s" % im)

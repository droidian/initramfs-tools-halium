#!/bin/sh

set -e

MINIENV_HOOKS="cryptroot plymouth unl0kr droidian-encryption-service parse-android-dynparts dmsetup"

export FLASH_KERNEL_SKIP=1
export DEBIAN_FRONTEND=noninteractive
DEFAULTMIRROR="https://archive.debian.org/debian"
APT_COMMAND="apt -y"

usage() {
	echo "Usage:

-a|--arch     Architecture to create initrd for. Default armhf
-m|--mirror   Custom mirror URL to use. Must serve your arch.
-r|--recovery Build a recovery image
-c|--compress Compression to use
-n|--name     Target file name
"
}

echob() {
	echo "Builder: $@"
}

while [ $# -gt 0 ]; do
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	-r | --recovery)
		echob "Recovery image request"
		IS_RECOVERY="yes"
		;;
	-a | --arch)
		[ -n "$2" ] && ARCH=$2 shift || usage
		;;
	-m | --mirror)
		[ -n "$2" ] && MIRROR=$2 shift || usage
		;;
	-c | --compress)
		[ -n "$2" ] && COMPRESS=$2 shift || usage
		;;
	-n | --name)
		[ -n "$2" ] && FILENAME=$2 shift || usage
		;;
	esac
	shift
done

# Defaults for all arguments, so they can be set by the environment
[ -z $ARCH ] && ARCH="armhf"
[ -z $MIRROR ] && MIRROR=$DEFAULTMIRROR
[ -z $RELEASE ] && RELEASE="stretch"
[ -z $ROOT ] && ROOT=./build/$ARCH
[ -z $OUT ] && OUT=./out
[ -z $IS_RECOVERY ] && IS_RECOVERY="no"
[ -z $COMPRESS ] && COMPRESS="gzip"
[ -z $FILENAME ] && FILENAME="initrd.img-halium-generic"

# list all packages needed for halium's initrd here
[ -z $INCHROOTPKGS ] && INCHROOTPKGS="initramfs-tools dctrl-tools e2fsprogs libc6-dev zlib1g-dev libssl-dev busybox-static lvm2 cryptsetup xkb-data dropbear pigz liblz4-tool"

BOOTSTRAP_BIN="debootstrap --arch $ARCH --variant=minbase"

umount_chroot() {
	chroot $ROOT umount /sys >/dev/null 2>&1 || true
	chroot $ROOT umount /proc >/dev/null 2>&1 || true
	chroot $ROOT umount /orig >/dev/null 2>&1 || true
	echo
}

do_chroot() {
	trap umount_chroot INT EXIT
	ROOT="$1"
	CMD="$2"
	echob "Executing \"$2\" in chroot"
	mount -o bind / $ROOT/orig
	chroot $ROOT mount -t proc proc /proc
	chroot $ROOT mount -t sysfs sys /sys
	chroot $ROOT $CMD
	umount_chroot
	trap - INT EXIT
}

if [ ! -e $ROOT/.min-done ]; then

	[ -d $ROOT ] && rm -r $ROOT

	# create a plain chroot to work in
	echob "Creating chroot with arch $ARCH in $ROOT"
	mkdir build || true
	$BOOTSTRAP_BIN $RELEASE $ROOT $MIRROR || cat $ROOT/debootstrap/debootstrap.log

	mkdir -p $ROOT/orig

	#sed -i 's/main$/main universe/' $ROOT/etc/apt/sources.list
	sed -i 's,'"$DEFAULTMIRROR"','"$MIRROR"',' $ROOT/etc/apt/sources.list

	# make sure we do not start daemons at install time
	mv $ROOT/sbin/start-stop-daemon $ROOT/sbin/start-stop-daemon.REAL
	echo $START_STOP_DAEMON >$ROOT/sbin/start-stop-daemon
	chmod a+rx $ROOT/sbin/start-stop-daemon

	echo $POLICY_RC_D >$ROOT/usr/sbin/policy-rc.d

	# after the switch to systemd we now need to install upstart explicitly
	echo "nameserver 8.8.8.8" >$ROOT/etc/resolv.conf
	do_chroot $ROOT "$APT_COMMAND update"

	# We also need to install dpkg-dev in order to use dpkg-architecture.
	do_chroot $ROOT "$APT_COMMAND install dpkg-dev --no-install-recommends"

	touch $ROOT/.min-done
else
	echob "Build environment for $ARCH found, reusing."
fi

# install all packages we need to roll the generic initrd
do_chroot $ROOT "$APT_COMMAND update"
do_chroot $ROOT "$APT_COMMAND dist-upgrade"
do_chroot $ROOT "$APT_COMMAND install $INCHROOTPKGS --no-install-recommends"
DEB_HOST_MULTIARCH=$(chroot $ROOT dpkg-architecture -q DEB_HOST_MULTIARCH)

# Droidian: copy touchscreen, keyboard data
cp /etc/udev/rules.d/90-touchscreen.rules "${ROOT}/etc/udev/rules.d"
cp -R /usr/share/X11/xkb/* "${ROOT}/usr/share/X11/xkb"
mkdir -p "${ROOT}/usr/lib/udev/hwdb.d"
cp -R /usr/lib/udev/hwdb.d/* "${ROOT}/usr/lib/udev/hwdb.d"

cp -a conf/halium ${ROOT}/usr/share/initramfs-tools/conf.d
cp -a scripts/* ${ROOT}/usr/share/initramfs-tools/scripts
cp -a hooks/* ${ROOT}/usr/share/initramfs-tools/hooks
if [ "${IS_RECOVERY}" = "yes" ]; then
	cp -av hooks-recovery/* ${tmpdir}/etc/initramfs-tools/hooks
fi

VER="$ARCH"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/lib/$DEB_HOST_MULTIARCH"

# Create minienv
export DESTDIR="/tmp/droidian-minienv"
export verbose="y"

# Create initial skeleton, hook might get confused
mkdir -p ${DESTDIR}/etc ${DESTDIR}/usr/lib ${DESTDIR}/lib ${DESTDIR}/mnt ${DESTDIR}/tmp

# Droidian specific
/usr/sbin/plymouth-set-default-theme -R droidian

export __MODULES_TO_ADD="$(mktemp "${TMPDIR:-/var/tmp}/modules_XXXXXX")"
for hook in ${MINIENV_HOOKS}; do
	bash -x /usr/share/initramfs-tools/hooks/${hook}
done

# stretch does not have /usr merged, so simply move stuff to /lib
# instead. This allows to properly overlay in /minienv
mv ${DESTDIR}/usr/lib/* ${DESTDIR}/lib

# Move the linker in a known place
mv -v ${DESTDIR}/lib/*/ld-linux-*.so.* ${DESTDIR}/lib/droidian-minienv-linker.so

if [ "${COMPRESS}" = "lz4" ] && [ ! -e "${ROOT}/usr/bin/lz4-wrapper" ]; then
	# This is unfortunately needed as mkinitramfs checks for the command
	# existence, so we can't overload the compress variable
	cat > ${ROOT}/usr/bin/lz4-wrapper <<EOF
#!/bin/sh -x
exec lz4 -9 -l $@
EOF
	chmod +x ${ROOT}/usr/bin/lz4-wrapper
	COMPRESS="lz4-wrapper"
fi
do_chroot $ROOT "env compress=${COMPRESS} update-initramfs -tc -khalium-generic -v"

rm -rf ${DESTDIR}

mkdir "$OUT" >/dev/null 2>&1 || true
cp "$ROOT/boot/initrd.img-halium-generic" "$OUT/${FILENAME}"
cd "$OUT"
sha256sum "${FILENAME}" > "${FILENAME}.sha256"
date -R > "${FILENAME}.timestamp"
cd - >/dev/null 2>&1

#!/bin/bash

. ./build.conf && export MKFLG

export MWD=`pwd`

ARCH_LIST="default i486 x86_64 armv4l armv6l"
ARCH_LIST_EX="i486 i586 i686 x86_64 armv4l armv4tl armv5l armv6l m68k mips mips64 mipsel powerpc powerpc-440fp sh2eb sh2elf sh4 sparc"

if ! which make &>/dev/null ; then
	echo "It looks like development tools are not installed.. stopping"
	exit 1
fi

help_msg() {
	echo "Build static apps in the queue defined in build.conf

Usage:
  $0 [options]

  Options:
  -pkg pkg    : compile specific pkg only
  -all        : force building all *_static pkgs
  -copyall    : copy all generated binaries to the initrd
                otherwise only the ones specified in
                INITRD_PROGS='..' in build.conf
  -arch target: compile for target arch
  -sysgcc     : use system gcc
  -cross      : use the cross compilers from Aboriginal Linux
  -download   : download pkgs only, this overrides other options
  -specs file : DISTRO_SPECS file to use
  -auto       : don't prompt for input
  -help       : show help and exit

  Valid <targets> for -arch:
      $ARCH_LIST_EX

  The most relevant <targets> for Puppy are:
      ${ARCH_LIST#default }

  Note that one target not yet supported by musl is aarch64 (arm64)
"
}

PROMPT=1

while [ "$1" ] ; do
	case $1 in
		-sysgcc)   USE_SYS_GCC=1       ; shift ;;
		-cross)    CROSS_COMPILE=1     ; shift ;;
		-all)      FORCE_BUILD_ALL=1   ; shift ;;
		-copyall)  COPY_ALL_BINARIES=1 ; shift ;;
		gz|xz)     INITRD_COMP=$1      ; shift ;;
		-download) export DLD_ONLY=1   ; shift ;;
		-auto)     PROMPT=0            ; shift ;;
		-pkg)      BUILD_PKG="$2"      ; shift 2
			       [ "$BUILD_PKG" = "" ] && { echo "$0 -pkg: Specify a pkg to compile" ; exit 1; } ;;
		-arch)     TARGET_ARCH="$2"    ; shift 2
			       [ "$TARGET_ARCH" = "" ] && { echo "$0 -arch: Specify a target arch" ; exit 1; } ;;
		-specs)    DISTRO_SPECS="$2"    ; shift 2
			       [ ! -f "$DISTRO_SPECS" ] && { echo "$0 -specs: '${DISTRO_SPECS}' is not a regular file" ; exit 1; } ;;
		-h|-help|--help) help_msg ; exit ;;
		-clean)
			echo -e "Press P and hit enter to proceed, any other combination to cancel.." ; read zz
			case $zz in p|P) echo rm -rf initrd.[gx]z initrd_progs-*.tar.* ZZ_initrd-expanded 00_* 0sources cross-compiler* ;; esac
			exit
			;;
		*)
			echo "Unrecognized option: $1"
			shift
			;;
	esac
done

ARCH=`uname -m`
OS_ARCH=$ARCH

if [ "$USE_SYS_GCC" != "1" -a "$CROSS_COMPILE" != "1" ] ; then
	# the cross compilers from landley.net were compiled on x86
	# if we're using the script in a non-x86 system
	# it means that the system gcc must be chosen by default
	# perhaps we're running qemu or a native linux os
	case $ARCH in
		i?86|x86_64) CROSS_COMPILE=1 ;;
		*) USE_SYS_GCC=1 ;;
	esac
fi

set_pkgs() {
	[ "$BUILD_PKG" != "" ] && PACKAGES="$BUILD_PKG"
	if [ "$FORCE_BUILD_ALL" = "1" ] ; then
		PACKAGES=$(find pkg -maxdepth 1 -type d -name '*_static' | sed 's|.*/||' | sort)
	fi
	PACKAGES=$(echo "$PACKAGES" | grep -Ev '^#|^$')
}

download_pkgs() {
	. ./func #retrieve
	set_pkgs
	for init_pkg in ${PACKAGES} ; do
		[ -d pkg/"${init_pkg}_static" ] && init_pkg=${init_pkg}_static
		file=$(ls pkg/${init_pkg}/*.petbuild)
		[ -f "$file" ] || continue
		URL=$(grep '^URL=' $file | sed 's|.*=||')
		SRC=$(grep '^SRC=' $file | sed 's|.*=||')
		VER=$(grep '^VER=' $file | sed 's|.*=||')
		COMP=$(grep '^COMP=' $file | sed 's|.*=||')
		( retrieve ${SRC}-${VER}.${COMP} )
	done
	exit #after running this func
}

###################################################################
#							MAIN
###################################################################

if [ "$USE_SYS_GCC" = "1" ] ; then
	which gcc &>/dev/null || { echo "No gcc aborting"; exit 1; }
	echo
	echo "Building in: $ARCH"
	echo
	echo "* Using system gcc"
	echo
	sleep 1.5
	[ "$DLD_ONLY" = "1" ] && download_pkgs

else

	#############################
	##     aboriginal linux     #
	#############################
	case $ARCH in
		i?86) ARCH=i486 ;;
		x86_64) echo -n ;;
		*)
			echo -e "*** The cross-compilers from aboriginal linux"
			echo -e "*** work in x86 systems only, I guess."
			echo -e "* Run $0 -sysgcc to use the system gcc ... \n"
			if [ "$PROMPT" = "1" ] ; then
				echo -n "Press CTRL-C to cancel, enter to continue..." ; read zzz
			else
				exit 1
			fi
	esac

	#--------------------------------------------------
	#             SELECT TARGET ARCH
	#--------------------------------------------------
	if [ "$TARGET_ARCH" != "" ] ; then
		for a in $ARCH_LIST ; do
			[ "$TARGET_ARCH" = "$a" ] && VALID_TARGET_ARCH=1 && break
		done
		if [ "$VALID_TARGET_ARCH" != "1" ] ; then
			echo "Invalid target arch: $TARGET_ARCH"
			exit 1
		else
			[ "$TARGET_ARCH" != "default" ] && ARCH=${TARGET_ARCH}
		fi
	fi

	if [ "$VALID_TARGET_ARCH" != "1" -a "$PROMPT" = "1" ] ; then
		echo
		echo "We're going to compile apps for the init ram disk"
		echo "Select the arch you want to compile to"
		echo
		x=1
		for a in $ARCH_LIST ; do
			case $a in
				default) echo "	${x}) default [${ARCH}]" ;;
				*) echo "	${x}) $a" ;;
			esac
			let x++
		done
		echo "	*) default [${ARCH}]"
		echo
		echo -n "Enter your choice: " ; read choice
		x=1
		for a in $ARCH_LIST ; do
			[ "$x" = "$choice" ] && selected_arch=$a && break
			let x++
		done
		#-
		case $selected_arch in
			default|"")ok=1 ;;
			*) ARCH=$selected_arch ;;
		esac
	fi

	case $OS_ARCH in
		*64) ok=1 ;;
		*)
			case $ARCH in *64)
				echo -e "\n*** Trying to compile for a 64bit arch in a 32bit system?"
				echo -e "*** That's not possible.. exiting.."
				exit 1
			esac
			;;
	esac
	echo
	echo "Arch: $ARCH"
	sleep 1.5

	#--------------------------------------------------
	#      CROSS COMPILER FROM ABORIGINAL LINUX
	#--------------------------------------------------
	CCOMP_DIR=cross-compiler-${ARCH}
	URL=http://landley.net/aboriginal/downloads/binaries
	PACKAGE=${CCOMP_DIR}.tar.gz
	echo
	## download
	if [ ! -f "0sources/${PACKAGE}" ];then
		echo "Download cross compiler from Aboriginal Linux"
		[ "$PROMPT" = "1" ] && echo -n "Press enter to continue, CTRL-C to cancel..." && read zzz
		wget -c -P 0sources ${URL}/${PACKAGE}
		if [ $? -ne 0 ] ; then
			rm -rf ${CCOMP_DIR}
			echo "failed to download ${PACKAGE}"
			exit 1
		fi
	else
		[ "$DLD_ONLY" = "1" ] && "Already downloaded ${PACKAGE}"
	fi

	[ "$DLD_ONLY" = "1" ] && download_pkgs

	## extract
	if [ ! -d "$CCOMP_DIR" ] ; then
		tar --directory=$PWD -xaf 0sources/${PACKAGE}
		if [ $? -ne 0 ] ; then
			rm -rf ${CCOMP_DIR}
			rm -fv 0sources/${PACKAGE}
			echo "failed to extract ${PACKAGE}"
			exit 1
		fi
	fi
	#-------------------------------------------------------------

	[ ! -d "$CCOMP_DIR" ] && { echo "$CCOMP_DIR not found"; exit 1; }
	if [ -d cross-compiler-${ARCH}/cc/lib ] ; then
		cp cross-compiler-${ARCH}/cc/lib/* cross-compiler-${ARCH}/lib
	fi
	echo
	echo "Using cross compiler from Aboriginal Linux"
	echo
	export OVERRIDE_ARCH=${ARCH}     # = cross compiling
	export XPATH=${PWD}/${CCOMP_DIR} # = cross compiling
	# see ./func
fi

#----------------------------------------------
mkdir -p 00_${ARCH}/bin 00_${ARCH}/log 0sources
#----------------------------------------------

function check_bin() {
	local init_pkg=$1
	case $init_pkg in
		""|'#'*) continue ;;
		coreutils_static) static_bins='cp' ;;
		dosfstools_static) static_bins='fsck.fat' ;;
		e2fsprogs_static) static_bins='fsck e2fsck resize2fs' ;;
		findutils_static) static_bins='find' ;;
		fuse_static) static_bins='fusermount' ;;
		module-init-tools_static) static_bins='lsmod modprobe' ;;
		util-linux_static) static_bins='losetup' ;;
		*) static_bins=${init_pkg%_*} ;;
	esac
	for sbin in ${static_bins} ; do
		ls ./00_${ARCH}/bin | grep -q "^${sbin}" || return 1
	done
}

build_pkgs() {
	rm -f .fatal
	echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
	echo
	echo "building packages for the initial ram disk"
	echo
	sleep 1
	set_pkgs
	for init_pkg in ${PACKAGES} ; do
		if [ -f .fatal ] ; then
			echo "Exiting.." ; rm -f .fatal
			exit 1
		fi
		[ -d pkg/"${init_pkg}_static" ] && init_pkg=${init_pkg}_static
		check_bin $init_pkg
		if [ $? -eq 0 ] ; then ##found
			echo "$init_pkg exists ... skipping"
			continue
		fi
		####
		echo
		cd pkg/${init_pkg}
		echo "+=============================================================================+"
		echo
		echo "building $init_pkg"
		sleep 1
		mkdir -p ${MWD}/00_${ARCH}/log
		sh ${init_pkg}.petbuild 2>&1 | tee ${MWD}/00_${ARCH}/log/${init_pkg}build.log
		if [ "$?" -eq 1 ];then 
			echo "$pkg build failure"
			case $HALT_ERRS in
				0) exit 1 ;;
			esac
		fi
		cd ${MWD}
		## extra check
		check_bin $init_pkg
		if [ $? -ne 0 ] ; then ##not found
			echo "target binary does not exist... exiting"
			[ "$HALT_ERRS" = "1" ] && exit 1
		fi
	done
}

build_pkgs
cd ${MWD}

rm -f .fatal

suspicious=$(
	ls 00_${ARCH}/bin/* | while read bin ; do file $bin ; done | grep -E 'dynamically|shared'
)
if [ "$suspicious" ] ; then
	echo
	echo "These files don't look good:"
	echo "$suspicious"
	echo
	if [ "$PROMPT" = "1" ] ; then
		echo -n "Press enter to continue, CTRL-C to end here.." ; read zzz
	else
		exit 1
	fi
fi

#----------------------------------------------------
#            create initial ramdisk
#----------------------------------------------------

case ${INITRD_COMP} in
	gz|xz) ok=1 ;;
	*) INITRD_COMP="gz" ;; #precaution
esac

INITRD_FILE="initrd.${INITRD_COMP}"
[ "$INITRD_GZ" = "1" ] && INITRD_FILE="initrd.gz"

if [ "$INITRD_CREATE" = "1" ] ; then
	echo
	[ "$PROMPT" = "1" ] && echo -n "Press enter to create ${INITRD_FILE}, CTRL-C to end here.." && read zzz
	echo
	echo "============================================"
	echo "Now creating the initial ramdisk (${INITRD_FILE}) (for 'huge' kernels)"
	echo "============================================"
	echo

	rm -rf ZZ_initrd-expanded
	mkdir -p ZZ_initrd-expanded
	cp -rf 0initrd/* ZZ_initrd-expanded
	find ZZ_initrd-expanded -type f -name '*MARKER' -delete
	cd ZZ_initrd-expanded
	[ -f dev.tar.gz ] && tar -zxf dev.tar.gz && rm -f dev.tar.gz

	if [ "$COPY_ALL_BINARIES" = "1" ] ; then
		cp -av --remove-destination ../00_${ARCH}/bin/* bin
	else
		for PROG in ${INITRD_PROGS} ; do
			case $PROG in ""|'#'*) continue ;; esac
			if [ -f ../00_${ARCH}/bin/${PROG} ] ; then
				cp -av --remove-destination ../00_${ARCH}/bin/${PROG} bin
			else
				echo "WARNING: 00_${ARCH}/bin/${PROG} not found"
			fi
		done
	fi

	echo
	if [ ! -f "$DISTRO_SPECS" ] ; then
		if [ -f ../0initrd/DISTRO_SPECS ] ; then
			DISTRO_SPECS='../0initrd/DISTRO_SPECS'
		else
			[ -f /etc/DISTRO_SPECS ] && DISTRO_SPECS='/etc/DISTRO_SPECS'
			[ -f /initrd/DISTRO_SPECS ] && DISTRO_SPECS='/initrd/DISTRO_SPECS'
		fi
	fi
	cp -fv "${DISTRO_SPECS}" .
	. "${DISTRO_SPECS}"
	
	cp -fv ../pkg/busybox_static/bb-create-symlinks bin # could contain updates
	cp -fv ../pkg/busybox_static/bb-delete-symlinks bin # could contain updates
	(  cd bin ; sh bb-create-symlinks 2>/dev/null )
	sed -i 's|^PUPDESKFLG=.*|PUPDESKFLG=0|' init
	if [ "$PROMPT" = "1" ] ; then
		echo
		echo "If you have anything to add or remove from ZZ_initrd-expanded do it now"
		echo
		echo -n "Press ENTER to generate ${INITRD_FILE} ..." ; read zzz
		echo
	fi
	####
	find . | cpio -o -H newc > ../initrd
	cd ..
	[ -f initrd.[gx]z ] && rm -fv initrd.*
	case ${INITRD_COMP} in
		gz) gzip -f initrd ;;
		xz) xz --check=crc32 --lzma2 initrd ;;
		*)  gzip -f initrd ;;
	esac
	if [ $? -eq 0 ] ; then
		echo
		echo "${INITRD_FILE} has been created"
		echo "You can inspect ZZ_initrd-expanded to see the final results"
	else
		echo "ERROR" ; exit 1
	fi
	[ "$INITRD_GZ" = "1" -a -f initrd.xz ] && mv -f initrd.xz initrd.gz
else
	echo "Not creating ${INITRD_FILE}"
fi

pkgx=initrd_progs-$(date "+%Y%m%d")-${ARCH}.tar.gz
rm -f ${pkgx%.*}.*
echo -en "\n** Creating $pkgx..."
tar zcf $pkgx 00_${ARCH}
echo

echo
echo " - Output files -"
echo "${INITRD_FILE}: use it in a frugal install for example"
echo "$pkgx: to store or distribute"
echo
echo "Finished."

### END ###
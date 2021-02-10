# This file is part of U-Boot verified boot support and is intended to be
# inherited from u-boot recipe and from kernel-fitimage.bbclass.
#
# The signature procedure requires the user to generate an RSA key and
# certificate in a directory and to define the following variable:
#
#   UBOOT_SIGN_KEYDIR = "/keys/directory"
#   UBOOT_SIGN_KEYNAME = "dev" # keys name in keydir (eg. "dev.crt", "dev.key")
#   UBOOT_MKIMAGE_DTCOPTS = "-I dts -O dtb -p 2000"
#   UBOOT_SIGN_ENABLE = "1"
#
# As verified boot depends on fitImage generation, following is also required:
#
#   KERNEL_CLASSES ?= " kernel-fitimage "
#   KERNEL_IMAGETYPE ?= "fitImage"
#
# The signature support is limited to the use of CONFIG_OF_SEPARATE in U-Boot.
#
# The tasks sequence is set as below, using DEPLOY_IMAGE_DIR as common place to
# treat the device tree blob:
#
# * u-boot:do_install_append
#   Install UBOOT_DTB_BINARY to datadir, so that kernel can use it for
#   signing, and kernel will deploy UBOOT_DTB_BINARY after signs it.
#
# * virtual/kernel:do_assemble_fitimage
#   Sign the image
#
# * u-boot:do_deploy[postfuncs]
#   Deploy files like UBOOT_DTB_IMAGE, UBOOT_DTB_SYMLINK and others.
#
# For more details on signature process, please refer to U-Boot documentation.

# Signature activation.
UBOOT_SIGN_ENABLE ?= "0"
SPL_SIGN_ENABLE ?= "0"

# Default value for deployment filenames.
UBOOT_DTB_IMAGE ?= "u-boot-${MACHINE}-${PV}-${PR}.dtb"
UBOOT_DTB_BINARY ?= "u-boot.dtb"
UBOOT_DTB_SYMLINK ?= "u-boot-${MACHINE}.dtb"
UBOOT_NODTB_IMAGE ?= "u-boot-nodtb-${MACHINE}-${PV}-${PR}.${UBOOT_SUFFIX}"
UBOOT_NODTB_BINARY ?= "u-boot-nodtb.${UBOOT_SUFFIX}"
UBOOT_NODTB_SYMLINK ?= "u-boot-nodtb-${MACHINE}.${UBOOT_SUFFIX}"
UBOOT_ITS ?= "u-boot-${MACHINE}-${PV}-${PR}.its"
SPL_DTB_IMAGE ?= "u-boot-spl-${MACHINE}-${PV}-${PR}.dtb"
SPL_DTB_BINARY ?= "u-boot-spl.dtb"
SPL_DTB_SYMLINK ?= "u-boot-spl-${MACHINE}.dtb"
SPL_NODTB_IMAGE ?= "u-boot-spl-nodtb-${MACHINE}-${PV}-${PR}.${UBOOT_SUFFIX}"
SPL_NODTB_BINARY ?= "u-boot-spl-nodtb.${UBOOT_SUFFIX}"
SPL_NODTB_SYMLINK ?= "u-boot-spl-nodtb-${MACHINE}.${UBOOT_SUFFIX}"

# Functions in this bbclass can be used by the U-Boot or Kernel PNs
UBOOT_PN = "${@d.getVar('PREFERRED_PROVIDER_u-boot') or 'u-boot'}"
KERNEL_PN = "${@d.getVar('PREFERRED_PROVIDER_virtual/kernel')}"

# Create a ITS file for the U-boot FIT, for use when
# we want to sign it so that the SPL can verify it
uboot_fitimage_assemble() {
	uboot_its="${1}"
	uboot_bin="${2}"
	uboot_dtb="${3}"
	uboot_csum="${FIT_HASH_ALG}"
	uboot_sign_algo="${FIT_SIGN_ALG}"
	uboot_sign_keyname="${UBOOT_SIGN_KEYNAME}"

	rm -f ${uboot_its}

	# First we create the ITS script
	cat << EOF >> ${uboot_its}
/dts-v1/;

/ {
	description = "U-boot FIT";
	#address-cells = <1>;

	images {
		firmware-1 {
			description = "U-Boot image";
			data = /incbin/("${uboot_bin}");
			type = "firmware";
			arch = "${UBOOT_ARCH}";
			compression = "none";
			hash@1 {
				algo = "${uboot_csum}";
			};
			signature@1 {
				algo = "${uboot_csum},${uboot_sign_algo}";
				key-name-hint = "${uboot_sign_keyname}";
			};
		};
		fdt-1 {
			description = "U-Boot FDT";
			data = /incbin/("${uboot_dtb}");
			type = "firmware";
			arch = "${UBOOT_ARCH}";
			compression = "none";
			hash@1 {
				algo = "${uboot_csum}";
			};
			signature@1 {
				algo = "${uboot_csum},${uboot_sign_algo}";
				key-name-hint = "${uboot_sign_keyname}";
			};
		};
	};

	configurations {
		default = "conf-1";
		conf-1 {
			description = "Boot with signed U-Boot and FDT";
			firmware = "firmware-1";
			fdt = "fdt-1";
			hash@1 {
				algo = "${uboot_csum}";
			};
			signature@1 {
				algo = "${uboot_csum},${uboot_sign_algo}";
				key-name-hint = "${uboot_sign_keyname}";
				sign-images = "firmware", "fdt";
			};
		};
	};
};
EOF

}

concat_dtb_helper() {
	if [ -e "${UBOOT_DTB_BINARY}" ]; then
		ln -sf ${UBOOT_DTB_IMAGE} ${DEPLOYDIR}/${UBOOT_DTB_BINARY}
		ln -sf ${UBOOT_DTB_IMAGE} ${DEPLOYDIR}/${UBOOT_DTB_SYMLINK}
	fi

	if [ -f "${UBOOT_NODTB_BINARY}" ]; then
		install ${UBOOT_NODTB_BINARY} ${DEPLOYDIR}/${UBOOT_NODTB_IMAGE}
		ln -sf ${UBOOT_NODTB_IMAGE} ${DEPLOYDIR}/${UBOOT_NODTB_SYMLINK}
		ln -sf ${UBOOT_NODTB_IMAGE} ${DEPLOYDIR}/${UBOOT_NODTB_BINARY}
	fi

	# Concatenate U-Boot w/o DTB & DTB with public key
	# (cf. kernel-fitimage.bbclass for more details)
	deployed_uboot_dtb_binary='${DEPLOY_DIR_IMAGE}/${UBOOT_DTB_IMAGE}'
	if [ "x${UBOOT_SUFFIX}" = "ximg" -o "x${UBOOT_SUFFIX}" = "xrom" ] && \
		[ -e "$deployed_uboot_dtb_binary" ]; then
		oe_runmake EXT_DTB=$deployed_uboot_dtb_binary
		install ${UBOOT_BINARY} ${DEPLOYDIR}/${UBOOT_IMAGE}
	elif [ -e "${DEPLOYDIR}/${UBOOT_NODTB_IMAGE}" -a -e "$deployed_uboot_dtb_binary" ]; then
		cd ${DEPLOYDIR}
		cat ${UBOOT_NODTB_IMAGE} $deployed_uboot_dtb_binary | tee ${B}/${CONFIG_B_PATH}/${UBOOT_BINARY} > ${UBOOT_IMAGE}
	else
		bbwarn "Failure while adding public key to u-boot binary. Verified boot won't be available."
	fi
}

concat_dtb() {
	if [ "${UBOOT_SIGN_ENABLE}" = "1" -a "${PN}" = "${UBOOT_PN}" -a -n "${UBOOT_DTB_BINARY}" ]; then
		mkdir -p ${DEPLOYDIR}
		if [ -n "${UBOOT_CONFIG}" ]; then
			for config in ${UBOOT_MACHINE}; do
				CONFIG_B_PATH="${config}"
				cd ${B}/${config}
				concat_dtb_helper
			done
		else
			CONFIG_B_PATH=""
			cd ${B}
			concat_dtb_helper
		fi
	fi
}

# Install UBOOT_DTB_BINARY to datadir, so that kernel can use it for
# signing, and kernel will deploy UBOOT_DTB_BINARY after signs it.
install_helper() {
	if [ -f "${UBOOT_DTB_BINARY}" ]; then
		install -d ${D}${datadir}
		# UBOOT_DTB_BINARY is a symlink to UBOOT_DTB_IMAGE, so we
		# need both of them.
		install ${UBOOT_DTB_BINARY} ${D}${datadir}/${UBOOT_DTB_IMAGE}
		ln -sf ${UBOOT_DTB_IMAGE} ${D}${datadir}/${UBOOT_DTB_BINARY}
	else
		bbwarn "${UBOOT_DTB_BINARY} not found"
	fi
}


# Similarly, install u-boot-spl.dtb, u-boot-spl-nodtb.bin and
# u-boot-nodtb.bin so that we can re-create the U-boot FIT
# and the SPL even from within the Kernel do_install function
install_spl_helper() {
	if [ "${PN}" = "${UBOOT_PN}" ]; then
		if [ -f "spl/${SPL_DTB_BINARY}" ]; then
			install -d ${D}${datadir}
			install spl/${SPL_DTB_BINARY} ${D}${datadir}/${SPL_DTB_IMAGE}
			ln -sf {SPL_DTB_IMAGE} ${D}${datadir}/${SPL_DTB_BINARY}
		else
			bbwarn "${SPL_DTB_BINARY} not found"
		fi

		if [ -f "spl/${SPL_NODTB_BINARY}" ]; then
			install -d ${D}${datadir}
			install spl/${SPL_NODTB_BINARY} ${D}${datadir}/${SPL_NODTB_IMAGE}
			ln -sf {SPL_NODTB_IMAGE} ${D}${datadir}/${SPL_NODTB_BINARY}
		else
			bbwarn "${SPL_NODTB_BINARY} not found"
		fi

		if [ -f "${UBOOT_NODTB_BINARY}" ]; then
			install -d ${D}${datadir}
			install ${UBOOT_NODTB_BINARY} ${D}${datadir}/${UBOOT_NODTB_IMAGE}
			ln -sf {UBOOT_NODTB_IMAGE} ${D}${datadir}/${UBOOT_NODTB_BINARY}
		else
			bbwarn "${UBOOT_NODTB_BINARY} not found"
		fi
	fi

}

do_install_append() {
	if [ "${UBOOT_SIGN_ENABLE}" = "1" -a "${PN}" = "${UBOOT_PN}" -a -n "${UBOOT_DTB_BINARY}" ]; then
		if [ -n "${UBOOT_CONFIG}" ]; then
			for config in ${UBOOT_MACHINE}; do
				cd ${B}/${config}
				install_helper
			done
		else
			cd ${B}
			install_helper
		fi
	fi

	if [ "${SPL_SIGN_ENABLE}" = "1" -a -n "${SPL_DTB_BINARY}" -a -n "${UBOOT_NODTB_BINARY}" ]; then
		if [ -n "${UBOOT_CONFIG}" ]; then
			for config in ${UBOOT_MACHINE}; do
				i=$(expr $i + 1);
				for TYPE in ${UBOOT_CONFIG}; do
					j=$(expr $j + 1);
					if [ $j -eq $i ]; then
						cd ${B}/${config}
						install_spl_helper
						# assemble_uboot_fitimage
					fi
				done
				unset j
			done
			unset i
		else
			cd ${B}
			install_spl_helper
			# assemble_uboot_fitimage
		fi
	fi

}

assemble_uboot_fitimage() {
	if [ "${PN}" = "${UBOOT_PN}" ]; then
		# U-boot's Makefile automatically creates the U-BOOT FIT, but doesn't
		# sign it. Since we're in the build directory, we can use the pristine
		# files. We also need to properly install the files to ${D} (see below)
		rm -f ${UBOOT_BINARY}
		rm -f ${SPL_BINARY}
		spl_dir = "spl/"

		if [ -n "${UBOOT_CONFIG}" ]; then
			uboot_dest_binary = "u-boot-${TYPE}.${UBOOT_SUFFIX}"
		else
			uboot_dest_binary = "${UBOOT_BINARY}"
		fi
	elif [ "${PN}" = "${KERNEL_PN}" ]; then
		if [ "${UBOOT_SIGN_ENABLE}" = "0" ]; then
			# No need to re-sign the U-boot FIT
			exit 0
		fi

		#  In the Kernel PN we need to fetch the u-boot-nodtb.img and
		#  u-boot-spl.dtb from staging, sign, and then leave to do_deploy
		#  to place things in the imagedir. It doesn't make sense to install
		#  those files since they can only work combined with the kernel now.
		cp ${STAGING_DATADIR}/${UBOOT_NODTB_IMAGE} ${UBOOT_NODTB_BINARY}
		cp ${STAGING_DATADIR}/${SPL_DTB_IMAGE} ${SPL_DTB_BINARY}
		cp ${STAGING_DATADIR}/${SPL_NODTB_IMAGE} ${SPL_NODTB_BINARY}
		spl_dir = ""
		uboot_dest_binary = "${UBOOT_BINARY}"
	fi

	# Assemble ITS with signature and hashes info
	uboot_fitimage_assemble uboot-fit-image.its \
		${UBOOT_NODTB_IMAGE} ${UBOOT_DTB_IMAGE}

	# (Re-)create the U-Boot FIT
	${UBOOT_MKIMAGE} \
		${@'-D "${UBOOT_MKIMAGE_DTCOPTS}"' if len('${UBOOT_MKIMAGE_DTCOPTS}') else ''} \
		-f uboot-fit-image.its ${uboot_dest_binary}

	# Sign the FIT, put pubkey in u-boot-spl.dtb
	${UBOOT_MKIMAGE_SIGN} \
		${@'-D "${UBOOT_MKIMAGE_DTCOPTS}"' if len('${UBOOT_MKIMAGE_DTCOPTS}') else ''} \
		-F -k "${UBOOT_SIGN_KEYDIR}" \
		-K ${spl_dir}${SPL_DTB_BINARY} \
		-r ${uboot_dest_binary} \
		${UBOOT_MKIMAGE_SIGN_ARGS}

	# Concatenate the SPL + SPL dtb (with pubkey)
	cat ${spl_dir}${SPL_NODTB_IMAGE} ${spl_dir}${SPL_DTB_BINARY} > ${SPL_BINARY}

	# If we're UBOOT_PN, need to re-install changed binaries
	if [ "${PN}" = "${UBOOT_PN}" ]; then
		if [ -n "${UBOOT_CONFIG}" ]; then
			install -D -m 644 ${uboot_dest_binary} ${D}/boot/u-boot-${TYPE}-${PV}-${PR}.${UBOOT_SUFFIX}
			ln -sf u-boot-${TYPE}-${PV}-${PR}.${UBOOT_SUFFIX} ${D}/boot/${UBOOT_BINARY}-${TYPE}
			ln -sf u-boot-${TYPE}-${PV}-${PR}.${UBOOT_SUFFIX} ${D}/boot/${UBOOT_BINARY}
			install -m 644 ${SPL_BINARY} ${D}/boot/${SPL_IMAGE}-${TYPE}-${PV}-${PR}
			ln -sf ${SPL_IMAGE}-${TYPE}-${PV}-${PR} ${D}/boot/${SPL_BINARYNAME}-${TYPE}
			ln -sf ${SPL_IMAGE}-${TYPE}-${PV}-${PR} ${D}/boot/${SPL_BINARYNAME}
		else
			install -D -m 644 ${uboot_dest_binary} ${D}/boot/${UBOOT_IMAGE}
			ln -sf ${UBOOT_IMAGE} ${D}/boot/${UBOOT_BINARY}
			install -m 644 ${SPL_BINARY} ${D}/boot/${SPL_IMAGE}
			ln -sf ${SPL_IMAGE} ${D}/boot/${SPL_BINARYNAME}
		fi
	fi
}

do_deploy_prepend_pn-${UBOOT_PN}() {
	if [ "${UBOOT_SIGN_ENABLE}" = "1" -a -n "${UBOOT_DTB_BINARY}" ]; then
		concat_dtb

}

do_deploy_prepend_pn-${KERNEL_PN}() {
	if [ "${UBOOT_SIGN_ENABLE}" = "1" -a "${SPL_SIGN_ENABLE}" = "1" \
	     -a -n "${SPL_BINARY}" -a -n "${SPL_DTB_BINARY}" ]; then
		install -D -m 644 ${B}/${UBOOT_BINARY} ${DEPLOYDIR}/${UBOOT_IMAGE}
		install -m 644 ${B}/${SPL_BINARY} ${DEPLOYDIR}/${SPL_IMAGE}
		cd ${DEPLOYDIR}
		rm -f ${UBOOT_BINARY} ${UBOOT_SYMLINK}
		ln -sf ${UBOOT_IMAGE} ${UBOOT_SYMLINK}
		ln -sf ${UBOOT_IMAGE} ${UBOOT_BINARY}
		rm -f ${DEPLOYDIR}/${SPL_BINARYNAME} ${DEPLOYDIR}/${SPL_SYMLINK}
		ln -sf ${SPL_IMAGE} ${DEPLOYDIR}/${SPL_BINARYNAME}
		ln -sf ${SPL_IMAGE} ${DEPLOYDIR}/${SPL_SYMLINK}
	fi
}

python () {
    if d.getVar('UBOOT_SIGN_ENABLE') == '1' and d.getVar('PN') == d.getVar('UBOOT_PN') and d.getVar('UBOOT_DTB_BINARY'):
        kernel_pn = d.getVar('KERNEL_PN')

        # Make "bitbake u-boot -cdeploy" deploys the signed u-boot.dtb
        d.appendVarFlag('do_deploy', 'depends', ' %s:do_deploy' % kernel_pn)
}

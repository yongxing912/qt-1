# Copyright 1999-2014 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

# @ECLASS: qt4-build-multilib.eclass
# @MAINTAINER:
# Qt herd <qt@gentoo.org>
# @AUTHOR:
# Davide Pesavento <pesa@gentoo.org>
# @BLURB: Eclass for Qt4 split ebuilds with multilib support.
# @DESCRIPTION:
# This eclass contains various functions that are used when building Qt4.
# Requires EAPI 5.

case ${EAPI} in
	5)	: ;;
	*)	die "qt4-build-multilib.eclass: unsupported EAPI=${EAPI:-0}" ;;
esac

inherit eutils flag-o-matic multilib toolchain-funcs # TODO multilib-minimal

HOMEPAGE="http://qt-project.org/ http://qt.digia.com/"
LICENSE="|| ( LGPL-2.1 GPL-3 )"
SLOT="4"

case ${PV} in
	4.?.9999)
		QT4_BUILD_TYPE="live"
		EGIT_REPO_URI=(
			"git://gitorious.org/qt/qt.git"
			"https://git.gitorious.org/qt/qt.git"
		)
		EGIT_BRANCH=${PV%.9999}
		inherit git-r3
		;;
	*)
		QT4_BUILD_TYPE="release"
		MY_P=qt-everywhere-opensource-src-${PV/_/-}
		SRC_URI="http://download.qt-project.org/official_releases/qt/${PV%.*}/${PV}/${MY_P}.tar.gz"
		S=${WORKDIR}/${MY_P}
		;;
esac

if [[ ${PN} != qttranslations ]]; then
	IUSE="aqua debug pch"
	[[ ${PN} != qtxmlpatterns ]] && IUSE+=" +exceptions"
fi

DEPEND="virtual/pkgconfig"
if [[ ${QT4_BUILD_TYPE} == live ]]; then
	DEPEND+=" dev-lang/perl"
fi

EXPORT_FUNCTIONS pkg_setup src_unpack src_prepare src_configure src_compile src_install src_test pkg_postinst pkg_postrm

# @FUNCTION: qt4-build-multilib_pkg_setup
# @DESCRIPTION:
# Sets up PATH and LD_LIBRARY_PATH.
qt4-build-multilib_pkg_setup() {
	# Warn users of possible breakage when downgrading to a previous release.
	# Downgrading revisions within the same release is safe.
	if has_version ">${CATEGORY}/${P}-r9999:4"; then
		ewarn
		ewarn "Downgrading Qt is completely unsupported and can break your system!"
		ewarn
	fi

	PATH="${S}/bin${PATH:+:}${PATH}"
	if [[ ${CHOST} != *-darwin* ]]; then
		LD_LIBRARY_PATH="${S}/lib${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH}"
	else
		DYLD_LIBRARY_PATH="${S}/lib${DYLD_LIBRARY_PATH:+:}${DYLD_LIBRARY_PATH}"
	fi
}

# @ECLASS-VARIABLE: QT4_EXTRACT_DIRECTORIES
# @DEFAULT_UNSET
# @DESCRIPTION:
# Space-separated list including the directories that will be extracted from
# Qt tarball.

# @ECLASS-VARIABLE: QT4_TARGET_DIRECTORIES
# @DEFAULT_UNSET
# @DESCRIPTION:
# Arguments for build_target_directories. Takes the directories in which the
# code should be compiled. This is a space-separated list.

# @FUNCTION: qt4-build-multilib_src_unpack
# @DESCRIPTION:
# Unpacks the sources.
qt4-build-multilib_src_unpack() {
	if [[ $(gcc-major-version) -lt 4 ]] || [[ $(gcc-major-version) -eq 4 && $(gcc-minor-version) -lt 4 ]]; then
		ewarn
		ewarn "Using a GCC version lower than 4.4 is not supported."
		ewarn
	fi

	if [[ ${PN} == qtwebkit ]]; then
		eshopts_push -s extglob
		if is-flagq '-g?(gdb)?([1-9])'; then
			ewarn
			ewarn "You have enabled debug info (probably have -g or -ggdb in your CFLAGS/CXXFLAGS)."
			ewarn "You may experience really long compilation times and/or increased memory usage."
			ewarn "If compilation fails, please try removing -g/-ggdb before reporting a bug."
			ewarn "For more info check out https://bugs.gentoo.org/307861"
			ewarn
		fi
		eshopts_pop
	fi

	case ${QT4_BUILD_TYPE} in
		live)
			git-r3_src_unpack
			;;
		release)
			local tarball="${MY_P}.tar.gz" target= targets=
			# On MacOS we need src/gui/kernel/qapplication_mac.mm for platform detection
			for target in \
				bin config.tests configure LICENSE.GPL3 LICENSE.LGPL mkspecs \
				projects.pro qmake src/{qbase,qt_install,qt_targets}.pri \
				$([[ ${CHOST} == *-apple-darwin* ]] && echo src/gui/kernel/qapplication_mac.mm) \
				${QT4_EXTRACT_DIRECTORIES}
			do
				targets+="${MY_P}/${target} "
			done

			ebegin "Unpacking parts of ${tarball}:" ${targets//${MY_P}\/}
			tar -xzf "${DISTDIR}"/${tarball} ${targets}
			eend $? || die "failed to unpack"
			;;
	esac
}

# @ECLASS-VARIABLE: PATCHES
# @DEFAULT_UNSET
# @DESCRIPTION:
# PATCHES array variable containing all various patches to be applied.
# This variable is expected to be defined in global scope of ebuild.
# Make sure to specify the full path. This variable is utilised in
# src_prepare() phase.
#
# @CODE
#   PATCHES=( "${FILESDIR}/mypatch.patch"
#             "${FILESDIR}/patches_folder/" )
# @CODE

# @FUNCTION: qt4-build-multilib_src_prepare
# @DESCRIPTION:
# Prepare the sources before the configure phase. Strip CFLAGS if necessary, and fix
# the build system in order to respect CFLAGS/CXXFLAGS/LDFLAGS specified in make.conf.
qt4-build-multilib_src_prepare() {
	qt4_prepare_env

	if [[ ${QT4_BUILD_TYPE} == live ]]; then
		QTDIR="." ./bin/syncqt || die "syncqt failed"
	fi

	if [[ ${PN} != qtcore ]]; then
		skip_qmake_build
		skip_project_generation
		symlink_tools_to_buildtree
	fi

	# skip X11 tests in non-gui packages to avoid spurious dependencies
	if has ${PN} qtbearer qtcore qtdbus qtscript qtsql qttest qttranslations qtxmlpatterns; then
		sed -i -e '/^if.*PLATFORM_X11.*CFG_GUI/,/^fi$/d' configure || die
	fi

	if use_if_iuse aqua; then
		sed -e '/^CONFIG/s:app_bundle::' \
			-e '/^CONFIG/s:plugin_no_soname:plugin_with_soname absolute_library_soname:' \
			-i mkspecs/$(qt4_get_mkspec)/qmake.conf || die
	fi

	# Bug 261632
	if use ppc64; then
		append-flags -mminimal-toc
	fi

	# Bug 373061
	# qmake bus errors with -O2 or -O3 but -O1 works
	if [[ ${CHOST} == *86*-apple-darwin* ]]; then
		replace-flags -O[23] -O1
	fi

	# Bug 417105
	# graphite on gcc 4.7 causes miscompilations
	if [[ $(gcc-version) == "4.7" ]]; then
		filter-flags -fgraphite-identity
	fi

	# Respect CC, CXX, {C,CXX,LD}FLAGS in .qmake.cache
	sed -e "/^SYSTEM_VARIABLES=/i \
		CC='$(tc-getCC)'\n\
		CXX='$(tc-getCXX)'\n\
		CFLAGS='${CFLAGS}'\n\
		CXXFLAGS='${CXXFLAGS}'\n\
		LDFLAGS='${LDFLAGS}'\n\
		QMakeVar set QMAKE_CFLAGS_RELEASE\n\
		QMakeVar set QMAKE_CFLAGS_DEBUG\n\
		QMakeVar set QMAKE_CXXFLAGS_RELEASE\n\
		QMakeVar set QMAKE_CXXFLAGS_DEBUG\n\
		QMakeVar set QMAKE_LFLAGS_RELEASE\n\
		QMakeVar set QMAKE_LFLAGS_DEBUG\n"\
		-i configure \
		|| die "sed SYSTEM_VARIABLES failed"

	# Respect CC, CXX, LINK and *FLAGS in config.tests
	find config.tests/unix -name '*.test' -type f -print0 | xargs -0 \
		sed -i -e "/bin\/qmake/ s: \"\$SRCDIR/: \
			'QMAKE_CC=$(tc-getCC)'    'QMAKE_CXX=$(tc-getCXX)'      'QMAKE_LINK=$(tc-getCXX)' \
			'QMAKE_CFLAGS+=${CFLAGS}' 'QMAKE_CXXFLAGS+=${CXXFLAGS}' 'QMAKE_LFLAGS+=${LDFLAGS}'&:" \
		|| die "sed config.tests failed"

	# Bug 172219
	sed -e 's:/X11R6/:/:' -i mkspecs/$(qt4_get_mkspec)/qmake.conf || die

	if [[ ${CHOST} == *-darwin* ]]; then
		# Set FLAGS *and* remove -arch, since our gcc-apple is multilib
		# crippled (by design) :/
		local mac_gpp_conf=
		if [[ -f mkspecs/common/mac-g++.conf ]]; then
			# qt < 4.8 has mac-g++.conf
			mac_gpp_conf="mkspecs/common/mac-g++.conf"
		elif [[ -f mkspecs/common/g++-macx.conf ]]; then
			# qt >= 4.8 has g++-macx.conf
			mac_gpp_conf="mkspecs/common/g++-macx.conf"
		else
			die "no known conf file for mac found"
		fi
		sed \
			-e "s:QMAKE_CFLAGS_RELEASE.*=.*:QMAKE_CFLAGS_RELEASE=${CFLAGS}:" \
			-e "s:QMAKE_CXXFLAGS_RELEASE.*=.*:QMAKE_CXXFLAGS_RELEASE=${CXXFLAGS}:" \
			-e "s:QMAKE_LFLAGS_RELEASE.*=.*:QMAKE_LFLAGS_RELEASE=-headerpad_max_install_names ${LDFLAGS}:" \
			-e "s:-arch\s\w*::g" \
			-i ${mac_gpp_conf} \
			|| die "sed ${mac_gpp_conf} failed"

		# Fix configure's -arch settings that appear in qmake/Makefile and also
		# fix arch handling (automagically duplicates our -arch arg and breaks
		# pch). Additionally disable Xarch support.
		local mac_gcc_confs="${mac_gpp_conf}"
		if [[ -f mkspecs/common/gcc-base-macx.conf ]]; then
			mac_gcc_confs+=" mkspecs/common/gcc-base-macx.conf"
		fi
		sed \
			-e "s:-arch i386::" \
			-e "s:-arch ppc::" \
			-e "s:-arch x86_64::" \
			-e "s:-arch ppc64::" \
			-e "s:-arch \$i::" \
			-e "/if \[ ! -z \"\$NATIVE_64_ARCH\" \]; then/,/fi/ d" \
			-e "s:CFG_MAC_XARCH=yes:CFG_MAC_XARCH=no:g" \
			-e "s:-Xarch_x86_64::g" \
			-e "s:-Xarch_ppc64::g" \
			-i configure ${mac_gcc_confs} \
			|| die "sed -arch/-Xarch failed"

		# On Snow Leopard don't fall back to 10.5 deployment target.
		if [[ ${CHOST} == *-apple-darwin10 ]]; then
			sed -e "s:QMakeVar set QMAKE_MACOSX_DEPLOYMENT_TARGET.*:QMakeVar set QMAKE_MACOSX_DEPLOYMENT_TARGET 10.6:g" \
				-e "s:-mmacosx-version-min=10.[0-9]:-mmacosx-version-min=10.6:g" \
				-i configure ${mac_gpp_conf} \
				|| die "sed deployment target failed"
		fi
	fi

	# this is needed for all systems with a separate -liconv, except
	# Darwin, for which the sources already cater for -liconv
	if use !elibc_glibc && [[ ${CHOST} != *-darwin* ]]; then
		sed -e 's|mac:\(LIBS += -liconv\)|\1|g' \
			-i config.tests/unix/iconv/iconv.pro \
			|| die "sed iconv.pro failed"
	fi

	# we need some patches for Solaris
	sed -i -e '/^QMAKE_LFLAGS_THREAD/a\QMAKE_LFLAGS_DYNAMIC_LIST = -Wl,--dynamic-list,' \
		mkspecs/$(qt4_get_mkspec)/qmake.conf || die
	# use GCC over SunStudio
	sed -i -e '/PLATFORM=solaris-cc/s/cc/g++/' configure || die
	# do not flirt with non-Prefix stuff, we're quite possessive
	sed -i -e '/^QMAKE_\(LIB\|INC\)DIR\(_X11\|_OPENGL\|\)\t/s/=.*$/=/' \
		mkspecs/$(qt4_get_mkspec)/qmake.conf || die

	# apply patches
	[[ ${PATCHES[@]} ]] && epatch "${PATCHES[@]}"
	debug-print "$FUNCNAME: applying user patches"
	epatch_user
}

# @FUNCTION: qt4-build-multilib_src_configure
# @DESCRIPTION:
# Runs configure and generates Makefiles for all QT4_TARGET_DIRECTORIES.
qt4-build-multilib_src_configure() {
	# configure arguments
	local conf="
		-prefix ${QT4_PREFIX}
		-bindir ${QT4_BINDIR}
		-libdir ${QT4_LIBDIR}
		-docdir ${QT4_DOCDIR}
		-headerdir ${QT4_HEADERDIR}
		-plugindir ${QT4_PLUGINDIR}
		-importdir ${QT4_IMPORTDIR}
		-datadir ${QT4_DATADIR}
		-translationdir ${QT4_TRANSLATIONDIR}
		-sysconfdir ${QT4_SYSCONFDIR}
		-examplesdir ${QT4_EXAMPLESDIR}
		-demosdir ${QT4_DEMOSDIR}
		-opensource -confirm-license
		-shared -fast -largefile -stl -verbose
		-nomake examples -nomake demos"

	# convert tc-arch to the values supported by Qt
	case $(tc-arch) in
		amd64|x64-*)		  conf+=" -arch x86_64" ;;
		ppc*-macos)		  conf+=" -arch ppc" ;;
		ppc*)			  conf+=" -arch powerpc" ;;
		sparc*)			  conf+=" -arch sparc" ;;
		x86-macos)		  conf+=" -arch x86" ;;
		x86*)			  conf+=" -arch i386" ;;
		alpha|arm|ia64|mips|s390) conf+=" -arch $(tc-arch)" ;;
		hppa|sh)		  conf+=" -arch generic" ;;
		*) die "$(tc-arch) is unsupported by this eclass. Please file a bug." ;;
	esac

	conf+=" -platform $(qt4_get_mkspec)"

	# debug/release
	if use_if_iuse debug; then
		conf+=" -debug"
	else
		conf+=" -release"
	fi
	conf+=" -no-separate-debug-info"

	# exceptions USE flag
	conf+=" $(in_iuse exceptions && qt_use exceptions || echo -exceptions)"

	# disable rpath (bug 380415), except on prefix (bug 417169)
	use prefix || conf+=" -no-rpath"

	# precompiled headers don't work on hardened, where the flag is masked
	conf+=" $(in_iuse pch && qt_use pch || echo -no-pch)"

	# -reduce-relocations
	# This flag seems to introduce major breakage to applications,
	# mostly to be seen as a core dump with the message "QPixmap: Must
	# construct a QApplication before a QPaintDevice" on Solaris.
	#   -- Daniel Vergien
	[[ ${CHOST} != *-solaris* ]] && conf+=" -reduce-relocations"

	# this one is needed for all systems with a separate -liconv, apart from
	# Darwin, for which the sources already cater for -liconv
	if use !elibc_glibc && [[ ${CHOST} != *-darwin* ]]; then
		conf+=" -liconv"
	fi

	if use_if_iuse aqua; then
		# On (snow) leopard use the new (frameworked) cocoa code.
		if [[ ${CHOST##*-darwin} -ge 9 ]]; then
			conf+=" -cocoa -framework"
			# We need the source's headers, not the installed ones.
			conf+=" -I${S}/include"
			# Add hint for the framework location.
			conf+=" -F${QT4_LIBDIR}"

			# We are crazy and build cocoa + qt3support :-)
			if use_if_iuse qt3support; then
				sed -e "/case \"\$PLATFORM,\$CFG_MAC_COCOA\" in/,/;;/ s|CFG_QT3SUPPORT=\"no\"|CFG_QT3SUPPORT=\"yes\"|" \
					-i configure || die
			fi
		else
			conf+=" -no-framework"
		fi
	fi

	conf+=" ${myconf}"
	myconf=

	einfo "Configuring with:" ${conf}
	./configure ${conf} || die "configure failed"

	local dir
	for dir in ${QT4_TARGET_DIRECTORIES}; do
		pushd ${dir} >/dev/null || die
		einfo "Running qmake in: ${dir}"
		"${S}"/bin/qmake \
			"LIBS+=-L${QT4_LIBDIR}" \
			"CONFIG+=nostrip" \
			|| die "qmake failed"
		popd >/dev/null || die
	done
}

# @FUNCTION: qt4-build-multilib_src_compile
# @DESCRIPTION:
# Compiles the code in QT4_TARGET_DIRECTORIES.
qt4-build-multilib_src_compile() {
	local dir
	for dir in ${QT4_TARGET_DIRECTORIES}; do
		pushd ${dir} >/dev/null || die
		emake \
			AR="$(tc-getAR) cqs" \
			CC="$(tc-getCC)" \
			CXX="$(tc-getCXX)" \
			LINK="$(tc-getCXX)" \
			RANLIB=":" \
			STRIP=":"
		popd >/dev/null || die
	done
}

# @FUNCTION: qt4-build-multilib_src_test
# @DESCRIPTION:
# Runs unit tests in all QT4_TARGET_DIRECTORIES.
qt4-build-multilib_src_test() {
	# QtMultimedia does not have any test suite (bug #332299)
	[[ ${PN} == qtmultimedia ]] && return

	local dir
	for dir in ${QT4_TARGET_DIRECTORIES}; do
		emake -j1 check -C ${dir}
	done
}

# @FUNCTION: qt4-build-multilib_src_install
# @DESCRIPTION:
# Performs the actual installation, running 'emake install'
# inside all QT4_TARGET_DIRECTORIES, and installing qconfigs.
qt4-build-multilib_src_install() {
	local dir
	for dir in ${QT4_TARGET_DIRECTORIES}; do
		pushd ${dir} >/dev/null || die
		emake INSTALL_ROOT="${D}" install
		popd >/dev/null || die
	done

	# install private headers of a few modules
	if has ${PN} qtcore qtdeclarative qtgui qtscript; then
		local moduledir=${PN#qt}
		local modulename=Qt$(tr 'a-z' 'A-Z' <<< ${moduledir:0:1})${moduledir:1}
		[[ ${moduledir} == core ]] && moduledir=corelib

		insinto "${QT4_HEADERDIR#${EPREFIX}}"/${modulename}/private
		find "${S}"/src/${moduledir} -type f -name '*_p.h' -exec doins '{}' + || die
	fi

	install_qconfigs
	fix_library_files
	fix_includes

	# remove .la files since we are building only shared libraries
	prune_libtool_files
}

# @FUNCTION: qt4-build-multilib_pkg_postinst
# @DESCRIPTION:
# Regenerate configuration, plus throw a message about possible
# breakages and proposed solutions.
qt4-build-multilib_pkg_postinst() {
	generate_qconfigs
}

# @FUNCTION: qt4-build-multilib_pkg_postrm
# @DESCRIPTION:
# Regenerate configuration when the package is completely removed.
qt4-build-multilib_pkg_postrm() {
	generate_qconfigs
}

# @FUNCTION: qt_use
# @USAGE: <flag> [feature] [enableval]
# @DESCRIPTION:
# This will echo "-${enableval}-${feature}" if <flag> is enabled, or
# "-no-${feature}" if it's disabled. If [feature] is not specified,
# <flag> will be used for that. If [enableval] is not specified, the
# "-${enableval}" prefix is omitted.
qt_use() {
	use "$1" && echo "${3:+-$3}-${2:-$1}" || echo "-no-${2:-$1}"
}


######  Internal functions  ######

# @FUNCTION: qt4_prepare_env
# @INTERNAL
# @DESCRIPTION:
# Prepares the environment for building Qt.
qt4_prepare_env() {
	# setup installation directories
	QT4_PREFIX=${EPREFIX}/usr
	QT4_HEADERDIR=${QT4_PREFIX}/include/qt4
	QT4_LIBDIR=${QT4_PREFIX}/$(get_libdir)/qt4
	QT4_PCDIR=${QT4_PREFIX}/$(get_libdir)/pkgconfig
	QT4_BINDIR=${QT4_LIBDIR}/bin
	QT4_PLUGINDIR=${QT4_LIBDIR}/plugins
	QT4_IMPORTDIR=${QT4_LIBDIR}/imports
	QT4_DATADIR=${QT4_PREFIX}/share/qt4
	QT4_DOCDIR=${QT4_PREFIX}/share/doc/qt-${PV}
	QT4_TRANSLATIONDIR=${QT4_DATADIR}/translations
	QT4_EXAMPLESDIR=${QT4_DATADIR}/examples
	QT4_DEMOSDIR=${QT4_DATADIR}/demos
	QT4_SYSCONFDIR=${EPREFIX}/etc/qt4
	QMAKE_LIBDIR_QT=${QT4_LIBDIR}

	PLATFORM=$(qt4_get_mkspec)
	unset QMAKESPEC

	export XDG_CONFIG_HOME="${T}"
}

# @ECLASS-VARIABLE: QCONFIG_ADD
# @DESCRIPTION:
# List options that need to be added to QT_CONFIG in qconfig.pri
: ${QCONFIG_ADD:=}

# @ECLASS-VARIABLE: QCONFIG_REMOVE
# @DESCRIPTION:
# List options that need to be removed from QT_CONFIG in qconfig.pri
: ${QCONFIG_REMOVE:=}

# @ECLASS-VARIABLE: QCONFIG_DEFINE
# @DESCRIPTION:
# List variables that should be defined at the top of QtCore/qconfig.h
: ${QCONFIG_DEFINE:=}

# @FUNCTION: install_qconfigs
# @INTERNAL
# @DESCRIPTION:
# Install gentoo-specific mkspecs configurations.
install_qconfigs() {
	local x
	if [[ -n ${QCONFIG_ADD} || -n ${QCONFIG_REMOVE} ]]; then
		for x in QCONFIG_ADD QCONFIG_REMOVE; do
			[[ -n ${!x} ]] && echo ${x}=${!x} >> "${T}"/${PN}-qconfig.pri
		done
		insinto ${QT4_DATADIR#${EPREFIX}}/mkspecs/gentoo
		doins "${T}"/${PN}-qconfig.pri
	fi

	if [[ -n ${QCONFIG_DEFINE} ]]; then
		for x in ${QCONFIG_DEFINE}; do
			echo "#define ${x}" >> "${T}"/gentoo-${PN}-qconfig.h
		done
		insinto ${QT4_HEADERDIR#${EPREFIX}}/Gentoo
		doins "${T}"/gentoo-${PN}-qconfig.h
	fi
}

# @FUNCTION: generate_qconfigs
# @INTERNAL
# @DESCRIPTION:
# Generates gentoo-specific qconfig.{h,pri}.
generate_qconfigs() {
	if [[ -n ${QCONFIG_ADD} || -n ${QCONFIG_REMOVE} || -n ${QCONFIG_DEFINE} || ${PN} == qtcore ]]; then
		local x qconfig_add qconfig_remove qconfig_new
		for x in "${ROOT}${QT4_DATADIR}"/mkspecs/gentoo/*-qconfig.pri; do
			[[ -f ${x} ]] || continue
			qconfig_add+=" $(sed -n 's/^QCONFIG_ADD=//p' "${x}")"
			qconfig_remove+=" $(sed -n 's/^QCONFIG_REMOVE=//p' "${x}")"
		done

		# these error checks do not use die because dying in pkg_post{inst,rm}
		# just makes things worse.
		if [[ -e "${ROOT}${QT4_DATADIR}"/mkspecs/gentoo/qconfig.pri ]]; then
			# start with the qconfig.pri that qtcore installed
			if ! cp "${ROOT}${QT4_DATADIR}"/mkspecs/gentoo/qconfig.pri \
				"${ROOT}${QT4_DATADIR}"/mkspecs/qconfig.pri; then
				eerror "cp qconfig failed."
				return 1
			fi

			# generate list of QT_CONFIG entries from the existing list
			# including qconfig_add and excluding qconfig_remove
			for x in $(sed -n 's/^QT_CONFIG +=//p' \
				"${ROOT}${QT4_DATADIR}"/mkspecs/qconfig.pri) ${qconfig_add}; do
					has ${x} ${qconfig_remove} || qconfig_new+=" ${x}"
			done

			# replace the existing QT_CONFIG list with qconfig_new
			if ! sed -i -e "s/QT_CONFIG +=.*/QT_CONFIG += ${qconfig_new}/" \
				"${ROOT}${QT4_DATADIR}"/mkspecs/qconfig.pri; then
				eerror "Sed for QT_CONFIG failed"
				return 1
			fi

			# create Gentoo/qconfig.h
			if [[ ! -e ${ROOT}${QT4_HEADERDIR}/Gentoo ]]; then
				if ! mkdir -p "${ROOT}${QT4_HEADERDIR}"/Gentoo; then
					eerror "mkdir ${QT4_HEADERDIR}/Gentoo failed"
					return 1
				fi
			fi
			: > "${ROOT}${QT4_HEADERDIR}"/Gentoo/gentoo-qconfig.h
			for x in "${ROOT}${QT4_HEADERDIR}"/Gentoo/gentoo-*-qconfig.h; do
				[[ -f ${x} ]] || continue
				cat "${x}" >> "${ROOT}${QT4_HEADERDIR}"/Gentoo/gentoo-qconfig.h
			done
		else
			rm -f "${ROOT}${QT4_DATADIR}"/mkspecs/qconfig.pri
			rm -f "${ROOT}${QT4_HEADERDIR}"/Gentoo/gentoo-qconfig.h
			rmdir "${ROOT}${QT4_DATADIR}"/mkspecs \
				"${ROOT}${QT4_DATADIR}" \
				"${ROOT}${QT4_HEADERDIR}"/Gentoo \
				"${ROOT}${QT4_HEADERDIR}" 2>/dev/null
		fi
	fi
}

# @FUNCTION: skip_qmake_build
# @INTERNAL
# @DESCRIPTION:
# Patches configure to skip qmake compilation, as it's already installed by qtcore.
skip_qmake_build() {
	sed -i -e "s:if true:if false:g" "${S}"/configure || die
}

# @FUNCTION: skip_project_generation
# @INTERNAL
# @DESCRIPTION:
# Exit the script early by throwing in an exit before all of the .pro files are scanned.
skip_project_generation() {
	sed -i -e "s:echo \"Finding:exit 0\n\necho \"Finding:g" "${S}"/configure || die
}

# @FUNCTION: symlink_tools_to_buildtree
# @INTERNAL
# @DESCRIPTION:
# Symlinks generated binaries to buildtree, so they can be used during compilation time.
symlink_tools_to_buildtree() {
	local bin
	for bin in "${QT4_BINDIR}"/{qmake,moc,rcc,uic}; do
		if [[ -e ${bin} ]]; then
			ln -s "${bin}" "${S}"/bin/ || die "failed to symlink ${bin}"
		fi
	done
}

# @FUNCTION: fix_library_files
# @INTERNAL
# @DESCRIPTION:
# Fixes the paths in *.la, *.prl, *.pc, as they are wrong due to sandbox and
# moves the *.pc files into the pkgconfig directory.
fix_library_files() {
	local libfile
	for libfile in "${D}"/${QT4_LIBDIR}/{*.la,*.prl,pkgconfig/*.pc}; do
		if [[ -e ${libfile} ]]; then
			sed -i -e "s:${S}/lib:${QT4_LIBDIR}:g" ${libfile} || die "sed on ${libfile} failed"
		fi
	done

	# pkgconfig files refer to WORKDIR/bin as the moc and uic locations
	for libfile in "${D}"/${QT4_LIBDIR}/pkgconfig/*.pc; do
		if [[ -e ${libfile} ]]; then
			sed -i -e "s:${S}/bin:${QT4_BINDIR}:g" ${libfile} || die "sed on ${libfile} failed"

		# Move .pc files into the pkgconfig directory
		dodir ${QT4_PCDIR#${EPREFIX}}
		mv ${libfile} "${D}"/${QT4_PCDIR}/ || die "moving ${libfile} to ${D}/${QT4_PCDIR}/ failed"
		fi
	done

	# Don't install an empty directory
	rmdir "${D}"/${QT4_LIBDIR}/pkgconfig
}

# @FUNCTION: fix_includes
# @DESCRIPTION:
# For MacOS X we need to add some symlinks when frameworks are
# being used, to avoid complications with some more or less stupid packages.
fix_includes() {
	if use_if_iuse aqua && [[ ${CHOST##*-darwin} -ge 9 ]]; then
		local frw dest f h rdir
		# Some packages tend to include <Qt/...>
		dodir "${QT4_HEADERDIR#${EPREFIX}}"/Qt

		# Fake normal headers when frameworks are installed... eases life later
		# on, make sure we use relative links though, as some ebuilds assume
		# these dirs exist in src_install to add additional files
		f=${QT4_HEADERDIR}
		h=${QT4_LIBDIR}
		while [[ -n ${f} && ${f%%/*} == ${h%%/*} ]] ; do
			f=${f#*/}
			h=${h#*/}
		done
		rdir=${h}
		f="../"
		while [[ ${h} == */* ]] ; do
			f="${f}../"
			h=${h#*/}
		done
		rdir="${f}${rdir}"

		for frw in "${D}${QT4_LIBDIR}"/*.framework; do
			[[ -e "${frw}"/Headers ]] || continue
			f=$(basename ${frw})
			dest="${QT4_HEADERDIR#${EPREFIX}}"/${f%.framework}
			dosym "${rdir}"/${f}/Headers "${dest}"

			# Link normal headers as well.
			for hdr in "${D}/${QT4_LIBDIR}/${f}"/Headers/*; do
				h=$(basename ${hdr})
				dosym "../${rdir}"/${f}/Headers/${h} \
					"${QT4_HEADERDIR#${EPREFIX}}"/Qt/${h}
			done
		done
	fi
}

# @FUNCTION: qt4_get_mkspec
# @RETURN: the specs-directory w/o path
# @INTERNAL
# @DESCRIPTION:
# Allows us to define which mkspecs dir we want to use.
qt4_get_mkspec() {
	local spec=

	case ${CHOST} in
		*-linux*)
			spec=linux ;;
		*-darwin*)
			use_if_iuse aqua &&
				spec=macx ||   # mac with carbon/cocoa
				spec=darwin ;; # darwin/mac with X11
		*-freebsd*|*-dragonfly*)
			spec=freebsd ;;
		*-netbsd*)
			spec=netbsd ;;
		*-openbsd*)
			spec=openbsd ;;
		*-aix*)
			spec=aix ;;
		hppa*-hpux*)
			spec=hpux ;;
		ia64*-hpux*)
			spec=hpuxi ;;
		*-solaris*)
			spec=solaris ;;
		*)
			die "${FUNCNAME}(): Unsupported CHOST '${CHOST}'" ;;
	esac

	case $(tc-getCXX) in
		*g++*)
			spec+=-g++ ;;
		*clang*)
			if [[ -d ${S}/mkspecs/unsupported/${spec}-clang ]]; then
				spec=unsupported/${spec}-clang
			else
				ewarn "${spec}-clang mkspec does not exist, falling back to ${spec}-g++"
				spec+=-g++
			fi ;;
		*icpc*)
			if [[ -d ${S}/mkspecs/${spec}-icc ]]; then
				spec+=-icc
			else
				ewarn "${spec}-icc mkspec does not exist, falling back to ${spec}-g++"
				spec+=-g++
			fi ;;
		*)
			die "${FUNCNAME}(): Unsupported compiler '$(tc-getCXX)'" ;;
	esac

	# Add -64 for 64-bit prefix profiles
	if use amd64-linux || use ia64-linux || use ppc64-linux ||
		use x64-macos ||
		use sparc64-freebsd || use x64-freebsd || use x64-openbsd ||
		use ia64-hpux ||
		use sparc64-solaris || use x64-solaris
	then
		[[ -d ${S}/mkspecs/${spec}-64 ]] && spec+=-64
	fi

	echo ${spec}
}
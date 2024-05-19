# Copyright 1999-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DOCS_BUILDER="doxygen"
DOCS_DEPEND="media-gfx/graphviz"
ROCM_SKIP_GLOBALS=1

LLVM_COMPAT=( 17 18 )

inherit cmake docs flag-o-matic llvm-r1 rocm

TEST_PV=${PV}

DESCRIPTION="C++ Heterogeneous-Compute Interface for Portability"
HOMEPAGE="https://github.com/ROCm/clr"
SRC_URI="https://github.com/ROCm/clr/archive/refs/tags/rocm-${PV}.tar.gz -> rocm-clr-${PV}.tar.gz
	https://github.com/ROCm/HIP/archive/refs/tags/rocm-${PV}.tar.gz -> hip-${PV}.tar.gz
	https://github.com/ROCm/hip-tests/archive/refs/tags/rocm-${TEST_PV}.tar.gz -> hip-test-${TEST_PV}.tar.gz"
S="${WORKDIR}/clr-rocm-${PV}/"
TEST_S="${WORKDIR}/hip-tests-rocm-${TEST_PV}/catch"

LICENSE="MIT"
SLOT="0/$(ver_cut 1-2)"
KEYWORDS="~amd64"

IUSE="debug test"
RESTRICT="!test? ( test )"

DEPEND="
	>=dev-util/rocminfo-5
	$(llvm_gen_dep '
		sys-devel/clang:${LLVM_SLOT}
	')
	dev-libs/rocm-comgr:${SLOT}
	dev-libs/rocr-runtime:${SLOT}
	x11-base/xorg-proto
	virtual/opengl
"
BDEPEND="test? ( dev-util/hipcc )"
RDEPEND="${DEPEND}
	dev-util/hipcc
	dev-perl/URI-Encode
	sys-devel/clang-runtime:=
	>=dev-libs/roct-thunk-interface-5"

PATCHES=(
	"${FILESDIR}/${PN}-5.7.1-disable-stack-protector.patch"
	"${FILESDIR}/${PN}-5.7.1-no_asan_doc.patch"
	"${FILESDIR}/${PN}-6.1.0-install.patch"
	"${FILESDIR}/${PN}-6.1.0-extend-isa-compatibility-check.patch"
)

hip_test_wrapper() {
	local CMAKE_USE_DIR="${TEST_S}"
	local BUILD_DIR="${TEST_S}_build"
	cd "${TEST_S}" || die
	$@
}

src_prepare() {
	# hipamd is itself built by cmake, and should never provide a
	# FindHIP.cmake module. But the reality is some package relies on it.
	# Set HIP and HIP Clang paths directly, don't search using heuristics
	sed -e "s:# Search for HIP installation:set(HIP_ROOT_DIR \"${EPREFIX}/usr\"):" \
		-e "s:#Set HIP_CLANG_PATH:set(HIP_CLANG_PATH \"$(get_llvm_prefix -d)/bin\"):" \
	    -i "${WORKDIR}"/HIP-rocm-${PV}/cmake/FindHIP.cmake || die

	cmake_src_prepare

	# With Clang>17 -amdgpu-early-inline-all=true causes OOMs in dependencies
	# https://github.com/llvm/llvm-project/issues/86332
	if [ "$LLVM_SLOT" != "17" ]; then
		sed -e "s/-mllvm=-amdgpu-early-inline-all=true //" -i hipamd/hip-config-amd.cmake || die
		sed -e "s/-mllvm=-amdgpu-early-inline-all=true;//" -i "${WORKDIR}"/HIP-rocm-${PV}/hip-lang-config.cmake.in
	fi

	local PATCHES=(
		"${FILESDIR}"/hip-test-6.0.2-hipcc-system-install.patch
		"${FILESDIR}"/hip-test-5.7.1-remove-incompatible-flag.patch
		"${FILESDIR}"/hip-test-6.1.0-disable-hipKerArgOptimization.patch
	)
	hip_test_wrapper cmake_src_prepare
}

src_configure() {
	# -Werror=strict-aliasing
	# https://bugs.gentoo.org/858383
	# https://github.com/ROCm/clr/issues/64
	#
	# Do not trust it for LTO either
	append-flags -fno-strict-aliasing
	filter-lto

	use debug && CMAKE_BUILD_TYPE="Debug"

	# Fix ld.lld linker error: https://github.com/ROCm/HIP/issues/3382
	# See also: https://github.com/gentoo/gentoo/pull/29097
	append-ldflags $(test-flags-CCLD -Wl,--undefined-version)

	local mycmakeargs=(
		-DCMAKE_PREFIX_PATH="$(get_llvm_prefix)"
		-DCMAKE_BUILD_TYPE=${buildtype}
		-DCMAKE_SKIP_RPATH=ON
		-DHIP_PLATFORM=amd
		-DHIP_COMMON_DIR="${WORKDIR}/HIP-rocm-${PV}"
		-DROCM_PATH="${EPREFIX}/usr"
		-DUSE_PROF_API=0
		-DFILE_REORG_BACKWARD_COMPATIBILITY=OFF
		-DCLR_BUILD_HIP=ON
		-DHIPCC_BIN_DIR="${EPREFIX}/usr/bin"
		-DOpenGL_GL_PREFERENCE="GLVND"
	)

	cmake_src_configure

	if use test; then
		local mycmakeargs=(
			-DROCM_PATH="${BUILD_DIR}"/hipamd
			-DHIP_PLATFORM=amd
			-DCMAKE_MODULE_PATH="${TEST_S}/external/Catch2/cmake/Catch2"
		)
		HIP_PATH="${EPREFIX}/usr" hip_test_wrapper cmake_src_configure
	fi
}

src_compile() {
	cmake_src_compile

	if use test; then
		HIP_PATH="${BUILD_DIR}"/hipamd \
			hip_test_wrapper cmake_src_compile build_tests
	fi
}

src_test() {
	check_amdgpu
	export LD_LIBRARY_PATH="${BUILD_DIR}/hipamd/lib"

	# TODO: research how to test Vulkan-related features.
	local CMAKE_SKIP_TESTS=(
		Unit_hipExternalMemoryGetMappedBuffer_Vulkan_Positive_Read_Write
		Unit_hipExternalMemoryGetMappedBuffer_Vulkan_Negative_Parameters
		Unit_hipImportExternalMemory_Vulkan_Negative_Parameters
		Unit_hipWaitExternalSemaphoresAsync_Vulkan_Positive_Binary_Semaphore
		Unit_hipWaitExternalSemaphoresAsync_Vulkan_Positive_Multiple_Semaphores
		Unit_hipWaitExternalSemaphoresAsync_Vulkan_Negative_Parameters
		Unit_hipSignalExternalSemaphoresAsync_Vulkan_Positive_Binary_Semaphore
		Unit_hipSignalExternalSemaphoresAsync_Vulkan_Positive_Multiple_Semaphores
		Unit_hipSignalExternalSemaphoresAsync_Vulkan_Negative_Parameters
		Unit_hipImportExternalSemaphore_Vulkan_Negative_Parameters
		Unit_hipDestroyExternalSemaphore_Vulkan_Negative_Parameters
	)

	MAKEOPTS="-j1" hip_test_wrapper cmake_src_test
}

src_install() {
	cmake_src_install

	# add version file that is required by some libraries
	mkdir "${ED}"/usr/include/rocm-core || die
	cat <<EOF > "${ED}"/usr/include/rocm-core/rocm_version.h || die
#pragma once
#define ROCM_VERSION_MAJOR $(ver_cut 1)
#define ROCM_VERSION_MINOR $(ver_cut 2)
#define ROCM_VERSION_PATCH $(ver_cut 3)
#define ROCM_BUILD_INFO "$(ver_cut 1-3).0-9999-unknown"
EOF
	dosym -r /usr/include/rocm-core/rocm_version.h /usr/include/rocm_version.h
}

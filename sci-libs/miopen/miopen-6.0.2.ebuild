# Copyright 1999-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

ROCM_VERSION=${PV}

inherit cmake flag-o-matic llvm rocm

GTEST_COMMIT="e2239ee6043f73722e7aa812a459f54a28552929"
GTEST_FILE="gtest-1.11.0_p20210611.tar.gz"

LLVM_MAX_SLOT=17

DESCRIPTION="AMD's Machine Intelligence Library"
HOMEPAGE="https://github.com/ROCm/MIOpen"

SRC_URI="https://github.com/ROCm/MIOpen/archive/rocm-${PV}.tar.gz -> MIOpen-${PV}.tar.gz
	test? ( https://github.com/google/googletest/archive/${GTEST_COMMIT}.tar.gz -> ${GTEST_FILE} )"

LICENSE="MIT"
KEYWORDS="~amd64"
SLOT="0/$(ver_cut 1-2)"

IUSE="debug test"
RESTRICT="!test? ( test )"

RDEPEND="
	dev-util/hip
	>=dev-db/sqlite-3.17
	sci-libs/rocBLAS:${SLOT}[${ROCM_USEDEP}]
	sci-libs/composable-kernel:${SLOT}[${ROCM_USEDEP}]
	dev-util/roctracer:${SLOT}[${ROCM_USEDEP}]
	>=dev-libs/boost-1.72
	dev-cpp/nlohmann_json
	dev-cpp/frugally-deep
"

DEPEND="${RDEPEND}"

BDEPEND="
	>=dev-libs/half-1.12.0-r1
	dev-build/rocm-cmake
"

S="${WORKDIR}/MIOpen-rocm-${PV}"

PATCHES=(
	"${FILESDIR}/${PN}"-6.0.2-enable-test.patch
	"${FILESDIR}/${PN}"-6.0.2-clang-17-offload-uniform.patch
)

src_prepare() {
	cmake_src_prepare

	sed -e "s:/opt/rocm/llvm:$(get_llvm_prefix ${LLVM_MAX_SLOT}) NO_DEFAULT_PATH:" \
		-e "s:/opt/rocm/hip:$(hipconfig -p) NO_DEFAULT_PATH:" \
		-e '/set( MIOPEN_INSTALL_DIR/s:miopen:${CMAKE_INSTALL_PREFIX}:' \
		-e '/MIOPEN_TIDY_ERRORS ALL/d' \
		-e 's/FLAGS_RELEASE} -s/FLAGS_RELEASE}/g' \
		-i CMakeLists.txt || die

	sed -e "/add_test/s:--build \${CMAKE_CURRENT_BINARY_DIR}:--build ${BUILD_DIR}:" \
		-i test/CMakeLists.txt || die

	sed -e "s:\${PROJECT_BINARY_DIR}/miopen/include:\${PROJECT_BINARY_DIR}/include:" \
		-i src/CMakeLists.txt || die

	sed -e "s:\${AMD_DEVICE_LIBS_PREFIX}/lib:${EPREFIX}/usr/lib/amdgcn/bitcode:" -i cmake/hip-config.cmake || die
}

src_configure() {
	if ! use debug; then
		append-cflags "-DNDEBUG"
		append-cxxflags "-DNDEBUG"
		CMAKE_BUILD_TYPE="Release"
	else
		CMAKE_BUILD_TYPE="Debug"
	fi

	# miopen 6.0.2 officially supports only clang-18 and requires patch for clang-17
	local hipcc_clang_version=$(hipcc --version | grep "clang version" | cut -d " " -f 3) || die
	if [[ $hipcc_clang_version == 17.* ]]; then
		local use_no_offload_uniform_block=OFF
	else
		local use_no_offload_uniform_block=ON
	fi

	local mycmakeargs=(
		-DCMAKE_SKIP_RPATH=ON
		-DAMDGPU_TARGETS="$(get_amdgpu_flags)"
		-DCMAKE_INSTALL_PREFIX="${EPREFIX}/usr"
		-DMIOPEN_BACKEND=HIP
		-DBoost_USE_STATIC_LIBS=OFF
		-DMIOPEN_USE_MLIR=OFF
		-DBUILD_TESTS=$(usex test ON OFF)
		-DBUILD_FILE_REORG_BACKWARD_COMPATIBILITY=OFF
		-DROCM_SYMLINK_LIBS=OFF
		-DMIOPEN_HIP_COMPILER_HAS_OPTION_OFFLOAD_UNIFORM_BLOCK=${use_no_offload_uniform_block}
	)

	if use test; then
		mycmakeargs+=(
			-DMIOPEN_TEST_ALL=ON
			-DBUILD_TESTING=ON
			-DMIOPEN_TEST_GDB=OFF
			-DGOOGLETEST_DIR="${WORKDIR}/googletest-${GTEST_COMMIT}"
		)
		for gpu_target in ${AMDGPU_TARGETS}; do
			mycmakeargs+=(-DMIOPEN_TEST_${gpu_target^^}=ON )
		done
	fi

	CXX=hipcc cmake_src_configure
}

src_test() {
	check_amdgpu
	LD_LIBRARY_PATH="${BUILD_DIR}"/lib cmake_src_test -j1
}

src_install() {
	cmake_src_install
}

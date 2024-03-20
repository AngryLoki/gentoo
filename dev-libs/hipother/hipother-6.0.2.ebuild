# Copyright 1999-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="ROCclr runtime implementation for non-AMD HIP platforms, like NVIDIA"
HOMEPAGE="https://github.com/ROCm/hipother"
SRC_URI="https://github.com/ROCm/hipother/archive/refs/tags/rocm-${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
KEYWORDS="~amd64"
SLOT="0/$(ver_cut 1)"

S="${WORKDIR}/hipother-rocm-${PV}"

src_install() {
	insinto /usr/include
	doins -r hipnv/include/hip
}

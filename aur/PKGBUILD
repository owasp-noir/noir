# Maintainer: HAHWUL <hahwul@gmail.com>
pkgname=noir
pkgver=0.30.0
pkgrel=1
pkgdesc="Attack surface detector that identifies endpoints by static analysis."
arch=('x86_64')
url="https://github.com/owasp-noir/noir"
license=('MIT')
source=("noir-${pkgver}::https://github.com/owasp-noir/noir/releases/download/v${pkgver}/noir-v${pkgver}-linux-x86_64")
sha256sums=('SKIP')

package() {
  install -Dm755 "${srcdir}/noir-${pkgver}" "${pkgdir}/usr/bin/noir"
  install -Dm644 "${srcdir}/../LICENSE" "${pkgdir}/usr/share/licenses/noir/LICENSE"
}

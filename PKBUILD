# Maintainer: CapitanOfLinux
pkgname=lse
pkgver=1.0
pkgrel=1
pkgdesc="LSE - Linux System Elements, a system information fetcher similar to Neofetch"
arch=('any')
url="https://github.com/CapitanOfLinux/lse-linux-system-element"
license=('GPL')
depends=('bash' 'lm_sensors' 'lshw' 'neofetch' 'coreutils')
source=("$pkgname.sh")
md5sums=('SKIP')

package() {
    install -Dm755 "$srcdir/$pkgname.sh" "$pkgdir/usr/bin/$pkgname"
}

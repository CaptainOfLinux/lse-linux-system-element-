# Maintainer: CaptainOfLinux <destansi52adam@example.com>
pkgname=lse
pkgver=1.0.0
pkgrel=1
pkgdesc="Minimal neofetch-style system information tool written in Bash"
arch=('any')
url="https://github.com/kullaniciadi/lse"
license=('MIT')
depends=('bash' 'coreutils' 'util-linux' 'procps-ng' 'grep' 'awk')
optdepends=('lm_sensors: CPU/GPU sıcaklık bilgileri için'
            'pciutils: GPU model bilgisi için'
            'smartmontools: disk modeli ve sağlık durumu için'
            'dmidecode: RAM marka/model bilgisi için'
            'nvidia-utils: NVIDIA GPU sıcaklık bilgisi için')
source=("$pkgname.sh")
sha256sums=('SKIP')

package() {
  install -Dm755 "$srcdir/$pkgname.sh" "$pkgdir/usr/bin/$pkgname"
}

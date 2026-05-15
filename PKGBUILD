# Maintainer: DuckTapeMan35 <luis.tomas.nogueira@gmail.com>
pkgname=duckwm
pkgver=0.1.0
pkgrel=1
pkgdesc="A constraint-based tiling window manager with Lua configuration"
arch=('x86_64')
url="https://github.com/DuckTapeMan35/duckwm"
license=('GPL-3.0-or-later')
depends=('libx11')
makedepends=('zig>=0.16.0')
optdepends=(
    'lua-language-server: LuaLS completion for config editing'
    'xterm: default terminal emulator in fallback config'
)
backup=('etc/duckwm/config.lua')
install=duckwm.install
source=("$pkgname-$pkgver.tar.gz::$url/archive/v$pkgver.tar.gz")
sha256sums=('SKIP')

build() {
    cd "$pkgname-$pkgver"
    zig build -Doptimize=ReleaseFast
    zig build meta
}

package() {
    cd "$pkgname-$pkgver"
    install -Dm755 zig-out/bin/duckwm \
        "$pkgdir/usr/bin/duckwm"
    install -Dm644 config/default.lua \
        "$pkgdir/etc/duckwm/config.lua"
    install -Dm644 dist/duckwm.desktop \
        "$pkgdir/usr/share/xsessions/duckwm.desktop"
    install -Dm644 dist/duckwm.desktop \
        "$pkgdir/usr/share/applications/duckwm.desktop"
    install -Dm644 meta/wm.lua \
        "$pkgdir/usr/share/duckwm/meta/wm.lua"
    install -Dm644 API.md \
        "$pkgdir/usr/share/doc/duckwm/API.md"
    install -Dm644 API.norg \
        "$pkgdir/usr/share/doc/duckwm/API.norg"
    install -Dm644 LICENSE \
        "$pkgdir/usr/share/licenses/duckwm/LICENSE"
    install -Dm644 NOTICE \
        "$pkgdir/usr/share/licenses/duckwm/NOTICE"
}

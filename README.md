# wmbattery with power draw

> Part of [wmodern](https://github.com/jaderfeijo/wmodern), a modern desktop on Window Maker: `wmodern install battery` installs it and keeps it up to date.

A patch for [`wmbattery`](https://www.dockapps.net/wmbattery), the battery dockapp for Window Maker, that shows the
**power the battery is delivering or taking right now, in watts**, where the plug icon used to be.

```
 13       two digits, whole watts, in the same LCD font as the percentage
 W -      the unit, and a sign:
            -   running on the battery (power draw)
            +   charging (power intake)
            =   on AC with the battery idle
```

The plug icon only said "plugged in or not"; the sign keeps that information (`+` or `=` means the charger is
connected, `-` means it is not) and adds how hard the machine is working. If the kernel does not report the power
the original plug icon is drawn, so nothing is lost on other hardware.

The number comes straight from the kernel: `/sys/class/power_supply/BAT*/power_now`, or `current_now × voltage_now`
on machines that only report those. With several batteries the power is summed. It updates when `wmbattery` refreshes
(every two to three seconds).

## Install

```
git clone https://github.com/jaderfeijo/wmbattery-power-draw.git
cd wmbattery-power-draw
./install.sh --dry-run            # see what it would do
./install.sh                      # build and install into ~/.local   (--install-deps installs the build tools)
```

`install.sh` downloads Debian's `wmbattery 2.56-1` source, **checks it against the SHA-256 sums in the `.dsc`**,
applies the patch, builds, and installs `wmbattery` into `~/.local/bin`. The system package is never touched.

Because `~/.local/bin` normally comes before `/usr/bin` on your `PATH`, a Dock entry that launches plain `wmbattery`
(and Window Maker's autostart) now runs the patched build. Replace the running one with
`pkill -x wmbattery; wmbattery &`; a docked copy goes back into its Dock slot. `./install.sh --uninstall` removes
it and the stock one is used again.

Build dependencies on Debian: `build-essential pkgconf patch curl libx11-dev libxext-dev libxpm-dev
libupower-glib-dev` (`./install.sh --install-deps` runs the `apt` command for you).

Options: `--prefix DIR`, `--source-dir DIR` (use source files you already downloaded), `--keep-build`, `--dry-run`.

## What is in the patch

`patches/0001-show-power-draw-instead-of-the-plug-icon.patch` changes only `wmbattery.c` (about 150 added lines):

* `read_power_watts()` reads the sysfs values;
* `draw_power()` clears the plug icon's area (x 5 to 16, the free column left of the charging icon), draws the digits
  with the existing small font sprites, then a 5×5 `W` and a 3×5 sign drawn pixel by pixel in the dockapp's teal;
* `recalc_window()` calls it, and falls back to the plug icon when the power is unknown.

## Tests

```
WMBATTERY_SOURCE_DIR=/path/to/downloaded/source tests/run.sh    # or without the variable: it downloads
```

Does a real build into a throwaway prefix and checks the install, the uninstall, that a tampered download is
refused, and that nothing machine-specific is in the repository.

## License

`wmbattery` is © Joey Hess, the Window Maker Developers Team and others, under the **GNU GPL version 2**; this
patch is a derivative work and is released under the same license (see [LICENSE](LICENSE)). The patch additions are
© 2026 jaderfeijo.

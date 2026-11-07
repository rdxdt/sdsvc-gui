<p align="center">
  <img src="img/sdsvcgui-128x128.png" alt="SystemD Service Manager GUI icon" width="128">
</p>

<h1 align="center">SystemD Service Manager GUI</h1>

<p align="center">
  A lightweight desktop application to view and control systemd services, written in Free Pascal with Lazarus/LCL.
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: GPL v3" src="https://img.shields.io/github/license/rdxdt/sdsvc-gui?color=blue"></a>
  <img alt="Platform: Linux" src="https://img.shields.io/badge/platform-Linux-FCC624?logo=linux&logoColor=black">
  <img alt="Debian 13" src="https://img.shields.io/badge/Debian-13%20trixie-A81D33?logo=debian&logoColor=white">
  <img alt="systemd" src="https://img.shields.io/badge/init-systemd-30D475?logo=linux&logoColor=white">
  <br>
  <img alt="Lazarus 4.0" src="https://img.shields.io/badge/Lazarus-4.0-1E5C99">
  <img alt="Free Pascal 3.2.2" src="https://img.shields.io/badge/Free%20Pascal-3.2.2-E8A33D">
  <img alt="Widgetset: qt6" src="https://img.shields.io/badge/widgetset-qt6-4A86CF?logo=gtk&logoColor=white">
  <a href="https://github.com/rdxdt/sdsvc-gui/commits/main"><img alt="Last commit" src="https://img.shields.io/github/last-commit/rdxdt/sdsvc-gui"></a>
  <a href="https://github.com/rdxdt/sdsvc-gui/issues"><img alt="Open issues" src="https://img.shields.io/github/issues/rdxdt/sdsvc-gui"></a>
</p>

---

## Features

- **Service list**: shows every systemd service unit with its unit name, scope (system or user), load state, enablement state, active state, status and description. Loaded units come from `systemctl list-units`, and installed unit files that systemd hasn't loaded (typically stopped, disabled services) are added from `systemctl list-unit-files`.
- **Filters**: show system services, your user services (`systemctl --user`), or both, and narrow the list to inactive, running or failed services.
- **Status icons**: each service is marked green (running), yellow (stopped) or red (failed).
- **Service details**: select a service to see its name and description in the side panel.
- **Service control**: **Start**, **Stop**, **Restart**, **Enable** and **Disable** the selected service. Each action asks for confirmation first.
- **Context-aware buttons**: only the actions that make sense for the service's current state are enabled. For example, *Stop* and *Restart* are enabled only while the service is running, *Enable* only for disabled services, and *Disable* only for enabled ones. Static, masked and generated units can't be enabled or disabled.
- **Scope-aware actions**: actions on a user service run against your user manager (`systemctl --user`), and actions on a system service run against the system manager.
- **Daemon reload**: run `systemctl daemon-reload` from the toolbar after editing unit files. It reloads the manager(s) selected by the scope filter: system, user, or both.
- **Refresh**: the list refreshes after every action, and on demand from the toolbar.

## Dependencies

### Runtime

| Package | Purpose |
|---|---|
| `systemd` | Provides `systemctl`, which the application calls for every operation |
| `libgtk2.0-0t64` | GTK2, if you're building with gtk2 |
| `libqt6pas6`| Default widget set of the application (runtime package) |
| `libqt6pas6-dev`| Default widget set of application (development) |
| `libglib2.0-0t64`, `libpango-1.0-0`, `libcairo2`, `libgdk-pixbuf-2.0-0`, `libatk1.0-0t64`, `libx11-6` | Libraries GTK2 depends on |

Package names are for **Debian 13 (trixie)**. If you install the `.deb`, `apt` pulls in all of them automatically.

### Build

| Package | Purpose |
|---|---|
| [Lazarus](https://www.lazarus-ide.org/) 4.0 (`lazarus-project`, or Debian's `lcl-utils` + `lcl-gtk2`) | LCL and the `lazbuild` command-line builder |
| [Free Pascal](https://www.freepascal.org/) 3.2.2 (`fpc-laz`, or Debian's `fpc`) | Compiler |
| `libgtk2.0-dev` | GTK2 development files for linking |
| `dpkg-dev`, `debhelper` | Only needed to build the `.deb` package |

## Building

### From the Lazarus IDE

Open `src/sdsvcgui.lpi` and press **Run → Build** (`Shift+F9`). The binary is written to `src/sdsvcgui`.

### From the command line

```bash
lazbuild --widgetset=qt6 src/sdsvcgui.lpi
```

## Packaging (.deb)

There are two ways to build a Debian package.

**1. Package an existing binary** (quick: uses whatever you last compiled in `src/`):

```bash
./build-deb.sh            # version taken from debian/changelog
./build-deb.sh 0.2.0      # or set the version yourself
```

The package is written to `dist/`.

**2. Full build from source** with the Debian toolchain (compiles and packages in one step):

```bash
dpkg-buildpackage -us -uc -b
```

The package is written to the parent directory (`../`).

## Installation

```bash
sudo apt install ./dist/sdsvcgui_0.1.0_amd64.deb
```

To uninstall:

```bash
sudo apt remove sdsvcgui
```

## Usage

Launch **SystemD Service Manager** from your desktop's application menu (under *System*), or from a terminal:

```bash
sdsvcgui
```

1. The main window lists systemd services. Use the filters to choose system services, user services or both, and which states to show. Use **Refresh** on the toolbar to reload the list.
2. Click a service to see its details in the side panel.
3. Use the **Start**, **Stop**, **Restart**, **Enable** or **Disable** buttons, and confirm the dialog.
4. After creating or editing unit files in `/etc/systemd/system/` (system) or `~/.config/systemd/user/` (user), click **Daemon Reload** so systemd picks up the changes. Select the matching scope filter first, or *All* to reload both.

> [!NOTE]
> Changing a system service's state requires administrator privileges. When you run the application as a normal user, systemd asks for your password through polkit, which needs a polkit authentication agent. Most desktop environments run one by default. User services don't need a password.

## Known issues

- User services need a running user session. If the application runs as root (for example through `sudo`), there's no user manager to talk to, and only system services are listed.
- See the [issue tracker](https://github.com/rdxdt/sdsvc-gui/issues) for other known issues.

## Project structure

```
.
├── src/              Lazarus project and Pascal sources
│   ├── sdsvcgui.lpi    Project file
│   ├── sdsvcgui.lpr    Program entry point
│   ├── ufrmmain.pas    Main window
│   └── service.pas     systemctl wrapper (TService / TServiceList)
├── img/              Application and UI icons
├── debian/           Debian packaging files
└── build-deb.sh      Script to package the compiled binary as .deb
```

## Credits

Icons from [freeicon.com](https://freeicon.com).

## License

This project is licensed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE) for details.

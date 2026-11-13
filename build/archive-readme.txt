Qt Installer Framework tools, linked against a static Qt
=======================================================

bin/        binarycreator, installerbase, archivegen, repogen, devtool
licenses/   licenses of the Qt Installer Framework, Qt, xz (liblzma), on Linux and Windows
            bzip2 (libbz2) and on Windows zlib, all of which are linked into the tools
VERSIONS    the versions built (Qt Installer Framework, Qt, xz, bzip2, zlib) and the platform

The tools need no Qt installation. On Linux they use the X11/xcb, fontconfig and FreeType
libraries of the desktop.

Licenses: the Qt Installer Framework is licensed under the GNU GPL v3 with the Qt GPL
exception 1.0 (licenses/qt-installer-framework); Qt under the GNU LGPL v3 (or GPL v2/v3,
licenses/qt). Installers created with these tools are covered by the Qt GPL exception.

Corresponding source: the build script, which downloads the unmodified upstream sources
(pinned by SHA-256) and builds them, is at

    https://github.com/virtualparadoxorg/qt-ifw-asset

Upstream sources:
    https://download.qt.io/official_releases/qt-installer-framework/
    https://download.qt.io/archive/qt/
    https://github.com/tukaani-project/xz/releases
    https://sourceware.org/pub/bzip2/
    https://github.com/madler/zlib/releases

## pipe-viewer

A lightweight application (fork of [straw-viewer](https://github.com/trizen/straw-viewer)) for searching and playing videos from YouTube.

This fork parses the YouTube website directly and relies on the invidious instances only as a fallback method.

### pipe-viewer

* command-line interface to YouTube.

![pipe-viewer](https://user-images.githubusercontent.com/614513/97738550-6d0faf00-1ad6-11eb-84ec-d37f28073d9d.png)

### gtk-pipe-viewer

* GTK+ interface to YouTube.

![gtk-pipe-viewer](https://user-images.githubusercontent.com/614513/127567550-d5742dee-593c-4167-acc4-6d80fd061ffc.png)


### AVAILABILITY

* Alpine Linux: `doas apk add pipe-viewer`
* Alt Linux: https://packages.altlinux.org/en/sisyphus/srpms/pipe-viewer/
* Arch Linux (AUR): https://aur.archlinux.org/packages/pipe-viewer-git/
* Debian/Ubuntu (MPR): Latest stable version https://mpr.makedeb.org/packages/pipe-viewer .Latest dev version https://mpr.makedeb.org/packages/pipe-viewer-git . MPR is like the AUR, but for Debian/Ubuntu. You need to install makedeb first https://www.makedeb.org/ .
* Void Linux: `sudo xbps-install pipe-viewer`
* Parabola GNU/Linux-libre: `pacman -S pipe-viewer`
* Gentoo Linux (kske overlay): `eselect repository enable kske && emerge -av net-misc/pipe-viewer`
* [Guix](https://guix.gnu.org):
Pipe-Viewer can be deployed on any GNU/Linux distribution using Guix.
To install in the user's default profile, do `guix install pipe-viewer`.
To test without installing, do `guix environment --pure --ad-hoc pipe-viewer mpv -- pipe-viewer`.

### REVIEWS

* [EN] How-to install pipe-viewer in Debian
    * https://hunden.linuxkompis.se/2021/11/14/how-to-install-pipe-viewer-in-debian.html

* [EN] pipe-viewer – lightweight YouTube client
    * https://www.linuxlinks.com/pipe-viewer-lightweight-youtube-client/

### VIDEO REVIEWS

* [EN] Pipe-Viewer and Straw-Viewer -- Search Youtube via Terminal - Linux CLI
    * https://www.youtube.com/watch?v=I4tfHUmklWo

* [TW] Pipe-viewer！有史以來最佳的 YouTube 體驗就在這裡～
    * https://wiwi.video/videos/watch/798d38cd-9d10-4f8a-ac1f-f776c6d0aa2c

### TRY

For trying the latest commit of `pipe-viewer`, without installing it, execute the following commands:

```console
    cd /tmp
    wget https://github.com/trizen/pipe-viewer/archive/main.zip -O pipe-viewer-main.zip
    unzip -n pipe-viewer-main.zip
    cd pipe-viewer-main
    ./bin/pipe-viewer
```

### INSTALLATION

To install `pipe-viewer`, run:

```console
    perl Build.PL
    sudo ./Build installdeps
    sudo ./Build install
```

To install `gtk-pipe-viewer` along with `pipe-viewer`, run:

```console
    perl Build.PL --gtk
    sudo ./Build installdeps
    sudo ./Build install
```

### DEPENDENCIES

#### For pipe-viewer:

* [libwww-perl](https://metacpan.org/release/libwww-perl)
* [LWP::Protocol::https](https://metacpan.org/release/LWP-Protocol-https)
* [Data::Dump](https://metacpan.org/release/Data-Dump)
* [JSON](https://metacpan.org/release/JSON)

#### For gtk-pipe-viewer:

* [Gtk3](https://metacpan.org/release/Gtk3)
* [File::ShareDir](https://metacpan.org/release/File-ShareDir)
* \+ the dependencies required by pipe-viewer.

#### Build dependencies:

* [Module::Build](https://metacpan.org/pod/Module::Build)

#### Optional dependencies:

* Local cache support: [LWP::UserAgent::Cached](https://metacpan.org/release/LWP-UserAgent-Cached)
* Better STDIN support (+history): [Term::ReadLine::Gnu](https://metacpan.org/release/Term-ReadLine-Gnu)
* Faster JSON deserialization: [JSON::XS](https://metacpan.org/release/JSON-XS)
* Fixed-width formatting: [Unicode::LineBreak](https://metacpan.org/release/Unicode-LineBreak) or [Text::CharWidth](https://metacpan.org/release/Text-CharWidth)
* For the `*_parallel` config-options: [Parallel::ForkManager](https://metacpan.org/release/Parallel-ForkManager)
* [yt-dlp](https://github.com/yt-dlp/yt-dlp) or [youtube-dl](https://github.com/ytdl-org/youtube-dl).


### PACKAGING

To package this application, run the following commands:

```console
    perl Build.PL --destdir "/my/package/path" --installdirs vendor [--gtk]
    ./Build test
    ./Build install --install_path script=/usr/bin
```

### INVIDIOUS INSTANCES

To use invidious instances, pass the [--invidious](https://github.com/trizen/pipe-viewer/commit/17fb2136f3f3d8ee6dacac05beabcc15082f699d) option:

```console
    pipe-viewer --invidious
```

or set in the configuration file (`~/.config/pipe-viewer/pipe-viewer.conf`):

```perl
    prefer_invidious => 1,
```

To use a specific invidious instance, like [invidious.fdn.fr](https://invidious.fdn.fr/), pass the `--api=HOST` option:

```console
    pipe-viewer --invidious --api=invidious.fdn.fr
```

To make the change permanent, set in the configuration file:

```perl
    api_host => "invidious.fdn.fr",
```

When `api_host` is set to `"auto"`, `pipe-viewer` picks a random invidious instance from [api.invidious.io](https://api.invidious.io/).

### SUPPORT AND DOCUMENTATION

After installing, you can find documentation with the following commands:

    man pipe-viewer
    perldoc WWW::PipeViewer

### LICENSE AND COPYRIGHT

Copyright (C) 2012-2025 Trizen

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See https://dev.perl.org/licenses/ for more information.

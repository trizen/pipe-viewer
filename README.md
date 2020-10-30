## pipe-viewer

A lightweight application (fork of [straw-viewer](https://github.com/trizen/straw-viewer)) for searching and playing videos from YouTube, using the [API](https://github.com/iv-org/invidious/wiki/API) of [invidio.us](https://invidio.us/).

The goal of this fork is to parse the YouTube website directly and rely on the invidious instances only as fallback methods.

### pipe-viewer

* command-line interface to YouTube.

![pipe-viewer](https://user-images.githubusercontent.com/614513/97738550-6d0faf00-1ad6-11eb-84ec-d37f28073d9d.png)

### gtk-pipe-viewer

* GTK+ interface to YouTube.

![gtk-pipe-viewer](https://user-images.githubusercontent.com/614513/97737137-89125100-1ad4-11eb-8ff3-b19cd0041528.png)


### STATUS

The project is in its early stages of development and some features are not implemented yet.


### AVAILABILITY

* Arch Linux (AUR): https://aur.archlinux.org/packages/pipe-viewer-git/


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


### TRY

For trying the latest commit of `pipe-viewer`, without installing it, execute the following commands:

```console
    cd /tmp
    wget https://github.com/trizen/pipe-viewer/archive/main.zip -O pipe-viewer-main.zip
    unzip -n pipe-viewer-main.zip
    cd pipe-viewer-main/bin
    perl -pi -ne 's{DEVEL = 0}{DEVEL = 1}' {gtk-,}pipe-viewer
    ./pipe-viewer
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
* Better STDIN support (+ history): [Term::ReadLine::Gnu](https://metacpan.org/release/Term-ReadLine-Gnu)
* Faster JSON deserialization: [JSON::XS](https://metacpan.org/release/JSON-XS)
* Fixed-width formatting (--fixed-width, -W): [Unicode::LineBreak](https://metacpan.org/release/Unicode-LineBreak) or [Text::CharWidth](https://metacpan.org/release/Text-CharWidth)


### PACKAGING

To package this application, run the following commands:

```console
    perl Build.PL --destdir "/my/package/path" --installdirs vendor [--gtk]
    ./Build test
    ./Build install --install_path script=/usr/bin
```

### INVIDIOUS INSTANCES

Sometimes, the default instance, [invidious.snopyta.org](https://invidious.snopyta.org/), may fail to work properly. When this happens, we can change the API host to some other instance of invidious, such as [invidious.tube](https://invidious.tube/):

```console
    pipe-viewer --api=invidious.tube
```

To make the change permanent, set in the configuration file:

```perl
    api_host => "invidious.tube",
```

Alternatively, the following will automatically pick a random invidious instance everytime the program is started:

```perl
    api_host => "auto",
```

The available instances are listed at: https://instances.invidio.us/


### SUPPORT AND DOCUMENTATION

After installing, you can find documentation with the following commands:

    man pipe-viewer
    perldoc WWW::PipeViewer

### LICENSE AND COPYRIGHT

Copyright (C) 2012-2020 Trizen

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

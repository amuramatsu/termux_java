# This is another try to run JavaVM on termux

## Information

This repository have not JavaVM itself, but contains builder of
Java system for termux.

The Java system built by this scripts is not compiled myself,
that is based on other OpenJDK binary distribution and modify it to
suitable for termux.

This project is inspired from
https://github.com/MasterDevX/Termux-Java and
https://github.com/Hax4us/java .

## Limitations

### GUI is not supported

Supporting GUI requires too many libraries.

## How to use

### Requirements

* Linux or Unix like system
* Perl 5
* [PatchELF](https://nixos.org/patchelf.html)
* [curl](https://curl.haxx.se)
* [bzip2](https://www.sourceware.org/bzip2/)
* [XZ Utils](https://tukaani.org/xz/)
  
### Usage

```sh
$ ./make_termuxjava.pl [-a arch] [-d distribution] [-v version]
```

* **arch** is supported only `aarch64` (default), `armv7` and `armv6`.

* **distribution** is selected form adopt (AdoptOpenJDK) or
  liberica (LibericaJDK). AdoptOpenJDK is recommended.
  
* **version** is version of JDK. I tested only 8u242-b08.

You get `termuxjava-jdk?-{version}-{distribution}-{arch}.tar.gz.
This archive contains install script and Java system. Copy the
archive to android-termux and install.

## What doing this builder

1. Download OpenJDK from [AdoptOpenJDK](https://adoptopenjdk.net)
   or [LibericaJDK](https://bell-sw.com/java)

2. Download shared-libraries needed by JDK from
   [archlinux ARM](https://archlinuxarm.org)

3. Modify JDK binary and library for using above libraries
   (by PatchELF)

4. Packaging JDK, libraries, font settings and wrapper scripts.

## Tested environments

### Build

* NetBSD 8,1-STABLE (amd64)

### JDK Distribution

* [AdoptOpenJDK](https://adoptopenjdk.net) 8u242-b08

### Running environment

* termux 0.88 on [Planet Computers](https://www.www3.planetcom.co.uk)
  Cosmo Communicator (Android 9, aarch64)

### Tested Java applications

* [PlantUML](http://plantuml.com) 2019.12
* [pdftk-java](https://gitlab.com/pdftk-java/pdftk)
* [sbt](https://www.scala-sbt.org) 1.3.7
* [Gradle](https://gradle.org) 6.1

## Acknoledgements

* [DejaVu fonts](https://dejavu-fonts.github.io)
* [Hax4us/java](https://github.com/Hax4us/java)
* [MasterDevX/Termux-java](https://github.com/MasterDevX/Termux-Java)
* [AdoptOpenJDK](https://adoptopenjdk.net)
* [LibericaJDK](https://bell-sw.com/java)
* [PRoot for termux](https://github.com/termux/proot)

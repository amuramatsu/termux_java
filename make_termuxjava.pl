#! /usr/bin/env perl
#
# Usage: make_termuxjava.pl [-a arch] [-v version] [-d openjdk_distribution]
#
#      -a arch          architecture of JDK [aarch64 (default), arm, armv7]
#      -v version       version of JDK [8u242-b08 (default)]
#      -d distribution  which distribution are used [adopt (default), liberica]
#
# This scripts need follow commands
#
# * curl
# * patchelf
# * xz

use strict;
use warnings;

use File::Copy;
use File::Path;
use File::Basename;
use Cwd 'getcwd';
use Getopt::Long qw(:config posix_default no_ignore_case gnu_compat);

my $CURL_OPTS = '';
my $ARCH = "aarch64";
#my $FULL_VERSION = "8u292-b10";
my $FULL_VERSION = "11.0.11+9";
my $DISTRIBUTION = "adopt";
GetOptions(
    "curl-opts=s" => \$CURL_OPTS,
    "arch|a=s" => \$ARCH,
    "version|v=s" => \$FULL_VERSION,
    "distribution|d=s" => \$DISTRIBUTION
    ) or die "Error in command line args";
my $JDK_ARCH = $ARCH;
my $LINUX_ARCH = $ARCH;
if ($ARCH eq "armv7") {
    $ARCH = "armv7h";
    $JDK_ARCH = "arm";
}
elsif ($ARCH eq "arm" || $ARCH eq "armv6") { 
    $ARCH = "armv6h";
    $JDK_ARCH = "arm";
}

# parse version number
#  FULL_VERSION 8u222-b10
#     VERSION -> 8u222
#     PATCH_VERSION -> 222
#     MAJOR_VERSION -> 8
#  FULL_VERSION 11.0.4+12
#     VERSION -> 11.0.4
#     MAJOR_VERSION -> 11
#     PATCH_VERSION -> 4
sub parse_version {
    my ($FULL_VER) = @_;
    my $VERSION = $FULL_VER;
    $VERSION =~ s/-b\d+$//;
    $VERSION =~ s/\+\d+$//;
    my $MAJOR_VERSION = $VERSION;
    $MAJOR_VERSION =~ s/[^0-9].*$//;
    my $PATCH_VERSION;
    if ($VERSION =~ /u(\d+)$/) {
	$PATCH_VERSION = $1;
    }
    elsif ($VERSION =~ /\.0\.(\d+)$/) {
	$PATCH_VERSION = $1;
    }
    return ($VERSION, $MAJOR_VERSION, $PATCH_VERSION);
}
my ($VERSION, $MAJOR_VERSION, $PATCH_VERSION) = parse_version($FULL_VERSION);
my $DESTDIR = "jdk${MAJOR_VERSION}";

my ($JDK_ARCHIVE, $JDK_REPO);
if ($DISTRIBUTION =~ /^liberica\s*(jdk)?$/i) {
    $DISTRIBUTION = "LibericaJDK";
    my $DLVERSION = $FULL_VERSION;
    if ($MAJOR_VERSION == 8 && $PATCH_VERSION < 242 ||
	$MAJOR_VERSION == 11 && $PATCH_VERSION < 6) {
	my $DLVERSION = $VERSION;
    }
    $FULL_VERSION = $VERSION;
    $JDK_ARCHIVE = "bellsoft-jdk${DLVERSION}-linux-${JDK_ARCH}.tar.gz";
    $JDK_REPO = "https://download.bell-sw.com/java/${DLVERSION}";
}
elsif ($DISTRIBUTION =~ /^adopt\s?(openjdk)?$/i) {
    $DISTRIBUTION = "AdoptOpenJDK";
    my $archive_version = $FULL_VERSION;
    my $nametype = ($MAJOR_VERSION == 8 &&
		    ($PATCH_VERSION == 242 || $PATCH_VERSION == 282)) ? 1 : 0;
    $archive_version =~ s/-//g if $nametype == 0;
    $archive_version = "jdk${archive_version}" if $nametype == 1;
    $archive_version =~ s/\+/_/g;
    $JDK_ARCHIVE = "OpenJDK${MAJOR_VERSION}U-jdk_${JDK_ARCH}_linux_hotspot_${archive_version}.tar.gz";
    if ($MAJOR_VERSION == 8) {
        $JDK_REPO = "https://github.com/AdoptOpenJDK/openjdk${MAJOR_VERSION}-binaries/releases/download/jdk${FULL_VERSION}";
    }
    else {
        $JDK_REPO = "https://github.com/AdoptOpenJDK/openjdk${MAJOR_VERSION}-binaries/releases/download/jdk-${FULL_VERSION}";
    }
}
else {
    die "JDK distribution '$DISTRIBUTION' is not supported yet";
}
print "Using $DISTRIBUTION $FULL_VERSION\n";

## arch linux settings

my (%SOLIBS, %SOLIBS_JDK11,
    $ARCH_REPO_CORE, $ARCH_REPO_EXTRA, @INTERPRETER_NAMES);
if ($ARCH eq "armv6h" || $ARCH eq "armv7h") {
    @INTERPRETER_NAMES = ("ld-linux-armhf.so.3",
			  "ld-linux.so.3",
			  "ld-2.32.so");
    $ARCH_REPO_CORE = "http://mirror.archlinuxarm.org/${ARCH}/core/";
    $ARCH_REPO_EXTRA = "http://mirror.archlinuxarm.org/${ARCH}/extra/";
    %SOLIBS = (
	"glibc-2.32-2-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/ld-2.32.so",
	    "usr/lib/libc-2.32.so",
	    "usr/lib/libc.so.6",
	    "usr/lib/libdl-2.32.so",
	    "usr/lib/libdl.so.2",
	    "usr/lib/libdl.so",
	    "usr/lib/libm-2.32.so",
	    "usr/lib/libm.so.6",
	    "usr/lib/libm.so",
	    "usr/lib/librt-2.32.so",
	    "usr/lib/librt.so.1",
	    "usr/lib/librt.so",
	    "usr/lib/libpthread-2.32.so",
	    "usr/lib/libpthread.so.0",
	    "usr/lib/libpthread.so",
	    "usr/lib/libresolv-2.32.so",
	    "usr/lib/libresolv.so.2",
	    "usr/lib/libresolv.so",
	    "usr/lib/libnss_files-2.32.so",
	    "usr/lib/libnss_files.so.2",
	    "usr/lib/libnss_files.so",
	    "usr/lib/libnss_dns-2.32.so",
	    "usr/lib/libnss_dns.so.2",
	    "usr/lib/libnss_dns.so",
	],
	"gcc-libs-10.2.0-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libgcc_s.so.1",
	],
	"zlib-1:1.2.11-4-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libz.so.1.2.11",
	    "usr/lib/libz.so.1",
	    "usr/lib/libz.so",
	],
	"libidn2-2.3.0-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libidn2.so.0.3.7",
	    "usr/lib/libidn2.so.0",
	    "usr/lib/libidn2.so",
	],
	"libunistring-0.9.10-3-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libunistring.so.2.1.0",
	    "usr/lib/libunistring.so.2",
	    "usr/lib/libunistring.so",
	],
	"expat-2.3.0-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libexpat.so.1.7.0",
	    "usr/lib/libexpat.so.1",
	    "usr/lib/libexpat.so",
	],
	"util-linux-libs-2.36.2-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libuuid.so.1.3.0",
	    "usr/lib/libuuid.so.1",
	    "usr/lib/libuuid.so",
	    "usr/lib/libmount.so.1.1.0",
	    "usr/lib/libmount.so.1",
	    "usr/lib/libmount.so",
	    "usr/lib/libblkid.so.1.1.0",
	    "usr/lib/libblkid.so.1",
	    "usr/lib/libblkid.so",
	],
	"libffi-3.3-4-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libffi.so.7.1.0",
	    "usr/lib/libffi.so.7",
	    "usr/lib/libffi.so",
	],
	"glib2-2.68.1-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libglib-2.0.so.0.6800.1",
	    "usr/lib/libglib-2.0.so.0",
	    "usr/lib/libglib-2.0.so",
	    "usr/lib/libgio-2.0.so.0.6800.1",
	    "usr/lib/libgio-2.0.so.0",
	    "usr/lib/libgio-2.0.so",
	    "usr/lib/libgmodule-2.0.so.0.6800.1",
	    "usr/lib/libgmodule-2.0.so.0",
	    "usr/lib/libgmodule-2.0.so",
	    "usr/lib/libgobject-2.0.so.0.6800.1",
	    "usr/lib/libgobject-2.0.so.0",
	    "usr/lib/libgobject-2.0.so",
	],
	"file-5.40-2-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libmagic.so.1.0.0",
	    "usr/lib/libmagic.so.1",
	    "usr/lib/libmagic.so",
	],
	"extra,fontconfig-2:2.13.93-4-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libfontconfig.so.1.12.0",
	    "usr/lib/libfontconfig.so.1",
	    "usr/lib/libfontconfig.so",
	],
	# "libgconf-2.so.4" is needed for get proxy settings, but it pulls
	#    dbus, dbus-glib, systemd-libs, and many libs.
	# "libgnomevfs-2.so.0" is also needed, but not exist on archlinux
	);
    
    # libraries for JDK11
    %SOLIBS_JDK11 = (
	"bzip2-1.0.8-4-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libbz2.so.1.0.8",
	    "usr/lib/libbz2.so.1.0",
	    "usr/lib/libbz2.so.1",
	    "usr/lib/libbz2.so",
	],
	"pcre-8.44-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libpcre.so.1.2.12",
	    "usr/lib/libpcre.so.1",
	    "usr/lib/libpcre.so",
	],
	"extra,freetype2-2.10.4-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libfreetype.so.6.17.4",
	    "usr/lib/libfreetype.so.6",
	    "usr/lib/libfreetype.so",
	],
	"extra,harfbuzz-2.8.0-3-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libharfbuzz.so.0.20800.0",
	    "usr/lib/libharfbuzz.so.0",
	    "usr/lib/libharfbuzz.so",
	],
	"extra,graphite-1:1.3.14-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libgraphite2.so.3.2.1",
	    "usr/lib/libgraphite2.so.3",
	    "usr/lib/libgraphite2.so",
	],
	"extra,libpng-1.6.37-3-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libpng16.so.16.37.0",
	    "usr/lib/libpng16.so.16",
	    "usr/lib/libpng16.so",
	],
	);
}
elsif ($ARCH eq "aarch64") {
    @INTERPRETER_NAMES = ("ld-linux-aarch64.so.1", "ld-2.32.so");
    $ARCH_REPO_CORE = "http://mirror.archlinuxarm.org/${ARCH}/core/";
    $ARCH_REPO_EXTRA = "http://mirror.archlinuxarm.org/${ARCH}/extra/";
    %SOLIBS = (
	"glibc-2.32-2-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/ld-2.32.so",
	    "usr/lib/libc-2.32.so",
	    "usr/lib/libc.so.6",
	    "usr/lib/libdl-2.32.so",
	    "usr/lib/libdl.so.2",
	    "usr/lib/libdl.so",
	    "usr/lib/libm-2.32.so",
	    "usr/lib/libm.so.6",
	    "usr/lib/libm.so",
	    "usr/lib/librt-2.32.so",
	    "usr/lib/librt.so.1",
	    "usr/lib/librt.so",
	    "usr/lib/libpthread-2.32.so",
	    "usr/lib/libpthread.so.0",
	    "usr/lib/libpthread.so",
	    "usr/lib/libresolv-2.32.so",
	    "usr/lib/libresolv.so.2",
	    "usr/lib/libresolv.so",
	    "usr/lib/libnss_files-2.32.so",
	    "usr/lib/libnss_files.so.2",
	    "usr/lib/libnss_files.so",
	    "usr/lib/libnss_dns-2.32.so",
	    "usr/lib/libnss_dns.so.2",
	    "usr/lib/libnss_dns.so",
	],
	"gcc-libs-10.2.0-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libgcc_s.so.1",
	],
	"zlib-1:1.2.11-4-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libz.so.1.2.11",
	    "usr/lib/libz.so.1",
	    "usr/lib/libz.so",
	],
	"libidn2-2.3.0-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libidn2.so.0.3.7",
	    "usr/lib/libidn2.so.0",
	    "usr/lib/libidn2.so",
	],
	"libunistring-0.9.10-3-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libunistring.so.2.1.0",
	    "usr/lib/libunistring.so.2",
	    "usr/lib/libunistring.so",
	],
	"expat-2.3.0-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libexpat.so.1.7.0",
	    "usr/lib/libexpat.so.1",
	    "usr/lib/libexpat.so",
	],
	"util-linux-libs-2.36.2-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libuuid.so.1.3.0",
	    "usr/lib/libuuid.so.1",
	    "usr/lib/libuuid.so",
	    "usr/lib/libmount.so.1.1.0",
	    "usr/lib/libmount.so.1",
	    "usr/lib/libmount.so",
	    "usr/lib/libblkid.so.1.1.0",
	    "usr/lib/libblkid.so.1",
	    "usr/lib/libblkid.so",
	],
	"libffi-3.3-4-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libffi.so.7.1.0",
	    "usr/lib/libffi.so.7",
	    "usr/lib/libffi.so",
	],
	"glib2-2.68.1-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libglib-2.0.so.0.6800.1",
	    "usr/lib/libglib-2.0.so.0",
	    "usr/lib/libglib-2.0.so",
	    "usr/lib/libgio-2.0.so.0.6800.1",
	    "usr/lib/libgio-2.0.so.0",
	    "usr/lib/libgio-2.0.so",
	    "usr/lib/libgmodule-2.0.so.0.6800.1",
	    "usr/lib/libgmodule-2.0.so.0",
	    "usr/lib/libgmodule-2.0.so",
	    "usr/lib/libgobject-2.0.so.0.6800.1",
	    "usr/lib/libgobject-2.0.so.0",
	    "usr/lib/libgobject-2.0.so",
	],
	"file-5.40-2-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libmagic.so.1.0.0",
	    "usr/lib/libmagic.so.1",
	    "usr/lib/libmagic.so",
	],
	"extra,fontconfig-2:2.13.93-4-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libfontconfig.so.1.12.0",
	    "usr/lib/libfontconfig.so.1",
	    "usr/lib/libfontconfig.so",
	],
	# "libgconf-2.so.4" is needed for get proxy settings, but it pulls
	#    dbus, dbus-glib, systemd-libs, and many libs.
	# "libgnomevfs-2.so.0" is also needed, but not exist on archlinux
	);
    
    # libraries for JDK11
    %SOLIBS_JDK11 = (
	"bzip2-1.0.8-4-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libbz2.so.1.0.8",
	    "usr/lib/libbz2.so.1.0",
	    "usr/lib/libbz2.so.1",
	    "usr/lib/libbz2.so",
	],
	"pcre-8.44-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libpcre.so.1.2.12",
	    "usr/lib/libpcre.so.1",
	    "usr/lib/libpcre.so",
	],
	"extra,freetype2-2.10.4-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libfreetype.so.6.17.4",
	    "usr/lib/libfreetype.so.6",
	    "usr/lib/libfreetype.so",
	],
	"extra,harfbuzz-2.8.0-3-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libharfbuzz.so.0.20800.0",
	    "usr/lib/libharfbuzz.so.0",
	    "usr/lib/libharfbuzz.so",
	],
	"extra,graphite-1:1.3.14-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libgraphite2.so.3.2.1",
	    "usr/lib/libgraphite2.so.3",
	    "usr/lib/libgraphite2.so",
	],
	"extra,libpng-1.6.37-3-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libpng16.so.16.37.0",
	    "usr/lib/libpng16.so.16",
	    "usr/lib/libpng16.so",
	],
	);
}
else {
    @INTERPRETER_NAMES = ("ld-linux-${ARCH}.so.1", "ld-2.32.so");
    $ARCH_REPO_CORE = "https://mex.mirror.pkgbuild.com/core/os/${ARCH}/";
    $ARCH_REPO_EXTRA = "https://mex.mirror.pkgbuild.com/extra/os/${ARCH}/";
    %SOLIBS = (
	"glibc-2.32-2-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/ld-2.32.so",
	    "usr/lib/ld-linux-${LINUX_ARCH}.so.1",
	    "usr/lib/libc-2.32.so",
	    "usr/lib/libc.so.6",
	    "usr/lib/libdl-2.32.so",
	    "usr/lib/libdl.so.2",
	    "usr/lib/libdl.so",
	    "usr/lib/libm-2.32.so",
	    "usr/lib/libm.so.6",
	    "usr/lib/libm.so",
	    "usr/lib/librt-2.32.so",
	    "usr/lib/librt.so.1",
	    "usr/lib/librt.so",
	    "usr/lib/libpthread-2.32.so",
	    "usr/lib/libpthread.so.0",
	    "usr/lib/libpthread.so",
	    "usr/lib/libresolv-2.32.so",
	    "usr/lib/libresolv.so.2",
	    "usr/lib/libresolv.so",
	    "usr/lib/libnss_files-2.32.so",
	    "usr/lib/libnss_files.so.2",
	    "usr/lib/libnss_files.so",
	    "usr/lib/libnss_dns-2.32.so",
	    "usr/lib/libnss_dns.so.2",
	    "usr/lib/libnss_dns.so",
	],
	"gcc-libs-10.2.0-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libgcc_s.so.1",
	],
	"zlib-1:1.2.11-4-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libz.so.1.2.11",
	    "usr/lib/libz.so.1",
	    "usr/lib/libz.so",
	],
	"libidn2-2.3.0-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libidn2.so.0.3.7",
	    "usr/lib/libidn2.so.0",
	    "usr/lib/libidn2.so",
	],
	"libunistring-0.9.10-3-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libunistring.so.2.1.0",
	    "usr/lib/libunistring.so.2",
	    "usr/lib/libunistring.so",
	],
	"expat-2.3.0-2-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libexpat.so.1.7.0",
	    "usr/lib/libexpat.so.1",
	    "usr/lib/libexpat.so",
	],
	"util-linux-libs-2.36.2-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libuuid.so.1.3.0",
	    "usr/lib/libuuid.so.1",
	    "usr/lib/libuuid.so",
	    "usr/lib/libmount.so.1.1.0",
	    "usr/lib/libmount.so.1",
	    "usr/lib/libmount.so",
	    "usr/lib/libblkid.so.1.1.0",
	    "usr/lib/libblkid.so.1",
	    "usr/lib/libblkid.so",
	],
	"libffi-3.3-4-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libffi.so.7.1.0",
	    "usr/lib/libffi.so.7",
	    "usr/lib/libffi.so",
	],
	"glib2-2.68.1-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libglib-2.0.so.0.6800.1",
	    "usr/lib/libglib-2.0.so.0",
	    "usr/lib/libglib-2.0.so",
	    "usr/lib/libgio-2.0.so.0.6800.1",
	    "usr/lib/libgio-2.0.so.0",
	    "usr/lib/libgio-2.0.so",
	    "usr/lib/libgmodule-2.0.so.0.6800.1",
	    "usr/lib/libgmodule-2.0.so.0",
	    "usr/lib/libgmodule-2.0.so",
	    "usr/lib/libgobject-2.0.so.0.6800.1",
	    "usr/lib/libgobject-2.0.so.0",
	    "usr/lib/libgobject-2.0.so",
	],
	"file-5.39-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libmagic.so.1.0.0",
	    "usr/lib/libmagic.so.1",
	    "usr/lib/libmagic.so",
	],
	"extra,fontconfig-2:2.13.93-4-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libfontconfig.so.1.12.0",
	    "usr/lib/libfontconfig.so.1",
	    "usr/lib/libfontconfig.so",
	],
	# "libgconf-2.so.4" is needed for get proxy settings, but it pulls
	#    dbus, dbus-glib, systemd-libs, and many libs.
	# "libgnomevfs-2.so.0" is also needed, but not exist on archlinux
	);
    
    # libraries for JDK11
    %SOLIBS_JDK11 = (
	"bzip2-1.0.8-4-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libbz2.so.1.0.8",
	    "usr/lib/libbz2.so.1.0",
	    "usr/lib/libbz2.so.1",
	    "usr/lib/libbz2.so",
	],
	"pcre-8.44-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libpcre.so.1.2.12",
	    "usr/lib/libpcre.so.1",
	    "usr/lib/libpcre.so",
	],
	"extra,freetype2-2.10.4-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libfreetype.so.6.17.4",
	    "usr/lib/libfreetype.so.6",
	    "usr/lib/libfreetype.so",
	],
	"extra,harfbuzz-2.8.0-3-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libharfbuzz.so.0.20800.0",
	    "usr/lib/libharfbuzz.so.0",
	    "usr/lib/libharfbuzz.so",
	],
	"extra,graphite-1:1.3.14-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libgraphite2.so.3.2.1",
	    "usr/lib/libgraphite2.so.3",
	    "usr/lib/libgraphite2.so",
	],
	"extra,libpng-1.6.37-3-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libpng16.so.16.37.0",
	    "usr/lib/libpng16.so.16",
	    "usr/lib/libpng16.so",
	],
	);
}

my $WORK = "./work";
my $curdir = getcwd;

my $TERMUX_PREFIX = $ENV{PREFIX} || "/data/data/com.termux/files/usr";
my $JVM_PREFIX = "${TERMUX_PREFIX}/share/${DESTDIR}";
my $SOLIB_DIR = "${JVM_PREFIX}/solib";
my $INTERPRETER = "${SOLIB_DIR}/$INTERPRETER_NAMES[0]";
my @RPATH_JDK = ("${JVM_PREFIX}/lib/jli",
		 "${JVM_PREFIX}/lib/server",
		 "${JVM_PREFIX}/lib",
		 "${SOLIB_DIR}",
		 "${TERMUX_PREFIX}/lib",
		 "/system/lib");
my @RPATH_JDK8 = ("${JVM_PREFIX}/lib/${ARCH}/jli",
		  "${JVM_PREFIX}/lib/${ARCH}",
		  "${SOLIB_DIR}",
		  "${TERMUX_PREFIX}/lib",
		  "/system/lib");
my @RPATH_JRE8 = ("${JVM_PREFIX}/jre/lib/${ARCH}/jli",
		  "${JVM_PREFIX}/jre/lib/${ARCH}",
		  "${SOLIB_DIR}",
		  "${TERMUX_PREFIX}/lib",
		  "/system/lib");

sub download {
    my ($url, $dest) = @_;
    $url =~ s/([^-:_.\/0-9a-zA-Z])/"%".uc(unpack("H2",$1))/eg;
    $url =~ s/\+/%2B/g;
    if ($dest) {
	system("curl $CURL_OPTS -L -o '$dest' '$url'") eq 0
	    or die "DOWNLOAD FAIlD from $url";
    }
    else {
	system("curl $CURL_OPTS -LO '$url'") eq 0
	    or die "DOWNLOAD FAILD from $url";
    }
}

sub copy_with_patch {
    my ($from, $to, $replaces) = @_;
    if (-d $to) {
	$to = "${to}/" . basename($from);
    }
    open my $infile, "<", $from or die "cannot open input file $from";
    open my $outfile, ">", $to or die "cannot open output file $to";
    while (<$infile>) {
	for my $replfrom (keys %{$replaces}) {
	    my $replto = $replaces->{$replfrom};
	    s/$replfrom/$replto/o;
	}
	print $outfile $_;
    }
    close $infile or die;
    close $outfile or die;
}

rmtree $WORK;
mkdir $WORK;

if (! -r $JDK_ARCHIVE) {
    my $url = "${JDK_REPO}/${JDK_ARCHIVE}";
    print "downloading '$url'\n";
    download($url, $JDK_ARCHIVE);
}

print "extract JDK ...";
system("gzcat '$JDK_ARCHIVE'|tar xf - -C '$WORK' >/dev/null 2>&1") eq 0
    or die "extracting $JDK_ARCHIVE is failed";
if ($MAJOR_VERSION == 8) {
    rename "${WORK}/jdk${FULL_VERSION}" => "${WORK}/${DESTDIR}"
        or die "JDK stracture is wrong";

    unlink "${WORK}/${DESTDIR}/src.zip";
    rmtree "${WORK}/${DESTDIR}/sample";
}
else {
    rename "${WORK}/jdk-${FULL_VERSION}" => "${WORK}/${DESTDIR}"
        or die "JDK stracture is wrong";

    unlink "${WORK}/${DESTDIR}/lib/src.zip";

    %SOLIBS = (%SOLIBS, %SOLIBS_JDK11);
}
rmtree "${WORK}/${DESTDIR}/demo";
print " DONE\n";
print "add solibs from arch linux ...";
mkdir "${WORK}/${DESTDIR}/solib";
for (keys %SOLIBS) {
    my ($url, $need_patch);
    my @libs = @{$SOLIBS{$_}};
    if (/^extra,/) {
	$_ =~ s/^extra,//;
	$url = "${ARCH_REPO_EXTRA}/$_";
    }
    else {
	$url = "${ARCH_REPO_CORE}/$_";
    }
    if (/^glibc/ || /^gcc-libs/) {
	$need_patch = 0;
    }
    else {
	$need_patch = 1;
    }
    download($url, $_) unless (-r $_);
    system("xzcat '$_'|tar xf - -C '$WORK' lib usr/lib >/dev/null 2>&1");
    for my $lib (@libs) {
	my $libname = (split(/\//, $lib))[-1];
	if ($need_patch && ! (-l "${WORK}/${lib}")) {
	    system("patchelf --set-rpath '${SOLIB_DIR}' '${WORK}/${lib}'") eq 0
		or die "patch to ${WORK}/${lib} in $_ is faied";
	}
	rename "${WORK}/${lib}" => "${WORK}/${DESTDIR}/solib/${libname}"
	    or die " $libname is not found in $_";
    }
    
    rmtree "${WORK}/usr";
    rmtree "${WORK}/lib";
}
chdir "${WORK}/${DESTDIR}/solib";

# make symlinks for dynamic linker
my $LD_FROM = pop @INTERPRETER_NAMES;
for (@INTERPRETER_NAMES) {
    symlink $LD_FROM, $_;
}
# libc.so link
symlink "libc.so.6", "libc.so";
chdir $curdir;
print " DONE\n";

print "patch to JDK ...";
if ($MAJOR_VERSION == 8) {
    for (glob("${WORK}/${DESTDIR}/bin/*")) {
	next if (/\.cgi$/);
	system("patchelf --set-rpath '" . join(":", @RPATH_JDK8) .
	       "' --set-interpreter '$INTERPRETER' '$_'") eq 0
	    or die "patch to $_ is faied";
    }
    for (glob("${WORK}/${DESTDIR}/jre/bin/*")) {
	system("patchelf --set-rpath '" . join(":", @RPATH_JRE8) .
	       "' --set-interpreter '$INTERPRETER' '$_'") eq 0
	    or die "patch to $_ is faied";
    }
    for (glob("${WORK}/${DESTDIR}/jre/lib/${JDK_ARCH}/*.so*"),
	 glob("${WORK}/${DESTDIR}/jre/lib/${JDK_ARCH}/*/*.so*")) {
	system("patchelf --set-rpath '" . join(":", @RPATH_JRE8) . "' '$_'") eq 0
	    or die "patch to $_ is faied";
    }
}
else {
    for (glob("${WORK}/${DESTDIR}/bin/*"),
	 glob("${WORK}/${DESTDIR}/lib/{jexec,jspawnhelper}")) {
	next if (/\.cgi$/);
	system("patchelf --set-rpath '" . join(":", @RPATH_JDK) .
	       "' --set-interpreter '$INTERPRETER' '$_'") eq 0
	    or die "patch to $_ is faied";
    }
    for (glob("${WORK}/${DESTDIR}/lib/*.so*"),
	 glob("${WORK}/${DESTDIR}/lib/*/*.so*")) {
	system("patchelf --set-rpath '" . join(":", @RPATH_JDK) . "' '$_'") eq 0
	    or die "patch to $_ is faied";
    }
}
print " DONE\n";

print "copy scripts\n";
mkdir "${WORK}/${DESTDIR}/scripts" or die "mkdir 'scripts' is failed";
for (glob "scripts/*") {
    copy_with_patch($_, "${WORK}/${DESTDIR}/scripts/",
		    { "\@DESTDIR\@" => $DESTDIR })
		    or die "copy script $_ is failed";
}
for (glob "${WORK}/${DESTDIR}/scripts/*") {
    chmod 0777, $_;
}
if ($MAJOR_VERSION == 8) {
    unlink "${WORK}/${DESTDIR}/scripts/jshell";
}
copy 'installer/uninstaller.sh', "${WORK}/${DESTDIR}"
    or die "copy uninstaller.sh is failed";
chmod 0777, "${WORK}/${DESTDIR}/uninstaller.sh";
copy_with_patch('installer/installer.sh.in', "${WORK}/installer.sh",
		{ "\@DESTDIR\@" => $DESTDIR })
    or die "copy installersh is failed";
chmod 0777, "${WORK}/installer.sh";

print "copy fonts\n";
if ($MAJOR_VERSION == 8) {
    for (glob "fontconfig.properties.*") {
	copy $_, "${WORK}/${DESTDIR}/jre/lib"
	    or die "copy $_ is failed";
    }
    mkdir "${WORK}/${DESTDIR}/jre/lib/fonts";
    for (glob "fonts/*") {
	copy $_, "${WORK}/${DESTDIR}/jre/lib/fonts"
	    or die "copy $_ is failed";
    }
    chdir "${WORK}/${DESTDIR}/jre/lib";
}
else {
    mkdir "${WORK}/${DESTDIR}/conf/fonts";
    for (glob "fontconfig.properties.*") {
	copy $_, "${WORK}/${DESTDIR}/conf/fonts"
	    or die "copy $_ is failed";
    }
    for (glob "fonts/*") {
	copy $_, "${WORK}/${DESTDIR}/conf/fonts"
	    or die "copy $_ is failed";
    }
    chdir "${WORK}/${DESTDIR}/conf/fonts";
}
symlink "fontconfig.properties.android6", "fontconfig.properties";
chdir $curdir;

print "make archive\n";
chdir $WORK or die "SOMETHING WRONG";
system("tar cf '${DESTDIR}.tar' '${DESTDIR}'") eq 0
    or die "make ${DESTDIR}.tar is failed";
rmtree $DESTDIR or die;
system("tar cf - *|".
       "gzip -c > '../termuxjava-${DESTDIR}-${FULL_VERSION}-${DISTRIBUTION}-${ARCH}.tar.gz'") eq 0
    or die "make archive is failed";
chdir $curdir;

print "cleanup\n";
rmtree "${WORK}";

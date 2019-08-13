#! /usr/bin/env perl
#
# Usage: make_termuxjava.pl [-a arch] [-v version] [-d openjdk_distribution]
#
#      -a arch          architecture of JDK [aarch64 (default), arm, armv7]
#      -v version       version of JDK [8u222-b10 (default)]
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
my $FULL_VERSION = "8u222-b10";
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
#     MAJOR_VERSION -> 8
#  FULL_VERSION 11.0.4+11.2
#     VERSION -> 11.0.4
#     MAJOR_VERSION -> 11
sub parse_version {
    my ($FULL_VER) = @_;
    my $VERSION = $FULL_VER;
    $VERSION =~ s/-b\d+$//;
    my $MAJOR_VERSION = $VERSION;
    $MAJOR_VERSION =~ s/[^0-9].*$//;
    return ($VERSION, $MAJOR_VERSION);
}
my ($VERSION, $MAJOR_VERSION) = parse_version($FULL_VERSION);
my $DESTDIR = "jdk${MAJOR_VERSION}";

my ($JDK_ARCHIVE, $JDK_REPO);
if ($DISTRIBUTION =~ /^liberica\s*(jdk)?$/i) {
    $DISTRIBUTION = "LibericaJDK";
    $FULL_VERSION = $VERSION;
    $JDK_ARCHIVE = "bellsoft-jdk${VERSION}-linux-${JDK_ARCH}.tar.gz";
    $JDK_REPO = "https://download.bell-sw.com/java/${VERSION}";
}
elsif ($DISTRIBUTION =~ /^adopt\s?(openjdk)?$/i) {
    $DISTRIBUTION = "AdoptOpenJDK";
    my $archive_version = $FULL_VERSION;
    $archive_version =~ s/-//g;
    $archive_version =~ s/\+/_/g;
    $JDK_ARCHIVE = "OpenJDK${MAJOR_VERSION}U-jdk_${JDK_ARCH}_linux_hotspot_${archive_version}.tar.gz";
    $JDK_REPO = "https://github.com/AdoptOpenJDK/openjdk${MAJOR_VERSION}-binaries/releases/download/jdk${FULL_VERSION}";
}
else {
    die "JDK distribution '$DISTRIBUTION' is not supported yet";
}
print "Using $DISTRIBUTION $FULL_VERSION\n";

## arch linux settings

my (%SOLIBS, $ARCH_REPO_CORE, $ARCH_REPO_EXTRA, @INTERPRETER_NAMES);
if ($ARCH eq "armv6h" || $ARCH eq "armv7h") {
    @INTERPRETER_NAMES = ("ld-linux-armhf.so.3",
			  "ld-linux.so.3",
			  "ld-2.29.so");
    $ARCH_REPO_CORE = "http://mirror.archlinuxarm.org/${ARCH}/core/";
    $ARCH_REPO_EXTRA = "http://mirror.archlinuxarm.org/${ARCH}/extra/";
    %SOLIBS = (
	"glibc-2.29-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/ld-2.29.so",
	    "usr/lib/libc-2.29.so",
	    "usr/lib/libc.so.6",
	    "usr/lib/libdl-2.29.so",
	    "usr/lib/libdl.so.2",
	    "usr/lib/libdl.so",
	    "usr/lib/libm-2.29.so",
	    "usr/lib/libm.so.6",
	    "usr/lib/libm.so",
	    "usr/lib/librt-2.29.so",
	    "usr/lib/librt.so.1",
	    "usr/lib/librt.so",
	    "usr/lib/libpthread-2.29.so",
	    "usr/lib/libpthread.so.0",
	    "usr/lib/libpthread.so",
	],
	"gcc-libs-8.3.0-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libgcc_s.so.1",
	],
	"zlib-1:1.2.11-3-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libz.so.1.2.11",
	    "usr/lib/libz.so.1",
	    "usr/lib/libz.so",
	],
	"expat-2.2.7-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libexpat.so.1.6.9",
	    "usr/lib/libexpat.so.1",
	    "usr/lib/libexpat.so",
	],
	"libutil-linux-2.34-3-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libuuid.so.1.3.0",
	    "usr/lib/libuuid.so.1",
	    "usr/lib/libuuid.so",
	],
	"extra,fontconfig-2:2.13.1+12+g5f5ec56-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libfontconfig.so.1.12.0",
	    "usr/lib/libfontconfig.so.1",
	    "usr/lib/libfontconfig.so",
	],
	);
}
elsif ($ARCH eq "aarch64") {
    @INTERPRETER_NAMES = ("ld-linux-aarch64.so.1", "ld-2.29.so");
    $ARCH_REPO_CORE = "http://mirror.archlinuxarm.org/${ARCH}/core/";
    $ARCH_REPO_EXTRA = "http://mirror.archlinuxarm.org/${ARCH}/extra/";
    %SOLIBS = (
	"glibc-2.29-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/ld-2.29.so",
	    "usr/lib/libc-2.29.so",
	    "usr/lib/libc.so.6",
	    "usr/lib/libdl-2.29.so",
	    "usr/lib/libdl.so.2",
	    "usr/lib/libdl.so",
	    "usr/lib/libm-2.29.so",
	    "usr/lib/libm.so.6",
	    "usr/lib/libm.so",
	    "usr/lib/librt-2.29.so",
	    "usr/lib/librt.so.1",
	    "usr/lib/librt.so",
	    "usr/lib/libpthread-2.29.so",
	    "usr/lib/libpthread.so.0",
	    "usr/lib/libpthread.so",
	],
	"gcc-libs-8.3.0-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libgcc_s.so.1",
	],
	"zlib-1:1.2.11-3-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libz.so.1.2.11",
	    "usr/lib/libz.so.1",
	    "usr/lib/libz.so",
	],
	"expat-2.2.7-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libexpat.so.1.6.9",
	    "usr/lib/libexpat.so.1",
	    "usr/lib/libexpat.so",
	],
	"libutil-linux-2.34-3-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libuuid.so.1.3.0",
	    "usr/lib/libuuid.so.1",
	    "usr/lib/libuuid.so",
	],
	"extra,fontconfig-2:2.13.1+12+g5f5ec56-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libfontconfig.so.1.12.0",
	    "usr/lib/libfontconfig.so.1",
	    "usr/lib/libfontconfig.so",
	],
	);
}
else {
    @INTERPRETER_NAMES = ("ld-linux-${ARCH}.so.1", "ld-2.29.so");
    $ARCH_REPO_CORE = "https://mex.mirror.pkgbuild.com/core/os/${ARCH}/";
    $ARCH_REPO_EXTRA = "https://mex.mirror.pkgbuild.com/extra/os/${ARCH}/";
    %SOLIBS = (
	"glibc-2.29-4-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/ld-2.29.so",
	    "usr/lib/ld-linux-${LINUX_ARCH}.so.1",
	    "usr/lib/libc-2.29.so",
	    "usr/lib/libc.so.6",
	    "usr/lib/libdl-2.29.so",
	    "usr/lib/libdl.so.2",
	    "usr/lib/libdl.so",
	    "usr/lib/libm-2.29.so",
	    "usr/lib/libm.so.6",
	    "usr/lib/libm.so",
	    "usr/lib/librt-2.29.so",
	    "usr/lib/librt.so.1",
	    "usr/lib/librt.so",
	    "usr/lib/libpthread-2.29.so",
	    "usr/lib/libpthread.so.0",
	    "usr/lib/libpthread.so",
	],
	"gcc-libs-9.1.0-2-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libgcc_s.so.1",
	],
	"zlib-1:1.2.11-3-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libz.so.1.2.11",
	    "usr/lib/libz.so.1",
	    "usr/lib/libz.so",
	],
	"expat-2.2.7-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libexpat.so.1.6.9",
	    "usr/lib/libexpat.so.1",
	    "usr/lib/libexpat.so",
	],
	"libutil-linux-2.34-3-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libuuid.so.1.3.0",
	    "usr/lib/libuuid.so.1",
	    "usr/lib/libuuid.so",
	],
	"extra,fontconfig-2:2.13.1+12+g5f5ec56-1-${ARCH}.pkg.tar.xz" => [
	    "usr/lib/libfontconfig.so.1.12.0",
	    "usr/lib/libfontconfig.so.1",
	    "usr/lib/libfontconfig.so",
	],
	);
}

my $WORK = "./work";
my $curdir = getcwd;

my $TERMUX_PREFIX = $ENV{PREFIX} || "/data/data/com.termux/files/usr";
my $JVM_PREFIX = "${TERMUX_PREFIX}/share/${DESTDIR}";
my $SOLIB_DIR = "${JVM_PREFIX}/solib";
my $INTERPRETER = "${SOLIB_DIR}/$INTERPRETER_NAMES[0]";
my @RPATH_JDK = ("${JVM_PREFIX}/lib/${ARCH}/jli",
		 "${JVM_PREFIX}/lib/${ARCH}",
		 "${SOLIB_DIR}",
		 "${TERMUX_PREFIX}/lib",
		 "/system/lib");
my @RPATH_JRE = ("${JVM_PREFIX}/jre/lib/${ARCH}/jli",
		 "${JVM_PREFIX}/jre/lib/${ARCH}",
		 "${SOLIB_DIR}",
		 "${TERMUX_PREFIX}/lib",
		 "/system/lib");

sub download {
    my ($url, $dest) = @_;
    $url =~ s/([^-:_.\/0-9a-zA-Z])/"%".uc(unpack("H2",$1))/eg;
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
rename "${WORK}/jdk${FULL_VERSION}" => "${WORK}/${DESTDIR}"
    or die "JDK stracture is wrong";
unlink "${WORK}/${DESTDIR}/src.zip";
rmtree "${WORK}/${DESTDIR}/demo";
rmtree "${WORK}/${DESTDIR}/sample";
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
for (glob("${WORK}/${DESTDIR}/bin/*")) {
    next if (/\.cgi$/);
    system("patchelf --set-rpath '" . join(":", @RPATH_JDK) .
	   "' --set-interpreter '$INTERPRETER' '$_'") eq 0
	or die "patch to $_ is faied";
}
for (glob("${WORK}/${DESTDIR}/jre/bin/*")) {
    system("patchelf --set-rpath '" . join(":", @RPATH_JRE) .
	   "' --set-interpreter '$INTERPRETER' '$_'") eq 0
	or die "patch to $_ is faied";
}
for (glob("${WORK}/${DESTDIR}/jre/lib/${JDK_ARCH}/*.so*"),
     glob("${WORK}/${DESTDIR}/jre/lib/${JDK_ARCH}/*/*.so*")) {
    system("patchelf --set-rpath '" . join(":", @RPATH_JRE) . "' '$_'") eq 0
	or die "patch to $_ is faied";
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
copy 'installer/uninstaller.sh', "${WORK}/${DESTDIR}"
    or die "copy uninstaller.sh is failed";
chmod 0777, "${WORK}/${DESTDIR}/uninstaller.sh";
copy_with_patch('installer/installer.sh.in', "${WORK}/installer.sh",
		{ "\@DESTDIR\@" => $DESTDIR })
    or die "copy installersh is failed";
chmod 0777, "${WORK}/installer.sh";

print "copy fonts\n";
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

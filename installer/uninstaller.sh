#! /data/data/com.termux/files/usr/bin/sh

curdir="$(dirname "$0")"
JVMDIR="${curdir##*/}"

cd "${curdir}/scripts"
for f in *; do
    fbase=$(readlink -f "$f")
    bin=$(readlink -f "${PREFIX}/bin/$f")
    if [ x"$fbase" = x"$bin" ]; then
	rm "$fbase"
    fi
done
cd "${PREFIX}/share"
rm -rf "$JVMDIR"

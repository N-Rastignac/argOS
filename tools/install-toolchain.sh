#!/usr/bin/env bash
# install-toolchain.sh — Linux Mint / Ubuntu / Debian
#
# Ce script NE TÉLÉCHARGE RIEN. Récupère toi-même les deux archives :
#     https://ftp.gnu.org/gnu/binutils/          binutils-X.YY.tar.xz
#     https://ftp.gnu.org/gnu/gcc/gcc-X.Y.Z/     gcc-X.Y.Z.tar.xz
# puis pose-les dans l'un de ces endroits (le script les cherche dans cet ordre) :
#     $SRC (= ~/opt/cross-src), le dossier courant, ~/Téléchargements, ~/Downloads
# ou indique-les explicitement :
#     BINUTILS_TAR=/chemin/binutils-2.44.tar.xz GCC_TAR=/chemin/gcc-14.2.0.tar.xz ./tools/install-toolchain.sh --cross
#
# La version est déduite du nom de fichier : n'importe quelle version récente
# de binutils (≥ 2.40) et de GCC (≥ 12) convient.
#
# Usage :   ./tools/install-toolchain.sh            (paquets + cross-compilateur)
#           ./tools/install-toolchain.sh --deps     (paquets seulement)
#           ./tools/install-toolchain.sh --cross    (cross-compilateur seulement)
#           ./tools/install-toolchain.sh --check    (vérifie juste que les archives sont là)
#
# Reprise : idempotent. Après un échec, relance avec --cross : les archives
# déjà décompressées et les ./configure déjà faits sont réutilisés.
#
# Variables : PREFIX, TARGET, JOBS, SRC, BINUTILS_TAR, GCC_TAR
set -euo pipefail

PREFIX="${PREFIX:-$HOME/opt/cross}"
TARGET="${TARGET:-i686-elf}"
JOBS="${JOBS:-$(nproc)}"
SRC="${SRC:-$HOME/opt/cross-src}"

trap 'code=$?; echo; echo "!! ÉCHEC ligne $LINENO (code $code). Rien nest cassé :"; \
      echo "   relance ./tools/install-toolchain.sh --cross pour reprendre,"; \
      echo "   ou lis le message derreur juste au-dessus."; exit $code' ERR

DO_DEPS=1; DO_CROSS=1; DO_BUILD=1
case "${1:-}" in
  --deps)  DO_CROSS=0 ;;
  --cross) DO_DEPS=0 ;;
  --check) DO_DEPS=0; DO_BUILD=0 ;;
  "") ;;
  *) echo "usage: $0 [--deps|--cross|--check]"; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Localisation des archives fournies par l'utilisateur.
# ---------------------------------------------------------------------------
SEARCH_DIRS=("$SRC" "$PWD" "$HOME/Téléchargements" "$HOME/Downloads" "$HOME")

locate_tarball() {      # locate_tarball <préfixe> <variable-imposée>
    local name="$1" forced="${2:-}"

    if [ -n "$forced" ]; then
        [ -f "$forced" ] || { echo "!! $forced introuvable" >&2; return 1; }
        echo "$forced"; return 0
    fi
    local d f
    for d in "${SEARCH_DIRS[@]}"; do
        [ -d "$d" ] || continue
        # la plus récente d'abord si plusieurs versions traînent
        for f in $(ls -1t "$d"/$name-[0-9]*.tar.{xz,bz2,gz} 2>/dev/null); do
            echo "$f"; return 0
        done
    done
    return 1
}

check_tarball() {       # check_tarball <chemin> → affiche la version
    local f="$1" base version
    base="$(basename "$f")"
    version="${base#*-}"; version="${version%%.tar.*}"
    if ! tar tf "$f" >/dev/null 2>&1; then
        echo "!! $f est corrompu ou n'est pas une archive tar valide." >&2
        echo "   (téléchargement interrompu ? retélécharge-le)" >&2
        return 1
    fi
    echo "$version"
}

if [ "$DO_DEPS" = 1 ]; then
  echo "==> Installation des paquets"
  sudo apt-get update
  sudo apt-get install -y \
    build-essential bison flex libgmp3-dev libmpc-dev libmpfr-dev texinfo \
    libisl-dev \
    qemu-system-x86 gdb \
    grub-pc-bin grub-common xorriso mtools \
    python3 python3-pip
  # Optionnel : émulateur Unicorn pour `make smoke` (test sans QEMU).
  pip3 install --user --break-system-packages unicorn pyelftools 2>/dev/null || true
  # gcc-multilib : nécessaire pour `make sim` du module 8 (gcc -m32) et pour
  # le repli "gcc -m32" du Makefile. Si apt propose de RETIRER des paquets
  # (conflit avec des cross-gcc ARM/MIPS déjà installés), réponds non et
  # installe-le plus tard à la main.
  sudo apt-get install -y gcc-multilib || true
fi

if [ "$DO_CROSS" = 1 ]; then
  if command -v "$TARGET-gcc" >/dev/null 2>&1; then
    echo "==> $TARGET-gcc déjà présent : $(command -v "$TARGET-gcc")"
    echo "    (supprime $PREFIX pour recompiler)"
    exit 0
  fi

  mkdir -p "$SRC" "$PREFIX"

  echo "==> Recherche des archives"
  BINUTILS_TAR="$(locate_tarball binutils "${BINUTILS_TAR:-}")" || {
      echo "!! Archive binutils introuvable."
      echo "   Cherchée sous le nom binutils-<version>.tar.{xz,bz2,gz} dans :"
      printf '     %s\n' "${SEARCH_DIRS[@]}"
      echo "   Télécharge-la sur https://ftp.gnu.org/gnu/binutils/ et place-la dans $SRC/"
      echo "   ou lance : BINUTILS_TAR=/chemin/vers/archive $0 --cross"
      exit 1; }
  GCC_TAR="$(locate_tarball gcc "${GCC_TAR:-}")" || {
      echo "!! Archive gcc introuvable."
      echo "   Cherchée sous le nom gcc-<version>.tar.{xz,bz2,gz} dans :"
      printf '     %s\n' "${SEARCH_DIRS[@]}"
      echo "   Télécharge-la sur https://ftp.gnu.org/gnu/gcc/ (dossier gcc-X.Y.Z/)"
      echo "   ou lance : GCC_TAR=/chemin/vers/archive $0 --cross"
      exit 1; }

  BINUTILS_VERSION="$(check_tarball "$BINUTILS_TAR")"
  GCC_VERSION="$(check_tarball "$GCC_TAR")"
  echo "  binutils $BINUTILS_VERSION  ←  $BINUTILS_TAR"
  echo "  gcc      $GCC_VERSION  ←  $GCC_TAR"

  [ "$DO_BUILD" = 1 ] || { echo "==> --check : archives valides, rien d'autre à faire."; exit 0; }

  cd "$SRC"
  echo "==> Décompression (quelques minutes pour gcc)"
  [ -d "binutils-$BINUTILS_VERSION" ] || tar xf "$BINUTILS_TAR"
  [ -d "gcc-$GCC_VERSION" ] || tar xf "$GCC_TAR"
  [ -d "binutils-$BINUTILS_VERSION" ] || { echo "!! l'archive binutils n'a pas créé binutils-$BINUTILS_VERSION/"; exit 1; }
  [ -d "gcc-$GCC_VERSION" ] || { echo "!! l'archive gcc n'a pas créé gcc-$GCC_VERSION/"; exit 1; }

  export PATH="$PREFIX/bin:$PATH"

  echo "==> Compilation de binutils (quelques minutes, $JOBS jobs)"
  mkdir -p build-binutils && cd build-binutils
  [ -f Makefile ] || "../binutils-$BINUTILS_VERSION/configure" \
    --target="$TARGET" --prefix="$PREFIX" \
    --with-sysroot --disable-nls --disable-werror
  make -j"$JOBS"
  make install
  cd ..

  echo "==> Compilation de gcc (10-20 minutes)"
  mkdir -p build-gcc && cd build-gcc
  [ -f Makefile ] || "../gcc-$GCC_VERSION/configure" \
    --target="$TARGET" --prefix="$PREFIX" \
    --disable-nls --enable-languages=c,c++ --without-headers \
    --disable-hosted-libstdcxx
  make -j"$JOBS" all-gcc
  make -j"$JOBS" all-target-libgcc
  make install-gcc
  make install-target-libgcc
  cd ..

  # --- PATH : écrire dans le bon fichier de config selon le shell.
  case "$(basename "${SHELL:-/bin/bash}")" in
    zsh)  RC="$HOME/.zshrc";                     LINE="export PATH=\"$PREFIX/bin:\$PATH\"" ;;
    fish) RC="$HOME/.config/fish/config.fish";   LINE="fish_add_path $PREFIX/bin" ;;
    *)    RC="$HOME/.bashrc";                    LINE="export PATH=\"$PREFIX/bin:\$PATH\"" ;;
  esac

  echo
  if [ -f "$RC" ] && grep -qF "$PREFIX/bin" "$RC"; then
    echo "==> $RC contient déjà $PREFIX/bin"
  else
    mkdir -p "$(dirname "$RC")"
    echo "$LINE" >> "$RC"
    echo "==> Ligne ajoutée à $RC :"
    echo "    $LINE"
  fi
  echo
  echo "==> Terminé. Ouvre un nouveau terminal (ou 'source $RC'), puis :"
  echo "    $TARGET-gcc --version && ./tools/check-env.sh"
  echo "    Tu peux libérer de la place : rm -rf $SRC/build-* $SRC/binutils-* $SRC/gcc-*"
fi

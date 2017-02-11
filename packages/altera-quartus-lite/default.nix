{ stdenv, fetchurl, utillinux, file, bash, glibc, pkgsi686Linux, writeScript
# Runtime dependencies
, zlib, glib, libpng12, freetype, libSM, libICE, libXrender, fontconfig
, libXext, libX11, bzip2, libelf
# From "QuartusLiteSetup* --help", these components can be disabled:
#   quartus quartus_help devinfo arria_lite cyclone cyclonev max max10
#   quartus_update modelsim_ase modelsim_ae
, disableComponents ? []
}:

let
  disableComponentsOption =
    if disableComponents != [] then
      ''--disable-components ${stdenv.lib.concatStringsSep "," disableComponents}''
    else "";

  runtimeLibPath =
    stdenv.lib.makeLibraryPath
      [ zlib glib libpng12 freetype libSM libICE libXrender fontconfig.lib
        libXext libX11 bzip2.out libelf
      ];

  setup-chroot-and-exec = writeScript "setup-chroot-and-exec"
    ''
      #!${bash}/bin/sh
      chrootdir=chroot  # relative to the current directory
      mkdir -p "$chrootdir"/host
      mkdir -p "$chrootdir"/proc
      mkdir -p "$chrootdir"/nix
      mkdir -p "$chrootdir"/tmp
      mkdir -p "$chrootdir"/dev
      mkdir -p "$chrootdir"/lib64
      mkdir -p "$chrootdir"/bin
      ${utillinux}/bin/mount --rbind /     "$chrootdir"/host
      ${utillinux}/bin/mount --rbind /proc "$chrootdir"/proc
      ${utillinux}/bin/mount --rbind /nix  "$chrootdir"/nix
      ${utillinux}/bin/mount --rbind /tmp  "$chrootdir"/tmp
      ${utillinux}/bin/mount --rbind /dev  "$chrootdir"/dev
      ${utillinux}/bin/mount --rbind "${glibc}"/lib64 "$chrootdir"/lib64
      ${utillinux}/bin/mount --rbind "${bash}"/bin "$chrootdir"/bin
      chroot "$chrootdir" $@
    '';

  # buildFHSUserEnv tries to mount a few directories that are not available in
  # sandboxed Nix builds (/sys, /run), hence we have our own slimmed down
  # variant.
  run-in-fhs-env = writeScript "run-in-fhs-env"
    ''
      #!${bash}/bin/sh
      if [ "$*" = "" ]; then
          echo "Usage: run-in-fhs-env <COMMAND> [ARGS...]"
          exit 1
      fi
      ${utillinux}/bin/unshare -r -U -m "${setup-chroot-and-exec}" $@
    '';

  # Because the tarball is so big (>8 GiB) and slow to extract, we split the
  # package in two derivations: one extracts the tarball and the other runs the
  # unpacked installer program. That allows changing the installer arguments
  # without doing expensive unpack operation (useful when developing).
  altera-quartus-prime-lite-installers =
    stdenv.mkDerivation rec {
      name = "altera-quartus-prime-lite-installers-${version}";
      version = "16.1.1.200";
      src = fetchurl {
        # The tarball is not publically available, users must register online
        # and receive private download URL.
        # See https://www.altera.com/downloads/download-center.html
        url = "http://manually_download_from_altera.com/Quartus-lite-${version}-linux.tar";
        sha256 = "c290a67af60f8c16113b9663870e838582782020c856237663bfb57312f5fe48";
      };
      buildCommand = ''
        mkdir -p "$out"
        echo "Extracting Altera Quartus tarball..."
        tar xvf "$src" -C "$out"
        echo "...done"
      '';
    };

in

stdenv.mkDerivation rec {
  name = "altera-quartus-prime-lite-${version}";
  version = altera-quartus-prime-lite-installers.version;
  src = altera-quartus-prime-lite-installers;
  buildInputs = [ file ];

  # Prebuilt binaries need special treatment
  dontStrip = true;
  dontPatchELF = true;

  unpackPhase = "true";

  # Quartus' setup.sh doesn't fit our needs (we want automatic and
  # distro-agnostic install), so call the actual setup program directly
  # instead.
  #
  # QuartusLiteSetup is a statically linked ELF executable that runs
  # open("/lib64/ld-linux-x86-64.so.2", ...). That obviously doesn't work in
  # sandboxed Nix builds.
  #
  # Things that do not work:
  # * patchelf the installer (there is no .interp section in static ELF)
  # * dynamic linker tricks (again, static ELF)
  # * proot (the installer somehow detects something is wrong and aborts)
  #
  # We need bigger guns: user namespaces and chroot. That way we make /lib64/
  # available to the installer. The installer installs dynamically linked ELF
  # files, so those we can fixup with usual tools.
  #
  # For runtime, injecting (or wrapping with) LD_LIBRARY_PATH is easier, but it
  # messes with the environment for all child processes. We take the less
  # invasive approach here, patchelf + RPATH. Unfortunately, Quartus itself
  # uses LD_LIBRARY_PATH in its wrapper scripts. This cause e.g. firefox to
  # fail due to LD_LIBRARY_PATH pulling in wrong libraries for it (happens if
  # clicking any URL in Quartus).
  installPhase = ''
    echo "Running QuartusLiteSetup (in FHS sandbox)..."
    echo "### ${run-in-fhs-env} $src/components/QuartusLiteSetup* --mode unattended ${disableComponentsOption} --installdir $out"
    ${run-in-fhs-env} "$src/components/QuartusLiteSetup* --mode unattended ${disableComponentsOption} --installdir $out"
    echo "...done"

    echo "Removing unneeded \"uninstall\" binaries (saves about 2 GiB, if all components are enabled)..."
    rm -rf "$out"/uninstall

    echo "Fixing ELF interpreter paths with patchelf..."
    find "$out" -type f | while read f; do
        case "$f" in
            *.debug) continue;;
        esac
        # A few files are read-only. Make them writeable for patchelf. (Nix
        # will make all files read-only after the build.)
        chmod +w "$f"
        magic=$(file "$f") || { echo "file \"$f\" failed"; exit 1; }
        case "$magic" in
            *ELF*dynamically\ linked*)
                orig_rpath=$(patchelf --print-rpath "$f") || { echo "FAILED: patchelf --print-rpath $f"; exit 1; }
                # Take care not to add ':' at start or end of RPATH, because
                # that is the same as '.' (current directory), and that's
                # insecure.
                if [ "$orig_rpath" != "" ]; then
                    orig_rpath="$orig_rpath:"
                fi
                new_rpath="$orig_rpath${runtimeLibPath}"
                # Some tools require libstdc++.so.6 and they are built
                # incorrect so they don't find their own library.
                # Out of the several copies in $out, pick one:
                new_rpath="$new_rpath:$out/quartus/linux64"
                case "$magic" in
                    *ELF*executable*)
                        interp=$(patchelf --print-interpreter "$f") || { echo "FAILED: patchelf --print-interpreter $f"; exit 1; }
                        # Note the LSB interpreters, required by some files
                        if [ "$interp" = "/lib64/ld-linux-x86-64.so.2" -o "$interp" = "/lib64/ld-lsb-x86-64.so.3" ]; then
                            new_interp=$(cat "$NIX_CC"/nix-support/dynamic-linker)
                            test -f "$new_interp" || { echo "$new_interp is missing"; exit 1; }
                            patchelf --set-interpreter "$new_interp" \
                                     --set-rpath "$new_rpath" "$f" || { echo "FAILED: patchelf --set-interpreter $new_interp --set-rpath $new_rpath $f"; exit 1; }
                        elif [ "$interp" = "/lib/ld-linux.so.2" -o "$interp" = "/lib/ld-lsb.so.3" ]; then
                            new_interp="${pkgsi686Linux.glibc}/lib/ld-linux.so.2"
                            test -f "$new_interp" || { echo "$new_interp is missing"; exit 1; }
                            patchelf --set-interpreter "$new_interp" "$f"
                            # TODO: RPATH for 32-bit executables
                        else
                            echo "FIXME: unsupported interpreter \"$interp\" in $f"
                            exit 1
                        fi
                        ;;
                    *ELF*shared\ object*x86-64*)
                        patchelf --set-rpath "$new_rpath" "$f" || { echo "FAILED: patchelf --set-rpath $f"; exit 1; }
                        ;;
                esac
                ;;
            *ELF*statically\ linked*)
                echo "WARN: $f is statically linked. Needs fixup?"
                ;;
        esac
    done

    # Modelsim is optional
    f="$out"/modelsim_ase/vco
    if [ -f "$f" ]; then
        echo "Fix hardcoded \"/bin/ls\" in .../modelsim_ase/vco"
        sed -i -e "s,/bin/ls,ls," "$f"

        echo "Fix support for Linux 4.x in .../modelsim_ase/vco"
        sed -i -e "/case \$utype in/a 4.[0-9]*) vco=\"linux\" ;;" "$f"
    fi

    # Provide convenience wrappers in $out/bin, so that the tools can be
    # started directly from PATH. Plain symlinks don't work, due to assumptions
    # of resources relative to arg0.
    wrap()
    {
        dest="$out/bin/$(basename "$1")"
        if [ -f "$dest" ]; then
            echo "ERROR: $dest already exist"
            exit 1
        fi
        cat > "$dest" << EOF
    #!${bash}/bin/sh
    exec "$1" "\$@"
    EOF
        chmod +x "$dest"
    }

    echo "Creating top-level bin/ directory with wrappers for common tools"
    mkdir -p "$out/bin"
    for p in "$out/"*"/bin/"*; do
        test -f "$p" || continue
        wrap "$p"
    done

    echo "Installing Desktop file..."
    mkdir -p "$out/share/applications"
    f="$out"/share/applications/quartus.desktop
    cat >> "$f" << EOF
    [Desktop Entry]
    Type=Application
    Version=0.9.4
    Name=Quartus Prime ${version} Lite Edition
    Comment=Quartus Prime ${version}
    Icon=$out/quartus/adm/quartusii.png
    Exec=$out/quartus/bin/quartus
    Terminal=false
    Path=$out
    EOF
  '';

  meta = with stdenv.lib; {
    description = "Development tools for Altera FPGA, CPLD and SoC designs";
    homepage = https://www.altera.com/;
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    maintainers = [ maintainers.bjornfor ];
  };
}

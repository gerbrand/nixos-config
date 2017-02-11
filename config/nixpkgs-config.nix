# Nixpkgs configuration file.

{
  allowUnfree = true;  # allow proprietary packages

  firefox.enableAdobeFlash = true;
  chromium.enablePepperFlash = true;

  packageOverrides = pkgs: {
    altera-quartus-prime-lite = callPackage ../packages/altera-quartus-prime-lite/default.nix {
      disableComponents = [
        /*"quartus"*/ "quartus_help" "devinfo" "arria_lite" "cyclone" "cyclonev"
        "max" "max10" "quartus_update" "modelsim_ase" "modelsim_ae"
        #
        #/*"quartus"*/ /*"quartus_help"*/ /*"devinfo"*/ /*"arria_lite"*/ "cyclone" "cyclonev"
        #/*"max" "max10"*/ /*"quartus_update" "modelsim_ase" "modelsim_ae"*/
      ];
    };

    ltsa = pkgs.callPackage ../packages/ltsa/default.nix { };

    mtdutils-for-swupdate = pkgs.mtdutils.overrideDerivation (args: rec {
      # Copied from the .bbappend file from meta-swupdate.
      postInstall = ''
        mkdir -p "$out/lib"
        mkdir -p "$out/include/mtd"
        cp lib/libmtd.a "$out/lib"
        cp ubi-utils/libubi*.a "$out/lib"
        install -m 0644 ubi-utils/include/libubi.h $out/include/mtd/
        install -m 0644 include/libmtd.h $out/include/mtd/
        install -m 0644 include/mtd/ubi-media.h $out/include/mtd/
      '';
    });

    spotify-ripper = pkgs.callPackage ../packages/spotify-ripper/default.nix { };

    winusb = pkgs.callPackage ../packages/winusb/default.nix { };
  };
}
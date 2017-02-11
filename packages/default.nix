{ pkgs, ... }:

with pkgs;

{
  altera-quartus-prime-lite = callPackage ./altera-quartus-prime-lite/default.nix {
    disableComponents = [
      #/*"quartus"*/ "quartus_help" "devinfo" "arria_lite" "cyclone" "cyclonev"
      #"max" "max10" "quartus_update" "modelsim_ase" "modelsim_ae"

      #/*"quartus"*/ /*"quartus_help"*/ /*"devinfo"*/ /*"arria_lite"*/ "cyclone" "cyclonev"
      #/*"max" "max10"*/ /*"quartus_update" "modelsim_ase" "modelsim_ae"*/
    ];
  };

  ltsa = callPackage ./ltsa/default.nix { };

  spotify-ripper = callPackage ./spotify-ripper/default.nix { };

  winusb = callPackage ./winusb/default.nix { };
}

# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./nixos-in-place.nix
      ./nginx
    ];

  # Use the GRUB 2 boot loader.
  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;
  # boot.loader.grub.efiSupport = true;
  # boot.loader.grub.efiInstallAsRemovable = true;
  # boot.loader.efi.efiSysMountPoint = "/boot/efi";
  # Define on which hard drive you want to install Grub.
  # boot.loader.grub.device = "/dev/sda"; # or "nodev" for efi only

  networking.hostName = "www"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Select internationalisation properties.
  # i18n = {
  #   consoleFont = "Lat2-Terminus16";
  #   consoleKeyMap = "us";
  #   defaultLocale = "en_US.UTF-8";
  # };

  # Set your time zone.
  # time.timeZone = "Europe/Amsterdam";

  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = with pkgs; [
     curl
     links
     git
  ] ++ cfg.extraPackages;

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.permitRootLogin = "no";

  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowPing = true;

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable the X11 windowing system.
  # services.xserver.enable = true;
  # services.xserver.layout = "us";
  # services.xserver.xkbOptions = "eurosign:e";

  # Enable the KDE Desktop Environment.
  # services.xserver.displayManager.kdm.enable = true;
  # services.xserver.desktopManager.kde4.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.extraUsers.gerbrand = {
     home = "/home/gerbrand";
     isNormalUser = true;
     extraGroups = [ "wheel" "networkmanager" ];
     openssh.authorizedKeys.keys = [
"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC8P/C+1vulPyGEkUgP+9qO3vbeaaCivY2jlaBl+wK9hW4abFvkpLjOvy3r9l/Bkk5GVh45AcyhRX3wC9+P4ulrMMS4LDA7UTqjL7pIb/ydF0HL/FHz6G4qfxJyKxKY24uih8SVPuCXRjIjjPCisZ/ZR5nX8gnnpHZr8gsX8jJv45SpUn60lAA43trjQxWCeoBtbuUxajIerFpSkApNSHr/ZBof8AUbgHzR0pSDprmOCwQjsmt9MWZi4BL5XaATjnPZbeSGP3xgj+LN3m29hHrha/h6edDifv0Lk8nu750N68UCcFwFIYQfllMf+KTTUsg//xtJWVRarqjG2IPeJgJv gerbrand@gerlaptop" ];
     uid = 1000;
   };

  services.httpd = {
      enable = true;
      adminAddr = "www@gerbrand-ict.nl";
      documentRoot = "/webroot";
    };

  # The NixOS release to be compatible with for stateful data such as databases.
  system.stateVersion = "16.09";

  system.autoUpgrade.enable = true;
}

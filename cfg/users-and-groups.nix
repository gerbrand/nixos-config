{ config, lib, pkgs, ... }:
{
  users.extraUsers = {
    gerbrand = {
      description = "Gerbrand van Dieyen";
      uid = 1000;
      extraGroups = [
        "audio"
        "cdrom"
        "dialout"  # for access to /dev/ttyUSBx
        "docker"
        "git"  # for read-only access to gitolite repos on the filesystem
        "libvirtd"
        "motion"
        "networkmanager"
        "plugdev"
        "scanner"
        "sudo"
        "syncthing"
        "systemd-journal"
        "tracing"
        "transmission"
        "tty"
        "usbmon"
        "usbtmc"
        "vboxusers"
        "video"
        "wheel"  # admin rights
        "wireshark"
      ];
      isNormalUser = true;
      initialPassword = "initialpw";
      # Subordinate user ids that user is allowed to use. They are set into
      # /etc/subuid and are used by newuidmap for user namespaces. (Needed for
      # LXC.)
      subUidRanges = [
        { startUid = 100000; count = 65536; }
      ];
      subGidRanges = [
        { startGid = 100000; count = 65536; }
      ];

    };
  };

  users.extraGroups = {
    plugdev = { gid = 500; };
    tracing = { gid = 501; };
    usbtmc = { gid = 502; };
    wireshark = { gid = 503; };
    usbmon = { gid = 504; };
  };
}

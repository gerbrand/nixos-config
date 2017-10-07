{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.borg-backup;
in
{
  options.services.borg-backup = {

    enable = mkEnableOption "enable borg backup service to take nightly backups.";

    repository = mkOption {
      type = types.str;
      default = "";
      example = "/mnt/backups/backup.borg";
      description = ''
        Path to Borg repository where the backup will be stored.
      '';
    };

    archiveBaseName = mkOption {
      type = types.str;
      default = "{hostname}";
      description = ''
        Complete archive names look like "$archiveBaseName-DATE".
      '';
    };

    excludeNix = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to exclude /nix/ (and the generated file /etc/nix/nix.conf)
        from the backup. Set it to false if you want to be able to do full
        system restore from your backup. Set it to true if you want to save
        some disk space and are okay with having to recover your system by
        running nixos-install. A prerequisite for this option is that
        pathsToBackup includes the Nix store.
      '';
    };

    pathsToBackup = mkOption {
      type = types.listOf types.str;
      default = [ "/" "/boot" ];
      example = [ "/home" "/srv" ];
      description = ''
        List of paths to backup. The backup does not cross filesystem
        boundaries, so each filesystem (mountpoint) you want to have backed up
        must be listed here.
      '';
    };

    preHook = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Shell commands to run before backing up. Abort backup if 'exit N'.
      '';
    };

    postHook = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Shell commands to run after backing up, pruning and checking the repository.
      '';
    };

  };

  config = mkIf cfg.enable {

    assertions = [
      { assertion = config.services.borg-backup.repository != "";
        message = "Please specify a value in services.borg-backup.repository.";
      }
      { assertion = config.services.borg-backup.pathsToBackup != [];
        message = "Please specify a value in services.borg-backup.pathsToBackup.";
      }
    ];

    # for convenience
    environment.sessionVariables = {
      BORG_REPO = "${cfg.repository}";
    };

    systemd.services.borg-backup = {
      # Restore everything:
      # $ cd /mnt/restore
      # $ [sudo] borg extract -v --list --numeric-owner /mnt/backup-disk/repo-name::archive-name
      #
      # Restore from remote repository:
      # $ [sudo BORG_RSH='ssh -i /home/bfo/.ssh/id_rsa'] borg extract -v --list --numeric-owner --remote-path="sudo borg" ssh://bfo@server/mnt/backup-disk/repo-name::archive-name
      #
      # Interactive restore (slower than 'borg extract'):
      # $ borg mount /mnt/backup-disk/repo-name /mnt/fuse-mountpoint
      # $ ls -1 /mnt/fuse-mountpoint
      # my-machine-20150220T234453
      # my-machine-20150321T114708
      # ... restore files (cp/rsync) ...
      # $ borg umount /mnt/fuse-mountpoint
      #
      #
      # == Disaster recovery
      #
      # 1. Boot NixOS Live CD/USB installer.
      #    (If doing full system restore, the PC must boot in the same firmware
      #    mode (BIOS/MBR v. EFI) as the old system.)
      #
      # 2. Install BorgBackup:
      #    $ nix-env -iA nixos.borgbackup
      #
      # 3. Make the backup available to borg.
      #    Here, an SSH example:
      #    $ export BORG_REMOTE_PATH="sudo borg"
      #    $ export BORG_REPO=ssh://user@server/backups/repo.borg
      #    (Remember to add SSH keys for the root user to be able to login to
      #    server as user.)
      #
      # 4. List available archives, choose one to restore from:
      #    $ borg list
      #    $ export ARCHIVE_NAME=some-archive-name-from-above
      #
      # 5. Partition, format and mount disk(s) on /mnt.
      #    - If doing full system restore, the partitions must have the same
      #      filesystem labels and/or uuids like the old system. Hint:
      #      $ mkdir etc_bak && cd etc_bak && borg extract ::$ARCHIVE_NAME etc
      #      $ # get label and uuid values from etc/nixos/*.nix files
      #      $ mkfs.ext4 -L $label -U $uuid /dev/my-disk-partition
      #    - If booting in EFI mode, the FAT32 formatted EFI System Partition
      #      must be mounted on /mnt/boot. (If booting in BIOS/MBR mode you
      #      don't _have_ to make a separate boot partition, as long as your
      #      root filesystem is supported by GRUB.)
      #
      # 6. Restore files:
      #    $ cd /mnt && borg extract -v --list --numeric-owner ::$ARCHIVE_NAME
      #    (If the backup includes the Nix store but you want to do a
      #    re-install anyway (e.g. to redo disk partitioning or migrating from
      #    BIOS/MBR to EFI), add `--exclude /nix` to the borg command.)
      #
      # 7. Make the system bootable.
      #    Alternative 1, the backup includes the Nix store. The disk just
      #    needs to be made bootable:
      #      For BIOS/MBR:
      #        $ grub-install --boot-director=/mnt/boot /dev/sdX
      #      For EFI:
      #        TODO: "bootctl --path=/mnt/boot update"?
      #
      #    Alternative 2, the backup does NOT include the Nix store. Must
      #    perform NixOS install. However, this allows changing between
      #    BIOS/MBR and EFI booting, as well as completely redesigning
      #    partitions/filesystems.
      #    - Check that bootloader and filesystem(s) is set up to your liking
      #      in NixOS configuration (which disk label/uuid to use etc.). If
      #      restoring onto new HW, pay attention when updating
      #      hardware-configuration.nix (`nixos-generate-config --dir /tmp`,
      #      then manually merge with /mnt/etc/nixos).
      #    - nixos-install
      #
      # 8. Reboot into your new old system :-)
      enable = true;
      description = "Borg Backup Service";
      startAt = "*-*-* 01:15:00";  # see systemd.time(7)
      environment = {
        BORG_RELOCATED_REPO_ACCESS_IS_OK = "yes";
      };
      path = with pkgs; [
        borgbackup utillinux coreutils
      ];
      serviceConfig.SyslogIdentifier = "borg-backup"; # else HASH-borg-backup
      serviceConfig.ExecStart =
        let
          # - The initial backup repo must be created manually:
          #     $ sudo borg init --encryption none $repository
          borgBackup = pkgs.writeScript "borg-backup" ''
            #!${pkgs.bash}/bin/sh
            repository="${cfg.repository}"

            die()
            {
                echo "$*"
                # Allow systemd to associate this message with the unit before
                # exit. Yep, it's a race.
                sleep 3
                exit 1
            }

            ${cfg.preHook}

            echo "Running 'borg create [...]'"
            borg create \
                --stats \
                --verbose \
                --list \
                --filter AME \
                --show-rc \
                --one-file-system \
                --exclude-caches \
                ${if cfg.excludeNix then ''
                  --exclude /etc/nix/nix.conf \
                  --exclude /nix/ \
                '' else ''\''}
                --exclude /tmp/ \
                --exclude /var/tmp/ \
                --exclude /var/swapfile \
                --exclude '/home/*/.cache/' \
                --exclude '/home/*/.thumbnails/' \
                --exclude '/home/*/.nox/' \
                --exclude '*/.Trash*/' \
                --exclude '*/$RECYCLE.BIN' \
                --exclude '*/System Volume Information' \
                --compression lz4 \
                "$repository::${cfg.archiveBaseName}-$(date +%Y%m%dT%H%M%S)" \
                ${lib.concatStringsSep " " cfg.pathsToBackup}
            create_ret=$?

            echo "Running 'borg prune [...]'"
            borg prune \
                --stats \
                --verbose \
                --list \
                --show-rc \
                --keep-within=2d --keep-daily=7 --keep-weekly=4 --keep-monthly=6 \
                --prefix ${cfg.archiveBaseName}- \
                "$repository"
            prune_ret=$?

            echo "Running 'borg check [...]'"
            borg check \
                --verbose \
                --show-rc \
                "$repository"
            check_ret=$?

            ${cfg.postHook}

            # Exit with error if either command failed
            if [ $create_ret != 0 -o $prune_ret != 0 -o $check_ret != 0 ]; then
                die "borg create, prune and/or check operation failed. Exiting with error."
            fi
          '';
        in
          borgBackup;
    };

  };

}

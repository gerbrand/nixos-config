{ config, lib, pkgs, ... }:

let
  myDomain = "cloud.gerbrand-ict.nl";
  phpSockName1 = "/run/phpfpm/pool1.sock";
in
{
  imports = [
    ../hardware-configuration.nix
    ../config/base-ger.nix
    ../nixos-in-place.nix
    ../config/clamav.nix
    ../config/gitolite.nix
    ../config/git-daemon.nix
    ../config/transmission.nix
    ../options/nextcloud.nix
    ../options/collectd-graph-panel.nix
    ../options/gitolite-mirror.nix
  ];

  networking.hostName = "cloud";

  users.extraUsers."lighttpd".extraGroups = [ "git" ];

  services = {

    postfix = {
      enable = true;
      domain = "gerbrand-ict.nl";
      hostname = "vps0";
      rootAlias = "gerbrand@vandieijen.nl";
    };

    lighttpd = {
      enable = true;
      mod_status = true; # don't expose to the public
      mod_userdir = true;
      enableModules = [ "mod_alias" "mod_proxy" "mod_access" "mod_fastcgi" "mod_redirect" ];
      extraConfig = ''
        # Uncomment one or more of these in case something doesn't work right
        #debug.log-request-header = "enable"
        #debug.log-request-header-on-error = "enable"
        #debug.log-response-header = "enable"
        #debug.log-file-not-found = "enable"
        #debug.log-request-handling = "enable"
        #debug.log-condition-handling = "enable"

        $HTTP["host"] =~ ".*" {
          dir-listing.activate = "enable"
          alias.url += ( "/munin" => "/var/www/munin" )

          # Reverse proxy for transmission bittorrent client
          proxy.server = (
            "/transmission" => ( "transmission" => (
                                 "host" => "127.0.0.1",
                                 "port" => 9091
                               ) )
          )
          # Fix transmission URL corner case: get error 409 if URL is
          # /transmission/ or /transmission/web. Redirect those URLs to
          # /transmission (no trailing slash).
          url.redirect = ( "^/transmission/(web)?$" => "/transmission" )

          fastcgi.server = (
            ".php" => (
              "localhost" => (
                "socket" => "${phpSockName1}",
              ))
          )

          # Block access to certain URLs if remote IP is not on LAN
          $HTTP["remoteip"] !~ "^(192\.168\.1|127\.0\.0\.1)" {
              $HTTP["url"] =~ "(^/transmission/.*|^/server-.*|^/munin/.*|^${config.services.lighttpd.collectd-graph-panel.urlPrefix}.*)" {
                  url.access-deny = ( "" )
              }
          }
        }

        # Lighttpd SSL/HTTPS documentation:
        # http://redmine.lighttpd.net/projects/lighttpd/wiki/Docs_SSL

        $HTTP["host"] == "nextcloud.gerbrand-ict.nl" {
          $SERVER["socket"] == ":443" {
            ssl.engine = "enable"
            ssl.pemfile = "/etc/lighttpd/certs/gerbrand-ict/certificate.pem"
            ssl.ca-file = "/etc/lighttpd/certs/gerbrand-ict/cabundle.crt"
          }
          $HTTP["scheme"] == "http" {
            url.redirect = ("^/.*" => "https://nextcloud.gerbrand-ict.nl$0")
          }
        }

        $HTTP["host"] == "cloud.gerbrand-ict.nl" {
          $SERVER["socket"] == ":443" {
            ssl.engine = "enable"
            ssl.pemfile = "/etc/lighttpd/certs/gerbrand-ict/certificate.pem"
            ssl.ca-file = "/etc/lighttpd/certs/gerbrand-ict/cabundle.crt"
          }
          $HTTP["scheme"] == "http" {
            $HTTP["url"] =~ "^/nextcloud.*" {
              url.redirect = ("^/.*" => "https://cloud.gerbrand-ict.nl$0")
            }
          }
        }

        $HTTP["host"] == "vps0.gerbrand-ict.nl" {
          $SERVER["socket"] == ":443" {
            ssl.engine = "enable"
            ssl.pemfile = "/etc/lighttpd/certs/gerbrand-ict/certificate.pem"
            ssl.ca-file = "/etc/lighttpd/certs/gerbrand-ict/cabundle.crt"
          }
          $HTTP["scheme"] == "http" {
            $HTTP["url"] =~ "^/nextcloud.*" {
              url.redirect = ("^/.*" => "https://vps0.gerbrand-ict.nl$0")
            }
          }
        }



      '';
      collectd-graph-panel.enable = true;
      nextcloud = {
	enable = true;
        vhostsPattern = ".*.gerbrand-ict.nl";
      };
      gitweb.enable = true;
      gitweb.projectroot = "/srv/git/repositories";
      gitweb.extraConfig = ''
        our $projects_list = '/srv/git/projects.list';
      '';
      cgit = {
        enable = true;
        configText = ''
          # HTTP endpoint for git clone is enabled by default
          #enable-http-clone=1

          # Specify clone URLs using macro expansion
          clone-url=http://${myDomain}/cgit/$CGIT_REPO_URL https://${myDomain}/cgit/$CGIT_REPO_URL git://${myDomain}/$CGIT_REPO_URL git@${myDomain}:$CGIT_REPO_URL

          # Show pretty commit graph
          #enable-commit-graph=1

          # Show number of affected files per commit on the log pages
          enable-log-filecount=1

          # Show number of added/removed lines per commit on the log pages
          enable-log-linecount=1

          # Enable 'stats' page and set big upper range
          max-stats=year

          # Allow download of archives in the following formats
          snapshots=tar.xz zip

          # Enable caching of up to 1000 output entries
          cache-size=1000

          # about-formatting.sh is impure (doesn't work)
          #about-filter=${pkgs.cgit}/lib/cgit/filters/about-formatting.sh
          # Add simple plain-text filter
          about-filter=${pkgs.writeScript "cgit-about-filter.sh"
            ''
              #!${pkgs.stdenv.shell}
              echo "<pre>"
              ${pkgs.coreutils}/bin/cat
              echo "</pre>"
            ''
          }

          # Search for these files in the root of the default branch of
          # repositories for coming up with the about page:
          readme=:README.asciidoc
          readme=:README.txt
          readme=:README
          readme=:INSTALL.asciidoc
          readme=:INSTALL.txt
          readme=:INSTALL

          # Group repositories on the index page by sub-directory name
          section-from-path=1

          # Allow using gitweb.* keys
          enable-git-config=1

          # (Can be) maintained by gitolite
          project-list=/srv/git/projects.list

          # scan-path must be last so that earlier settings take effect when
          # scanning
          scan-path=/srv/git/repositories
        '';
      };
    };

    phpfpm.poolConfigs = lib.mkIf config.services.lighttpd.enable {
      pool1 = ''
        listen = ${phpSockName1}
        listen.group = lighttpd
        user = nobody
        pm = dynamic
        pm.max_children = 75
        pm.start_servers = 10
        pm.min_spare_servers = 5
        pm.max_spare_servers = 20
        pm.max_requests = 500
      '';
    };

    apcupsd.enable = true;

    collectd = {
      enable = true;
      extraConfig = ''
        # Interval at which to query values. Can be overwritten on per plugin
        # with the 'Interval' option.
        # WARNING: You should set this once and then never touch it again. If
        # you do, you will have to delete all your RRD files.
        Interval 10

        # Load plugins
        LoadPlugin apcups
        LoadPlugin contextswitch
        LoadPlugin cpu
        LoadPlugin df
        LoadPlugin disk
        LoadPlugin ethstat
        LoadPlugin interface
        LoadPlugin irq
        LoadPlugin virt
        LoadPlugin load
        LoadPlugin memory
        LoadPlugin network
        LoadPlugin nfs
        LoadPlugin processes
        LoadPlugin rrdtool
        LoadPlugin sensors
        LoadPlugin tcpconns
        LoadPlugin uptime

        <Plugin "virt">
          Connection "qemu:///system"
        </Plugin>

        <Plugin "df">
          MountPoint "/"
          MountPoint "/mnt/data/"
          MountPoint "/mnt/backup-disk/"
        </Plugin>

        # Output/write plugin (need at least one, if metrics are to be persisted)
        <Plugin "rrdtool">
          CacheFlush 120
          WritesPerSecond 50
        </Plugin>
      '';
    };

    munin-node.extraConfig = ''
      cidr_allow 192.168.1.0/24
    '';

    mysql = {
      enable = true;
      package = pkgs.mysql;
      extraOptions = ''
        # This is added in the [mysqld] section in my.cnf
      '';
    };

    tftpd = {
      enable = true;
      path = "/srv/tftp";
    };

    ntopng = {
      # It constantly breaks due to geoip database hash changes.
      # TODO: See if fetching geoip databases can be done with a systemd
      # service instead of using Nix.
      #enable = true;
      extraConfig = "--disable-login";
    };
  };
}

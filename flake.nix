{
  description = "Shopware6 Ide flake";
  inputs = { 
    nixpkgs.url = "github:nixos/nixpkgs?rev=87a9c680df85ae813191023f3920f9ac50b8bf57"; 
    nixpkgs_latest.url = "github:nixos/nixpkgs"; 
    # nixpkgs-22 = {
    #   url = "github:nixos/nixpkgs?ref=22.05";
    #   flake = false;
    # };
    flake-utils.url = "github:numtide/flake-utils";
    phps.url = "github:fossar/nix-phps?rev=d242ccad64fbbd1f44ddc96d6510904922a4e3d1"; 
    shopware = {
      url = "github:shopware/shopware?ref=v6.5.6.0";
      flake = false;
    };
  };
  outputs = { self, nixpkgs, nixpkgs_latest, flake-utils, shopware, phps}: 
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        pkgs_latest = nixpkgs_latest.legacyPackages.${system};
        helix = pkgs_latest.helix;
        # node16 = pkgs.nodejs_16.overrideAttrs (o: {meta = o.meta // {knownVulnerabilities = [];};});
        node = pkgs.nodejs_18;
        watchexec = pkgs.watchexec;
        redis = pkgs.redis;
        php = phps.packages.${system}.php82;
        phpactor = pkgs.phpactor;
        composer = phps.packages.${system}.php82.packages.composer;
        nginx = pkgs.nginx;        
        starship = pkgs.starship;
        uutils-coreutils = pkgs_latest.uutils-coreutils;
        git = pkgs.git;
        fish = pkgs.fish;
        zellij = pkgs_latest.zellij;
        pnpm = pkgs.nodePackages.pnpm;
        mariadb = pkgs.mysql80;
        envsubst = pkgs.envsubst;
        runit = pkgs.runit;
        dbname = "shopware";
        dbuser = "shopware";
        dbpass = "shopware";
        dbhost = "127.0.0.1";
        dbport = "3307";
        phpfpmport = "9124";
        redisport = "7777";
        hostname = "localhost";
        port = "8081";
      in {
        devShell = pkgs.mkShell {
          buildInputs = [
            helix
            phpactor
            nginx
            starship
            uutils-coreutils
            git
            php
            composer
            fish
            node
            # node16
            pnpm
            mariadb
            envsubst
            runit
            zellij
          ];
          NGINX_PATH = nginx;
          PHPFPMPORT = phpfpmport;
          REDISPORT = redisport;
          HOSTNAME = hostname;
          DBHOST = dbhost;
          NODE_OPTIONS= "--openssl-legacy-provider";
          SW_PORT= port;
          APP_URL = "http://${hostname}:${port}";
          DATABASE_URL = "mysql://${dbuser}:${dbpass}@${dbhost}:${dbport}/${dbname}";
          shellHook = "
              if ! [ -e flake.nix ]; then
                echo \"Please execute nix develop in the directory where your flake.nix is located.\"
                exit 1
              fi
              export HOME=$PWD
              export XDG_HOME=$PWD
              export SVDIR=$HOME/.state/services

              chmod -R 755 .state

              #mariadb setup 
              if ! [ -e $HOME/.state/mariadb/.dbcreated ]; then
                cat .state/mariadb/maria_subst.cnf | envsubst > .state/mariadb/maria.cnf
                cat .state/services/mariadb/run_subst | envsubst > .state/services/mariadb/run 
                cat .state/services/mariadb/log/run_subst | envsubst > .state/services/mariadb/log/run
                mysqld --datadir=$HOME/.state/mariadb/data --initialize-insecure
              fi;

              #nginx setup
              if ! [ -e .state/nginx/nginx.pid ]; then
                cat .state/nginx/subst.conf | D='\$' envsubst > .state/nginx/nginx.conf
                cat .state/services/nginx/run_subst | envsubst > .state/services/nginx/run 
                cat .state/services/nginx/log/run_subst | envsubst > .state/services/nginx/log/run
                touch .state/nginx/logs/error.log
                touch .state/nginx/logs/access.log
                touch .state/nginx/nginx.pid
              fi
                         
              #php-fpm setup
              if ! [ -e .state/phpfpm/phpfpm.conf ]; then
                touch .state/phpfpm/logs/php-fpm.log
                touch .state/phpfpm/php-fpm.pid
                cat .state/phpfpm/subst.conf | envsubst > .state/phpfpm/phpfpm.conf
                cat .state/services/phpfpm/run_subst | envsubst > .state/services/phpfpm/run 
                cat .state/services/phpfpm/log/run_subst | envsubst > .state/services/phpfpm/log/run
                touch .state/phpfpm/phpfpm.conf
              fi
                     
              chmod -R 755 .state
              runsvdir .state/services &
              RUNSVDIRPID=$!
              trap 'sv stop mariadb && sv stop phpfpm && sv stop nginx && kill -SIGHUP $RUNSVDIRPID' EXIT
              sleep 3
              sv status mariadb

              if ! [ -e $HOME/.state/mariadb/.dbcreated ]; then
                mysql -S $HOME/.state/mariadb/tmp/mysql.sock -u root --execute 'CREATE DATABASE IF NOT EXISTS ${dbname};'
                mysql -S $HOME/.state/mariadb/tmp/mysql.sock -u root --execute \"CREATE USER IF NOT EXISTS '${dbuser}'@'localhost' IDENTIFIED BY '${dbpass}'\"
                mysql -S $HOME/.state/mariadb/tmp/mysql.sock -u root --execute \"GRANT ALL PRIVILEGES ON *.* TO '${dbuser}'@'localhost';\" && touch $HOME/.state/mariadb/.dbcreated
              fi;

              #install shopware
              if ! [ -e .state/shopware/.shopwareinstalled ]; then
                chmod -R 755 shopware
                cp -r ${shopware}/* $HOME/shopware/
                cat $HOME/shopware/.env_subst | envsubst > $HOME/shopware/.env
                mkdir shopware/custom
                mkdir shopware/var
                mkdir shopware/files
                chmod -R 755 shopware
                composer --working-dir=$HOME/shopware install
                DATABASE_URL=$DATABASE_URL php -d memory_limit=6G shopware/bin/console system:install --basic-setup --create-database --force
                DATABASE_URL=$DATABASE_URL shopware/bin/console bundle:dump
                DATABASE_URL=$DATABASE_URL shopware/bin/console feature:dump
                npm --prefix shopware/src/Administration/Resources/app/administration/ install
                PROJECT_ROOT=$HOME/shopware ENV_FILE=$HOME/shopware/.env npm run --prefix shopware/src/Administration/Resources/app/administration/ build
                npm --prefix shopware/src/Storefront/Resources/app/storefront install
                PROJECT_ROOT=$HOME/shopware ENV_FILE=$HOME/shopware/.env npm run --prefix shopware/src/Storefront/Resources/app/storefront development
                node shopware/src/Storefront/Resources/app/storefront/copy-to-vendor.js
                DATABASE_URL=$DATABASE_URL shopware/bin/console assets:install
                touch .state/shopware/.shopwareinstalled 
              fi
              if [ -e shopware/config/jwt/public.pem ]; then
                chmod 660 shopware/config/jwt/public.pem 
              fi
              if [ -e shopware/config/jwt/private.pem ]; then
                chmod 660 shopware/config/jwt/private.pem 
              fi
              zellij
          ";
        };
      }  
    );
  }

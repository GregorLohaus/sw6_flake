{
  description = "A very basic flake";
  inputs = { 
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    phps.url = "github:fossar/nix-phps";  
    shopware = {
      url = "github:shopware/shopware?ref=v6.4.20.2";
      flake = false;
    };
    nginxconfshopware = {
      url = "github:GregorLohaus/nginx_conf_for_sw_flakes?ref=sw-v-6-5-0-0";
      flake = false;
    };
    dotenv = {
      url = "github:GregorLohaus/dot_env_for_sw6_flake?ref=sw-v-6-5-0-0";
      flake = false;
    };
    redisconf = {
      url = "github:GregorLohaus/redis_conf_for_sw_flakes?ref=sw-v-6-5-0-0";
      flake = false;
    };
    mariadbcnf = {
      url = "github:GregorLohaus/mariadb_conf_for_sw_flakes?ref=sw-v-6-5-0-0";
      flake = false;
    };
    mariadbservice = {
      url = "github:GregorLohaus/runit_mariadb_service_for_sw_flakes?ref=sw-v-6-5-0-0";
      flake = false;
    };
    nginxservice = {
      url = "github:GregorLohaus/runit_nginx_service_for_sw_flakes?ref=sw-v-6-5-0-0";
      flake = false;
    };
    redisservice = {
      url = "github:GregorLohaus/runit_redis_service_for_sw_flakes?ref=sw-v-6-5-0-0";
      flake = false;
    };
    phpfpmservice = {
      url = "github:GregorLohaus/runit_phpfpm_service_for_sw_flakes?ref=sw-v-6-5-0-0";
      flake = false;
    };
    phpfpmconf = {
      url = "github:GregorLohaus/php_fpm_conf_for_sw_flakes?ref=sw-v-6-5-0-0";
      flake = false;
    };
  };
  outputs = { self, nixpkgs, flake-utils, phps, shopware, nginxconfshopware,redisconf,redisservice, mariadbcnf, mariadbservice, nginxservice, phpfpmconf, dotenv, phpfpmservice}: 
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        node = pkgs.nodejs_16.overrideAttrs (o: {meta = o.meta // {knownVulnerabilities = [];};});
        watchexec = pkgs.watchexec;
        redis = pkgs.redis;
        php  = phps.packages.${system}.php82;
        composer = phps.packages.${system}.php82.packages.composer;
        box = phps.packages.${system}.php82.packages.box;
        nginx = pkgs.nginx;
        maria = pkgs.mysql80;
        envsubst = pkgs.envsubst;
        runit = pkgs.runit;
        sd = pkgs.sd;
        dbname = "shopware";
        dbuser = "shopware";
        dbpass = "shopware";
        dbhost = "0.0.0.0";
        dbport = "3306";
        phpfpmport = "9123";
        redisport = "7777";
        hostname = "localhost";
      in {
        devShell = pkgs.mkShell {
          buildInputs = [
            watchexec
            node
            box
            redis
            php
            nginx
            maria
            envsubst
            runit
            composer
            sd
          ];
          SHOPWARE_SRC=shopware;
          NGINX_PATH = nginx;
          HOSTNAME = hostname;
          DBPASS = dbpass;
          DBUSER = dbuser;
          DBHOST = dbhost;
          DBPORT = dbport; 
          DBNAME = dbname;
          PHPFPMPORT = phpfpmport;
          REDISPORT = redisport;
          NODE_OPTIONS= "--openssl-legacy-provider";
          INSTALL_URL = "http://localhost:8050";
          CYPRESS_dbHost = hostname;
          CYPRESS_dbUser = dbuser;
          CYPRESS_dbPassword = dbpass;
          CYPRESS_dbName = dbname;
          APP_URL = "http://localhost:8080";
          APP_SECRET = "devsecret";
          DATABASE_URL = "mysql://${dbuser}:${dbpass}@${dbhost}:${dbport}/${dbname}";
          shellHook = "
            #env setup
            export HOME=$PWD
            export XDG_HOME=$PWD
            export SVDIR=$HOME/services
            mkdir -p services
            chmod -R 755 .
            #check for directory correctness
            #if ! [ -e flake.nix ]; then
            #  echo 'Only Execute nix develop in the direcory where the flake.nix file is located'
            #  exit 1
            #fi
            
            #mariadb setup
            if ! [ -e my.cnf ]; then
              cat ${mariadbcnf}/my.cnf | envsubst > my.cnf
              mkdir -p mariadb
              mkdir -p mariadb/data
              mkdir -p mariadb/english
              mkdir -p mariadb/tmp
              touch mariadb/tmp/mysql.sock
              mkdir -p services/mariadb
              cp -r -u -f ${mariadbservice}/. services/mariadb/
              mkdir -p services/mariadb/logs
              chmod -R 777 services/mariadb
              cat services/mariadb/run_subst | envsubst > services/mariadb/run 
              cat services/mariadb/log/run_subst | envsubst > services/mariadb/log/run
              chmod -R 777 services/mariadb
              mysql_install_db --datadir=./mariadb/data
            fi

            #nginx setup
            if ! [ -e nginx.conf ]; then
              cat ${nginxconfshopware}/shopware6.conf | envsubst > nginx.conf
              cp -r -u -f ${nginxservice}/. services/
              chmod -R 777 services/nginx
              cat services/nginx_subst/run_subst | envsubst > services/nginx/run 
              cat services/nginx_subst/log/run_subst | envsubst > services/nginx/log/run
              chmod -R 777 services/nginx_subst
              rm -r services/nginx_subst
              chmod -R 777 services/nginx
              mkdir -p nginxlogs
              touch nginxlogs/error.log
              touch nginxlogs/access.log
              touch nginxlogs/nginx.pid
            fi

            #redis setup
            if ! [ -e redis.conf ]; then
              cat ${redisconf}/redis.conf | envsubst > redis.conf
              cp -r -u -f ${redisservice}/. services/
              chmod -R 777 services/redis
              cat services/redis_subst/run_subst | envsubst > services/redis/run 
              cat services/redis_subst/log/run_subst | envsubst > services/redis/log/run
              chmod -R 777 services/redis_subst
              rm -r services/redis_subst
              chmod -R 777 services/redis
              touch redis.pid
              touch redis.log
            fi

            #php-fpm setup
            if ! [ -e php-fpm.conf ]; then
              mkdir -p tmp
              mkdir -p phpfpmlogs 
              touch phpfpmlogs/php-fpm.log
              touch phpfpmlogs/php-fpm.pid
              chmod -R 777 phpfpmlogs
              chmod -R 777 tmp
              cat ${phpfpmconf}/php-fpm.conf | envsubst > php-fpm.conf
              cp -r -u -f ${phpfpmservice}/. services/
              chmod -R 777 services/phpfpm
              cat services/phpfpm_subst/run_subst | envsubst > services/phpfpm/run 
              cat services/phpfpm_subst/log/run_subst | envsubst > services/phpfpm/log/run
              chmod -R 777 services/phpfpm_subst
              rm -r services/phpfpm_subst
              chmod -R 777 services/phpfpm
              touch php-fpm.sock
            fi
            
            #start services
            runsvdir services &
            RUNSVDIRPID=$!
            trap 'sv stop redis && sv stop nginx && sv stop phpfpm && sv stop mariadb && kill -SIGHUP $RUNSVDIRPID' EXIT
            sv status mariadb
            sleep 5
            #shopware install
            if ! [ -e .dbcreated ]; then 
              mysql -S $HOME/mariadb/tmp/mysql.sock -u $USER --execute 'CREATE DATABASE IF NOT EXISTS ${dbname};'
              mysql -S $HOME/mariadb/tmp/mysql.sock -u $USER --execute \"CREATE USER IF NOT EXISTS '${dbuser}'@'localhost' IDENTIFIED BY '${dbpass}'\"
              mysql -S $HOME/mariadb/tmp/mysql.sock -u $USER --execute \"GRANT ALL PRIVILEGES ON *.* TO '${dbuser}'@'localhost';\" && touch .dbcreated
            fi

            #install shopware
            if ! [ -e .shopwareinstalled ]; then
              cp -r ${shopware}/. $HOME/
              cat ${dotenv}/.env | envsubst > .env
              mkdir custom
              mkdir var
              mkdir files
              chmod -R 755 public
              chmod -R 755 config
              chmod -R 755 var
              chmod -R 755 files
              chmod -R 755 src
              chmod -R 755 custom
              composer install
              php -d memory_limit=6G bin/console system:install --basic-setup --create-database --force
              bin/console bundle:dump
              bin/console feature:dump
              npm --prefix src/Administration/Resources/app/administration/ install
              PROJECT_ROOT=$HOME ENV_FILE=$HOME/.env npm run --prefix src/Administration/Resources/app/administration/ build
              npm --prefix src/Storefront/Resources/app/storefront install
              PROJECT_ROOT=$HOME ENV_FILE=$HOME/.env npm run --prefix src/Storefront/Resources/app/storefront development
              node src/Storefront/Resources/app/storefront/copy-to-vendor.js
              bin/console assets:install
              touch .shopwareinstalled 
            fi
            if [ -e config/jwt/public.pem ]; then
              chmod 660 config/jwt/public.pem 
            fi
            if [ -e config/jwt/private.pem ]; then
              chmod 660 config/jwt/private.pem 
            fi
          ";
        };
      }  
    );
  }

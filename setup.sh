#!/bin/bash

DB_NAME='wordpress'
DB_USER='user'
DB_PASSWORD='password'
DB_PREFIX='wp_'
HOMEPAGE_DIR='genuss'
HOMEPAGE_URL='genussamsee.com'
REMOTE_HOST='tk_wp'

SETUP=false

db='false'
plugins='false'
themes='false'
uploads='false'
all='false'

UP='false'
DOWN='false'

fallback='true'
here=''

NO_DIR='false'

print_usage(){
  echo "Usage:"
  echo "    tk_wp setup"
  echo "        Runs a setup for your local wordpress installation."
  echo "        Make sure you filled in the correct data for the db."
  echo "        Note that the DB must not exist for a successfull setup."
  echo "    tk_wp sync [ --all, --plugins, --uploads, --db ]"
  echo "        Syncs the local db with the db from the server by default."
  echo "        You can also partially sync any part of the wp project you want."
  echo "        Make sure you have got the tk_wp ssh connection filled in."
  echo "    tk_wp deploy [ --plugins, --themes, --uploads, --db ]"
  echo "        Deploys the current theme only by default."
  echo "        --themes ... uploads themes only"
  echo "        --plugins ... uploads plugin onlys"
  echo "        --db ... only syncs db"
  echo "        --uploads... uploads files in /wp-content/uploads only"
  echo ""
  echo "    --git-sync"
  echo "        Allows to sync the git files to the server. false by default!"
  exit 1
}

check_param(){
  echo ${1}
  if [ -z "$1" ]
    then
      echo "No argument supplied"
      echo ""
      print_usage
      break
  fi
}

OPTION=''
GIT_SYNC='false'

while true; do
  case "$1" in
    setup)  OPTION='setup'; shift ;;
    core_setup) OPTION='core_setup'; shift ;;
    apache_setup) OPTION='apache_setup'; shift ;;
    sync)   OPTION='sync'; shift;;
    deploy) OPTION='deploy'; shift;;
    -h | --help) print_usage; shift;;
    # -u | --up) check_param ${2}; REMOTE_HOST="$2"; UP='true' shift 2 ;;
    --themes) themes='true'; fallback='false'; shift;;
    --plugins) plugins='true'; fallback='false'; shift;;
    --db) db='true'; fallback='false'; shift;;
    --uploads) uploads='true'; fallback='false'; shift;;
    --git-sync) GIT_SYNC='true'; shift;;
    --all) all='true'; shift ;;
    * ) break ;;
  esac
done

upload_files(){
  NAME=$1
  if [ "$HOMEPAGE_DIR" = '' ]; then
        NO_DIR='true'
      else
        cd wp-content

        if [ "$GIT_SYNC" = true ]; then
          tar cfvz ${NAME}.tar.gz ./${NAME}
        else
          tar cfvz ${NAME}.tar.gz ./${NAME} --exclude='.git*'
        fi
        scp ./${NAME}.tar.gz ${REMOTE_HOST}:/kunden/homepages/17/d588880548/htdocs/

        ssh ${REMOTE_HOST} << ENDSSH
          mv ${NAME}.tar.gz "clickandbuilds/WordPress/$HOMEPAGE_DIR/wp-content/"
          cd "clickandbuilds/WordPress/$HOMEPAGE_DIR/wp-content/"
          if [ ! -d "backups" ]; then
            mkdir backups
          fi
          mv ${NAME} "./backups/uploads_$(date -Iseconds)"
          tar -xzf ${NAME}.tar.gz
          rm ${NAME}.tar.gz
ENDSSH
        rm ${NAME}.tar.gz
        cd ..
  fi
}

download_files(){
  NAME=$1
  if [ "$HOMEPAGE_DIR" = '' ]; then
    NO_DIR='true'
  else
    ssh ${REMOTE_HOST} << ENDSSH
      cd "clickandbuilds/WordPress/$HOMEPAGE_DIR/wp-content/"
      tar cfvz ${NAME}.tar.gz ./${NAME}
ENDSSH
    cd wp-content
    scp "$REMOTE_HOST:/kunden/homepages/17/d588880548/htdocs/clickandbuilds/WordPress/$HOMEPAGE_DIR/wp-content/${NAME}.tar.gz" ./
    rm -rf ${NAME}
    tar -xzf ${NAME}.tar.gz
    rm ${NAME}.tar.gz
    cd ..
    ssh ${REMOTE_HOST} << ENDSSH
      cd "clickandbuilds/WordPress/$HOMEPAGE_DIR/wp-content/"
      rm ${NAME}.tar.gz
ENDSSH
   fi  
}

remove_git(){
  /bin/rm -rf .git*
}

apache_setup(){
  echo "<VirtualHost *:80>
    ServerName ${HOMEPAGE_URL}
    DocumentRoot ${PWD}
   
    <Directory ${PWD}> 
      AllowOverride All 
      Require all granted 
    </Directory> 
   
</VirtualHost>" > ${HOMEPAGE_DIR}.conf
  sudo mv ./${HOMEPAGE_DIR}.conf /etc/apache2/sites-available/
  sudo a2ensite ${HOMEPAGE_DIR}.conf
  sudo service apache2 reload
}

wp_core_setup(){
  wp core config --dbname=${DB_NAME} --dbuser=${DB_USER} --dbpass=${DB_PASSWORD} --dbprefix=${DB_PREFIX}
  wp core install --url=${HOMEPAGE_URL} --title=${HOMEPAGE_DIR} --admin_user=tk_admin --admin_password='`|HA_i9c1@KU{p' --admin_email=contact@tastenwerk.com
}

run_setup(){ 
  remove_git
  echo "CHANGE FOLDER"
  cd .. 
  mv plain-1and1/ ${HOMEPAGE_DIR}
  cd ${HOMEPAGE_DIR}
  echo "WRITE APACHE FILES"
  apache_setup
  echo "INSTALL WP CORE"
  wp core download
  echo "CREATE DB"
  echo "type in root password for mysql"
  mysql -u root -p << EOF  
    CREATE DATABASE ${DB_NAME};
    CREATE USER ${DB_USER}@localhost IDENTIFIED BY '${DB_PASSWORD}';
    GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO ${DB_USER}@localhost;
    FLUSH PRIVILEGES;
EOF
  echo "CONFIG WP"
  wp_core_setup
  echo "WP SETUP finished!"
  echo "REMEMBER TO MAKE AN /etc/hosts ENTRY"
}

run_sync(){
  if [ "$db" = true ] || [ "$all" = true ] || [ "$fallback" = true ]; then
    ssh ${REMOTE_HOST} << ENDSSH
      mysqldump -h "$DB_NAME".db.1and1.com -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" > tables.sql
ENDSSH
    scp ${REMOTE_HOST}:/kunden/homepages/17/d588880548/htdocs/tables.sql . 
    mysql -u"$DB_USER" -p"$DB_PASSWORD"  "$DB_NAME" < tables.sql   
    rm tables.sql
  fi

  if [ "$uploads" = true ] || [ "$all" = true ]; then
    download_files uploads
  fi

  if [ "$plugins" = true ] || [ "$all" = true ]; then
    download_files plugins    
  fi
  
  if [ "$NO_DIR" = true ]; then
    echo "ERROR: <HOMEPAGE_DIR_NAME> needed!"
    print_usage
  fi
}

run_deploy(){
  if [ "$db" = true ] || [ "$all" = true ]; then
    mysqldump -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" > tables.sql
    scp ./tables.sql ${REMOTE_HOST}:/kunden/homepages/17/d588880548/htdocs/
    ssh ${REMOTE_HOST} << ENDSSH
      mysql -h "$DB_NAME".db.1and1.com -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < tables.sql   
      rm tables.sql
ENDSSH
    rm tables.sql
  fi

  if [ "$uploads" = true ] || [ "$all" = true ]; then
    upload_files uploads
  fi

  if [ "$plugins" = true ] || [ "$all" = true ]; then
    upload_files plugins
  fi

  if [ "$themes" = true ] || [ "$all" = true ] || [ "$fallback" = true ]; then
    upload_files themes   
  fi

  if [ "$NO_DIR" = true ]; then
    echo "ERROR: <HOMEPAGE_DIR_NAME> needed!"
    print_usage
  fi
}

case ${OPTION} in
  setup) run_setup ;;
  core_setup) wp_core_setup ;;
  apache_setup) apache_setup ;;
  sync) run_sync ;;
  deploy) run_deploy ;;
esac


#!/bin/bash

# Script to update tables data

# Set db_name


# Variables #####################################################################################

# Subject and usage
  subject=mmega_update
  usage="USAGE = mmega_update.sh <account_name|all>"

# Colors and symbols
  txtred=$(tput setaf 1)  # red
  txtgrn=$(tput setaf 2)  # green
  txtylw=$(tput setaf 3)  # yellow
  txtbld=$(tput bold)     # text bold
  txtrst=$(tput sgr0)     # text reset

  ok="[ ${txtgrn}OK${txtrst} ]"
  fail="[${txtred}FAIL${txtrst}]"
  wait="[ ${txtylw}--${txtrst} ]"

# Binaries
  MEGADF=$(which megadf)
  MEGACOPY=$(which megacopy)
  MEGALS=$(which megals)

# Database
  db_name=""

# Checks ########################################################################################

# Check binaries
  if [ -z "$MEGADF" ] || [ -z "$MEGACOPY" ] || [ -z "$MEGALS" ];then
     echo "$fail binary not found"
     exit 1
  fi

# Check mysql server
  if [ -z $(pgrep mysqld | head -n1) ];then
     echo "$fail mysql is not running"
     exit 1
  fi

# Check credential file ~/.my.cnf
  if [ ! -O ~/.my.cnf ];then
     echo "$fail file my.cnf not found or readable by user"
     exit 1
  fi

# Check database
  if [ -z "$db_name" ];then
     echo "$fail no database set"
     exit 1
  fi

  # Test if database exists
    mysql --login-path=local -e "USE $db_name" 2>/dev/null
    if [ $? = 1 ];then
       echo "$fail database $db_name does not exists"
       exit 1
    fi


# Lock file and tmp directory ###################################################################

# Lock file
  lock_file=/tmp/$subject.lock
  if [ -f "$lock_file" ]; then echo; echo -e "$fail Script is already running" ; echo; exit 1; fi
  touch $lock_file

# Make a tmp directory
  tmp_dir=$(mktemp -d)

# Delete tmp directory and lock file at exit
  trap "rm -rf $tmp_dir $lock_file" EXIT
  #trap "rm -rf $lock_file" EXIT


# Functions #####################################################################################

# Check command
test(){
  if [ $? = 0 ];then
     printf "%-6s %-50s\n" "$ok" "$1"
  else
     printf "%-6s %-50s\n" "$fail" "$1"
  fi
}

test2(){
  if [ $? = 0 ];then
     printf "%-12s %-50s\n" "       $ok" "$1"
  else
     printf "%-12s %-50s\n" "       $fail" "$1"
  fi
}

# Get input
get_input_account(){
  if [ -z $1 ];then
     echo "$fail No account name"
     echo "       $usage"
     echo
     exit 1
  fi

  # Get list accounts
    list_accounts_raw=$(mysql --login-path=local -sN -e "USE $db_name; SELECT name FROM config")

    declare -a list_accounts=()
    for line in $list_accounts_raw;do
       list_accounts+=("$line")
    done

  # Set account/all
    if [ "$1" == "all" ];then
       input_account="all"
    else
       # Test if account exists
         for account in "${list_accounts[@]}";do
            if [ "$account" == "$1" ];then
               input_account="$account"
               account_found="yes"
            fi
         done

         if [ "$account_found" != "yes" ];then
            echo "$fail Account not found"
            exit 1
         fi
    fi
}

# Get credentials
get_credentials() {
  email=$(mysql --login-path=local -Ns -e "USE $db_name; SELECT email FROM config WHERE name = '$1'")
  passwd=$(mysql --login-path=local -Ns -e "USE $db_name; SELECT passwd FROM config WHERE name = '$1'")

  if [ -z "$email" ] || [ -z "$passwd" ];then
     no_credentials="yes"
  fi
}

get_directories(){
  local_dir=$(mysql --login-path=local -Ns -e "USE $db_name; SELECT local_dir FROM config WHERE name = '$1'" )
  remote_dir=$(mysql --login-path=local -Ns -e "USE $db_name; SELECT remote_dir FROM config WHERE name = '$1'")

  if [ ! -d "$local_dir" ];then
     no_local="yes"
  fi
}


# Get disk stats
get_disk_stats() {
  data_num=$($MEGADF -u "$email" -p "$passwd" 2>&1 | grep 'Total\|Free\|Used') #in bytes
  if [ -z "$data_num" ];then
     no_data="yes"
  else
     total=$(echo "$data_num" | grep  Total | cut -d ' ' -f 2)
     free=$(echo "$data_num" | grep  Free | cut -d ' ' -f 3)
     used=$(echo "$data_num" | grep  Used | cut -d ' ' -f 3)
  fi
}

get_remote_files(){
  $MEGALS -u "$email" -p "$passwd" -R --long --export > $tmp_dir/remote_files_raw_$1
  if [ $? = 1 ];then
      no_remote_files="yes"
  else
     cat $tmp_dir/remote_files_raw_$1 | sed -e 's/ \{1,\}/ /1' -e 's/ \{1,\}/ /3' -e 's/ \{1,\}/ /5' | grep ^" https" | \
                                        cut -d ' ' -f2,6,7,8,9- | \
                                        sed -e 's/¬/_/' \
                                            -e 's/ /¬/1' \
                                            -e 's/ /¬/1' \
                                            -e 's/ /¬/2' \
                                            -e 's/$/¬/g' | \
                                        sed -e 's/^\|$/"/g' -e 's/¬/"¬"/g' > $tmp_dir/remote_files_$1

     cat $tmp_dir/remote_files_raw_$1 | sed -e 's/ \{1,\}/ /1' -e 's/ \{1,\}/ /3' -e 's/ \{1,\}/ /5' | grep -v ^" http" | \
                                        cut -d ' ' -f7- | grep ^1 | cut -d ' ' -f15-  | \
                                        sed -e 's/¬/_/' \
                                            -e 's/ /¬/2' \
                                            -e 's/$/¬/g' \
                                            -e 's/^\|$/"/g' \
                                            -e 's/¬/"¬"/g' > $tmp_dir/remote_directories_$1
  fi
}

# Insert remote files into database (from file created)
insert_remote_files(){
  # Delete table
    mysql --login-path=local -e "USE $db_name; TRUNCATE remote_files_$1"

  # Insert file
mysql --login-path=local $db_name << EOF
LOAD DATA LOCAL INFILE "$tmp_dir/remote_files_$1"
INTO TABLE remote_files_$1
    FIELDS TERMINATED BY '¬'
           OPTIONALLY ENCLOSED BY '"'
    LINES  TERMINATED BY '\n' -- or \r\n
    (link, size_bytes, mod_date, path);
EOF
  test2 "Inserting remote files"
}


insert_remote_directories(){
  # Delete table
    mysql --login-path=local -e "USE $db_name; TRUNCATE remote_directories_$1"

  # Insert file
mysql --login-path=local $db_name << EOF
LOAD DATA LOCAL INFILE "$tmp_dir/remote_directories_$1"
INTO TABLE remote_directories_$1
    FIELDS TERMINATED BY '¬'
           OPTIONALLY ENCLOSED BY '"'
    LINES  TERMINATED BY '\n' -- or \r\n
    (mod_date, path);
EOF
  test2 "Inserting remote directories"
}

complete_remote_files_tbl(){
 # Add column filename and size (test empty hash [first run] before to do it)
   # Get hash from database
     hash_db=$(mysql --login-path=local -sN -e "USE $db_name; SELECT md5_hash FROM hashes WHERE table_name ='remote_files_$1';")

     if [ "$hash_db" == "md5_hash" ];then
        mysql --login-path=local -e "USE $db_name; ALTER TABLE remote_files_$1 ADD COLUMN filename VARCHAR(255) FIRST;"
        mysql --login-path=local -e "USE $db_name; ALTER TABLE remote_files_$1 ADD COLUMN size VARCHAR(255) AFTER size_bytes;"
     fi

 # Insert filename and size
   mysql --login-path=local -e "USE $db_name; UPDATE remote_files_$1 \
                                                 SET filename=(SUBSTRING_INDEX(path, '/', -1)), \
                                                     size=sys.format_bytes(size_bytes) \
                                               WHERE path=path;"
 # Order by filename
   mysql --login-path=local -e "USE $db_name; ALTER TABLE local_files_$1 ORDER BY filename;"

 # Insert md5 hashes
   hash=$(md5sum $tmp_dir/remote_files_$1 | cut -d ' ' -f1)

   mysql --login-path=local -e "USE $db_name; UPDATE hashes \
                                                 SET md5_hash='$hash', \
                                                     last_update=NOW()
                                               WHERE table_name='remote_files_$1';
                                              UPDATE hashes \
                                                 SET md5_hash='$hash', \
                                                     last_update=NOW()
                                               WHERE table_name='remote_directories_$1';"
}

# Get local files
get_local_files(){
 # Get files
   find "$local_dir" -type f -exec stat -c "%s %y %n" {} \; | cut -d ' ' -f1-3,5- | sed -e 's/¬/_/' \
                                                                                        -e 's/ /¬/1' \
                                                                                        -e 's/ /¬/2' \
                                                                                        -e 's/^\|$/"/g' \
                                                                                        -e 's/¬/"¬"/g' > $tmp_dir/local_files_$1
 if [ $? = 1 ];then
     no_local_files="yes"
 fi

 # Get directories
   find "$local_dir" -type d -exec stat -c "%y %n" {} \; | sed 's/\./ /1' | cut -d ' ' -f1,2,5- | sed -e 's/¬/_/' \
                                                                                                      -e 's/ /¬/2' \
                                                                                                      -e 's/¬/"¬"/g' \
                                                                                                      -e 's/^\|$/"/g' > $tmp_dir/local_directories_$1
}


# Insert local files into database (from file created)
insert_local_files(){
  # Delete table
    mysql --login-path=local -e "USE $db_name; TRUNCATE local_files_$1"

  # Insert file
mysql --login-path=local $db_name << EOF
LOAD DATA LOCAL INFILE "$tmp_dir/local_files_$1"
INTO TABLE local_files_$1
    FIELDS TERMINATED BY '¬'
           OPTIONALLY ENCLOSED BY '"'
    LINES  TERMINATED BY '\n' -- or \r\n
    (size_bytes, mod_date, path);
EOF
  test2 "Inserting local files"
}

insert_local_directories(){
  # Delete table
    mysql --login-path=local -e "USE $db_name; TRUNCATE local_directories_$1"

  # Insert file
mysql --login-path=local $db_name << EOF
LOAD DATA LOCAL INFILE "$tmp_dir/local_directories_$1"
INTO TABLE local_directories_$1
    FIELDS TERMINATED BY '¬'
           OPTIONALLY ENCLOSED BY '"'
    LINES  TERMINATED BY '\n' -- or \r\n
    (mod_date, path);
EOF
  test2 "Inserting local directories"
}

complete_local_files_tbl(){
 # Add column filename and size (test empty hash [first run] before to do it)
   # Get hash from database
     hash_db=$(mysql --login-path=local -sN -e "USE $db_name; SELECT md5_hash FROM hashes WHERE table_name ='local_files_$1';")

     if [ "$hash_db" == "md5_hash" ];then
        mysql --login-path=local -e "USE $db_name; ALTER TABLE local_files_$1 ADD COLUMN filename VARCHAR(255) FIRST;"
        mysql --login-path=local -e "USE $db_name; ALTER TABLE local_files_$1 ADD COLUMN size VARCHAR(255) AFTER size_bytes;"
     fi

 # Insert filename and size
   mysql --login-path=local -e "USE $db_name; UPDATE local_files_$1 \
                                                 SET filename=(SUBSTRING_INDEX(path, '/', -1)), \
                                                     size=sys.format_bytes(size_bytes) \
                                               WHERE path=path;"
 # Order by filename
   mysql --login-path=local -e "USE $db_name; ALTER TABLE local_files_$1 ORDER BY filename;"

 # Insert md5 hash
   hash=$(md5sum $tmp_dir/local_files_$1 | cut -d ' ' -f1)

   mysql --login-path=local -e "USE $db_name; UPDATE hashes \
                                                 SET md5_hash='$hash', \
                                                     last_update=NOW()
                                               WHERE table_name='local_files_$1';
                                              UPDATE hashes \
                                                 SET md5_hash='$hash', \
                                                     last_update=NOW()
                                               WHERE table_name='local_directories_$1';"
}

get_file_stats(){
 # Number of files local and remote
   remote=$(mysql --login-path=local -sN -e "USE $db_name; SELECT COUNT(filename) FROM remote_files_$1;" )
   local=$(mysql --login-path=local -sN -e "USE $db_name; SELECT COUNT(filename) FROM local_files_$1;")

 # Number of files to download
   to_down=$(mysql --login-path=local -sN -e "USE $db_name; SELECT COUNT(filename) \
                                                                   FROM remote_files_$1 \
                                                       WHERE NOT EXISTS (SELECT filename \
                                                                           FROM local_files_$1 \
                                                                          WHERE remote_files_$1.filename=local_files_$1.filename);")
 # Number of files to upload
   to_up=$(mysql --login-path=local -sN -e "USE $db_name; SELECT COUNT(filename) \
                                                                  FROM local_files_$1 \
                                                      WHERE NOT EXISTS (SELECT filename \
                                                                          FROM remote_files_$1 \
                                                                         WHERE local_files_$1.filename=remote_files_$1.filename);")
 # Number of synchronized files
   sync=$(mysql --login-path=local -sN -e "USE $db_name; SELECT COUNT(filename) \
                                                           FROM local_files_$1 \
                                                   WHERE EXISTS (SELECT filename \
                                                                   FROM remote_files_$1 \
                                                                   WHERE local_files_$1.filename=remote_files_$1.filename);")
}

# Update disk stats
update_disk_stats(){
  mysql --login-path=local -e "USE $db_name; UPDATE disk_stats \
                                                SET total_bytes='$total', \
                                                    free_bytes='$free', \
                                                    used_bytes='$used', \
                                                    total=sys.format_bytes(total_bytes), \
                                                    free=sys.format_bytes(free_bytes), \
                                                    used=sys.format_bytes(used_bytes), \
                                                    last_update=NOW() \
                                              WHERE name='$1';"
}


# Update files stats
update_file_stats(){
  mysql --login-path=local -e "USE $db_name; UPDATE file_stats \
                                                SET local='$local', \
                                                    remote='$remote', \
                                                    to_down='$to_down', \
                                                    to_up='$to_up', \
                                                    sync='$sync', \
                                                    last_update=NOW() \
                                              WHERE name='$1';"
}

# Update global stats
update_global_stats(){
  mysql --login-path=local -e "USE $db_name; UPDATE global_stats \
                                                SET sum_acc=(SELECT COUNT(config.name) FROM config), \
                                                    sum_total=(SELECT sys.format_bytes(SUM(disk_stats.total_bytes)) FROM disk_stats), \
                                                    sum_free=(SELECT sys.format_bytes(SUM(disk_stats.free_bytes)) FROM disk_stats), \
                                                    sum_used=(SELECT sys.format_bytes(SUM(disk_stats.used_bytes)) FROM disk_stats), \
                                                    sum_local=(SELECT SUM(file_stats.local) AS local FROM file_stats), \
                                                    sum_remote=(SELECT SUM(file_stats.remote) AS remote FROM file_stats), \
                                                    sum_to_down=(SELECT SUM(file_stats.to_down) AS download FROM file_stats), \
                                                    sum_to_up=(SELECT SUM(file_stats.to_up) AS upload FROM file_stats), \
                                                    sum_sync=(SELECT SUM(file_stats.sync) AS synced FROM file_stats), \
                                                    last_update=NOW();"
}

# Full checks (local files, free space and remote files)
is_account_updated(){
  last_update=$(mysql --login-path=local -sN -e "USE $db_name; SELECT DATE_FORMAT(last_update,'%d-%m-%y %H:%i') FROM hashes WHERE table_name = 'remote_files_$1'")

  echo -n "$wait Checking tables for ${txtbld}$1${txtrst} [$last_update]"

  # Get credentials
    get_credentials "$1"
    if [ "$no_credentials" = "yes" ];then
        echo -e "\r$ok Cheking tables for ${txtred}$1${txtrst} [$last_update] [${txtred}fail${txtrst} no credentials found]"
        no_check="yes"
        no_credentials=""
        continue
    fi

    get_directories "$1"
    if [ "$no_local" = "yes" ];then
       echo -e "\r$ok Cheking tables for ${txtred}$1${txtrst} [$last_update] [${txtred}fail${txtrst} no local directory found]"
       no_check="yes"
       no_local=""
       continue
    fi

 # Test first run
   local_hash_db=$(mysql --login-path=local -sN -e "USE $db_name; SELECT md5_hash FROM hashes WHERE table_name='local_files_$1'")
   remote_hash_db=$(mysql --login-path=local -sN -e "USE $db_name; SELECT md5_hash FROM hashes WHERE table_name='remote_files_$1'")

   if [ "$local_hash_db" == "md5_hash" ] && [ "$remote_hash_db" == "md5_hash" ];then
      echo -e "\r$ok Cheking tables for ${txtbld}$1${txtrst} [$last_update] [${txtgrn}first run${txtrst}]"
      updated="no"
   else
      # Test changes in local files (no connection)
        local_hash_db=$(mysql --login-path=local -sN -e "USE $db_name; SELECT md5_hash FROM hashes WHERE table_name='local_files_$1'")
        get_local_files "$1"
        if [ "$no_local_files" = "yes" ];then
           echo -e "\r$ok Cheking tables for ${txtred}$1${txtrst} [$last_update] [${txtred}fail${txtrst} no local files found]"
           no_check="yes"
           no_local_files=""
           continue
        fi
        local_hash_updated=$(md5sum $tmp_dir/local_files_$1 | cut -d ' ' -f1)

        if [ "$local_hash_updated" != "$local_hash_db" ];then
           echo -e "\r$ok Cheking tables for ${txtbld}$1${txtrst} [$last_update] [${txtylw}outdated${txtrst}]"
           updated="no"
        else
           # Test changes in free espace (one connection, fast)
             free_bytes_mega=$($MEGADF -u "$email" -p "$passwd" | grep "Free" | cut -d ' ' -f3 2>/dev/null )
             if [ $? = 1 ];then
                echo -e "\r$ok Cheking tables for ${txtred}$1${txtrst} [$last_update] [${txtred}fail${txtrst} no connexion]"
                no_check="yes"
                continue
             fi

             free_bytes_db=$(mysql --login-path=local -sN -e "USE $db_name; SELECT free_bytes FROM disk_stats WHERE name = '$1'")

             if [ "$free_bytes_mega" != "$free_bytes_db" ];then
                echo -e "\r$ok Cheking tables for ${txtbld}$1${txtrst} [$last_update] [${txtylw}outdated${txtrst}]"
                updated="no"
             else
                # Test changes in remote files (one connection, slow)
                  remote_hash_db=$(mysql --login-path=local -sN -e "USE $db_name; SELECT md5_hash FROM hashes WHERE table_name='remote_files_$1'")
                  get_remote_files "$1"

                  if [ "$no_remote_files" = "yes" ];then
                     echo -e "\r$ok Cheking tables for ${txtred}$1${txtrst} [$last_update] [${txtred}fail${txtrst} no local files found]"
                     no_check="yes"
                     no_remote_files=""
                     continue
                  fi

                  remote_hash_updated=$(md5sum $tmp_dir/remote_files_$1 | cut -d ' ' -f1)

                  if [ "$remote_hash_updated" != "$remote_hash_db" ];then
                     echo -e "\r$ok Cheking tables for ${txtbld}$1${txtrst} [$last_update] [${txtylw}outdated${txtrst}]"
                     updated="no"
                  else
                     # Test sync
                       to_up=$(mysql --login-path=local -sN -e "USE $db_name; SELECT to_up from file_stats where name = '$1';")
                       to_down=$(mysql --login-path=local -sN -e "USE $db_name; SELECT to_down from file_stats where name = '$1';")

                       if [ "$to_up" = 0 ] && [ "$to_down" = 0 ];then
                          is_sync="and ${txtgrn}sync${txtrst}"
                       else
                          is_sync="but ${txtylw}not sync${txtrst}"
                       fi

                       echo -e "\r$ok Cheking tables for ${txtgrn}$1${txtrst} [$last_update] [${txtgrn}updated${txtrst} $is_sync]"
                       updated="yes"
                  fi
             fi
        fi
    fi
}

# Update tables (only one account)
update_tables(){
  echo "$wait Updating..."

  # Get credentials
    get_credentials "$1"

    if [ "$no_credentials" = "yes" ];then
       printf "%-12s %-50s\n" "       $fail" "Jumping account, no credentials found"
       no_credentials=""
       continue
    fi

  # Get directories
    get_directories "$1"

    if [ "$no_local" = "yes" ];then
       printf "%-12s %-50s\n" "       $fail" "Jumping account, no local directory found"
       no_local=""
       continue
    fi

  # Disk stats
    printf "%-12s %-50s\r" "       $wait" "Getting disk stats"
    get_disk_stats

    if [ "$no_data" = "yes" ];then
       printf "%-12s %-50s\n" "       $fail" "Jumping account, no disks stats data found"
       no_data=""
       continue
    else
       printf "%-12s %-50s\n" "       $ok" "Getting disk stats"

       printf "%-12s %-50s\r" "       $wait" "Updating disk stats"
       update_disk_stats "$1"
       test2 "Updating disk stats"
    fi

  # Get local files
    printf "%-12s %-50s\r" "       $wait" "Getting local files"
    get_local_files "$1"

    if [ "$no_local_files" = "yes" ];then
       printf "%-12s %-50s\n" "       $fail" "Jumping account, no local files found"
       continue
    else
      printf "%-12s %-50s\n" "       $ok" "Getting local files"
      insert_local_files "$1"
      insert_local_directories "$1"
      complete_local_files_tbl "$1"
    fi

  # Get remote files
    printf "%-12s %-50s\r" "       $wait" "Getting remote files"
    get_remote_files "$1"

    if [ "$no_remote_files" = "yes" ];then
       printf "%-12s %-50s\n" "       $fail" "Jumping account, no remote files found [connexion error]"
    else
       printf "%-12s %-50s\n" "       $ok" "Getting remote files"
       insert_remote_files "$1"
       insert_remote_directories "$1"
       complete_remote_files_tbl "$1"
    fi

  # File stats
    get_file_stats "$1"
    update_file_stats "$1"
}

show_status_all(){
  mysql --login-path=local -e "USE $db_name; SELECT name, \
                                                    lpad(total,11,' ') AS total, \
                                                    lpad(free,11,' ') AS free, \
                                                    lpad(used,11,' ') AS used, \
                                                    DATE_FORMAT(last_update,'%d-%m-%y %H:%i') AS last_update \
                                               FROM disk_stats;"

  mysql --login-path=local -e "USE $db_name; SELECT name, local, remote, to_down, to_up, sync, DATE_FORMAT(last_update,'%d-%m-%y %H:%i') \
                                                 AS last_update \
                                               FROM file_stats;"

  mysql --login-path=local -e "USE $db_name; SELECT sum_acc, \
                                                    lpad(sum_total,11,' ') AS sum_total, \
                                                    lpad(sum_free,11,' ') AS sum_free, \
                                                    lpad(sum_used,11,' ') AS sum_used, \
                                                    sum_local, \
                                                    sum_remote, \
                                                    sum_to_down, \
                                                    sum_to_up, \
                                                    sum_sync, \
                                                    DATE_FORMAT(last_update,'%d-%m-%y %H:%i') AS last_update \
                                               FROM global_stats;"
  echo
}

show_status_one(){
  mysql --login-path=local -e "USE $db_name; SELECT name, \
                                                    lpad(total,11,' ') AS total, \
                                                    lpad(free,11,' ') AS free, \
                                                    lpad(used,11,' ') AS used, \
                                                    DATE_FORMAT(last_update,'%d-%m-%y %H:%i') AS last_update \
                                               FROM disk_stats \
                                              WHERE name = '$1';"

  mysql --login-path=local -e "USE $db_name; SELECT name, \
                                                    local, \
                                                    remote, \
                                                    to_down, \
                                                    to_up, \
                                                    sync, \
                                                    DATE_FORMAT(last_update,'%d-%m-%y %H:%i') AS last_update \
                                               FROM file_stats \
                                              WHERE name = '$1';"
  echo
}

# Start #######################################################################################

# Title
echo "                                                __       __      ";
echo "  __ _   __ _  ___  ___ _ ___ _  __ __ ___  ___/ /___ _ / /_ ___ ";
echo " /  ' \ /  ' \/ -_)/ _ \`// _ \`/ / // // _ \/ _  // _ \`// __// -_)";
echo "/_/_/_//_/_/_/\__/ \_, / \_,_/  \_,_// .__/\_,_/ \_,_/ \__/ \__/ ";
echo "                  /___/             /_/                          ";
echo



#  echo
#  echo "${txtbld}        #### Update database and tables #### ${txtrst}"
#  echo

# Get input
get_input_account "$1"

if [ "$input_account" == "all" ];then
   list_accounts="$list_accounts_raw"

   # Show current status
     echo "${txtbld} Current status ${txtrst}"
     show_status_all

   # Check tables
     echo "${txtbld} Checking tables ${txtrst}"
     echo
     for account in $list_accounts; do
         is_account_updated "$account"
         if [ "$updated" == "no" ];then
            changes="yes"
            update_tables "$account"
            updated=""
         fi
     done
     update_global_stats

   # Show updated status if changes
     if [ "$changes" == "yes" ];then
        echo
        echo "${txtbld} Updated status ${txtrst}"
        show_status_all
        changes=""
     else
        echo "$ok No changes in database"
     fi

# One account
else
   list_accounts=$(echo "$list_accounts_raw" | grep "$input_account")

   # Show current status
     echo "${txtbld} Current status ${txtrst}"
     show_status_one "$list_accounts"

   # Check tables
     echo "${txtbld} Checking tables ${txtrst}"
     echo
     for account in $list_accounts; do
         is_account_updated "$account"
         if [ "$updated" == "no" ] ;then
            changes="yes"
            update_tables "$account"
            updated=""
         fi
     done

   # Show updated status if changes
     if [ "$changes" == "yes" ];then
        echo
        echo "${txtbld} Updated status ${txtrst}"
        show_status_one "$list_accounts"
        changes=""
     else
        echo "$ok No changes in database"
     fi
fi

echo
exit

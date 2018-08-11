#!/bin/bash

# Script to create database and tables for mega accounts

# Set MySQL user and passwords for user and root (encrypted if you want, see README). Only needed during database creation and for granting privileges.
# Root password is used only once time, so you can unset it and MySQL will ask you only once. It's still practical because this script is not run often.

# Before you run this script you have to create a file in your home directory [~/.my.cnf] with login credentials and made readable only by you (using
# chmod 0600 ~/.my.cnf)
# Make sure that you have the option secure_file_priv="" in /etc/mysql/mysql.conf.d/mysqld.cnf to use LOAD INFILE LOCAL DATA FUNCTION
# Make sure that you are using UTF-8 character encoding (filenames could change). Add to /etc/mysql/my.cnf
#    [mysqld]
#    collation-server = utf8_unicode_ci
#    init-connect='SET NAMES utf8'
#    character-set-server = utf8

# Set db_name.
# Set path of config file. Make sure that it haven't any trailing spaces or empty lines


# Variables #####################################################################################

# Subject and usage
  subject=mmega_create
  usage="USAGE = mmega_create.sh"

# Colors and symbols
  txtred=$(tput setaf 1)  # red
  txtgrn=$(tput setaf 2)  # green
  txtylw=$(tput setaf 3)  # yellow
  txtbld=$(tput bold)     # text bold
  txtrst=$(tput sgr0)     # text reset

  ok="[ ${txtgrn}OK${txtrst} ]"
  fail="[${txtred}FAIL${txtrst}]"
  wait="[ ${txtylw}--${txtrst} ]"

# MySQL credentials
  user="$USER"
  user_passwd=""
  root_passwd="" # optional

# Database and config file
  db_name=""
  config_file=""

# Scripts
  scripts_dir="$PWD"

  declare -a scripts_list=(
  "$scripts_dir/mmega_update.sh"
  "$scripts_dir/mmega_sync.sh"
  "$scripts_dir/mmega_query.sh")

# Completion
  completion_dir="$PWD/bash_completion"

  declare -a completion_list=(
  "$completion_dir/mmega_update_completion"
  "$completion_dir/mmega_sync_completion"
  "$completion_dir/mmega_query_completion"
  "$completion_dir/mmega_rc_completion"
)

# Checks ###########################################################################################

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

# Check user
  if [ -z $user ];then
     echo "$fail no user set"
     exit 1
  fi

# Check passwords
  if [ -z "$user_passwd" ] || [ -z "$root_passwd" ];then
     echo "$fail no password set"
     exit 1
  fi

# Check database
  if [ -z $db_name ];then
     echo "$fail no database set"
     exit 1
  fi

  # Only alphanumeric or an underscore characters
    db_name_tmp=${db_name//[^a-zA-Z0-9_]/}

  # Limit to 255 characters

    if [ $(echo "$db_name_tmp" | wc -m ) -gt 255 ];then
       echo "$fail db_name too big (255 chars max)"
       exit 1
    else
       db_name="$db_name_tmp"
    fi

  # Test if database exists
    mysql --login-path=local -e "USE $db_name;" 2>/dev/null
    if [ $? = 0 ];then
       echo "$fail database $db_name already exists"
       exit 1
    fi

# Check config file
  if [ -z $config_file ];then
     echo "$fail no config file set"
     exit 1
  fi

  # Check empty lines
    IFS_old="$IFS"
    IFS=$'\n'
    for line in $conf_file;do
        if [[ -n "$( echo $line | grep -qxF '')" ]] || [[ -n "$( echo $line | grep -Ex '[[:space:]]+' )" ]];then
           conf_file=$( echo "$conf_file" | sed '/^\s*$/d' )
        fi
    done
    IFS="$IFS_old"

# Check scripts
  status=0
  if [ $( ls $scripts_dir/mmega_create.sh ) ];then
     for script in "${scripts_list[@]}";do
          ls "$script" > /dev/null
          status=$?
     done
  fi

  if [ $status != 0 ];then
     echo "$fail no scripts found"
  fi

# Check completion files
  status=0
  if [ $( ls $completion_dir/mmega_create.sh ) ];then
     for completion_file in "${completion_list[@]}";do
          ls "$completion_file" > /dev/null
          status=$?
     done
  fi

  if [ $status != 0 ];then
     echo "$fail no completion files found"
  fi

# Lock file ####################################################################################

# Lock file
  lock_file=/tmp/$subject.lock
  if [ -f "$lock_file" ]; then echo; echo -e "$fail Script is already running" ; echo; exit 1; fi
  touch $lock_file

# Delete lock file at exit
  trap "rm -rf $lock_file" EXIT


# Functions ####################################################################################

# Commons functions ----------------------------------------------------------------------------
test(){
  if [ $? = 0 ];then
     printf "%-6s %-50s\n" "$ok" "$1"
  else
     printf "%-6s %-50s\n" "$fail" "$1"
  fi
}

describe_tbl(){
  mysql --login-path=local -e "USE $db_name; DESCRIBE $1 "
}

show_tbl(){
  mysql --login-path=local -e "USE $db_name; SELECT * FROM $1 "
}


# Create functions ------------------------------------------------------------------------------
# Create db and grant privileges
create_db(){
  mysql -uroot -p"$root_passwd" -e "CREATE DATABASE IF NOT EXISTS $1; \
                                    GRANT USAGE ON $1.* TO '$user'@'localhost' IDENTIFIED BY '$user_passwd'; \
                                    GRANT ALL PRIVILEGES ON $1.* TO '$user'@'localhost'; \
                                    GRANT EXECUTE ON FUNCTION sys.format_bytes TO '$user'@'localhost'; \
                                    FLUSH PRIVILEGES;" 2>/dev/null
  test "Creating database ${txtbld}$1${txtrst} granted to ${txtbld}$user${txtrst}"
}

# Create tables
create_tbl_config(){
  mysql --login-path=local -e "USE $db_name; CREATE TABLE config ( id INT(11) NOT NULL AUTO_INCREMENT, \
                                                                             name VARCHAR(255), \
                                                                             email VARCHAR(255), \
                                                                             passwd VARCHAR(255), \
                                                                             local_dir VARCHAR(255), \
                                                                             remote_dir VARCHAR(255), \
                                                                             created DATETIME, \
                                                                             PRIMARY KEY (id) );"
  test "${txtbld}Creating table config ${txtrst}"
}

create_tbl_disk_stats(){
  mysql --login-path=local -e "USE $db_name; CREATE TABLE disk_stats ( name VARCHAR(255), \
                                                                             total_bytes BIGINT, \
                                                                             free_bytes BIGINT, \
                                                                             used_bytes BIGINT, \
                                                                             total VARCHAR(255), \
                                                                             free VARCHAR(255), \
                                                                             used VARCHAR(255),
                                                                             last_update DATETIME );"
  test "${txtbld}Creating table disk_stats ${txtrst}"
}

create_tbl_file_stats(){
  mysql --login-path=local -e "USE $db_name; CREATE TABLE file_stats ( name VARCHAR(255), \
                                                                             local INT, \
                                                                             remote INT, \
                                                                             to_down INT, \
                                                                             to_up INT, \
                                                                             sync INT, \
                                                                             last_update DATETIME );"
  test "${txtbld}Creating table file_stats ${txtrst}"
}


create_tbl_global_stats(){
  mysql --login-path=local -e "USE $db_name; CREATE TABLE global_stats ( sum_acc INT, \
                                                               sum_total VARCHAR(255), \
                                                               sum_free VARCHAR(255), \
                                                               sum_used VARCHAR(255), \
                                                               sum_local INT, \
                                                               sum_remote INT, \
                                                               sum_to_down INT, \
                                                               sum_to_up INT, \
                                                               sum_sync INT, \
                                                               last_update DATETIME );"
  test "${txtbld}Creating table of global stats ${txtrst}"
}

create_tbls_of_files(){
  mysql --login-path=local -e "USE $db_name; CREATE TABLE remote_files_$1 ( link VARCHAR(255), \
                                                                            size_bytes BIGINT, \
                                                                            mod_date DATETIME, \
                                                                            path VARCHAR(255) ); \
                                             CREATE TABLE local_files_$1 ( size_bytes BIGINT, \
                                                                           mod_date DATETIME, \
                                                                           path VARCHAR(255) ); \
                                             CREATE TABLE remote_directories_$1 ( mod_date DATETIME, \
                                                                                  path VARCHAR(255) ); \
                                             CREATE TABLE local_directories_$1 ( mod_date DATETIME, \
                                                                                 path VARCHAR(255) );"
}

create_tbl_hashes(){
  mysql --login-path=local -e "USE $db_name; CREATE TABLE hashes (table_name VARCHAR(255), md5_hash CHAR(32), last_update DATETIME );"
  test "${txtbld}Creating table of hashes ${txtrst}"
}


# Insert functions -----------------------------------------------------------------------------------------
get_list_accounts() {
  list_accounts=$(mysql --login-path=local -sN -e "USE $db_name; SELECT name FROM config")

  if [ -z "$list_accounts" ];then
     printf "%-6s %-50s\n" "$fail no accounts found in table config using database $db_name"
     exit 1
  fi
}

# Insert config data to database
insert_config_data(){
mysql --login-path=local $db_name << EOF
LOAD DATA LOCAL INFILE "$config_file"
INTO TABLE $1
    FIELDS TERMINATED BY ','
           OPTIONALLY ENCLOSED BY '"'
    LINES  TERMINATED BY '\n' -- or \r\n
    (name, email, passwd, local_dir, remote_dir);
EOF
   test "Inserting ${txtbld}accounts config data ${txtrst}from file"
}

insert_created(){
  mysql --login-path=local -e "USE $db_name; UPDATE config SET created=NOW() WHERE name='$1';"
}

insert_disk_stats(){
  mysql --login-path=local -e "USE $db_name; INSERT INTO disk_stats (name, \
                                                                     total_bytes, \
                                                                     free_bytes, \
                                                                     used_bytes, \
                                                                     total, \
                                                                     free, \
                                                                     used, \
                                                                     last_update) \
                                             VALUES ('$1', 0, 0, 0, '0 bytes', '0 bytes', '0 bytes', NOW());"
}

insert_file_stats(){
  mysql --login-path=local -e "USE $db_name; INSERT INTO file_stats (name, local, remote, to_down, to_up, sync, last_update) \
                                             VALUES ('$1', 0, 0, 0, 0, 0, NOW());"
}


insert_global_stats(){
  mysql --login-path=local -e "USE $db_name; INSERT INTO global_stats (sum_acc, \
                                                                       sum_total, \
                                                                       sum_free, \
                                                                       sum_used, \
                                                                       sum_local, \
                                                                       sum_remote, \
                                                                       sum_to_down, \
                                                                       sum_to_up, \
                                                                       sum_sync, \
                                                                       last_update)
                                             VALUES ("$sum_acc", '0 bytes', '0 bytes', '0 bytes', 0, 0, 0, 0, 0, NOW());"
  test "Inserting default global stats"
}

insert_tbl_hashes(){
  mysql --login-path=local -e "USE $db_name; INSERT INTO hashes (table_name, md5_hash, last_update)
                                             VALUES ('local_files_$1', 'md5_hash', NOW());

                                             INSERT INTO hashes (table_name, md5_hash, last_update)
                                             VALUES ('remote_files_$1', 'md5_hash', NOW());

                                             INSERT INTO hashes (table_name, md5_hash, last_update)
                                             VALUES ('local_directories_$1', 'md5_hash', NOW());

                                             INSERT INTO hashes (table_name, md5_hash, last_update)
                                             VALUES ('remote_directories_$1', 'md5_hash', NOW());"
}

set_db_name_in_scripts(){
  echo "$wait Setting database $db_name in the scritps"

  for script in "${scripts_list[@]}";do
     sed -i 0,/db_name=.*/s//db_name=\"$db_name\"/ "$script"
  done

  echo -en "\033[1A\033[2K" # Delete previus line
  echo -e "$ok Set up db name $db_name"
  echo

  # Show changes
    for script in "${scripts_list[@]}";do
       name_script=$(echo "$script" | rev | cut -d / -f 1 | rev)
       grep_result=$(grep "db_name=" "$script" | head -n1 | tr -d ' ')
       printf "        %-20s %-20s\n" "$name_script" "$grep_result"
    done
    echo
}

set_db_in_completion(){
  echo "$wait Setting up autocompletion files"

  for completion_file in "${completion_list[@]}";do
     sed -i 0,/db_name=.*/s//db_name=\"$db_name\"/ "$completion_file"
  done

  echo -en "\033[1A\033[2K" # Delete previus line
  echo "$ok Set up autocompletion files [copy them to /etc/bash_completion.d]"
  echo
}


# Start #######################################################################################

# Title
echo "                                                       __      ";
echo "  __ _   __ _  ___  ___ _ ___ _  ____ ____ ___  ___ _ / /_ ___ ";
echo " /  ' \ /  ' \/ -_)/ _ \`// _ \`/ / __// __// -_)/ _ \`// __// -_)";
echo "/_/_/_//_/_/_/\__/ \_, / \_,_/  \__//_/   \__/ \_,_/ \__/ \__/ ";
echo "                  /___/                                        ";
echo

#  echo
#  echo "${txtbld}        #### Create database for mega accounts #### ${txtrst}"
#  echo

# Create database and tables (for tables of files and links see below)
  create_db "$db_name"
  echo

  create_tbl_config
  describe_tbl "config"
  echo

  create_tbl_disk_stats
  describe_tbl "disk_stats"
  echo

  create_tbl_file_stats
  describe_tbl "file_stats"
  echo

  create_tbl_global_stats
  describe_tbl "global_stats"
  echo

  create_tbl_hashes
  describe_tbl "hashes"
  echo

# Insert
  # Insert config data from file
    insert_config_data "config"

  # Get list of accounts
    get_list_accounts

  # Create tables of files for each account (no default values)
    test "Creating tables of files"
    for account in $list_accounts;do
        echo "       - $account"
        create_tbls_of_files "$account"
    done

  # Insert disk and files stats tables with default values
    test "Inserting default values"
    for account in $list_accounts;do
       echo "       - $account"
       insert_created "$account"
       insert_disk_stats "$account"
       insert_file_stats "$account"
       insert_tbl_hashes "$account"
    done

  # Insert global stats
    sum_acc=$(mysql --login-path=local -sN -e "USE $db_name; SELECT COUNT(config.name) FROM config;")
    insert_global_stats

# Show tables and default values
  echo
  echo "${txtbld} Table config ${txtrst}"
  # With hashed password
    mysql --login-path=local -e "USE $db_name; SELECT name,email,SHA1(passwd) AS hashed_passwd,local_dir,remote_dir FROM config;"

  echo
  echo "${txtbld} Table disk_stats ${txtrst}"
  show_tbl "disk_stats"

  echo
  echo "${txtbld} Table file_stats ${txtrst}"
  show_tbl "file_stats"

  echo
  echo "${txtbld} Table global_stats ${txtrst}"
  show_tbl "global_stats"

  echo
  echo "${txtbld} Table hashes ${txtrst}"
  show_tbl "hashes"
  echo

set_db_name_in_scripts
set_db_in_completion

echo
exit

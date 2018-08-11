#!/bin/bash

# Interact with database


# Variables #####################################################################################

# Subject and usage
  subject=mmega_query
  usage="
  USAGE = mmega_query.sh config|account|files|change|add|del|search|set_rc|set_db|summary [options by query]

            config  <account_name|all> [optional plaintext] [defautl all]
            account <account_name|all> [defautl all]
            files   <account_name> local|remote|sync|to_down|to_up|link
            change  <account_name> name|email|passwd|local_dir|remote_dir <new_parameter>
            add     <new_account_name|new_file_config>
            del     <account_name>
            search  <file_to_search>   [optional account, defautl all]
            set_rc  <account_name>
            set_db  <database_name>
            summary
        "

# Colors and symbols
  txtred=$(tput setaf 1)  # red
  txtgrn=$(tput setaf 2)  # green
  txtylw=$(tput setaf 3)  # yellow
  txtbld=$(tput bold)     # text bold
  txtrst=$(tput sgr0)     # text reset

  ok="[ ${txtgrn}OK${txtrst} ]"
  fail="[${txtred}FAIL${txtrst}]"
  wait="[ ${txtylw}--${txtrst} ]"

  yes_grn="${txtgrn}yes${txtrst}"
  no_red="${txtred}no${txtrst}"

# Database
  db_name=""

# Scripts dir
  scripts_dir="$PWD"

# Scritps (all except mmega_create_db.sh)
  declare -a scripts_list=( "$scripts_dir/mmega_update.sh" "$scripts_dir/mmega_sync.sh" "$scripts_dir/mmega_query.sh")


# Checks ########################################################################################

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
  if [ -z $db_name ];then
     echo "$fail no database set"
     exit 1
  fi

  # Test if database exists
    mysql --login-path=local -e "USE $db_name" 2>/dev/null
    if [ $? = 1 ];then
       echo "$fail database $db_name does not exists"
       exit 1
    fi

  # Test if update was run the first time
    test_global_sum=$(mysql -sN -e "USE $db_name; SELECT sum_total FROM global_stats;")
    if [ "$test_global_sum" == "0 bytes" ];then
       echo "$fail The database $db_name has never been updated. Make the first run with mmega_update.sh"
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


# Functions #####################################################################################

# Check command
test(){
  if [ $? = 0 ];then
     printf "%-6s %-50s\n" "$ok" "$1"
  else
     printf "%-6s %-50s\n" "$fail" "$1"
  fi
}

# Get query type
get_query_type(){
  case "$1" in
     files)
     query_type="files"
     echo "$ok Query type ${txtbld}$query_type ${txtrst}"
     ;;
     search)
     query_type="search"
     echo "$ok Query type ${txtbld}$query_type ${txtrst}"
     ;;
     set_rc)
     query_type="set_rc"
     echo "$ok Query type ${txtbld}$query_type ${txtrst}"
     ;;
     set_db)
     query_type="set_db"
     echo "$ok Query type ${txtbld}$query_type ${txtrst}"
     ;;
     account)
     query_type="account"
     echo "$ok Query type ${txtbld}$query_type ${txtrst}"
     ;;
     change)
     query_type="change"
     echo "$ok Query type ${txtbld}$query_type ${txtrst}"
     ;;
     config)
     query_type="config"
     echo "$ok Query type ${txtbld}$query_type ${txtrst}"
     ;;
     summary)
     query_type="summary"
     echo "$ok Query type ${txtbld}$query_type ${txtrst}"
     ;;
     add)
     query_type="add"
     echo "$ok Query type ${txtbld}add account ${txtrst}"
     ;;
     del)
     query_type="del"
     echo "$ok Query type ${txtbld}delete account ${txtrst}"
     ;;
     *)
     echo "$fail Unknown query type"
     echo "$usage"
     exit 1
     ;;
  esac
}

get_input_account(){
 # Get list accounts
   list_accounts_raw=$(mysql --login-path=local -sN -e "USE $db_name; SELECT name FROM config;")

   declare -a list_accounts=()
   for line in $list_accounts_raw;do
      list_accounts+=("$line")
   done

   if [ -z "$1" ] && [ "$query_type" == "files" ] ;then
      echo "$fail No account name"
      echo "$usage"
      exit 1
   fi

   if [ -z "$1" ] && [ "$query_type" == "change" ];then
      echo "$fail No account name"
      echo "$usage"
      exit 1
   fi

   if [ -z "$1" ] && [ "$query_type" == "search" ] || [ "$1" == "all" ];then
      input_account="all"
   fi

   if [ -z "$1" ] && [ "$query_type" == "account" ] || [ "$1" == "all" ];then
      input_account="all"
   fi

   if [ -z "$1" ] && [ "$query_type" == "config" ] || [ "$1" == "all" ];then
      input_account="all"
   fi

   if [ -n "$1" ] && [ "$input_account" != "all" ];then
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

# Functions only used by FILES QUERY
get_input_file_type(){
  if [ -z $input_file_type ];then
     echo "$fail No file type"
     echo "$usage "
     exit 1
  fi

  if [ "$input_file_type" == "local" ] || [ "$input_file_type" == "remote" ] || [ "$input_file_type" == "sync" ] || \
     [ "$input_file_type" == "to_down" ] || [ "$input_file_type" == "to_up" ] || [ "$input_file_type" == "link" ];then
     input_file_type="$input_file_type"
     type_found="yes"
  else
     echo "$fail Only local|remote|sync|to_down|to_up|link type are accepted"
     echo "$usage"
     exit 1
  fi
}


show_file_type(){
  if [ "$input_file_type" == "local" ];then
     echo
     echo "${txtbld} Local files of $input_account ${txtrst}"
     mysql --login-path=local -te "USE $db_name; SELECT path AS local_files_$input_account, \
                                                       lpad(size,11,' ') AS size, \
                                                       DATE_FORMAT(mod_date, '%d-%m-%y') AS mod_date \
                                                  FROM local_files_$input_account;"

     sum=$( mysql --login-path=local -sN -e "USE $db_name; SELECT local FROM file_stats WHERE name = '$input_account';")
     total_size_local=$( mysql --login-path=local -sN -e "USE $db_name; SELECT sys.format_bytes(SUM(size_bytes)) AS total_size_local FROM local_files_$input_account;")
     echo " $sum local files in $input_account [size $total_size_local]"
  fi

  if [ "$input_file_type" == "remote" ];then
     echo
     echo "${txtbld} Remote files of $input_account ${txtrst}"
     mysql --login-path=local -te "USE $db_name; SELECT path AS remote_files_$input_account, \
                                                       lpad(size,11,' ') AS size, \
                                                       DATE_FORMAT(mod_date, '%d-%m-%y') AS mod_date \
                                                  FROM remote_files_$input_account;"

     sum=$( mysql --login-path=local -sN -e "USE $db_name; SELECT remote FROM file_stats WHERE name = '$input_account';")
     total_size_remote=$( mysql --login-path=local -sN -e "USE $db_name; SELECT sys.format_bytes(SUM(size_bytes)) AS total_size_remote FROM remote_files_$input_account;")
     echo " $sum remote files in $input_account [size $total_size_remote]"
  fi


  if [ "$input_file_type" == "link" ];then
     echo
     echo "${txtbld} Links of $input_account ${txtrst}"
     mysql --login-path=local -te "USE $db_name; SELECT filename, \
                                                       link, \
                                                       lpad(size,11,' ') AS size \
                                                  FROM remote_files_$input_account;"

     sum=$( mysql --login-path=local -sN -e "USE $db_name; SELECT COUNT(remote_files_$input_account.link) FROM remote_files_$input_account;")
     echo " $sum links in $input_account"
  fi



  # Show sync files
    if [ "$input_file_type" == "sync" ];then
       echo
       echo "${txtbld} Syncronized files of $input_account ${txtrst}"
       mysql --login-path=local -te "USE $db_name; SELECT path AS sync_files_of_$input_account, \
                                                         lpad(size,11,' ') AS size, \
                                                         DATE_FORMAT(mod_date, '%d-%m-%y %H:%i') AS local_mod_date \
                                                    FROM local_files_$input_account \
                                            WHERE EXISTS (SELECT filename \
                                                            FROM remote_files_$input_account \
                                                           WHERE local_files_$input_account.filename=remote_files_$input_account.filename);"

       remote_sum=$( mysql --login-path=local -sN -e "USE $db_name; SELECT remote FROM file_stats WHERE name = '$input_account';")
       local_sum=$( mysql --login-path=local -sN -e "USE $db_name; SELECT local FROM file_stats WHERE name = '$input_account';")
       sync_sum=$( mysql --login-path=local -sN -e "USE $db_name; SELECT sync FROM file_stats WHERE name = '$input_account';")
       total_size_sync=$( mysql --login-path=local -sN -e "USE $db_name; SELECT sys.format_bytes(SUM(size_bytes)) AS total_size_sync \
                                                                           FROM local_files_$input_account \
                                                                   WHERE EXISTS (SELECT filename \
                                                                                   FROM remote_files_$input_account \
                                                                                  WHERE local_files_$input_account.filename=remote_files_$input_account.filename);" )
       echo " $sync_sum syncronized files in $input_account [$local_sum local $remote_sum remote] [size $total_size_sync]"
   fi

   if [ "$input_file_type" == "to_down" ];then
      echo
      echo "${txtbld} Files to download from $input_account ${txtrst}"
      mysql --login-path=local -te "USE $db_name; SELECT path AS files_to_download_from_$input_account, \
                                                        lpad(size,11,' ') AS size, \
                                                        DATE_FORMAT(mod_date, '%d-%m-%y %H:%i') AS mod_date \
                                                   FROM remote_files_$input_account \
                                       WHERE NOT EXISTS (SELECT filename \
                                                           FROM local_files_$input_account \
                                                          WHERE remote_files_$input_account.filename=local_files_$input_account.filename);"

      remote_sum=$( mysql --login-path=local -sN -e "USE $db_name; SELECT remote FROM file_stats WHERE name = '$input_account';")
      local_sum=$( mysql --login-path=local -sN -e "USE $db_name; SELECT local FROM file_stats WHERE name = '$input_account';")
      sum_to_down=$( mysql --login-path=local -sN -e "USE $db_name; SELECT to_down FROM file_stats WHERE name = '$input_account';")
      total_size_to_down=$( mysql --login-path=local -sN -e "USE $db_name; SELECT sys.format_bytes(SUM(size_bytes)) AS total_size_to_down \
                                                                             FROM remote_files_$input_account \
                                                                 WHERE NOT EXISTS (SELECT filename \
                                                                                     FROM local_files_$input_account \
                                                                                    WHERE remote_files_$input_account.filename=local_files_$input_account.filename);" )
      echo " $sum_to_down files to download from $input_account [$local_sum local $remote_sum remote] [size $total_size_to_down]"
   fi

   if [ "$input_file_type" == "to_up" ];then
      echo
      echo "${txtbld} Files to upload to $input_account ${txtrst}"
      mysql --login-path=local -te "USE $db_name; SELECT path AS files_to_upload_to_$input_account, \
                                                        lpad(size,11,' ') AS size, \
                                                        DATE_FORMAT(mod_date, '%d-%m-%y %H:%i') AS mod_date \
                                                   FROM local_files_$input_account \
                                       WHERE NOT EXISTS (SELECT filename \
                                                           FROM remote_files_$input_account \
                                                          WHERE local_files_$input_account.filename=remote_files_$input_account.filename);"

      remote_sum=$( mysql --login-path=local -sN -e "USE $db_name; SELECT remote FROM file_stats WHERE name = '$input_account';")
      local_sum=$( mysql --login-path=local -sN -e "USE $db_name; SELECT local FROM file_stats WHERE name = '$input_account';")
      sum_to_up=$( mysql --login-path=local -sN -e "USE $db_name; SELECT to_up FROM file_stats WHERE name = '$input_account';")
      total_size_to_up=$( mysql --login-path=local -sN -e "USE $db_name; SELECT sys.format_bytes(SUM(size_bytes)) AS total_size_to_up \
                                                                           FROM local_files_$input_account \
                                                               WHERE NOT EXISTS (SELECT filename \
                                                                                   FROM remote_files_$input_account \
                                                                                  WHERE local_files_$input_account.filename=remote_files_$input_account.filename);" )
      echo " $sum_to_up files to upload to $input_account [$local_sum local $remote_sum remote] [size $total_size_to_up]"
   fi
}

# Functions used only by SEARCH QUERY
get_input_search_file(){
   if [ -z "$file_to_search" ];then
      read -r -p "$wait Enter file to search: " file_to_search_raw
   else
      echo "$wait Processing file to search"
      file_to_search_raw="$file_to_search"
   fi

  # Delete ';'
    file_to_search_tmp=$( echo "$file_to_search_raw" | tr -d ';')

  # Limit to 255 characters
    num_char=$(echo "$file_to_search_raw" | wc -m )

    if [ $num_char -gt 255 ];then
       echo "$fail input too big (255 chars max)"
       exit 1
    else
       file_to_search="$file_to_search_tmp"

       echo -en "\033[1A\033[2K" # Delete previus line
       echo "$ok Searching: $file_to_search"

    fi
}

get_acc_data(){
  email=$(mysql --login-path=local -Ns -e "USE $db_name; SELECT email FROM config WHERE name = '$1'")
  local_dir=$(mysql --login-path=local -Ns -e "USE $db_name; SELECT local_dir FROM config WHERE name = '$1'" )
  remote_dir=$(mysql --login-path=local -Ns -e "USE $db_name; SELECT remote_dir FROM config WHERE name = '$1'")
}

test_match(){
# Reset test variables
  test_match=""
  local_match=""
  remote_match=""

# Search $file_to_search
  local_match=$(mysql --login-path=local -sN -e "USE $db_name; SELECT filename FROM local_files_$1 WHERE filename LIKE '%$file_to_search%'")
  local_match_num=$(mysql --login-path=local -sN -e "USE $db_name; SELECT filename FROM local_files_$1 WHERE filename LIKE '%$file_to_search%'" | wc -l)

  remote_match=$(mysql --login-path=local -sN -e "USE $db_name; SELECT filename FROM remote_files_$1 WHERE filename LIKE '%$file_to_search%'")
  remote_match_num=$(mysql --login-path=local -sN -e "USE $db_name; SELECT filename FROM remote_files_$1 WHERE filename LIKE '%$file_to_search%'" | wc -l)

# Results
  total_match=$(( $local_match_num + $remote_match_num ))

  if [ -n "$local_match" ] || [ -n "$remote_match" ] ;then
     test_match="yes"
  fi

  if [ -n "$local_match" ];then
     local_match="yes"
  fi

  if [ -n "$remote_match" ];then
     remote_match="yes"
  fi
}

show_match(){
  touch $tmp_dir/match_$1

  # grep color
  if [ "$local_match_num" = 1 ] && [ "$remote_match_num" = 1 ];then
     export GREP_COLORS='ms=01;32'
  else
     export GREP_COLORS='ms=01;33'
  fi

  if [ "$local_match" == "yes" ];then
     echo "   [local $yes_grn] -> $local_dir" >> $tmp_dir/match_$1
  else
     echo "   [local $no_red]" >> $tmp_dir/match_$1
  fi

  if [ "$remote_match" == "yes" ];then
     echo "   [remote $yes_grn] -> $remote_dir" >> $tmp_dir/match_$1
  else
     echo "   [remote $no_red]" >> $tmp_dir/match_$1
  fi

  if [ "$local_match" == "yes" ] && [ "$remote_match" == "yes" ];then
     echo "   [synchronized $yes_grn]" >> $tmp_dir/match_$1
  else
     echo "   [synchronized $no_red]" >> $tmp_dir/match_$1
  fi

  if [ "$local_match" == "yes" ];then
     mysql --login-path=local -t -e "USE $db_name; SELECT path AS local_files_$1_match, \
                                                          lpad(size, 11, ' ') AS size \
                                                     FROM local_files_$1 \
                                                    WHERE filename LIKE '%$file_to_search%'" >> $tmp_dir/match_$1
  fi

  if [ "$remote_match" == "yes" ];then
     mysql --login-path=local -t -e "USE $db_name; SELECT path AS remote_files_$1_match, \
                                                          lpad(size, 11, ' ') AS size, \
                                                          link \
                                                     FROM remote_files_$1 \
                                                    WHERE filename LIKE '%$file_to_search%'" >> $tmp_dir/match_$1
  fi

  if [ "$local_match_num" = 1 ] && [ "$remote_match_num" = 1 ];then
     echo " [full match ${txtgrn}$total_match${txtrst}] [local ${txtgrn}$local_match_num${txtrst}] [remote ${txtgrn}$remote_match_num${txtrst}]" \
          >> $tmp_dir/match_$1
  elif [ "$total_match" -lt 2 ];then
     echo " [partial match ${txtylw}$total_match${txtrst}] [local ${txtylw}$local_match_num${txtrst}] [remote ${txtylw}$remote_match_num${txtrst}]" \
          >> $tmp_dir/match_$1
  else
     echo " [multi match ${txtylw}$total_match${txtrst}] [local ${txtylw}$local_match_num${txtrst}] [remote ${txtylw}$remote_match_num${txtrst}]" \
         >> $tmp_dir/match_$1
  fi
}

# Functions used only by SET_RC QUERY
makefile_megarc(){
  # Get credentials
    email=$(mysql --login-path=local -sN -e "USE $db_name; SELECT email FROM config WHERE name = '$input_account'")
    passwd=$(mysql --login-path=local -sN -e "USE $db_name; SELECT passwd FROM config WHERE name = '$input_account'")

    if [ -z "$email" ] || [ -z "$passwd" ];then
       printf "%-6s %-50s\n" "$fail Error getting credentials for account $input_account [Using database $db_name ]"
       exit 1
    fi

  # Conctruct megarc file (the original one will be delete)
    echo "[Login]" > ~/.megarc
    echo "Username = $email" >> ~/.megarc
    echo "Password = $passwd" >> ~/.megarc
}


# Functions used only by SET_DB QUERY
get_input_new_db_name(){
   if [ -z $1 ];then
      read -r -p "Enter name for database: " new_db_name_raw
   else
      new_db_name_raw="$1"
   fi

  # Only alphanumeric or an underscore characters
    new_db_name_tmp=${new_db_name_raw//[^a-zA-Z0-9_]/}

  # Limit to 255 characters
    num_char=$(echo "$new_db_name_tmp" | wc -m )

    if [ $num_char -gt 255 ];then
       echo "$fail input too big (255 chars max)"
       exit 1
    else
       new_db_name="$new_db_name_tmp"
    fi
}

# Functions used only by ACCOUNT QUERY
show_status_all(){
  mysql --login-path=local -e "USE $db_name; SELECT name AS disk_stats, \
                                                    lpad(total,11,' ') AS total, \
                                                    lpad(free,11,' ') AS free, \
                                                    lpad(used,11,' ') AS used, \
                                                    lpad(CONCAT(TRUNCATE((disk_stats.free_bytes/disk_stats.total_bytes) * 100 ,1), ' %'), 6, ' ') AS '% free', \
                                                    DATE_FORMAT(last_update,'%d-%m-%y %H:%i') AS last_update \
                                               FROM disk_stats;"

  mysql --login-path=local -e "USE $db_name; SELECT name AS file_stats, \
                                                    local, \
                                                    remote, \
                                                    to_down, \
                                                    to_up, \
                                                    sync, \
                                                    (SELECT IF(file_stats.to_up=0 AND file_stats.to_down=0, 'yes', 'no')) AS synced, \
                                                    DATE_FORMAT(last_update,'%d-%m-%y %H:%i') AS last_update \
                                               FROM file_stats;"

  mysql --login-path=local -e "USE $db_name; SELECT sum_acc AS accounts, \
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
}

show_status_one(){
  mysql --login-path=local -e "USE $db_name; SELECT name AS disk_stats, \
                                                    lpad(total,11,' ') AS total, \
                                                    lpad(free,11,' ') AS free, \
                                                    lpad(used,11,' ') AS used, \
                                                    lpad(CONCAT(TRUNCATE((disk_stats.free_bytes/disk_stats.total_bytes) * 100 ,1), ' %'), 6, ' ') AS '% free', \
                                                    DATE_FORMAT(last_update,'%d-%m-%y %H:%i') AS last_update \
                                               FROM disk_stats \
                                              WHERE name = '$1';"

  mysql --login-path=local -e "USE $db_name; SELECT name as file_stats, \
                                                    local, \
                                                    remote, \
                                                    to_down, \
                                                    to_up, \
                                                    sync, \
                                                    (SELECT IF(file_stats.to_up=0 AND file_stats.to_down=0, 'yes', 'no')) AS synced, \
                                                    DATE_FORMAT(last_update,'%d-%m-%y %H:%i') AS last_update \
                                               FROM file_stats \
                                              WHERE name = '$1';"
}


# Functions used by SUMMARY QUERY
show_global_status(){
  mysql --login-path=local -e "USE $db_name; SELECT sum_acc AS accounts, \
                                                    lpad(sum_total,11,' ') AS total, \
                                                    lpad(sum_free,11,' ') AS free, \
                                                    lpad(sum_used,11,' ') AS used, \
                                                    sum_local AS local, \
                                                    sum_remote AS remote, \
                                                    sum_to_down AS to_down, \
                                                    sum_to_up AS to_up, \
                                                    DATE_FORMAT(last_update,'%d-%m-%y %H:%i') AS last_update \
                                               FROM global_stats;"
}

show_summary(){
  mysql --login-path=local -e "USE $db_name; SELECT config.name, \
                                                    config.email, \
                                                    lpad(disk_stats.free, 11 ,' ') AS free, \
                                                    lpad(CONCAT(TRUNCATE((disk_stats.free_bytes/disk_stats.total_bytes) * 100 ,1), ' %'), 6, ' ') AS '% free', \
                                                    file_stats.local, \
                                                    file_stats.remote, \
                                                    (SELECT IF(file_stats.to_up=0 AND file_stats.to_down=0, 'yes', 'no')) AS synced, \
                                                    DATE_FORMAT(file_stats.last_update, '%d-%m-%y %H:%i') AS last_update
                                               FROM config, disk_stats, file_stats \
                                              WHERE config.name = disk_stats.name \
                                                AND config.name = file_stats.name;"

}

# Functions used by CHANGE QUERY
get_config_change(){

  if [ -n "$1" ] && [ "$1" == "name" ] || [ "$1" == "email" ] || [ "$1" == "passwd" ] || \
     [ "$1" == "local_dir" ] || [ "$1" == "remote_dir" ];then
     type_change="$1"
  else
    echo "$fail Only name, email, passwd, local_dir and remote_dir can be changed"
    echo "$usage"
    exit 1
  fi

}

make_changes(){
  # show current config
    echo
    echo "${txtbld} Current config ${txtrst}"
    mysql --login-path=local -e "USE $db_name; SELECT name, email, SHA1(passwd) AS hashed_passwd, local_dir, remote_dir \
                                                 FROM config \
                                                WHERE name = '$input_account';"

  # update config
    echo
    echo "$wait Changing config"
    mysql --login-path=local -e "USE $db_name; UPDATE config SET $set_parm='$new_parameter' WHERE name = '$input_account';"

    if [ "$set_parm" == "name" ];then # Change name in all others tables
       new_name="$new_parameter"

       mysql --login-path=local -e "USE $db_name; UPDATE disk_stats SET name='$new_name' WHERE name = '$input_account';"
       mysql --login-path=local -e "USE $db_name; UPDATE file_stats SET name='$new_name' WHERE name = '$input_account';"

       mysql --login-path=local -e "USE $db_name; UPDATE hashes SET table_name='local_files_$new_name' \
                                                              WHERE table_name = 'local_files_$input_account';"
       mysql --login-path=local -e "USE $db_name; UPDATE hashes SET table_name='remote_files_$new_name' \
                                                              WHERE table_name = 'remote_files_$input_account';"
       mysql --login-path=local -e "USE $db_name; UPDATE hashes SET table_name='local_directories_$new_name' \
                                                              WHERE table_name = 'local_directories_$input_account';"
       mysql --login-path=local -e "USE $db_name; UPDATE hashes SET table_name='remote_directories_$new_name' \
                                                              WHERE table_name = 'remote_directories_$input_account';"

       mysql --login-path=local -e "USE $db_name; RENAME TABLE local_files_$input_account TO local_files_$new_name;"
       mysql --login-path=local -e "USE $db_name; RENAME TABLE remote_files_$input_account TO remote_files_$new_name;"
       mysql --login-path=local -e "USE $db_name; RENAME TABLE local_directories_$input_account TO local_directories_$new_name;"
       mysql --login-path=local -e "USE $db_name; RENAME TABLE remote_directories_$input_account TO remote_directories_$new_name;"

    fi

    echo -en "\033[1A\033[2K" # Delete previus line
    echo "$ok Changed config"

  # show new config
    if [ "$set_parm" == "name" ];then
       input_account="$new_parameter"
    fi
    echo
    echo "${txtbld} New config ${txtrst}"
    mysql --login-path=local -e "USE $db_name; SELECT name, email, SHA1(passwd) AS hashed_passwd, local_dir,remote_dir \
                                                 FROM config \
                                                WHERE name = '$input_account';"
    echo
}

# Functions used by ADD QUERY
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


add_account(){
  echo "S1 $1"
  echo "S2 $2"
  echo "S3 $3"

  # Check config file
  if [ -z $2 ];then
     echo "$fail You have to provide a config file or an account name"
     exit 1
  fi

  if [ -f $2 ];then
     config_file=$2
     echo "$ok Adding accounts from config file $config_file"

     # Check empty lines
     IFS_old="$IFS"
     IFS=$'\n'
     for line in $conf_file;do
        if [[ -n "$( echo $line | grep -qxF '')" ]] || [[ -n "$( echo $line | grep -Ex '[[:space:]]+' )" ]];then
           conf_file=$( echo "$conf_file" | sed '/^\s*$/d' )
        fi
     done
     IFS="$IFS_old"
  else
     # Read args
       name="$2"
       echo "$ok Adding account $name from command line"

       if [ -n "$3" ];then
          email="$3"
          echo "$ok email $email"
       fi

       if [ -n "$4" ];then
          passwd="$4"
          echo "$ok passwd $passwd"
       fi

       if [ -n "$5" ];then
          local_dir="$5"
          echo "$ok local dir $local_dir"
       fi

       if [ -n "$6" ];then
          remote_dir="$6"
          echo "$ok remote dir $remote_dir"
       fi
   fi


   if [[ -n "$name" ]];then
      new_account="$name"
      test "Creating new account $new_account"
      mysql --login-path=local -e "USE $db_name; INSERT INTO config (name, email, passwd, local_dir, remote_dir, created) \
                                                       VALUES ('$new_account', '$email', '$passwd', '$local_dir', '$remote_dir', NOW());"
      create_tbls_of_files "$new_account"
      insert_disk_stats "$new_account"
      insert_file_stats "$new_account"
      insert_tbl_hashes "$new_account"

      # Show new account with hashed password
      echo
      echo "${txtbld} Table config ${txtrst}"
      mysql --login-path=local -e "USE $db_name; SELECT name,email,SHA1(passwd) AS hashed_passwd,local_dir,remote_dir FROM config WHERE name = '$new_account';"
   else
      # config file (one or several accounts)
      mysql --login-path=local -sN -e "USE $db_name; SELECT name FROM config;" | sort > $tmp_dir/old_accs
      test "Inserting new config data from file"
      insert_config_data "config"
      mysql --login-path=local -sN -e "USE $db_name; SELECT name FROM config;" | sort > $tmp_dir/all_accs
      new_accounts=$(comm -23 $tmp_dir/all_accs $tmp_dir/old_accs | sort)

      for new_account in $new_accounts;do
         insert_created "$new_account"
         create_tbls_of_files "$new_account"
         insert_disk_stats "$new_account"
         insert_file_stats "$new_account"
         insert_tbl_hashes "$new_account"

         # Show new account with hashed password
         echo "${txtbld} New account $new_account added ${txtrst}"
         mysql --login-path=local -e "USE $db_name; SELECT name,email,SHA1(passwd) AS hashed_passwd,local_dir,remote_dir FROM config WHERE name = '$new_account';"
         echo
      done
   fi
}


# Functions used by DEL QUERY
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

delete_account(){
   if [ -z "$1" ];then
      echo "$fail You have to provide account name to delete"
      echo "$usage"
      exit 1
   fi

  # Delete rows from config, disk stats and file stats
  test "Deleting rows from config, disk stats and file stats"
  mysql --login-path=local -e "USE $db_name; DELETE FROM config WHERE name =  '$input_account'; \
                                             DELETE FROM disk_stats WHERE name = '$input_account'; \
                                             DELETE FROM file_stats WHERE name = '$input_account';"

  # Delete tables of hashes
  test "Deleting tables of hashes"
  mysql --login-path=local -e "USE $db_name; DELETE FROM hashes WHERE table_name = 'local_files_$input_account'; \
                                             DELETE FROM hashes WHERE table_name = 'remote_files_$input_account'; \
                                             DELETE FROM hashes WHERE table_name = 'local_directories_$input_account'; \
                                             DELETE FROM hashes WHERE table_name = 'remote_directories_$input_account';"

  # Delete tables of files
  test "Deleting tables of files"
  mysql --login-path=local -e "USE $db_name; DROP table local_files_$input_account; \
                                             DROP table remote_files_$input_account; \
                                             DROP table local_directories_$input_account; \
                                             DROP table remote_directories_$input_account;"
  test "Updating global stats"
  update_global_stats
}


# Start #######################################################################################
echo "  __ _   __ _  ___  ___ _ ___ _  ___ _ __ __ ___  ____ __ __";
echo " /  ' \ /  ' \/ -_)/ _ \`// _ \`/ / _ \`// // // -_)/ __// // /";
echo "/_/_/_//_/_/_/\__/ \_, / \_,_/  \_, / \_,_/ \__//_/   \_, / ";
echo "                  /___/          /_/                 /___/  ";
echo

# Get query type
get_query_type "$1"


# FILE QUERY
if [ "$query_type" == "files" ];then
   input_account="$2"
   get_input_account "$input_account"

   input_file_type="$3"
   get_input_file_type "$input_file_type"
   show_file_type "$input_file_type"

   echo
   exit
fi


# SEARCH QUERY
if [ "$query_type" == "search" ];then

   # Get input file and account
     file_to_search="$2"
     get_input_search_file "$file_to_search"

     input_account="$3"
     get_input_account "$input_account"

   # Create grep input to hihglight match
     grep_input=$(echo "$file_to_search")

   # Search
     if [ "$input_account" == "all" ];then
        list_accounts_to_search="$list_accounts_raw"
     else
        list_accounts_to_search=$(echo "$list_accounts_raw" | grep "$input_account")
     fi

     for account_s in $list_accounts_to_search; do
         test_match "$account_s"

         if [ "$test_match" == "yes" ];then
            echo
            get_acc_data "$account_s"
            echo "${txtbld} match found in ${txtgrn}$account_s ${txtrst}[$email]"
            show_match "$account_s"
            cat $tmp_dir/match_$account_s | grep -E --color --ignore-case  "$grep_input|$"
            match="done"
         fi
     done

     if [ "$match" != "done" ];then
        echo "$fail File not found in $input_account [use quotation marks \"file to search\"]"
     fi

     echo
     exit
fi


# SET_RC QUERY
if [ "$query_type" == "set_rc" ];then
   input_account="$2"
   get_input_account "$input_account"
   makefile_megarc "$input_account"

   echo "$ok megarc set to $input_account [$email]"
   echo
fi


# SET_DB QUERY
if [ "$query_type" == "set_db" ];then
   get_input_new_db_name "$2"

   echo "$ok Setting up new database name for scripts [$new_db_name]"

   # Test if database exists
     mysql --login-path=local -e "USE $new_db_name" 2>/dev/null
     if [ $? = 1 ];then
        echo "$fail database $new_db_name does not exists"
        exit 1
     fi
     echo

  # Show old state
    echo "       Old"

    for script in "${scripts_list[@]}";do
        name_script=$(echo "$script" | rev | cut -d / -f 1 | rev)
        grep_result=$(grep "db_name=" "$script" | head -n1 | tr -d ' ')
        printf "         %-20s %-20s\n" "$name_script" "$grep_result"
    done
    echo

  # Set up new name
    echo "$wait Setting up new name $new_db_name"
    for script in "${scripts_list[@]}";do
        sed -i 0,/db_name=.*/s//db_name=\"$new_db_name\"/ "$script"
    done
    echo -en "\033[1A\033[2K" # Delete previus line
    echo "$ok Set up new name $new_db_name"
    echo

  # Show new state
    echo "       New"

    for script in "${scripts_list[@]}";do
        name_script=$(echo "$script" | rev | cut -d / -f 1 | rev)
        grep_result=$(grep "db_name=" "$script" | head -n1 | tr -d ' ')
        printf "         %-20s %-20s\n" "$name_script" "$grep_result"
    done

    echo
    exit
fi

# ACCOUNT QUERY
if [ "$query_type" == "account" ];then
   input_account="$2"
   get_input_account "$input_account"

   if [ "$input_account" == "all" ];then
      echo
      echo "${txtbld} Summary status all accounts ${txtrst}"
      show_status_all
      echo
   else
     echo
     echo "${txtbld} Summary status of $input_account ${txtrst}"
     show_status_one "$input_account"
   fi

fi

# CHANGE QUERY
if [ "$query_type" == "change" ];then
   input_account="$2"
   get_input_account "$input_account"

   type_change="$3"
   get_config_change "$type_change"

   new_parameter="$4"

   if [ -z "$new_parameter" ];then
      echo "$fail You must provide a new $type_change parameter"
      echo "$usage"
      exit 1
   fi

   if [ "$type_change" == "name" ];then
      set_parm='name'
      make_changes
   fi

   if [ "$type_change" == "email" ];then
      set_parm='email'
      make_changes
   fi

   if [ "$type_change" == "passwd" ];then
      set_parm='passwd'
      make_changes
   fi

   if [ "$type_change" == "local_dir" ];then
      set_parm='local_dir'
      make_changes
   fi

   if [ "$type_change" == "remote_dir" ];then
      set_parm='remote_dir'
      make_changes
   fi
fi

# SUMMARY QUERY
if [ "$query_type" == "summary" ];then
   echo
   echo "${txtbld} Summary ${txtrst}"
   show_summary
   echo
   echo "${txtbld} Global status ${txtrst}"
   show_global_status
   echo
fi

# CONFIG QUERY
if [ "$query_type" == "config" ];then
   input_account="$2"
   get_input_account "$input_account"

   clear="$3"
   if [ "$clear" == "plaintext" ];then
      if [ "$input_account" == "all" ];then
         echo
         echo "${txtbld} Config all accounts ${txtrst}"
         mysql --login-path=local -e "USE $db_name; SELECT name,email, passwd, local_dir, remote_dir FROM config;"
         echo
      else
         echo
         echo "${txtbld} Config of $input_account ${txtrst}"
         mysql --login-path=local -e "USE $db_name; SELECT name, email, passwd, local_dir, remote_dir FROM config WHERE name = '$input_account';"
         echo
      fi

   else
      if [ "$input_account" == "all" ];then
         echo
         echo "${txtbld} Config all accounts ${txtrst}"
         mysql --login-path=local -e "USE $db_name; SELECT name,email,SHA1(passwd) AS hashed_passwd,local_dir,remote_dir FROM config;"
         echo
      else
         echo
         echo "${txtbld} Config of $input_account ${txtrst}"
         mysql --login-path=local -e "USE $db_name; SELECT name,email,SHA1(passwd) AS hashed_passwd,local_dir,remote_dir FROM config WHERE name = '$input_account';"
         echo
      fi
   fi
fi


# ADD QUERY
if [ "$query_type" == "add" ];then
  # Check config file
  if [ -z $2 ];then
     echo "$fail You have to provide a config file or an account name"
     exit 1
  fi

  if [ -f $2 ];then
     config_file=$2
     echo "$ok Adding accounts from config file $config_file"

     # Check empty lines
     IFS_old="$IFS"
     IFS=$'\n'
     for line in $conf_file;do
        if [[ -n "$( echo $line | grep -qxF '')" ]] || [[ -n "$( echo $line | grep -Ex '[[:space:]]+' )" ]];then
           conf_file=$( echo "$conf_file" | sed '/^\s*$/d' )
        fi
     done
     IFS="$IFS_old"
  else
     # Read args
       name="$2"
       echo "$ok Adding account $name from command line"

       if [ -n "$3" ];then
          email="$3"
       fi

       if [ -n "$4" ];then
          passwd="$4"
       fi

       if [ -n "$5" ];then
          local_dir="$5"
       fi

       if [ -n "$6" ];then
          remote_dir="$6"
       fi
   fi

   if [[ -n "$name" ]];then
      new_account="$name"
      test "Creating new account $new_account"
      mysql --login-path=local -e "USE $db_name; INSERT INTO config (name, email, passwd, local_dir, remote_dir, created) \
                                                       VALUES ('$new_account', '$email', '$passwd', '$local_dir', '$remote_dir', NOW());"
      create_tbls_of_files "$new_account"
      insert_disk_stats "$new_account"
      insert_file_stats "$new_account"
      insert_tbl_hashes "$new_account"

      # Show new account with hashed password
      echo
      echo "${txtbld} Table config ${txtrst}"
      mysql --login-path=local -e "USE $db_name; SELECT name,email,SHA1(passwd) AS hashed_passwd,local_dir,remote_dir FROM config WHERE name = '$new_account';"
   else
      # config file (one or several accounts)
      mysql --login-path=local -sN -e "USE $db_name; SELECT name FROM config;" | sort > $tmp_dir/old_accs
      test "Inserting new config data from file"
      insert_config_data "config"
      mysql --login-path=local -sN -e "USE $db_name; SELECT name FROM config;" | sort > $tmp_dir/all_accs
      new_accounts=$(comm -23 $tmp_dir/all_accs $tmp_dir/old_accs | sort)
      echo

      for new_account in $new_accounts;do
         insert_created "$new_account"
         create_tbls_of_files "$new_account"
         insert_disk_stats "$new_account"
         insert_file_stats "$new_account"
         insert_tbl_hashes "$new_account"

         # Show new account with hashed password
         echo "${txtbld} New account $new_account added ${txtrst}"
         mysql --login-path=local -e "USE $db_name; SELECT name,email,SHA1(passwd) AS hashed_passwd,local_dir,remote_dir FROM config WHERE name = '$new_account';"
         echo
      done
   fi

  test "Updating global stats"
  update_global_stats

fi

# DELETE QUERY
if [ "$query_type" == "del" ];then
   input_account="$2"
   get_input_account "$input_account"
   delete_account "$input_account"
fi

exit

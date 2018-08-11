#!/bin/bash

# Download, upload or synchronize files
# up    = upload all diferent files from local to remote
# down  = download all diferent files from remote to local
# sync  - with_local  = upload all differents files and delete all remote differents files
#       - with_remote = download all differents files and delete all local different files

# Variables #####################################################################################

# Subject and usage
  subject=mmega_sync
  usage="USAGE = mmega_sync.sh <account_name|all> up|down|sync [with_local|with_remote]
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

# Binaries
  MEGACOPY=$(which megacopy)
  MEGARM=$(which megarm)
  MEGADF=$(which megadf)
  MEGALS=$(which megals)

# Scripts
  #@FIX this does not work
  MMEGA_UPDATE="$PWD/mmega_update.sh"

# Database
  db_name="mega_db_test2"


# Checks ########################################################################################

# Check binaries and scripts
  if [ -z $MEGACOPY ] || [ -z $MEGARM ] || [ -z $MEGALS ] || [ -z $MMEGA_UPDATE ];then
     echo "$fail binaries or scripts not found"
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

# Get input account
get_input_account(){
  if [ -z "$1" ];then
     echo "$fail No account name"
     echo "       $usage"
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

get_sync_action(){
  if [ -z "$1" ];then
     echo "$fail No sync type seleted"
     echo "       $usage"
     exit 1
  fi

  if [ "$1" == "up" ] || [ "$1" == "down" ];then
     action_type="$1"
  elif [ "$1" == "sync" ];then
     action_type="$1"

     if [ -z "$2" ];then
        echo "$fail sync type need direction parameter [with_local or with_remote]"
        echo "       $usage"
        exit 1
     elif [ "$2" == "with_local" ] || [ "$2" == "with_remote" ];then
        direction="$2"
     else
        echo "$fail sync direction only accept <with_local|with_remote> options"
        echo "       $usage"
        exit 1
     fi
  else
     echo "$fail Only up|down|sync type are accepted"
     echo "       $usage"
     exit 1
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

# Get local files
get_local_files(){
 find "$local_dir" -type f -exec stat -c "%s %y %n" {} \; | cut -d ' ' -f1-3,5- | sed -e 's/¬/_/' \
                                                                                      -e 's/ /¬/1' \
                                                                                      -e 's/ /¬/2' \
                                                                                      -e 's/^\|$/"/g' \
                                                                                      -e 's/¬/"¬"/g' > $tmp_dir/local_files_$1
 if [ $? = 1 ];then
     no_local_files="yes"
 fi
}

# Minimal checks (local files and free space) to maximize speed
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
      # Test changes in free espace
        free_bytes_mega=$($MEGADF -u "$email" -p "$passwd" | grep "Free" | cut -d ' ' -f3)
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
}

update_database(){
  printf "%s %s\r" "$wait" "Updating tables of $1"
  $MMEGA_UPDATE "$1" 1>/dev/null
  printf "%-50s\r" " "
  printf "%s %s\n" "$ok" "Updated tables of $1"
}

upload(){
  printf "%-s\n" "${txtbld} Uploading files to $1 ${txtrst}"

  # Show files to upload
    mysql --login-path=local -e "USE $db_name; SELECT path AS files_to_upload_to_$1, \
                                                      lpad(size,11,' ') AS size, \
                                                      DATE_FORMAT(mod_date, '%d-%m-%y %H:%i') AS mod_date \
                                                 FROM local_files_$1 \
                                      WHERE NOT EXISTS (SELECT filename \
                                                          FROM remote_files_$1 \
                                                         WHERE local_files_$1.filename=remote_files_$1.filename);"

    to_up=$(mysql --login-path=local -sN -e "USE $db_name; SELECT to_up FROM file_stats WHERE name = '$1'" )
    echo " $to_up files to upload to $1"
    echo

  # Confirmation
    read -p "$wait Corfirm? (y/n) " confirmation

    if [[ "$confirmation" =~ [Yy|YesYES]$ ]]; then
       echo -en "\033[1A\033[2K" # Delete previus line
       confirmation="upload files"
       echo "$ok Confirm? $confirmation"

       # Upload local files
         to_up=""
         echo "$wait Uploading files to $1"
         $MEGACOPY -u "$email" -p "$passwd" --reload --local "$local_dir" --remote "$remote_dir" 2>/dev/null

       # Update database
         update_database "$1"
    else
       echo -en "\033[1A\033[2K"
       confirmation="upload canceled"
       echo "$ok Confirm? $confirmation"
       exit
    fi
}

download(){
  printf "%-s\n" "${txtbld} Downloading files from $1 ${txtrst}"

  # Show files to download
    mysql --login-path=local -e "USE $db_name; SELECT path AS files_to_download_from_$1, \
                                                      lpad(size,11,' ') AS size, \
                                                      DATE_FORMAT(mod_date, '%d-%m-%y %H:%i') AS mod_date \
                                                 FROM remote_files_$1 \
                                     WHERE NOT EXISTS (SELECT filename \
                                                         FROM local_files_$1 \
                                                        WHERE remote_files_$1.filename=local_files_$1.filename);"

    to_down=$(mysql --login-path=local -sN -e "USE $db_name; SELECT to_down FROM file_stats WHERE name = '$1'" )
    echo " $to_down files to download from $1"
    echo

  # Confirmation
    read -p "$wait Corfirm? (y/n) " confirmation

    if [[ "$confirmation" =~ [Yy|YesYES]$ ]]; then
       echo -en "\033[1A\033[2K" # Delete previus line
       confirmation="download files"
       echo "$ok Confirm? $confirmation"

      # Download remote files
         echo "$wait Downloading files from $1"
         $MEGACOPY -u "$email" -p "$passwd" --reload --download --local "$local_dir" --remote "$remote_dir" 2>/dev/null

      # Update database
        update_database "$1"
    else
       echo -en "\033[1A\033[2K"
       confirmation="download canceled"
       echo "$ok Confirm? $confirmation"
       exit
    fi
}

download_remote_files(){
 if [ "$to_download" != 0 ];then
    to_download=0
    echo "$wait Downloading files from $1"
    $MEGACOPY -u "$email" -p "$passwd" --reload --download --local "$local_dir" --remote "$remote_dir" 2>/dev/null
 fi
}

delete_local_files(){
  # Delete files
  if [ "$to_delete" != 0 ];then
     to_delete=0
     echo "$wait" "Deleting local files"
     old_IFS="$IFS"
     IFS=$'\n'
     for file in $(cat $tmp_dir/local_files_to_delete_$1);do
         echo "Deleting local $file"
         rm "$file"
     done
  fi

  # Delete empty directoires
    for directory in $(cat $tmp_dir/local_directories_to_check_$1);do
        if [ -z "$(ls -A $directory )" ]; then
           echo "Deleting local directory $directory"
           rm -R "$directory"
        fi

    done
    IFS="$old_IFS"
}


# Synchronize local directory with remote directory (it will download remote files and delete local files!)
sync_with_remote(){
  printf "%-s\n" "${txtbld} Synchronizing $1 with remote directory ${txtrst}"

  # Get local files (with path) to delete from database
    mysql --login-path=local -sN -e "USE $db_name; SELECT path AS local_files_to_delete_from_$1 \
                                                 FROM local_files_$1 \
                                      WHERE NOT EXISTS (SELECT filename \
                                                          FROM remote_files_$1 \
                                                         WHERE local_files_$1.filename=remote_files_$1.filename);" > $tmp_dir/local_files_to_delete_$1

  # Get local directories to check and delete if empty
    mysql --login-path=local -sN -e "USE $db_name; SELECT path AS directories_to_check_from_$1 \
                                                     FROM local_directories_$1;" > $tmp_dir/local_directories_to_check_$1

  # Show local files to delete (from database)
    mysql --login-path=local -e "USE $db_name; SELECT path AS local_files_to_delete_to_$1, \
                                                      lpad(size,11,' ') AS size, \
                                                      DATE_FORMAT(mod_date, '%d-%m-%y %H:%i') AS mod_date \
                                                 FROM local_files_$1 \
                                      WHERE NOT EXISTS (SELECT filename \
                                                          FROM remote_files_$1 \
                                                         WHERE local_files_$1.filename=remote_files_$1.filename);"

    to_delete=$(mysql --login-path=local -sN -e "USE $db_name; SELECT to_up FROM file_stats WHERE name = '$1';")
    echo " $to_delete local files to delete from $1"
    echo

  # Show files to download (from database)
    mysql --login-path=local -e "USE $db_name; SELECT path AS remote_files_to_download_from_$1, \
                                                      lpad(size,11,' ') AS size, \
                                                      DATE_FORMAT(mod_date, '%d-%m-%y %H:%i') AS mod_date \
                                                 FROM remote_files_$1 \
                                     WHERE NOT EXISTS (SELECT filename \
                                                         FROM local_files_$1 \
                                                        WHERE remote_files_$1.filename=local_files_$1.filename);"

    to_download=$(mysql --login-path=local -sN -e "USE $db_name; SELECT to_down FROM file_stats WHERE name = '$1';")
    echo " $to_download remote files to download from $1"
    echo

 # Confirmation
   read -p "$wait Confirm? ${txtbld}S${txtrst}ync ${txtbld}C${txtrst}ancel [${txtbld}D${txtrst}ownload_only D${txtbld}e${txtrst}lete_only] [This can not be undone] " confirmation

    if [[ "$confirmation" =~ [Ss]$ ]]; then
        echo -en "\033[1A\033[2K" # Delete previus line
        confirmation="synchronize account"
        echo "$ok Confirm? $confirmation"
        download_remote_files "$1"
        delete_local_files "$1"

       # Update database
         update_database "$1"

    elif [[ "$confirmation" =~ [Dd]$ ]]; then
         echo -en "\033[1A\033[2K" # Delete previus line
         confirmation="download only"
         echo "$ok Confirm? $confirmation"
         download_remote_files "$1"

       # Update database
         update_database "$1"

    elif [[ "$confirmation" =~ [Ee]$ ]]; then
         echo -en "\033[1A\033[2K" # Delete previus line
         confirmation="delete only"
         echo "$ok Confirm? $confirmation"
         delete_local_files "$1"

       # Update database
         update_database "$1"
    else
        echo -en "\033[1A\033[2K" # Delete previus line
        confirmation="remote synchronization canceled"
        echo "$ok Confirm? $confirmation"
    fi
}

#Cambios en if conditions
upload_local_files(){
  if [ "$to_upload" != 0 ];then
     to_upload=""
     echo "$wait Uploading files to $1"
     $MEGACOPY -u "$email" -p "$passwd" --reload --local "$local_dir" --remote "$remote_dir" 2>/dev/null
  fi
}

delete_remote_files(){
  if [ "$to_delete" != 0 ];then
     to_detele=""
     printf "%-6s %-50s\n" "$wait" "Deleting remote files"

     old_IFS="$IFS"
     IFS=$'\n'
     for file in $(cat $tmp_dir/remote_files_to_delete_$1);do
         echo "Deleting remote file $file"
         $MEGARM -u "$email" -p "$passwd" --reload "$file" 2>/dev/null
     done

     # Delete empty directoires
       for directory in $(cat $tmp_dir/remote_directories_to_check_$1);do
           empty=$($MEGALS -u "$email" -p "$passwd" --reload -R "$directory" | grep -oP ^"$directory/\K.*")
           if [ -z "$empty" ];then
              echo "Deleting remote directory $directory"
              $MEGARM -u "$email" -p "$passwd" --reload "$directory" #2>/dev/null
           fi
       done
       IFS="$old_IFS"

  fi
}

# Synchronize remote directory with local directory (it will upload local files and delete remote files!)
sync_with_local(){
  printf "%-s\n" "${txtbld} Synchronizing $1 with local directory ${txtrst}"

  # Get remote files (with path) to delete
    mysql --login-path=local -sN -e "USE $db_name; SELECT path AS remote_files_to_delete_from_$1 \
                                                     FROM remote_files_$1 \
                                         WHERE NOT EXISTS (SELECT filename \
                                                             FROM local_files_$1 \
                                                            WHERE remote_files_$1.filename=local_files_$1.filename);" > $tmp_dir/remote_files_to_delete_$1

  # Get remote directories to check and delete if empty
    mysql --login-path=local -sN -e "USE $db_name; SELECT path AS directories_to_check_from_$1 \
                                                     FROM remote_directories_$1;" > $tmp_dir/remote_directories_to_check_$1

  # Show remote files to delete (from database)
    mysql --login-path=local -e "USE $db_name; SELECT path AS remote_files_to_delete_from_$1, \
                                                      lpad(size,11,' ') AS size, \
                                                      DATE_FORMAT(mod_date, '%d-%m-%y %H:%i') AS mod_date \
                                                 FROM remote_files_$1 \
                                     WHERE NOT EXISTS (SELECT filename \
                                                         FROM local_files_$1 \
                                                        WHERE remote_files_$1.filename=local_files_$1.filename);"

   to_delete=$(mysql --login-path=local -sN -e "USE $db_name; SELECT to_down FROM file_stats WHERE name = '$1';")
   echo " $to_delete remote files to delete from $1"
   echo

 # Show local files to upload
   mysql --login-path=local -e "USE $db_name; SELECT path AS local_files_to_upload_to_$1, \
                                                     lpad(size,11,' ') AS size, \
                                                     DATE_FORMAT(mod_date, '%d-%m-%y %H:%i') AS mod_date \
                                                FROM local_files_$1 \
                                     WHERE NOT EXISTS (SELECT filename \
                                                         FROM remote_files_$1 \
                                                        WHERE local_files_$1.filename=remote_files_$1.filename);"

    to_upload=$(mysql --login-path=local -sN -e "USE $db_name; SELECT to_up FROM file_stats WHERE name = '$1';")
    echo " $to_upload local files to upload to $1"
    echo

  # Confirmation
    read -p "$wait Confirm? ${txtbld}S${txtrst}ync ${txtbld}C${txtrst}ancel [${txtbld}U${txtrst}pload_only D${txtbld}e${txtrst}lete_only] [This can not be undone] " confirmation

    if [[ "$confirmation" =~ [Ss]$ ]]; then
        echo -en "\033[1A\033[2K" # Delete previus line
        confirmation="synchronize account"
        echo "$ok Confirm? $confirmation"
        upload_local_files "$1"
        delete_remote_files "$1"

       # Update database
         update_database "$1"

    elif [[ "$confirmation" =~ [Uu]$ ]]; then
         echo -en "\033[1A\033[2K"
         confirmation="upload only"
         echo "$ok Confirm? $confirmation"
         upload_local_files "$1"

       # Update database
         update_database "$1"

    elif [[ "$confirmation" =~ [Ee]$ ]]; then
         echo -en "\033[1A\033[2K"
         confirmation="delete only"
         echo "$ok Confirm? $confirmation"
         delete_remote_files "$1"

       # Update database
         update_database "$1"

    else
        echo -en "\033[1A\033[2K"
        confirmation="local synchronization canceled"
        echo "$ok Confirm? $confirmation"
    fi
}

sync_action(){
 # Test if database is updated
   is_account_updated "$1"

   if [ "$updated" == "yes" ] && [ "$no_check" != "yes" ];then

       # Select action
         if [ "$2" == "up" ];then
            to_up=$(mysql --login-path=local -sN -e "USE $db_name; SELECT to_up FROM file_stats WHERE name = '$1'" )

            if [ "$to_up" = 0 ];then
               echo "$ok Remote directory has every file [nothing to upload]"
               echo
            else
               echo
               upload "$1"
            fi
         fi

         if [ "$2" == "down" ];then
            to_down=$(mysql --login-path=local -sN -e "USE $db_name; SELECT to_down FROM file_stats WHERE name = '$1'" )

            if [ $to_down = 0 ];then
               echo "$ok Local directory has every file [nothing to download]"
               echo
            else
               echo
               download "$1"
            fi
         fi

         if [ "$2" == "sync" ];then
            # Get direction
              if [ "$3" == "with_local" ];then
                 # Test if files to delete and files to download are 0 (the account is sync)
                   to_delete=$(mysql --login-path=local -sN -e "USE $db_name; SELECT to_down FROM file_stats WHERE name = '$1';")
                   to_up=$(mysql --login-path=local -sN -e "USE $db_name; SELECT to_up FROM file_stats WHERE name = '$1';")

                   if [ "$to_delete" = 0 ] && [ "$to_up" = 0 ];then
                      echo "$ok The account is sync [nothing to sync]"
                      echo
                   else
                      echo
                      sync_with_local "$1"
                   fi
              fi

              if [ "$3" == "with_remote" ];then
                 # Test if files to delete and files to download are 0 (the account is sync)
                   to_delete=$(mysql --login-path=local -sN -e "USE $db_name; SELECT to_up FROM file_stats WHERE name = '$1';")
                   to_down=$(mysql --login-path=local -sN -e "USE $db_name; SELECT to_down FROM file_stats WHERE name = '$1';")

                   if [ "$to_delete" = 0 ] && [ "$to_down" = 0 ];then
                      echo "$ok The account is sync [nothing to sync]"
                      echo
                   else
                      echo
                      sync_with_remote "$1"
                   fi
              fi
         fi
   else
       echo "$fail Account outdated. Update database before continue"
       #echo
   fi

}

show_sync_files(){
  # Show sync files
    echo "${txtbld} Syncronized files ${txtrst}"
    mysql --login-path=local -e "USE $db_name; SELECT filename AS sync_files_of_$1\
                                                 FROM local_files_$1 \
                                         WHERE EXISTS (SELECT filename \
                                                         FROM remote_files_$1 \
                                                        WHERE local_files_$1.filename=remote_files_$1.filename);"


  # Get number of sync files
    sync_files=$(mysql --login-path=local -sN -e "USE $db_name; SELECT sync FROM file_stats WHERE name = '$1';")

  echo " $sum syncronized files in $1"
  echo
}

# Start #######################################################################################

# Title
echo "  __ _   __ _  ___  ___ _ ___ _  ___ __ __ ___  ____";
echo " /  ' \ /  ' \/ -_)/ _ \`// _ \`/ (_-</ // // _ \/ __/";
echo "/_/_/_//_/_/_/\__/ \_, / \_,_/ /___/\_, //_//_/\__/ ";
echo "                  /___/            /___/            ";
echo



#  echo
#  echo "${txtbld}        #### Donwload, upload or synchronize files #### ${txtrst}"
#  echo

# Get inputs
  get_input_account "$1"
  get_sync_action "$2" "$3"

  if [ "$input_account" == "all" ];then
     list_accounts="$list_accounts_raw"
  else
     list_accounts=$(echo "$list_accounts_raw" | grep "$input_account")
  fi

  for account in $list_accounts; do
       sync_action "$account" "$action_type" "$direction"
  done

echo
exit


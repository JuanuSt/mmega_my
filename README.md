# MEGAtools multi-account [MySQL] 
Check and administrate several registered accounts in mega.nz cloud using the nice code [megatools](https://github.com/megous/megatools) written by [megaus](https://megatools.megous.com/man/megarc.html).

This version uses MySQL to store accounts info (check out [PostgreSQL flavor](https://bitbucket.org/juanust/mmega_pg)) and is composed by four scripts. Storing the files info in database allows to consult all accounts all at once, search for files or get remote links very quickly.


### EDIT
I don't use mysql at this moment and I'm just continuing with the psql version. Other reasons to opt for psql have been the integration with the system and the facility to insert files.

This suite still works, it is still possible to create a mysql's database with all the information of your files in minutes, although maybe you have to make some fixes to make it work correctly. Maybe I can inspire someone.

I have rewritten this doc to include the functionalities that I have developed for both versions. Today the two documents are the same, however I will only continue with the psql version.

### Dependencies
* megatools 1.9.97 
* MySQL 5.7 (The queries are simple, so it can work in higher versions)
* Some bash specific commands 

### Install
Install MySQL

Create a file `.my.cnf` in your home directory with login credentials:

    [client]
    user=user_name
    password="PaSs W0Rd"

Made it readable only by you: `chmod 0600 ~/.my.cnf`

Edit the file `/etc/mysql/mysql.conf.d/mysqld.cnf` and change:

    secure_file_priv=""   
    This allows to use the function LOAD INFILE LOCAL DATA

Make sure that you are using UTF-8 character encoding (filenames could change). Edit `/etc/mysql/my.cnf`:

    [mysqld]
    collation-server = utf8_unicode_ci
    init-connect='SET NAMES utf8'
    character-set-server = utf8

Restart mysql server.

Clone or download this repository (four scripts and one directory with four completion files).

Edit `mmega_create.sh` and set the credentials for MySQL: **user**, **password for user** and **password for root**. They are needed only during database creation and for granting privileges. The root password is used only once, so you can unset it and MySQL will ask you only once. The user's password is used to grant the access, so it can not be in unset.

Set the **db_nam** that you want. It will be set in all other scripts.

Set **config_file path**. The path to your config file (see below) 

### How it works
The suite is composed by four scripts:

|Script|Function|
|--|--|
| mmega_create | To create the database from a config file |
| mmega_update | To get data and store them in database |
| mmega_query | To interact with the database and retrieve info |
| mmega_sync | To interact with the accounts (**risky!**) |

As in [first version](https://bitbucket.org/juanust/mmega), we start with a config file with account's parameters (login and directories) for each account (see below). This file isn't parsed to check common mistakes in format (five fields comma separated) as was done in previus version, so make sure that it haven't any trailing spaces or empty lines. Using this file `mmega_create` will create the database based on the accounts found there.

### Config file
It contains the account's parameters per line. The structure is comma separated with 5 fields:

    name1,email1,passwd1,local_dir1,remote_dir1,
    name2,email2,passwd2,local_dir2,remote_dir2,
    name3,email3,passwd3,local_dir3,remote_dir3,
    ...

| Field | Description |
|--|--|
| name | The name to describe the account |
| email | The registered email in mega.nz | 
| passwd | The registered account password (in plaintext) |
| local_dir | The account's local directory |
| remote_dir | The account's remote directory (often /Root) | 

# Scripts
### mmega_create
See intall before running this script.
```
USAGE = mmega_create.sh
```
Execute `./mmega_create.sh` without any argument. If there were no errors the script:

 * will create the database
 * will insert the config info of each account
 * will create file's tables accordingly to config file
 * will insert the database's name in other scripts (mmega_update, mmega_query and mmega_sync) for a later use
 * will set this database in the four completion files. 

>It will also insert default values (all of them zero) and will show the config table.

Copy the completion files to */etc/bash_completion.d* directory (root privileges are needed) and create these aliases in *~/.bash_aliases* adapting the `scripts_dir` to your path:
 
    alias mmega_update="~/scripts_dir/mmega_update.sh"
    alias mmega_sync="~/scripts_dir/mmega_sync.sh"
    alias mmega_query="~/scripts_dir/mega/mmega_query.sh"
    alias mmega_rc="~/scripts_dir/mmega_query.sh set_rc" (see below for this alias)

Source them with `source ~/.bashrc`. From this moment all accounts and options in the scripts will be available with TAB.

>If you only use one database this script only runs once.

### mmega_update
```
USAGE = mmega_update.sh <account_name|all>
```
After database creation this script will contact mega.nz to retrive remote directory and will check local directory to insert all file's info into database. First, it make a check for each account to detect changes in local and remote directories. This check is done every time and for each account. The check consist in three steps:

1. It get local files info, creates a file with path, size and modification date of each file and hash it (md5). This hash is compared with that stored in database, if they are different the database is considerated outdated.

2. If the hashes are identical (no changes in local directory) then it proceeds to check the free space in remote directory and compare it against that stored in the database. If they are different the account is considerated outdated.
   >  This connection is fast.
3. Even if free space is identical the script make a second connection to retrieve remote files info (some modifications are not detected). It creates a file (path, size, modification date and link) and hash it. This hash is compared with that stored in database, if they are different the database is considerated outdated.
   >This connection is slowed down by the mega servers when creating the links. All links are created without password (see note about links).
   
If any check declares the database outdated it proceeds to to update the database.

1. It connects to mega.nz and get disk usage stats (in bytes) using the command `megadf` and insert this info in the database.
2. It creates a file with local files info, hashs it and stores in database.
3. It connects to mega.nz again to take files info from remote directory using the command `megals --long --export /Root`, creates a file with remote files info, hashs it and stores in database.
4. It will calculate global stats and insert them into database.

> When it runs by the first time it alters file's tables adding filename column (extracted from path) and size column (in humand readable form).

> This script is used by `mmega_sync` when there was changes in files after synchronization, so the path to this script should not be altered.

### mmega_query
```
USAGE = mmega_query.sh config|account|files|change|add|del|search|set_rc|set_db|summary [options by query]

        config  <account_name|all> [optional password] [defautl all]
        status  <account_name|all> [defautl all]
        files   <account_name> local|remote|sync|to_down|to_up|link
        change  <account_name> name|email|passwd|local_dir|remote_dir <new_parameter>
        add     <new_account_name|new_file_config>
        del     <account_name>
        search  <file_to_search>   [optional account, defautl all]
        set_rc  <account_name>
        set_db  <database_name>
        summary
```
Once the database has been created and populated with the file's info we can interact and retrive information. It has many options and you can add as many as you want, because most of them are just normal queries to the database.

| Option | Description |
|--|--|
| `config` | This option is used to view the accounts configuration. By default is set to all, if you want just to check one account pass it as argument. By default the password is shown hashed, if you want to see the password pass the argument `plaintext` (to show all accounts you will have to pass as first argument all: `mmega_query config all plaintext`).|
| `status` | This option checks the account/s state. It shows all revelant information about the status account.
| `files` | This is one of more useful options when managing accounts. It shows account's files by type. So `local` argument will show the files in local\_dir, `remote` will do the same with remote\_dir, then you can check if there are files to upload (`to_up`) or download (`to_down`). Finally, the `link` option gives the remote files with links (see note about links). |
| `change` | This option is used to change the configuration of the accounts. This option is useful if you do not write a complete config file or you added an incomplete account through add (see below).|
| `add` | This option allows to add one account by command line or serveral accounts through a new configuration file. If first argument is a file it will be read and all accounts will be added to database. If the first is a string it will be considerated as the account's name. The minimal config for this option is name but you can pass all other arguments like in the config file (in the same order): `mmega_query.sh add $name [minimal config]` `mmega_query.sh add $name $email $password $local_dir $remote_dir` |
| `del` | This option deletes all tables and info from the account passed as argument. Only one account can be deleted at time. |
| `search` | This option is used to search for files in the database. When used, if you do not pass any argument it will ask for the filename. If you find many files, you can narrow the search to only one account. Observe that the account paramenter is given in last position |
| `set_rc` | Megatools allows a file with account login parameters to avoid to write them each time (see megatools manual). With this option you can set up a megarc file to any account in the database. It is really useful when you are using megatools for several accounts and you need to 'jump' from one account to another. This option is used often, then is suggested to write a alias in your bash\_aliases file like this: alias mmega_rc='~/scripts_dir/mmega_query.sh set_rc |
| `set_db` | This option it only useful if you use several databases. This option set the database (only if it exists) to the others scripts (mmega_update and mmega_sync) and itself. That allows use the whole suite with several databases. However the completion files are never set to the new database, you will have to change them 'by hand' (the $db\_name variable is at the beginning of the completion file).|
| `summary` | This option shows a summary of all accounts. |

>**About links**. I have not completely understood the creation of links in mega.nz, but it seems that when a link has been created and then used (only if it is used), the creation of new links deletes the old link, that is, if this link was shared it has to be shared again.

### mmega_sync
```
USAGE = mmega_sync.sh <account_name|all> up|down|sync [with_local|with_remote]

        up               = upload all diferent files from local to remote
        down             = download all diferent files from remote to local
        sync with_local  = upload all differents files and delete all remote differents files
             with_remote = download all differents files and delete all local different files    
```
The others scripts never modify files but this script can delete local and remote files. **Be careful when using it, I decline all responsibility as megaus does**. As security method, before to make any change the script will show the files (with path) to upload, download or delete (check everything) and will ask for confirmation before proceeding.
> Observe that **is not a proper synchronization process**, it only detects the files that are different between the local and remote directories (it does not detect the modification's date or the different size between files). Indeed if two copies of the same file are named the different way they will be considerated as two differents files. Perhaps it is more appropriate to call it mmega_copy (as megaus does).
> When using `megacopy` megatools provides a secutity method to never overwrite files. If there are discrepancies the files are marked with a number (that desings the node) and the word "conflict". You will have to check 'by hand' these descrepancies.

Before starting the synchronization process the script will check that the database is updated (this slows down the process considerably). This is very important since the files are taken from the database to determine which files upload, download or delete, so the state of the database should reflect the actual accounts state.

| Option | Description |
|--|--|
|`up`| Upload all diferent files from local to remote. Using `megacopy --reload` command (safe). Although the displayed files come from the database, all responsibility for synchronization lies in megacopy command (there may be differences).|
|`down`| Download all diferent files from remote to local. Using `megacopy --reload --download` command (safe). Although the displayed files come from the database, all responsibility for synchronization lies in megacopy command (there may be differences). |
|`sync with_local  ` | It will upload local files (using `megacopy --reload` command (safe)) and will **delete the remote files that are not in local** (using `megarm --reload $path_to_file` command (**danger!**)). The remote directory becomes a copy of the local directory. |
|`sync with_remote  ` | It will download remote files (`megacopy --reload --download` command (safe)) and will **delete the local files that are not in remote** (using `rm $path_to_file` command (**danger!**)). The local directory becomes a copy of the remote directory.|

The confirmation options are:

| Option | Confirmation options |
|--|--|
|`up`| y / n (upload or not) |
|`down`| y / n (download or not) |
|`sync with_local` | **S**ync **C**ancel [**U**pload_only D**e**lete_only]. Use bold letters to choose the option|
||**Sync** will do the two actions, it will upload local files and will delete remote differents files (in this order)|
||**Cancel** will cancel the synchronization process |
||**Upload_only** only will upload the local files to remote directory (safe)|
||**Delete_only** only will delete remote files (danger!) |
|`sync with_remote` | **S**ync **C**ancel [**D**ownload_only D**e**lete_only]. Use bold letters to choose the option |
||**Sync** will do the two actions, it will download remote files and will delete local differents files (in this order)|
||**Cancel** will cancel the synchronization process |
||**Donwload_only** only will download the remote files to local directory (safe)|
||**Delete_only** only will delete local files (danger!) |

The biggest problem with dealing with files is filename. I have tried to take into account all types errors (spaces, special characters, etc.) but in complex directories with long filenames (usually with special characters) there are almost always problems. In addition, megatools and this suite treat filenames differently, so discrepancies may occur. Even with this handicap the possibility of working with several accounts is worth it.

Do not hesitate to commit changes, suggest features or improve the documentation.

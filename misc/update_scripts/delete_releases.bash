#!/bin/bash

# Exit Codes
# 100: No realpath found in $PATH
# 101: Unable to determine where the nzbfiles are kept

start="$(date "+%s.%N")"
debug=${debug:-0}
quiet=${quiet:-0}
logfile="/tmp/$(basename $0)-$(date '+%Y-%M-%d-%R').log"
if [[ -n "$quiet" && "$quiet" = "1" ]]; then
  exec > $logfile
  exec 2>&1
fi

if [[ -z "$(which realpath)" ]]; then
  echo -e "Install realpath (sudo apt-get install realpath), and try this again."
  exit 100
fi

# We will assume $0 is installed in $NEWZNAB_INSTALL_DIR/misc/update_scripts
self="$(realpath -P $0)"
nzbfiles_dir="$(realpath -P $(dirname $self)/../../nzbfiles)"
if [[ ! -d "$nzbfiles_dir" ]]; then
  echo -e "Can't find the 'nzbfiles' directory ($nzbfiles_dir)."
  echo -e 'This script should be installed in "$NEWZNAB_INSTALL_DIR/misc/update_scripts".'
  exit 101
fi
db_name="newznab"
tmp_nzbfiles="/tmp/nzbfiles"
mkdir -p "$tmp_nzbfiles"
mysql_args="--defaults-file=/etc/mysql/debian.cnf"
sql_file="$tmp_nzbfiles/delete_releases.sql"
prune_date="$(date --date='00:00 1 week ago' '+%Y-%M-%d %H:%M:%S')"
declare -a delete_categories
delete_categories=(
"6000"
"6010"
"6020"
"6030"
"6040"
"6050"
"6060"
"6070"
"8000"
"8010"
)

if [[ -n "$debug" && "$debug" = 1 ]]; then
  echo -e "MariaDB Query statement:"
  echo -e "select guid from releases where categoryID in($(IFS=,;echo "${delete_categories[*]/ /,}")) and adddate < '$prune_date';"
fi

count=0
for guid in $(mysql $mysql_args $db_name -B -s -e "select guid from releases where categoryID in($(IFS=,;echo "${delete_categories[*]/ /,}")) and adddate < '$prune_date';")
do
  ((count++))
  if [[ -f "$nzbfiles_dir/${guid:0:1}/$guid.nzb.gz" ]]; then
    mv "$nzbfiles_dir/${guid:0:1}/$guid.nzb.gz" /tmp/nzbfiles/
  fi
  echo -e "\r Marking $count\c"
  echo -e "delete from releases where guid='$guid';" >> $sql_file
done

# No need for this if no output from guid for loop above
if [[ "$count" -gt "0" ]]; then
  echo
fi

# Read in das sql commands to das MariaDB
if [[ -f "$sql_file" ]]; then
  mysql $mysql_args $db_name -B -s < $sql_file
  echo -e "Deleted $count releases"
else
  echo -e "Found nothing to delete."
fi

# Keep file if $debug!=0, and $debug defined.
if [[ -z "$debug" || "$debug" = "0" ]]; then
  if [[ -d "$tmp_nzbfiles" ]]; then
    rm -r "$tmp_nzbfiles"
  fi
fi

# How long you take? Long time no like!
printf "Finished in %.3f seconds.\n" $(echo $(date "+%s.%N")-$start|bc)

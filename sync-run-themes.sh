#!/bin/bash -eu

#checks that script is being run as root user else exits
[ `whoami` = root ] || { sudo "$0" "$@"; exit $?; }

# add location as an env variable remoteBucketURL

# Constants:
readonly bucket_url="${remoteBucketURL}"
readonly remote_dir="${remoteBucketURL}/wordpress/wp-content/themes"
readonly local_dir="/var/www/html/wp-content/themes"

readonly local_bucket_version_file="/var/www/wp_version.md5"
readonly remote_bucket_version_file="${bucket_url}/versioning/wp_version.md5"

readonly local_bucket_lock_file="/var/www/wp_bucket.lock"
readonly remote_bucket_lock_file="${bucket_url}/versioning/wp_bucket.lock"

readonly local_app_dir="/var/www/html/"
readonly remote_app_dir="${bucket_url}/wordpress/"

readonly push_process_lock_file="/tmp/sync_push.lock"

 function sync_files_from_bucket() {
   gsutil -m rsync -r -c -d ${remote_dir} ${local_dir}
   chown -Rf www-data:www-data ${local_dir}
 }

# Local push process lock operations:
# (prevent more than one sync out operation being run at once):

function lock_push_process() {
  touch /tmp/sync_push.lock
}

function unlock_push_process() {
  rm -f /tmp/sync_push.lock
}

function is_push_process_locked() {
  [[ -f /tmp/syncS_push.lock ]]
}

function pull() {
  echo 'Sync: Attempting to sync files...'
  if is_push_process_locked; then
      echo 'Sync: Ongoing push detected. Skipping this sync sequence...'
      return 1
  fi
  lock_push_process
  sync_files_from_bucket
  unlock_push_process
}

# Main process:
echo 'Sync: Attempting to push to Storage'

until pull
do
  sleep 5
  echo "Trying again"
done
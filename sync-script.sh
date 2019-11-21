source /opt/my-utils || exit 1

# Constants:
readonly bucket_url="${remoteBucketURL}"
readonly remote_dir="${remoteBucketURL}/wordpress/wp-content/plugins"
readonly local_dir="/var/www/html/wp-content/plugins"

readonly local_bucket_version_file="/var/www/wp_version.md5"
readonly remote_bucket_version_file="${bucket_url}/versioning/wp_version.md5"

readonly local_bucket_lock_file="/var/www/wp_bucket.lock"
readonly remote_bucket_lock_file="${bucket_url}/versioning/wp_bucket.lock"

readonly local_app_dir="/var/www/html/"
readonly remote_app_dir="${bucket_url}/wordpress/"

readonly push_process_lock_file="/tmp/sync_push.lock"


# Bucket files operations: -x wp-content/uploads"
function sync_files_out_to_bucket() {
  gsutil -m rsync -R -p -d "${local_app_dir}" "${remote_app_dir}"
  gsutil cp "${local_bucket_version_file}" "${remote_bucket_version_file}"
}

# Bucket lock operations:
# (prevent new readers from starting reading data while they are changed)
function lock_bucket() {
  touch "${local_bucket_lock_file}"
  gsutil cp "${local_bucket_lock_file}" "${remote_bucket_lock_file}"
}

function unlock_bucket() {
  rm -f "${local_bucket_lock_file}"
  if ! gsutil rm -f "${remote_bucket_lock_file}"; then
    echo "Sync: the bucket lock file did not exist"
  fi
}

function is_bucket_locked() {
  gsutil -q stat "${remote_bucket_lock_file}"
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
  [[ -f /tmp/sync_push.lock ]]
}

# Local app version operations:
function read_bucket_version_local() {
  if [[ -f "${local_bucket_version_file}" ]]; then
    cat "${local_bucket_version_file}"
  else
    echo "0"
  fi
}

function update_bucket_version_local() {
  local -r new_sum="$1"
  echo "${new_sum}" > "${local_bucket_version_file}"
}

# Detecting local files modifications and sending them out to bucket:
function calculate_checksum_for_local_app() {
  local -r dir="$1"
  # Generate a list of all files and directories under the main app directory
  # (paths + last modification time), sort the list, calulate md5 checksum for
  # the list and return it. This way we detect files updates, creations and
  # deletions.
  find "${dir}" -printf "%P %T@\n" | sort -n | md5sum | cut -d ' ' -f 1
}

function push() {
  echo 'Sync: Attempting to push to Storage'
  if is_push_process_locked; then
      echo 'Sync: Ongoing push detected. Skipping this push sequence...'
      return 1
  fi
  if is_bucket_locked; then
      echo 'Sync: Bucket locked. Skipping this push sequence...'
      return 2
  fi

  lock_push_process
  lock_bucket

  sync_files_out_to_bucket

  unlock_bucket
  unlock_push_process
}

function push_if_changed() {
  local -r curr_sum="$(calculate_checksum_for_local_app "${local_app_dir}")"
  local -r prev_sum="$(read_bucket_version_local)"
  echo "Sync: files checksum: ${curr_sum} vs ${prev_sum}"

  if [[ "${curr_sum}" != "${prev_sum}" ]]; then
    echo "Sync: change detected - syncing to bucket"
    update_bucket_version_local "${curr_sum}"
    push
  else
    echo "Sync: no change detected in app files - skipping"
  fi
}

# Main process:
unlock_bucket
unlock_push_process
while [[ true ]]; do
    push_if_changed
    sleep 10
done



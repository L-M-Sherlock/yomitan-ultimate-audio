#!/usr/bin/env bash

# Check for required environment variables
if [[ -z "$R2_ACCESS_KEY_ID" || -z "$R2_SECRET_ACCESS_KEY" || -z "$R2_ACCOUNT_ID" ]]; then
  echo "Error: Required environment variables not set"
  echo "Please set the following environment variables:"
  echo "  - R2_ACCESS_KEY_ID: Your R2 access key"
  echo "  - R2_SECRET_ACCESS_KEY: Your R2 secret key"
  echo "  - R2_ACCOUNT_ID: Your Cloudflare account ID"
  exit 1
fi

# Array of folders to upload
folders=(
  "daijisen_files"
  "forvo_ext2_files"
  "forvo_ext_files"
  "forvo_files"
  "jpod_files"
  "nhk16_files"
  "ozk5_files"
  "shinmeikai8_files"
  "taas_files"
  "tts_files"
)

# Bucket name
BUCKET="yomitan-audio-bucket"

# Create a temporary rclone config file
TEMP_CONFIG=$(mktemp)
cat > "$TEMP_CONFIG" << EOF
[temp_r2]
type = s3
provider = Cloudflare
access_key_id = $R2_ACCESS_KEY_ID
secret_access_key = $R2_SECRET_ACCESS_KEY
endpoint = https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com
acl = private
EOF

for folder in "${folders[@]}"; do
  echo "Processing folder: $folder"

  # List remote files (relative paths) and save to a temporary file.
  rclone lsf "temp_r2:$BUCKET/$folder" --recursive --files-only --config="$TEMP_CONFIG" > "${folder}_remote.txt"

  # List local files (relative to the folder) using find.
  (cd "data/$folder" && find . -type f | sed 's|^\./||') > "${folder}_local.txt"

  # Sort both files and use 'comm' to find files present locally but missing remotely.
  comm -23 <(sort "${folder}_local.txt") <(sort "${folder}_remote.txt") > "${folder}_missing.txt"

  missing_count=$(wc -l < "${folder}_missing.txt")
  echo "$missing_count files missing on remote for $folder."

  if [ "$missing_count" -gt 0 ]; then
    echo "Uploading missing files for $folder..."
    rclone copy "data/$folder" "temp_r2:$BUCKET/$folder" \
      --files-from "${folder}_missing.txt" \
      --progress \
      --transfers=32 \
      --checkers=32 \
      --fast-list \
      --config="$TEMP_CONFIG"
  else
    echo "No missing files in $folder."
  fi

  # Remove temporary files
  rm "${folder}_remote.txt" "${folder}_local.txt" "${folder}_missing.txt"
done

# Remove temporary config file
rm "$TEMP_CONFIG"

echo "All folders processed."
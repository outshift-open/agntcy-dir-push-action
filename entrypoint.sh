#!/bin/bash

# Copyright © 2025 Cisco Systems, Inc. and its affiliates.
# All rights reserved.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.



set -e
declare -A options

DIRCTL_ARTIFACTS_DIR="/tmp/dirctl-artifacts"
DIRCTL_OUTPUT_LOG="${DIRCTL_ARTIFACTS_DIR}/dirctl_output.log"

function error_exit {
  local error_msg="Error: $@"
  echo "$error_msg" 1>&2
  echo "$error_msg" >> "$DIRCTL_OUTPUT_LOG"
  exit 1
}

function setup_options {
  options["directory_endpoint"]=""
  options["dirctl_client_id"]=""
  options["dirctl_secret"]=""
  options["record_file"]=""
  options["organization_name"]=""
  options["record_name"]=""
  options["record_version"]=""
  options["cosign_private_key"]=""
  options["cosign_private_key_password"]=""


  local OPTIND OPT
  while getopts ":e:c:s:f:o:n:v:k:p:" OPT; do
    case $OPT in
      e) options["directory_endpoint"]="$OPTARG" ;;
      c) options["dirctl_client_id"]="$OPTARG" ;;
      s) options["dirctl_secret"]="$OPTARG" ;;
      f) options["record_file"]="$OPTARG" ;;
      o) options["organization_name"]="$OPTARG" ;;
      n) options["record_name"]="$OPTARG" ;;
      v) options["record_version"]="$OPTARG" ;;
      k) options["cosign_private_key"]="$OPTARG" ;;
      p) options["cosign_private_key_password"]="$OPTARG" ;;
      :) error_exit "Option -$OPTARG requires an argument." ;;
      ?) error_exit "Invalid option -$OPTARG." ;;
    esac
  done
}

function check_option_set {
  local value="$1"
  [[ -n "$value" ]]
}

function process_record {
  local record_file="${options["record_file"]}"

  if [[ ! -f "$record_file" ]]; then
    error_exit "Directory record file not found: $record_file"
  fi

  echo "Processing directory record file: $record_file"
  RECORD_BASENAME=$(basename "$record_file")

  # Create a working copy with processed prefix
  PROCESSED_RECORD_FILE="${DIRCTL_ARTIFACTS_DIR}/processed-${RECORD_BASENAME}"
  cp "$record_file" "$PROCESSED_RECORD_FILE"

  # Validate JSON
  if ! jq -e . >/dev/null 2>&1 < "$PROCESSED_RECORD_FILE"; then
    error_exit "Invalid JSON format in record file"
  fi

  CURRENT_NAME=$(jq -r '.name // empty' "$PROCESSED_RECORD_FILE")
  CURRENT_VERSION=$(jq -r '.version // empty' "$PROCESSED_RECORD_FILE")

  if [[ -z "$CURRENT_NAME" || -z "$CURRENT_VERSION" ]]; then
    error_exit "Invalid agent directory json format, record file must contain a 'name' and 'version' field"
  fi

  echo "Current name in record: $CURRENT_NAME"
  echo "Current version in record: $CURRENT_VERSION"

  RECORD_NAME="$CURRENT_NAME"
  NEW_VERSION="$CURRENT_VERSION"

  # Apply record name override if provided
  if check_option_set "${options["record_name"]}"; then
    RECORD_NAME="${options["record_name"]}"
    echo "Overriding record name: $CURRENT_NAME -> $RECORD_NAME"
  fi

  # Apply version override if provided
  if check_option_set "${options["record_version"]}"; then
    NEW_VERSION="${options["record_version"]}"
    echo "Overriding version: $CURRENT_VERSION -> $NEW_VERSION"
  fi

  # Update the working copy JSON file with new values
  if [[ "$RECORD_NAME" != "$CURRENT_NAME" ]]; then
    echo "Updating name in record: $CURRENT_NAME -> $RECORD_NAME"
    jq --arg name "$RECORD_NAME" '.name = $name' "$PROCESSED_RECORD_FILE" > "${PROCESSED_RECORD_FILE}.tmp"
    mv "${PROCESSED_RECORD_FILE}.tmp" "$PROCESSED_RECORD_FILE"
  fi

  if [[ "$NEW_VERSION" != "$CURRENT_VERSION" ]]; then
    echo "Updating version in record: $CURRENT_VERSION -> $NEW_VERSION"
    jq --arg version "$NEW_VERSION" '.version = $version' "$PROCESSED_RECORD_FILE" > "${PROCESSED_RECORD_FILE}.tmp"
    mv "${PROCESSED_RECORD_FILE}.tmp" "$PROCESSED_RECORD_FILE"
  fi

  # Get organization name (required)
  ORG_NAME="${options["organization_name"]}"
  echo "Organization for push: $ORG_NAME"
  echo "Record name: $RECORD_NAME"

  export ORG_NAME
  export RECORD_NAME
  export PROCESSED_RECORD_FILE

  FINAL_RECORD_FILE="$PROCESSED_RECORD_FILE"
  export FINAL_RECORD_FILE
}

function sign_record {
  if ! check_option_set "${options["cosign_private_key"]}"; then
    echo "No cosign private key provided, skipping signing step"
    return 0
  fi

  echo "Cosign private key provided, signing directory record"

  # Extract CID from push output (grep for line starting with 'bae')
  local CID
  CID=$(grep -oE '^baear[a-z0-9]+' "$DIRCTL_OUTPUT_LOG" | head -n 1)

  if [[ -z "$CID" ]]; then
    error_exit "Failed to extract CID from push output"
  fi

  echo "Record CID to sign: $CID"

  # Create temporary key file with restricted permissions
  local TEMP_KEY
  TEMP_KEY=$(mktemp)
  chmod 600 "$TEMP_KEY"
  echo "${options["cosign_private_key"]}" > "$TEMP_KEY"

  # Set password if provided
  if check_option_set "${options["cosign_private_key_password"]}"; then
    export COSIGN_PASSWORD="${options["cosign_private_key_password"]}"
  fi

  export DIRCTL_CLIENT_ID="${options["dirctl_client_id"]}"
  export DIRCTL_CLIENT_SECRET="${options["dirctl_secret"]}"

  local SIGN_OUTPUT_LOG="${DIRCTL_ARTIFACTS_DIR}/dirctl_sign_output.log"
  echo "Executing: dirctl hub --server-address ${options["directory_endpoint"]} sign --no-cache $ORG_NAME $CID --key $TEMP_KEY"

  if dirctl hub \
    --server-address "${options["directory_endpoint"]}" \
    sign \
    --no-cache \
    "$ORG_NAME" \
    "$CID" \
    --key "$TEMP_KEY" > "$SIGN_OUTPUT_LOG" 2>&1; then
    cat "$SIGN_OUTPUT_LOG"
    echo "Successfully signed directory record with CID: $CID"
  else
    cat "$SIGN_OUTPUT_LOG"
    rm -f "$TEMP_KEY"
    unset COSIGN_PASSWORD DIRCTL_CLIENT_ID DIRCTL_CLIENT_SECRET
    error_exit "Failed to sign directory record"
  fi

  # Cleanup
  rm -f "$TEMP_KEY"
  unset COSIGN_PASSWORD DIRCTL_CLIENT_ID DIRCTL_CLIENT_SECRET
}

function push_to_directory {
  echo "Pushing directory record to directory"
  echo "Organization: $ORG_NAME"
  echo "Record name: $RECORD_NAME"
  echo "Endpoint: ${options["directory_endpoint"]}"
  echo "File: $FINAL_RECORD_FILE"

  # Display the final record content that will be pushed
  echo ""
  echo "========== FINAL RECORD CONTENT TO BE PUSHED =========="
  cat "$FINAL_RECORD_FILE"
  echo ""
  echo "======================================================="
  echo ""

  # Api key authentication via environment variables
  export DIRCTL_CLIENT_ID="${options["dirctl_client_id"]}"
  export DIRCTL_CLIENT_SECRET="${options["dirctl_secret"]}"
  echo "Executing: dirctl hub --server-address ${options["directory_endpoint"]} push --no-cache $ORG_NAME $FINAL_RECORD_FILE"

  if dirctl hub \
    --server-address "${options["directory_endpoint"]}" \
    push \
    --no-cache \
    "$ORG_NAME" \
    "$FINAL_RECORD_FILE" > "$DIRCTL_OUTPUT_LOG" 2>&1; then
    cat "$DIRCTL_OUTPUT_LOG"
    echo "Successfully pushed directory record to directory"
  else
    cat "$DIRCTL_OUTPUT_LOG"
    error_exit "Failed to push directory record to directory"
  fi

  # Clean up env vars
  unset DIRCTL_CLIENT_ID DIRCTL_CLIENT_SECRET
}

function cleanup {
  rm -f "${PROCESSED_RECORD_FILE}.tmp"
}

function main {
  setup_options "$@"
  mkdir -p "$DIRCTL_ARTIFACTS_DIR"
  # Check mandatory fields
  for option in directory_endpoint dirctl_client_id dirctl_secret record_file organization_name; do
    if [[ -z "${options[$option]}" ]]; then
      error_exit "$option is required but not provided"
    fi
  done

  echo "Starting Agent Directory Push"
  process_record
  push_to_directory
  sign_record
  cleanup
  echo "Agent Directory Push completed successfully!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

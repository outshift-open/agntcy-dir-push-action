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

  # Parse org/agent from name
  if [[ "$CURRENT_NAME" =~ ^([^/]+)/(.+)$ ]]; then
    CURRENT_ORG="${BASH_REMATCH[1]}"
    CURRENT_AGENT="${BASH_REMATCH[2]}"
  else
    error_exit "Invalid name format in record file. Expected: 'organization/agent_name', got: '$CURRENT_NAME'"
  fi

  # Apply overrides
  NEW_ORG="$CURRENT_ORG"
  NEW_AGENT="$CURRENT_AGENT"
  NEW_VERSION="$CURRENT_VERSION"

  if check_option_set "${options["organization_name"]}"; then
    NEW_ORG="${options["organization_name"]}"
    echo "Overriding organization: $CURRENT_ORG -> $NEW_ORG"
  fi

  if check_option_set "${options["record_name"]}"; then
    NEW_AGENT="${options["record_name"]}"
    echo "Overriding agent name: $CURRENT_AGENT -> $NEW_AGENT"
  fi

  if check_option_set "${options["record_version"]}"; then
    NEW_VERSION="${options["record_version"]}"
    echo "Overriding version: $CURRENT_VERSION -> $NEW_VERSION"
  fi

  # Update the working copy JSON file with new values
  NEW_NAME="${NEW_ORG}/${NEW_AGENT}"

  if [[ "$NEW_NAME" != "$CURRENT_NAME" ]]; then
    echo "Updating name in record: $CURRENT_NAME -> $NEW_NAME"
    jq --arg name "$NEW_NAME" '.name = $name' "$PROCESSED_RECORD_FILE" > "${PROCESSED_RECORD_FILE}.tmp"
    mv "${PROCESSED_RECORD_FILE}.tmp" "$PROCESSED_RECORD_FILE"
  fi

  if [[ -n "$NEW_VERSION" && "$NEW_VERSION" != "$CURRENT_VERSION" ]]; then
    echo "Updating version in record: $CURRENT_VERSION -> $NEW_VERSION"
    jq --arg version "$NEW_VERSION" '.version = $version' "$PROCESSED_RECORD_FILE" > "${PROCESSED_RECORD_FILE}.tmp"
    mv "${PROCESSED_RECORD_FILE}.tmp" "$PROCESSED_RECORD_FILE"
  fi

  # Push
  FINAL_REPOSITORY="${NEW_ORG}/${NEW_AGENT}"
  echo "Final repository path for push: $FINAL_REPOSITORY"

  export FINAL_REPOSITORY
  export PROCESSED_RECORD_FILE
}

function sign_record {
  local has_signature
  has_signature=$(jq -r '.signature // empty' "$PROCESSED_RECORD_FILE")

  if check_option_set "${options["cosign_private_key"]}"; then
    echo "Cosign private key provided, signing directory record"
    # Create temporary key file with restricted permissions
    TEMP_KEY=$(mktemp)
    chmod 600 "$TEMP_KEY"
    echo "${options["cosign_private_key"]}" > "$TEMP_KEY"

    # Sign the record
    if check_option_set "${options["cosign_private_key_password"]}"; then
      export COSIGN_PASSWORD="${options["cosign_private_key_password"]}"
    fi
    SIGNED_RECORD_FILE="${DIRCTL_ARTIFACTS_DIR}/signed-${RECORD_BASENAME}"
    if cat "$PROCESSED_RECORD_FILE" | dirctl sign --stdin --key "$TEMP_KEY" > "$DIRCTL_OUTPUT_LOG" 2>&1; then
      mv "$DIRCTL_OUTPUT_LOG" "$SIGNED_RECORD_FILE"
      echo "Successfully signed directory record"
    else
      rm -f "$TEMP_KEY"
      error_exit "Failed to sign directory record"
    fi

    rm -f "$TEMP_KEY"
    unset COSIGN_PASSWORD
    FINAL_RECORD_FILE="$SIGNED_RECORD_FILE"
  elif [[ -n "$has_signature" ]]; then
    echo "Directory record already contains signature, proceeding without signing"
    FINAL_RECORD_FILE="$PROCESSED_RECORD_FILE"

  else
    error_exit "No cosign private key provided and directory record file has no signature field. Cannot proceed, agent signature is required."
  fi

  export FINAL_RECORD_FILE
}

function push_to_directory {
  echo "Pushing directory record to directory"
  echo "Repository: $FINAL_REPOSITORY"
  echo "Endpoint: ${options["directory_endpoint"]}"
  echo "File: $FINAL_RECORD_FILE"

  # Api key authentication via environment variables
  export DIRCTL_CLIENT_ID="${options["dirctl_client_id"]}"
  export DIRCTL_CLIENT_SECRET="${options["dirctl_secret"]}"
  echo "Executing: dirctl hub --server-address ${options["directory_endpoint"]} push --no-cache $FINAL_REPOSITORY $FINAL_RECORD_FILE"

  if dirctl hub \
    --server-address "${options["directory_endpoint"]}" \
    push \
    --no-cache \
    "$FINAL_REPOSITORY" \
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
  for option in directory_endpoint dirctl_client_id dirctl_secret record_file; do
    if [[ -z "${options[$option]}" ]]; then
      error_exit "$option is required but not provided"
    fi
  done

  echo "Starting Agent Directory Push"
  process_record
  sign_record
  push_to_directory
  cleanup
  echo "Agent Directory Push completed successfully!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

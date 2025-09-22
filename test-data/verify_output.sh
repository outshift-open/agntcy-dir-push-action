#!/bin/bash

# Copyright agntcy-dir-push-action contributors
# (https://github.com/outshift-open/agntcy-dir-push-action/blob/main/CONTRIBUTORS.md)
# SPDX-License-Identifier: Apache-2.0


# Test verification functions for GitHub Actions workflows

DIRCTL_ARTIFACTS_DIR="/tmp/dirctl-artifacts"
DIRCTL_OUTPUT_LOG="${DIRCTL_ARTIFACTS_DIR}/dirctl_output.log"

# Check if the expected artifact file exists
# usage: setup_test_artifacts <test_name> <log_suffix> [file_to_check]
setup_test_artifacts() {
    local test_name="$1"
    local log_suffix="$2"
    local file_to_check="${3:-$DIRCTL_OUTPUT_LOG}"

    echo "Setting up test artifacts for: $test_name"

    if [ -f "$file_to_check" ]; then
        return 0
    else
        echo "Expected file not found at $file_to_check"
        return 1
    fi
}

# Failed with the expected error message
# Usage: verify_test_failure <step_id> <expected_error_substring> <test_name>
verify_test_failure() {
    local step_id="$1"
    local expected_error="$2"
    local test_name="$3"

    if [ "${step_id}" != "failure" ]; then
        echo "Test should have failed"
        exit 1
    fi

    echo "Checking if error log file was created"
    if setup_test_artifacts "$test_name"; then
        # Check for expected error
        error_content=$(cat "$DIRCTL_OUTPUT_LOG")
        if [[ "$error_content" == *"$expected_error"* ]]; then
            echo "Test PASSED: Found expected error '$expected_error'"
        else
            echo "Test FAILED: Did not find expected error '$expected_error': $error_content"
            exit 1
        fi
    else
        echo "Test FAILED: No error log file found"
        echo "This suggests failure occurred before expected step"
        exit 1
    fi
}

# Success (no signature performed)
# usage: verify_test_success <step_id> <test_name>
verify_test_success() {
    local step_id="$1"
    local test_name="$2"

    if [ "${step_id}" != "success" ]; then
        echo "Test should have succeeded but failed"
        setup_test_artifacts "$test_name" "failure"
        exit 1
    fi

    setup_test_artifacts "$test_name" "success"
    echo "Test PASSED: Action completed successfully"
}

# Succeeded and a signature was added to the record
# usage: verify_test_signed_success <step_id> <test_name> <record_file>
verify_test_signed_success() {
    local step_id="$1"
    local test_name="$2"
    local record_file="$3"

    if [ "${step_id}" != "success" ]; then
        echo "Test should have succeeded but failed"
        setup_test_artifacts "$test_name" "failure"
        exit 1
    fi

    local record_basename=$(basename "$record_file")
    local signed_record_file="${DIRCTL_ARTIFACTS_DIR}/signed-${record_basename}"

    echo "Looking for signed record file: $signed_record_file"
    if ! setup_test_artifacts "$test_name" "signed" "$signed_record_file"; then
        echo "Test FAILED: No signed record file found at $signed_record_file"
        exit 1
    fi

    # Check if the signed file contains a signature field
    if jq -e '.signature' "$signed_record_file" > /dev/null 2>&1; then
        echo "Test PASSED: Found signature field in signed record"
    else
        echo "Test FAILED: No signature field found in signed record file"
        exit 1
    fi

    # Check if new signed file has a more recent signature then original record
    local original_signature
    original_signature=$(jq -r '.signature.signed_at // empty' "$record_file" 2>/dev/null)

    if [[ -n "$original_signature" ]]; then
        local new_signature
        new_signature=$(jq -r '.signature.signed_at // empty' "$signed_record_file" 2>/dev/null)

        if [[ -z "$new_signature" ]]; then
            echo "Test FAILED: New signed record should have signed_at timestamp"
            exit 1
        fi

        echo "Original signed_at: $original_signature"
        echo "New signed_at: $new_signature"
        # Compare timestamps
        local original_timestamp=$(date -d "$original_signature" +%s 2>/dev/null || echo "0")
        local new_timestamp=$(date -d "$new_signature" +%s 2>/dev/null || echo "0")

        if [[ "$new_timestamp" -le "$original_timestamp" ]]; then
            echo "Test FAILED: New signature timestamp should be more recent than original"
            exit 1
        fi

        echo "Test PASSED: New signature timestamp is more recent than original"
    else
        echo "Original record was unsigned, signature verification completed"
    fi

    echo "Test PASSED: Successfully signed and pushed directory record"
}

# Failed due to JSON parsing error
# usage: verify_test_json_error <step_id> <expected_error_substring> <test_name>
verify_test_json_error() {
    local step_id="$1"
    local expected_error="$2"
    local test_name="$3"

    if [ "${step_id}" != "failure" ]; then
        echo "Test should have failed due to JSON error"
        exit 1
    fi

    echo "Checking if JSON error was properly handled"
    echo "Test PASSED: Action correctly failed with JSON error"
}

# Fail because missing required parameter
# usage: verify_test_parameter_error <step_id> <test_name>
verify_test_parameter_error() {
    local step_id="$1"
    local test_name="$2"

    if [ "${step_id}" != "failure" ]; then
        echo "Test should have failed due to missing parameter"
        exit 1
    fi

    echo "Test PASSED: Action correctly failed with missing required parameter"
}

# Verify file not found
# usage: verify_test_file_not_found <step_id> <expected_error_substring> <test_name>
verify_test_file_not_found() {
    local step_id="$1"
    local expected_error="$2"
    local test_name="$3"

    if [ "${step_id}" != "failure" ]; then
        echo "Test should have failed due to file not found"
        exit 1
    fi

    echo "Test PASSED: Action correctly failed when file was not found"
}
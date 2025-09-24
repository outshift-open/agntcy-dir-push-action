# Agent Directory Sign and Push Action

![GitHub Release (latest by date)](https://img.shields.io/github/v/release/outshift-open/agntcy-dir-push-action)
[![Tests](https://github.com/outshift-open/agntcy-dir-push-action/actions/workflows/test-signing-and-pushing.yml/badge.svg?branch=main)](https://github.com/outshift-open/agntcy-dir-push-action/actions/workflows/test-signing-and-pushing.yml)
[![License](https://img.shields.io/github/license/outshift-open/agntcy-dir-push-action)](LICENSE.md)

Push records to your [Agent Directory](https://agent-directory.outshift.com) using the [dirctl CLI](https://github.com/agntcy/dir).

## How It Works

The action prepares the `dirctl` CLI for your runner's environment and **processes your record file**, applying any specified overrides for organization, name, or version. It then smartly **handles the record's signature** before **pushing the final version** to your specified Agent Directory.


## Features

- **Downloads** the correct `dirctl` binary for your runner's OS and architecture.
- **Pushes** records that are already signed.
- **Signs** unsigned records on-the-fly using a provided Cosign key.
- **Re-signs** an already signed record with a new key.
- Dynamically **overrides** `organization_name`, `record_name`, and `record_version` at runtime.
- Uses GitHub **secrets** for API keys and signing credentials.
- Automatically provides GitHub action **artifacts** for easy troubleshooting.

## Supported Platforms

- Linux (amd64, arm64)
- macOS (amd64, arm64)

## Prerequisites

### Agent Directory API Credentials

You'll need **API Key credentials** for your Agent Directory instance. Follow these steps to generate them:

1. **Login to your Agent Directory:**
   ```bash
   dirctl hub login
   ```

2. **Create an API key for your organization:**
   ```bash
   dirctl hub apikey create --role ROLE_ORG_ADMIN --org-name your_org_name
   ```

   Choose the appropriate role for your needs:
   - `ROLE_ORG_ADMIN` - Full administration (can delete organization)
   - `ROLE_ADMIN` - Administrative privileges
   - `ROLE_EDITOR` - Write access
   - `ROLE_VIEWER` - Read-only access


> **Important**: The `name` field in your directory record file must always be in the format `"my-org/my-record"`. The organization part (`my-org`) must match the `--org-name` used to create the API key. If they differ, use the `organization_name` input to override it.

3. **Extract the credentials:**

   The command will output your `client_id`:
   ```
   API Key created successfully:
   {
     "client_id": "abcd1234-56ef-78gh-90ij-klmnopqrstuv@ak.example.io",
     "role_name": "ROLE_ORG_ADMIN"
   }
   ```

   The `secret` (base64 encoded) can be found in your session file:
   - Location: `~/.dirctl/session.json`
   - Path: `[hub_sessions][your-directory-url][api_key_access][secret]`

4. **Add them as GitHub secrets in your repository:**

   Create secrets with any names you prefer, for example:
   - `AGENT_DIRECTORY_CLIENT_ID`
   - `AGENT_DIRECTORY_SECRET`

>**Important:** The GitHub action secret names you choose must match the input parameters in your workflow.

### Cosign Private Key (Optional)

To sign your directory records during the push:

1. Generate a Cosign keypair (`cosign generate-key-pair`) or use an existing one
2. Add the private key content as a GitHub secret with any name you prefer (e.g., `COSIGN_PRIVATE_KEY`)
3. If your key is encrypted, add the password as another secret (e.g., `COSIGN_PRIVATE_KEY_PASSWORD`)

The private key should be in the format:
```
-----BEGIN ENCRYPTED SIGSTORE PRIVATE KEY-----
your-private-key-content-here
-----END ENCRYPTED SIGSTORE PRIVATE KEY-----
```

>**Note:** You can sign the record with `dirctl` **locally** by executing:\
> `cat your-record.json | dirctl hub sign --stdin --key cosign.key > signed-record.json`

### Directory Record File

Your directory record JSON file **must be present in your repository**. You can place it anywhere in your repository structure (e.g., `./records/my-record.json`).

## Override Behavior

The action supports overriding specific fields in your **record file** by providing the following inputs to the GitHub action:

- `organization_name` overrides the organization part of the `name` field.
- `record_name` overrides the record name part of the `name` field.
- `record_version` overrides the `version` field.


> **Organization Matching**: The organization in your directory record (or the overridden organization) must match the organization used when creating your API key. If your API key was created with `--org-name my-company`, then your directory record must have `"name": "my-company/record-name"` or you must override it with `organization_name: "my-company"`.

Override Example:
- API key created with: `--org-name my-company`
- Original record: `"name": "old-org/old-record", "version": "1.0"`
- With overrides: `organization_name: "my-company"`, `record_version: "2.0"`
- Final record: `"name": "my-company/old-record", "version": "2.0"`


## Usage Examples

**Runner Compatibility:** This action works on any GitHub Actions runner. The examples below use `ubuntu-latest`, but you can use `macos-latest`, `alpine-latest`, or any other runner. The action automatically downloads the appropriate dirctl binary.

### Basic Usage (Pre-signed Record)

```yaml
name: Push Agent to Directory
on: push
jobs:
  push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Push Directory Record
        uses: outshift-open/agntcy-dir-push-action@v1
        with:
          dirctl_client_id: ${{ secrets.AGENT_DIRECTORY_CLIENT_ID }}
          dirctl_secret: ${{ secrets.AGENT_DIRECTORY_SECRET }}
          record_file: "./records/my-record-signed.json"
```

### With On-the-fly Signing

```yaml
name: Push and Sign Record
on: push
jobs:
  push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Push Signed Directory Record
        uses: outshift-open/agntcy-dir-push-action@v1
        with:
          dirctl_client_id: ${{ secrets.MY_CLIENT_ID }}
          dirctl_secret: ${{ secrets.MY_SECRET }}
          record_file: "./records/my-record.json"
          cosign_private_key: ${{ secrets.MY_COSIGN_KEY }}
          cosign_private_key_password: ${{ secrets.MY_COSIGN_PASSWORD }}
```

### With Override Parameters

```yaml
name: Push Record with Overrides
on: push
jobs:
  push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Push Record with Custom Values
        uses: outshift-open/agntcy-dir-push-action@v1
        with:
          dirctl_client_id: ${{ secrets.DIRECTORY_CLIENT }}
          dirctl_secret: ${{ secrets.DIRECTORY_SECRET }}
          record_file: "./record-template.json"
          organization_name: "my-org"
          record_name: "my-custom-record"
          record_version: "${{ github.sha }}"
          cosign_private_key: ${{ secrets.SIGNING_KEY }}
```

### Custom Agent Directory Endpoint

```yaml
name: Push to Custom Directory
on: push
jobs:
  push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Push to Custom Directory
        uses: outshift-open/agntcy-dir-push-action@v1
        with:
          directory_endpoint: "https://my-custom-directory.example.com"
          dirctl_client_id: ${{ secrets.CUSTOM_DIRECTORY_CLIENT_ID }}
          dirctl_secret: ${{ secrets.CUSTOM_DIRECTORY_SECRET }}
          record_file: "./my-record.json"
```

## Input Parameters

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `directory_endpoint` | The Agent Directory SaaS endpoint URL | No | `https://agent-directory.outshift.com` |
| `dirctl_client_id` | Client ID for Agent Directory API key authentication | Yes | - |
| `dirctl_secret` | Secret for Agent Directory API key authentication | Yes | - |
| `record_file` | Path to the JSON file containing the directory record to push (relative to repository root) | Yes | - |
| `organization_name` | Override the organization name in the record file (keep `record_name` as written in record file) | No | - |
| `record_name` | Override the record name in the record file (keep `organization_name` as written in record file) | No | - |
| `record_version` | Override the version in the record file | No | - |
| `cosign_private_key` | Cosign private key content for signing | No | - |
| `cosign_private_key_password` | Password for encrypted cosign private key | No | - |
| `dirctl_version` | Version of dirctl to download and use | No | `v0.3.0` |

## Directory Record File Format

Your directory record file should be a JSON file stored in your repository following this structure:

```json
{
  "name": "organization/record-name",
  "version": "1.0.0",
  "description": "Description of your AI agent",
  "schema_version": "0.7.0",
  "skills": [
    {
      "class_uid": 10201
    }
  ],
  "locators": [
    {
      "type": "package-source-code",
      "url": "https://github.com/example/my-record"
    }
  ]
}
```

### With Existing Signature (Example)

If your record is already signed, include the signature block:

```json
{
  "name": "organization/record-name",
  "version": "1.0.0",
  "description": "Description of your AI agent",
  "schema_version": "0.7.0",
  "skills": [
    {
      "class_uid": 10201
    }
  ],
  "locators": [
    {
      "type": "package-source-code",
      "url": "https://github.com/example/my-record"
    }
  ],
  "signature": {
    "algorithm": "SHA2_256",
    "signature": "abcdef123456789example0123456789abcdef123456789example0123456789abcd",
    "content_type": "application/vnd.dev.sigstore.bundle.v0.3+json",
    "content_bundle": "CoNtEnTbUnDlE...",
    "signed_at": "2025-01-02T03:04:05Z"
  }
}
```

## Error Handling

The action will fail with clear error messages in these scenarios:

- Directory record file not found
- Invalid JSON in directory record file
- Missing required `name` field in directory record
- Invalid name format (must be `organization/record-name`)
- No signing key provided and no existing signature in record
- **Organization mismatch between API key and directory record**
- Failed to download dirctl for your platform
- Failed to sign the record
- Failed to push to the directory

## Artifacts and Debugging

The action generates artifacts during execution that can be useful for debugging or retrieving processed files.

### Available Artifacts

When the action runs, it creates the following files in the artifacts directory (`/tmp/dirctl-artifacts/`):

- **`processed-{filename}.json`** - Your original record file with any overrides applied (organization, record name, version)
- **`signed-{filename}.json`** - The signed version of your record (only if signing was performed)
- **`dirctl_output.log`** - Complete output from dirctl commands for debugging

### Downloading Artifacts

To access these files after your workflow runs:

1. Go to your GitHub Actions run
2. Scroll down to the "Artifacts" section
3. Download the artifacts for the specific test

## Troubleshooting

### Using Artifacts for Debugging

If your workflow fails, download the artifacts to inspect logs, processed and signed records.

### Organization Mismatch Error

If you receive an error during push, it might be due to organization mismatch:

**Problem**: Your API key was created for organization `company-a` but your directory record has `"name": "company-b/my-record"`

**Solution**: Either:
1. **Override the organization** in your workflow:
   ```yaml
   - name: Push Directory Record
     uses: outshift-open/agntcy-dir-push-action@v1
     with:
       dirctl_client_id: ${{ secrets.AGENT_DIRECTORY_CLIENT_ID }}
       dirctl_secret: ${{ secrets.AGENT_DIRECTORY_SECRET }}
       record_file: "./my-record.json"
       organization_name: "company-a"  # Override to match API key
   ```

2. **Create a new API key** for the correct organization:
   ```bash
   dirctl hub apikey create --role ROLE_ORG_ADMIN --org-name company-b
   ```

3. **Update your directory record file** to use the correct organization:
   ```
   {
     "name": "company-a/my-record",
     ...
   }
   ```

### Record Already Exists Error

If you receive a `unique constraint` error, it means you are trying to push a record with a **name and version that already exists** in the organization.

**Solution**: You must provide a unique version for each push. You can either:

1.  **Update** the record **version** either by modifying the `version` field in your **record file** before pushing, or by **overriding it dynamically** in your **workflow**:
    ```yaml
    - name: Push record with updated version
      uses: outshift-open/agntcy-dir-push-action@v1
      with:
        dirctl_client_id: ${{ secrets.AGENT_DIRECTORY_CLIENT_ID }}
        dirctl_secret: ${{ secrets.AGENT_DIRECTORY_SECRET }}
        record_file: "./my-record.json"
        record_version: "${{ github.sha }}" # Use commit SHA for a unique version
    ```

2.  **Change** the record **name** either in the record **file** or dynamically with the `record_name` **input**:
    ```yaml
    - name: Push record with updated name
      uses: outshift-open/agntcy-dir-push-action@v1
      with:
        dirctl_client_id: ${{ secrets.AGENT_DIRECTORY_CLIENT_ID }}
        dirctl_secret: ${{ secrets.AGENT_DIRECTORY_SECRET }}
        record_file: "./my-record.json"
        record_name: "my-new-record" # Creates a new record in the same organization
    ```

## Testing Scenarios

- **Authentication failure testing** - Validates error handling with invalid credentials
- **Unsigned record handling** - Tests pushing unsigned records without signing keys
- **Pre-signed record pushing** - Validates pushing records that are already signed
- **On-the-fly signing** - Tests signing during the push process
- **Re-signing behavior** - Tests re-signing already signed records
- **Different Organization** - Tests API Key not belonging to the correct organization

> **Note:** The test workflow (`.github/workflows/test-signing-and-pushing.yml`) can be triggered manually by providing the `record_version`.

## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are greatly appreciated. For detailed contributing guidelines, please see [contributing guidelines](CONTRIBUTING.md).

## License

Distributed under Apache 2.0 License. See [Copyright Notice and License](LICENSE.md) for more information.

## Support

For issues related to this GitHub Action, please open an issue in this repository.

For issues related to the Agent Directory service or dirctl CLI, please refer to the [dirctl documentation](https://github.com/agntcy/dir).


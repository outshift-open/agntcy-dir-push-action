# Agent Directory Push Action

![GitHub Release (latest by date)](https://img.shields.io/github/v/release/outshift-open/agntcy-dir-push-action)
[![Tests](https://github.com/outshift-open/agntcy-dir-push-action/actions/workflows/test-signing-and-pushing.yml/badge.svg?branch=main)](https://github.com/outshift-open/agntcy-dir-push-action/actions/workflows/test-signing-and-pushing.yml)
[![License](https://img.shields.io/github/license/outshift-open/agntcy-dir-push-action)](LICENSE.md)

Push [OASF](https://github.com/agntcy/oasf) records to the [Hosted Outshift Agent Directory](https://agent-directory.outshift.com) using the [dirctl CLI](https://github.com/agntcy/dir).

## How It Works

This GitHub Action streamlines the process of publishing your AI agents to the Agent Directory:

*  **Environment Setup**: Automatically downloads and configures the correct `dirctl` CLI binary (v0.5.0+) for your runner's OS and architecture
*  **Record Processing**: Reads your agent record file and applies runtime overrides (record name, version)
*  **Secure Push**: Pushes the record to the specified organization using authenticated API credentials
*  **Optional Signing**: If a Cosign private key is provided, signs the record after push using the returned CID
*  **Secret Handling**: Uses GitHub secrets for API keys and signing credentials
*  **Troubleshooting**: Automatically provides artifacts for debugging

## Supported Platforms

- Linux (amd64, arm64)
- macOS (amd64, arm64)

## Prerequisites

### Agent Directory API Credentials

You'll need **API Key credentials** for your Agent Directory instance:

1. **Login to your Agent Directory:**
   ```bash
   dirctl hub login
   ```

2. **Create an API key for your organization:**
   ```bash
   dirctl hub apikey create --role ROLE_ORG_ADMIN --org-name your_org_name
   ```

   Choose the appropriate role:
   - `ROLE_ORG_ADMIN` - Full administration
   - `ROLE_ADMIN` - Administrative privileges
   - `ROLE_EDITOR` - Write access
   - `ROLE_VIEWER` - Read-only access

   The command outputs:
   ```
   DIRCTL_CLIENT_ID=3603e7f1-6903-44ec-868e-b78fab3cf43f@ak.eticloud.io
   DIRCTL_CLIENT_SECRET=*********************************************
   ```

1. **Add them as GitHub secrets in your repository:**

   Create secrets with any names you prefer, for example:
   - `AGENT_DIRECTORY_CLIENT_ID`
   - `AGENT_DIRECTORY_SECRET`

>**Important:** The GitHub action secret names you choose must match the input parameters in your workflow.

### Cosign Private Key (Optional)

To sign records after push:

1. Generate a Cosign keypair (`cosign generate-key-pair`) or use an existing one
2. Add the private key as a GitHub secret (e.g., `COSIGN_PRIVATE_KEY`)
3. If encrypted, add the password as a secret (e.g., `COSIGN_PASSWORD`)

Private key format:
```
-----BEGIN ENCRYPTED SIGSTORE PRIVATE KEY-----
your-private-key-content-here
-----END ENCRYPTED SIGSTORE PRIVATE KEY-----
```

### Directory Record File

Your directory record JSON file **must be present in your repository**. You can place it anywhere in your repository structure (e.g., `./records/my-record.json`).

**Record format:**
```json
{
  "name": "my-record-name",
  "version": "1.0.0",
  "description": "My agent description",
  "skills": [],
  "locators": [],
  "authors": [
    "author"
  ],
  "created_at": "2025-01-01T09:01:01.017Z",
}
```

> **Important**: The `name` field contains **only the record name**. The organization is specified separately via the `organization_name` input parameter.

## Input Parameters

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `directory_endpoint` | Agent Directory endpoint URL | No | `https://agent-directory.outshift.com` |
| `dirctl_client_id` | Client ID for API key authentication | **Yes** | - |
| `dirctl_secret` | Secret for API key authentication | **Yes** | - |
| `record_file` | Path to JSON record file (relative to repo root) | **Yes** | - |
| `organization_name` | Organization where to push the record | **Yes** | - |
| `record_name` | Override the `name` field in the record file | No | - |
| `record_version` | Override the `version` field in the record file | No | - |
| `cosign_private_key` | Cosign private key for signing (optional) | No | - |
| `cosign_private_key_password` | Password for encrypted private key | No | - |
| `dirctl_version` | Version of dirctl to use | No | `v0.5.0-rc.3` |

## Usage Examples

### Basic Push (No Signing)

```yaml
name: Push Agent to Directory
on: push
jobs:
  push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Push Directory Record
        uses: outshift-open/agntcy-dir-push-action@v2
        with:
          organization_name: "my-org"
          dirctl_client_id: ${{ secrets.AGENT_DIRECTORY_CLIENT_ID }}
          dirctl_secret: ${{ secrets.AGENT_DIRECTORY_SECRET }}
          record_file: "./records/my-record.json"
```

### Push with Signing

```yaml
name: Push and Sign Record
on: push
jobs:
  push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Push and Sign Directory Record
        uses: outshift-open/agntcy-dir-push-action@v2
        with:
          organization_name: "my-org"
          dirctl_client_id: ${{ secrets.AGENT_DIRECTORY_CLIENT_ID }}
          dirctl_secret: ${{ secrets.AGENT_DIRECTORY_SECRET }}
          record_file: "./records/my-record.json"
          cosign_private_key: ${{ secrets.COSIGN_PRIVATE_KEY }}
          cosign_private_key_password: ${{ secrets.COSIGN_PASSWORD }}
```

### With Runtime Overrides

```yaml
name: Push with Dynamic Version
on: push
jobs:
  push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Push Record with Commit SHA Version
        uses: outshift-open/agntcy-dir-push-action@v2
        with:
          organization_name: "my-org"
          dirctl_client_id: ${{ secrets.AGENT_DIRECTORY_CLIENT_ID }}
          dirctl_secret: ${{ secrets.AGENT_DIRECTORY_SECRET }}
          record_file: "./records/template.json"
          record_name: "my-custom-agent"
          record_version: "${{ github.sha }}"
```

### Custom Directory Endpoint

```yaml
name: Push to Self-Hosted Directory
on: push
jobs:
  push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Push to Custom Directory
        uses: outshift-open/agntcy-dir-push-action@v2
        with:
          directory_endpoint: "https://my-directory.example.com"
          organization_name: "my-org"
          dirctl_client_id: ${{ secrets.CUSTOM_DIRECTORY_CLIENT_ID }}
          dirctl_secret: ${{ secrets.CUSTOM_DIRECTORY_SECRET }}
          record_file: "./my-record.json"
```

## How Signing Works

With dirctl v0.5.0+, signing happens **after** the push:

1. **Push**: Record is pushed to the directory, which returns a **CID** (Content Identifier)
2. **Sign** (optional): If `cosign_private_key` is provided, the returned CID is used for signing by running the follwing command:
   ```bash
   dirctl hub sign <org-name> <cid> --key <private-key>
   ```

This means:
- Records can be pushed **without** signatures
- Signing is **optional**
- You can sign records **after** they're published

## Error Handling

The action fails with clear messages for:

- Directory record file not found
- Invalid JSON in record file
- Missing required `name` or `version` fields in directory record
- Authentication failure given to invalid API key
- Organization mismatch when API the key is for different org
- Record already exists (duplicate CID)
- Failed to download dirctl binary
- Failed to sign record, if signing key is provided

## Artifacts and Debugging

Artifacts are created in `/tmp/dirctl-artifacts/`:

- **`processed-{filename}.json`** - Record file with overrides applied
- **`dirctl_output.log`** - Push command output, which includes CID
- **`dirctl_sign_output.log`** - Sign command output, if signing performed

To download artifacts:
1. Go to your GitHub Actions run
2. Scroll to "Artifacts" section
3. Download the artifacts

## Troubleshooting

### Record Already Exists

**Error**: `AlreadyExists` - record with same name and version exists.

**Solution**: Use a unique version for each push:

```yaml
- uses: outshift-open/agntcy-dir-push-action@v2
  with:
    # ...other inputs...
    record_version: "${{ github.sha }}"  # Unique per commit
```

### Organization Mismatch

**Error**: `API key does not belong to the organization`

**Solution**: Ensure the `organization_name` input matches the organization used when creating the API key:

```bash
# API key created with:
dirctl hub apikey create --org-name company-a

# Workflow must use:
organization_name: "company-a"  # Must match!
```

### Sign Failure

**Error**: `Failed to sign directory record`

**Possible causes**:
- Invalid Cosign private key format
- Wrong password for encrypted key
- Network issues connecting to directory

**Solution**: Verify your `COSIGN_PRIVATE_KEY` secret contains the complete key including `-----BEGIN` and `-----END` markers.

## Testing Scenarios

The action includes comprehensive tests:

- Authentication with fake credentials (failure expected)
- Push without signing (success)
- Push with signing (success)
- Push with wrong password (push succeeds, sign fails)
- Push duplicate record (failure expected)
- Push to wrong organization (failure expected)
- Invalid JSON handling
- Missing required parameters

Run tests manually:
```bash
gh workflow run test-signing-and-pushing.yml -f record_version="test-$(date +%s)"
```

## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are greatly appreciated. For detailed contributing guidelines, please see [contributing guidelines](CONTRIBUTING.md).

## License

Distributed under Apache 2.0 License. See [Copyright Notice and License](LICENSE.md) for more information.

## Support

For issues related to this GitHub Action, please open an issue in this repository.

For issues related to the Agent Directory service or dirctl CLI, please refer to the [dirctl documentation](https://github.com/agntcy/dir).


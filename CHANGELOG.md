# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0]

### Breaking Changes

- **Signature Architecture**: Signing now happens **after** push using the returned CID, not before
- **Signature Optionality**: Record signatures are now **optional**, records can be pushed without signing
- **Organization Parameter**: `organization_name` is now **required** (was optional in v1)
- **Record Format**: Record file `name` field now contains only the record name (no `org/` prefix)
- **Minimum dirctl Version**: Requires dirctl v0.5.0 or higher (v0.3.0-v0.4.0 no longer supported)

### Added

- Post-push signing workflow using CID returned from push command
- Support for pushing unsigned records (signature completely optional)
- New `dirctl hub sign <org> <cid> --key <key>` command integration
- Improved test coverage for new signing scenarios

### Changed

- Default dirctl version updated to `v0.5.1`
- Push command now: `dirctl hub push --no-cache <org> <file>`
- Sign command now: `dirctl hub sign --no-cache <org> <cid> --key <key>`
- Error messages updated to match dirctl v0.5.0+ format (`AlreadyExists` vs old format)

### Removed

- Pre-signed record validation logic (signatures no longer embedded in files before push)
- Organization/record name parsing from `name` field (now separate parameters)
- Tests for pre-signed records (no longer relevant with new architecture)


### Migration Guide

To migrate from v1 to v2:

1. **Update action version** in workflows: `@v1` to `@v2`
2. **Add `organization_name`** parameter (now required):
   ```yaml
   - uses: outshift-open/agntcy-dir-push-action@v2
     with:
       organization_name: "my-org"  # NEW: Required parameter
   ```
3. **Update record files**: Change `"name": "org/record"` to `"name": "record"`
4. **Optional**: Remove `cosign_private_key` if you don't need signing since it's now optional

## [1.0.0]

### Added

- Initial release of Agent Directory Sign and Push Action
- Support for pushing records to Agent Directory using dirctl CLI v0.3.0-v0.4.0
- Automatic dirctl binary download for Linux and macOS (amd64, arm64)
- Pre-push signing with Cosign private keys
- Support for pushing pre-signed records
- Re-signing capability for already signed records
- Dynamic override support for organization name, record name, and version
- GitHub secrets integration for API keys and signing credentials
- Automatic artifact generation for debugging and troubleshooting
- Error handling and validation
- Support for custom Agent Directory endpoints
- Test suite covering signing and pushing scenarios

[2.0.0]: https://github.com/outshift-open/agntcy-dir-push-action/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/outshift-open/agntcy-dir-push-action/releases/tag/v1.0.0

# Changelog

## 1.0.0 (2025-09-19)

### Feat

- Initial release of Agent Directory Sign and Push Action
- Support for pushing records to Agent Directory using dirctl CLI
- Automatic dirctl binary download for Linux and macOS (amd64, arm64)
- On-the-fly signing of unsigned records using Cosign private keys
- Support for pushing pre-signed records
- Re-signing capability for already signed records
- Dynamic override support for organization name, record name, and version
- GitHub secrets integration for API keys and signing credentials
- Automatic artifact generation for debugging and troubleshooting
- Error handling and validation
- Support for custom Agent Directory endpoints
- Test suite covering signing and pushing scenarios

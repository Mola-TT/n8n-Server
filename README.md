# n8n Server Initialization Scripts

Ubuntu scripts for initializing an n8n server. The scripts are developed on Windows but deployed on Ubuntu systems.

## Quick Start

1. **Configure your environment** (optional):
   ```bash
   cp conf/user.env.template conf/user.env
   # Edit conf/user.env with your specific settings
   ```

2. **Run the initialization**:
   ```bash
   sudo ./init.sh
   ```

## Project Structure

```
├── init.sh                    # Main initialization script
├── conf/
│   ├── default.env           # Default configuration values
│   └── user.env.template     # Template for user customization
├── lib/
│   ├── logger.sh            # Color-coded logging system
│   └── utilities.sh         # Helper functions
├── setup/
│   └── general_config.sh    # System configuration functions
└── test/
    └── run_tests.sh         # Test runner for validation
```

## Configuration

- **Default settings**: `conf/default.env` - Contains default values for all configuration
- **User overrides**: `conf/user.env` - Optional file for user-specific settings (copy from template)
- **Environment loading**: The script automatically loads default settings first, then overrides with user settings if available

## Milestone 1 Features

- ✅ Silent Ubuntu server updates
- ✅ Timezone configuration
- ✅ Root privilege checking
- ✅ Automatic script permission management
- ✅ Environment variable loading with override capability
- ✅ Color-coded logging with file output
- ✅ Utility functions for system operations
- ✅ Test suite for validation

## Usage

The `init.sh` script:
1. Makes all scripts in lib/, setup/, and test/ directories executable
2. Updates system packages silently
3. Sets timezone from configuration
4. Loads environment variables (defaults + user overrides)
5. Runs tests to validate the setup

## Development Notes

- **Minimal Code** – No unnecessary complexity
- **Direct Implementation** – Shortest and clearest approach
- **Single Source of Truth** – All configuration in main scripts
- **No Hotfixes** – All fixes implemented directly in main scripts 
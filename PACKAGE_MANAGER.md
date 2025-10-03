# Mint Package Manager

A package manager for the Mint framework that provides easy installation, updating, and management of Mint modules.

## Overview

The Mint Package Manager simplifies the process of installing and managing modules for the Mint framework. It provides a standardized way to:

- Install modules from a central repository
- Update installed modules to newer versions
- Remove modules that are no longer needed
- Manage module dependencies automatically

## Directory Structure

When you install a package, it creates the following structure:

```
mint/
├── <package-name>.lua            # Launcher script for easy access
├── .mint-package/                # Package code directory
│   └── <package-name>/           # Contains all package files
├── .config/                      # Configuration files
│   ├── configs/                  # User configurations
│   └── templates/                # Configuration templates
└── .cache/mint-package/          # Package metadata and cache
```

## Usage

### Installing a Package

```
$ lua mint-package.lua install <package-name>
```

This will:
1. Download the package and its dependencies
2. Create a launcher script in the root directory
3. Install configuration templates
4. Set up any required directories

### Updating a Package

```
$ lua mint-package.lua update <package-name>
```

or update all installed packages:

```
$ lua mint-package.lua update all
```

### Removing a Package

```
$ lua mint-package.lua remove <package-name>
```

### Listing Installed Packages

```
$ lua mint-package.lua list
```

### Searching for Available Packages

```
$ lua mint-package.lua search <query>
```

### Getting Package Information

```
$ lua mint-package.lua info <package-name>
```

## Package Manifest Format

Packages are defined in a central repository using a JSON manifest file. Here's an example of a package definition:

```json
{
  "name": "miner",
  "version": "1.0.0",
  "description": "Automated mining turtle module",
  "author": "aceh",
  "tags": ["turtle", "mining"],
  "dependencies": ["tunnel"],
  "launcher": "main",
  "files": [
    {
      "path": "miner/main.lua",
      "description": "Main entry point"
    }
  ],
  "templates": [
    {
      "name": "state",
      "filename": "miner.state.template",
      "description": "Miner state configuration"
    }
  ],
  "usage": "Run 'miner' to start mining operations"
}
```

## Creating a Package

To create your own package:

1. Organize your code following the standard structure
2. Create a package definition in the manifest format
3. Create configuration templates for any settings
4. Submit a pull request to the package repository

## Integration with Mint Configuration System

The package manager is integrated with Mint's configuration system. When a package is installed:

1. Its configuration templates are placed in the templates directory
2. When a module loads a config, it's automatically created from the template if needed
3. Configuration files are stored in `.config/configs/<module-name>/`

## License

MIT License
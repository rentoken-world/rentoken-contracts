# RenToken Contracts

Smart contracts for the RenToken project.

## Development Setup

### Prerequisites

- Python 3.7+ (for pre-commit)
- pip (Python package manager)

### Installation

1. Install pre-commit:

```bash
pip install pre-commit
# or on macOS with Homebrew:
# brew install pre-commit
```

1. Install the pre-commit hooks:

```bash
pre-commit install
```

1. (Optional) Run pre-commit on all files:

```bash
pre-commit run --all-files
```

## Pre-commit Hooks

The following checks run automatically before each commit:

- **Trailing whitespace removal** - Removes trailing whitespace from files
- **End-of-file fixer** - Ensures files end with a newline
- **YAML validation** - Checks YAML files for syntax errors
- **Large file check** - Prevents giant files from being committed
- **Merge conflict check** - Ensures no merge conflict markers remain
- **Case conflict check** - Prevents case-sensitivity issues
- **Markdown linting** - Lints and fixes Markdown files
- **Prettier formatting** - Formats Markdown files consistently

## Manual Formatting

To manually format files:

```bash
# Format all markdown files
pre-commit run prettier --all-files

# Lint all markdown files
pre-commit run markdownlint --all-files

# Remove trailing whitespace from all files
pre-commit run trailing-whitespace --all-files
```

## License

MIT License - see [LICENSE](LICENSE) file for details.

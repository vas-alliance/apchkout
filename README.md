# Git Advanced Checkout (`apchkout`)

A global Git tool for branch management with automatic PostgreSQL database isolation for Django projects.

## Installation

From this directory, run:

```bash
./install-apchkout.sh
```

This will:
1. Install `apchkout` to `/usr/local/bin/` making it available globally
2. Create a git alias `git apchkout` that maps to the `apchkout` command

## Requirements

All your Django projects must have:
- Standard directory structure: `project-root/django-root/`
- `.env` file at project root with database configuration
- `DJANGO_SETTINGS_MODULE` defined in `.env`
- `manage.py createdevdata` command available

## Usage

Navigate to any directory within your Django project and run:

```bash
# Using the command directly
apchkout feature/new-feature --with-db

# Or using the git alias
git apchkout feature/new-feature --with-db

# Create branch with database, or force recreate if exists
apchkout feature/existing --with-db --force

# Just checkout branch (no database changes)
apchkout feature/code-review

# List all branch databases
apchkout --list

# Clean up databases for deleted branches
apchkout --clean

# Drop a specific database
apchkout --drop {branch_name}

# Drop all branch databases
apchkout --drop --all
```

## Required variables in `.env`

```bash
DB_NAME=your_base_db_name
DB_USER=your_db_user
DB_PASSWORD=your_db_password
DB_HOST=localhost
DB_PORT=5432
DJANGO_SETTINGS_MODULE={app_name}.settings.dev
```
The library will introduce a new variable in your `.env`:
```bash
DEV_APCHKOUT_DB_NAME_BASE={original_db_name}      # Original DB name to be used as the base db name for branch-specific databases
```

## Database Naming Convention

- `master` branch → `{base_db_name}`
- `feature/new-api` → `{base_db_name}_feature_new_api`
- `fix/bug-123` → `{base_db_name}_fix_bug_123`

## Uninstall

```bash
./uninstall-apchkout.sh
```

This will remove both the global command and the git alias.

## Notes

- Command should be run from within a Django project directory
- Works with any Django project that follows the standard structure
- Database credentials are read from each project's `.env` file
- The `DEV_APCHKOUT_DB_NAME_BASE` variable stored in `.env`
- Both `apchkout` command and `git apchkout` alias work identically
- `master` branch always uses the original database name, apchkout commands have no effect on it
#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_title() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Detect project root from git repository
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"

if [ -z "$PROJECT_ROOT" ]; then
    print_error "Not in a git repository"
    print_warning "This command must be run from within a git repository"
    exit 1
fi

# Set paths relative to project root
DJANGO_ROOT="$PROJECT_ROOT/django-root"

if [ ! -d "$DJANGO_ROOT" ]; then
    print_error "django-root directory not found at $DJANGO_ROOT"
    print_warning "Make sure you're in a Django project with the standard structure"
    exit 1
fi

# Load environment variables from .env file if it exists
ENV_FILE="$PROJECT_ROOT/.env"
if [ ! -f "$ENV_FILE" ]; then
    print_error ".env file not found at $ENV_FILE"
    print_warning "Please create a .env file with database configuration"
    exit 1
fi

export $(cat "$ENV_FILE" | grep -v '^#' | xargs)

cd "$DJANGO_ROOT"

# Get database credentials from environment
DB_USER="${DB_USER}"
DB_PASSWORD="${DB_PASSWORD}"
DB_PORT="${DB_PORT:-5432}"
DB_HOST="${DB_HOST:-localhost}"

# Validate required environment variables
if [ -z "$DB_USER" ]; then
    print_error "DB_USER is not set in .env file"
    exit 1
fi

if [ -z "$DB_NAME" ] && [ -z "$DEV_APCHKOUT_DB_NAME_BASE" ]; then
    print_error "DB_NAME is not set in .env file"
    exit 1
fi

# Determine base database name
# Use DEV_APCHKOUT_DB_NAME_BASE if it exists, otherwise use current DB_NAME
if [ -n "$DEV_APCHKOUT_DB_NAME_BASE" ]; then
    BASE_DB_NAME="$DEV_APCHKOUT_DB_NAME_BASE"
else
    BASE_DB_NAME="${DB_NAME}"
fi

# Build psql connection string
PGPASSWORD="$DB_PASSWORD"
export PGPASSWORD

# Test database connection
print_info "Testing database connection..."
if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c '\q' 2>/dev/null; then
    print_error "Failed to connect to database server"
    print_error "Host: $DB_HOST, Port: $DB_PORT, User: $DB_USER"
    print_warning "Please check your database credentials in .env file"
    print_warning "Make sure PostgreSQL is running and accessible"
    exit 1
fi

# Function to list all branch databases
list_databases() {
    print_title "Branch Databases"
    echo ""

    # Get all databases that start with base_db_name
    DATABASES=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -tAc "SELECT datname FROM pg_database WHERE datname LIKE '${BASE_DB_NAME}_%' ORDER BY datname;")

    if [ -z "$DATABASES" ]; then
        print_warning "No branch databases found"
        return
    fi

    # Get current database from .env
    CURRENT_DB="${DB_NAME:-$BASE_DB_NAME}"

    echo -e "${BLUE}Current Database:${NC} $CURRENT_DB"
    echo ""
    echo -e "${BLUE}Available Branch Databases:${NC}"

    for db in $DATABASES; do
        # Extract branch name from database name
        BRANCH_NAME=$(echo "$db" | sed "s/^${BASE_DB_NAME}_//" | sed "s/fix_/fix\//g" | sed "s/feature_/feature\//g" | tr '_' '-')

        if [ "$db" = "$CURRENT_DB" ]; then
            echo -e "  ${GREEN} $db${NC} (${YELLOW}ACTIVE${NC}) → $BRANCH_NAME"
        else
            echo -e "    $db → $BRANCH_NAME"
        fi
    done

    echo ""
    print_info "Total branch databases: $(echo "$DATABASES" | wc -l | tr -d ' ')"
}

# Function to clean up old branch databases
clean_databases() {
    print_title "Clean Up Old Branch Databases"
    echo ""

    # Get all databases
    DATABASES=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -tAc "SELECT datname FROM pg_database WHERE datname LIKE '${BASE_DB_NAME}_%' ORDER BY datname;")

    if [ -z "$DATABASES" ]; then
        print_warning "No branch databases found"
        return
    fi

    # Get current database from .env
    CURRENT_DB="${DB_NAME:-$BASE_DB_NAME}"

    # Get all git branches
    GIT_BRANCHES=$(git branch -a | sed 's/^[* ]*//' | sed 's/remotes\/origin\///' | sort -u)

    echo "Checking for databases without corresponding branches..."
    echo ""

    DATABASES_TO_DELETE=""

    for db in $DATABASES; do
        # Skip current database
        if [ "$db" = "$CURRENT_DB" ]; then
            continue
        fi

        # Extract branch name from database name
        BRANCH_NAME=$(echo "$db" | sed "s/^${BASE_DB_NAME}_//" | sed "s/fix_/fix\//g" | sed "s/feature_/feature\//g" | tr '_' '-')

        # Check if branch exists
        if ! echo "$GIT_BRANCHES" | grep -q "^${BRANCH_NAME}$"; then
            echo -e "  ${RED}✗${NC} $db → Branch '$BRANCH_NAME' not found"
            DATABASES_TO_DELETE="$DATABASES_TO_DELETE $db"
        fi
    done

    if [ -z "$DATABASES_TO_DELETE" ]; then
        print_info "No orphaned databases found"
        return
    fi

    echo ""
    print_warning "The following databases will be deleted:"
    for db in $DATABASES_TO_DELETE; do
        echo "  - $db"
    done

    echo ""
    read -p "Do you want to delete these databases? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        for db in $DATABASES_TO_DELETE; do
            print_info "Dropping database: $db"
            psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$db\";"
        done
        print_info "Cleanup completed"
    else
        print_info "Cleanup cancelled"
    fi
}

# Function to drop a specific database
drop_database() {
    local DB_TO_DROP="$1"

    if [ -z "$DB_TO_DROP" ]; then
        print_error "Database name is required"
        echo "Usage: $0 --drop <database_name>"
        exit 1
    fi

    # Check if database exists
    DB_EXISTS=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_TO_DROP'")

    if [ "$DB_EXISTS" != "1" ]; then
        print_error "Database '$DB_TO_DROP' does not exist"
        exit 1
    fi

    # Get current database
    CURRENT_DB="${DB_NAME:-$BASE_DB_NAME}"

    if [ "$DB_TO_DROP" = "$CURRENT_DB" ]; then
        print_error "Cannot drop the currently active database: $DB_TO_DROP"
        print_warning "Switch to a different database first"
        exit 1
    fi

    print_warning "You are about to drop database: $DB_TO_DROP"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Dropping database: $DB_TO_DROP"
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "DROP DATABASE \"$DB_TO_DROP\";"
        print_info "Database dropped successfully"
    else
        print_info "Operation cancelled"
    fi
}

drop_all_databases() {
    print_title "Drop All Branched Databases"

    # Get all git branches
    GIT_BRANCHES=$(git branch -a | sed 's/^[* ]*//' | sed 's/remotes\/origin\///' | sort -u)

    # Get list of all databases
    local databases
    databases=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -tAc "SELECT datname FROM pg_database WHERE datname LIKE '${BASE_DB_NAME}_%';")

    if [ -z "$databases" ]; then
        print_info "No branch databases found."
        return
    fi

    local warning=false
    local warning_message=""

    # Detect if any db matches an active branch name or is used by current branch
    for db in $databases; do
        # Extract branch name from database name
        BRANCH_NAME=$(echo "$db" | sed "s/^${BASE_DB_NAME}_//" | sed "s/fix_/fix\//g" | sed "s/feature_/feature\//g" | tr '_' '-')

        if echo "$GIT_BRANCHES" | grep -q "^${BRANCH_NAME}$"; then
            warning=true
            warning_message+="• $db (has matching branch)\n"
        fi

        if [[ "$db" == "${DB_NAME:-$BASE_DB_NAME}" ]]; then
            warning=true
            warning_message+="• $db (currently active database)\n"
        fi
    done

    if [ "$warning" = true ]; then
        echo -e "\nThe following databases may be in active use or have matching Git branches:"
        echo -e "$warning_message"
        read -p $'\nAre you sure you want to delete ALL of them? (y/N): ' -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Operation aborted."
            return
        fi
    else
        read -p $'\nAre you sure you want to delete ALL branch databases? (y/N): ' -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Operation cancelled."
            return
        fi
    fi

    echo ""
    print_info "Deleting ALL branch databases..."
    for db in $databases; do
        print_info "Dropping: $db"
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$db\";"
    done

    print_info "All branch databases deleted."
}

# Function to show usage
show_usage() {
    echo "Git Advanced Checkout with Database Management"
    echo ""
    echo "Usage:"
    echo "  $0 <branch-name> [--with-db] [--force]    # Checkout/create branch"
    echo "  $0 --list                                 # List all branch databases"
    echo "  $0 --clean                                # Remove databases for deleted branches"
    echo "  $0 --drop <database_name>                 # Drop a specific database"
    echo ""
    echo "Options:"
    echo "  --with-db                       # Create/switch to branch database"
    echo "  --force                         # Force recreate database (use with --with-db)"
    echo "  --list                          # Show all branch databases"
    echo "  --clean                         # Clean up orphaned databases"
    echo "  --drop <db_name>                # Drop a specific database"
    echo "  --drop --all                    # Drops all branched databases"
    echo ""
    echo "Examples:"
    echo "  $0 feature/new-api --with-db           # Create branch and database (or switch if exists)"
    echo "  $0 feature/existing --with-db --force  # Force recreate database with fresh migrations"
    echo "  $0 feature/existing                    # Just checkout branch"
    echo "  $0 --list                              # List all databases"
    echo "  $0 --clean                             # Clean up old databases"
    echo "  $0 --drop alliance_app_feature_old     # Drop specific database"
    echo "  $0 --drop --all                        # Drop all branched databases"
}

# Parse arguments
if [ -z "$1" ]; then
    print_error "No arguments provided"
    echo ""
    show_usage
    exit 1
fi

# Handle management commands
case "$1" in
    --list)
        list_databases
        exit 0
        ;;
    --clean)
        clean_databases
        exit 0
        ;;
    --drop)
        if [ "$2" = "--all" ]; then
            drop_all_databases
            exit 0
        else
            drop_database "$2"
            exit 0
        fi
        ;;
    --help|-h)
        show_usage
        exit 0
        ;;
    --*)
        print_error "Unknown option: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac

# Normal branch checkout mode
BRANCH_NAME="$1"
CREATE_DB=false
FORCE_RECREATE=false

# Check for --with-db and --force flags
for arg in "$@"; do
    if [ "$arg" == "--with-db" ]; then
        CREATE_DB=true
    fi
    if [ "$arg" == "--force" ]; then
        FORCE_RECREATE=true
    fi
done

# Check if branch exists locally
BRANCH_EXISTS_LOCAL=$(git branch --list "$BRANCH_NAME" | wc -l | tr -d ' ')

# Check if branch exists on remote
BRANCH_EXISTS_REMOTE=$(git branch -r --list "origin/$BRANCH_NAME" | wc -l | tr -d ' ')

if [ "$BRANCH_EXISTS_LOCAL" -eq 0 ]; then
    if [ "$BRANCH_EXISTS_REMOTE" -eq 1 ]; then
        # Branch exists on remote, check it out
        print_info "Branch exists on remote, checking out: $BRANCH_NAME"
        git checkout "$BRANCH_NAME"
    else
        # Branch doesn't exist anywhere, create it
        print_info "Creating new branch: $BRANCH_NAME"
        git checkout -b "$BRANCH_NAME"
    fi
else
    # Branch exists locally, just check it out
    print_info "Checking out existing branch: $BRANCH_NAME"
    git checkout "$BRANCH_NAME"
fi

if [ "$CREATE_DB" = true ]; then
    # Generate database name from branch name
    # For master branch, use base database name without suffix
    if [ "$BRANCH_NAME" = "master" ]; then
        NEW_DB_NAME="$BASE_DB_NAME"
        print_info "Switching to base database: $NEW_DB_NAME"

        # Update .env file with base database name (no drop/recreate for master)
        if [ -f "$ENV_FILE" ]; then
            # Store the base DB name if not already stored in .env
            if ! grep -q "^DEV_APCHKOUT_DB_NAME_BASE=" "$ENV_FILE"; then
                echo "DEV_APCHKOUT_DB_NAME_BASE=$BASE_DB_NAME" >> "$ENV_FILE"
            fi

            # Update DB_NAME in .env
            TMP_ENV="$(mktemp)"
            sed "s/^DB_NAME=.*/DB_NAME=$NEW_DB_NAME/" "$ENV_FILE" > "$TMP_ENV" && mv "$TMP_ENV" "$ENV_FILE"
            print_info "Updated $ENV_FILE with DB_NAME=$NEW_DB_NAME"
        else
            echo "DEV_APCHKOUT_DB_NAME_BASE=$BASE_DB_NAME" > "$ENV_FILE"
            echo "DB_NAME=$NEW_DB_NAME" >> "$ENV_FILE"
            print_info "Created $ENV_FILE with DB_NAME=$NEW_DB_NAME"
        fi

        print_info "Switched to master branch with base database: $NEW_DB_NAME"
    else
        # Replace slashes and special characters with underscores
        SAFE_BRANCH_NAME=$(echo "$BRANCH_NAME" | sed 's/[^a-zA-Z0-9_]/_/g' | tr '[:upper:]' '[:lower:]')
        NEW_DB_NAME="${BASE_DB_NAME}_${SAFE_BRANCH_NAME}"

        # Check if database already exists
        DB_EXISTS=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$NEW_DB_NAME'")

        if [ "$DB_EXISTS" = "1" ]; then
            # Database exists
            if [ "$FORCE_RECREATE" = true ]; then
                # Force flag provided, drop and recreate
                print_warning "Database $NEW_DB_NAME already exists - dropping and recreating for fresh migrations (--force flag)"
                psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$NEW_DB_NAME\";"

                # Create new database
                print_info "Creating database: $NEW_DB_NAME"
                psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "CREATE DATABASE \"$NEW_DB_NAME\" OWNER \"$DB_USER\";"

                NEED_MIGRATIONS=true
            else
                # No force flag, just switch to existing database
                print_info "Database $NEW_DB_NAME already exists, switching to it (use --force to recreate)"
                NEED_MIGRATIONS=false
            fi
        else
            # Database doesn't exist, create it
            print_info "Creating new branch database: $NEW_DB_NAME"
            psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "CREATE DATABASE \"$NEW_DB_NAME\" OWNER \"$DB_USER\";"
            NEED_MIGRATIONS=true
        fi

        # Update .env file with new database name
        if [ -f "$ENV_FILE" ]; then
            # Store the base DB name if not already stored in .env
            if ! grep -q "^DEV_APCHKOUT_DB_NAME_BASE=" "$ENV_FILE"; then
                echo "DEV_APCHKOUT_DB_NAME_BASE=$BASE_DB_NAME" >> "$ENV_FILE"
            fi

            # Update DB_NAME in .env
            TMP_ENV="$(mktemp)"
            sed "s/^DB_NAME=.*/DB_NAME=$NEW_DB_NAME/" "$ENV_FILE" > "$TMP_ENV" && mv "$TMP_ENV" "$ENV_FILE"
            print_info "Updated $ENV_FILE with DB_NAME=$NEW_DB_NAME"
        else
            echo "DEV_APCHKOUT_DB_NAME_BASE=$BASE_DB_NAME" > "$ENV_FILE"
            echo "DB_NAME=$NEW_DB_NAME" >> "$ENV_FILE"
            print_info "Created $ENV_FILE with DB_NAME=$NEW_DB_NAME"
        fi

        if [ "$NEED_MIGRATIONS" = true ]; then
            # Reload environment variables to pick up the new DB_NAME
            export $(cat "$ENV_FILE" | grep -v '^#' | xargs)

            # Run migrations
            print_info "Running migrations on $NEW_DB_NAME"

            # Check if DJANGO_SETTINGS_MODULE is set (should be loaded from .env)
            if [ -z "$DJANGO_SETTINGS_MODULE" ]; then
                print_error "DJANGO_SETTINGS_MODULE is not set in .env file"
                print_warning "Please add DJANGO_SETTINGS_MODULE to your .env file"
                exit 1
            fi

            export DJANGO_SETTINGS_MODULE
            python manage.py migrate

            # Create dev data
            print_info "Creating development data"
            python manage.py createdevdata

            print_info "Database $NEW_DB_NAME created, migrations applied, and dev data created successfully!"
            print_info "You can now work on branch $BRANCH_NAME with database $NEW_DB_NAME"
            print_warning "Remember: Run cleanup or drop once you're done with the branch to avoid cluttering your database server."
        else
            print_info "Switched to branch database: $NEW_DB_NAME"
        fi
    fi
else
    print_info "Checked out branch: $BRANCH_NAME"

    # If checking out master without --with-db, update DB_NAME to base name
    if [ "$BRANCH_NAME" = "master" ] && [ -f "$ENV_FILE" ]; then
        if grep -q "^DEV_APCHKOUT_DB_NAME_BASE=" "$ENV_FILE"; then
            # Get the base DB name
            STORED_BASE_NAME=$(grep "^DEV_APCHKOUT_DB_NAME_BASE=" "$ENV_FILE" | cut -d'=' -f2)

            # Update DB_NAME to base name
            TMP_ENV="$(mktemp)"
            sed "s/^DB_NAME=.*/DB_NAME=$STORED_BASE_NAME/" "$ENV_FILE" > "$TMP_ENV" && mv "$TMP_ENV" "$ENV_FILE"

            print_info "Reverted to base database: $STORED_BASE_NAME"
        fi
    else
        print_info "--with-db not set, no changes to database configuration made."
        print_info "Using database: ${DB_NAME}"
    fi
fi

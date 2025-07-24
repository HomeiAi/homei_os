#!/bin/bash
# Homie OS Variable Loader
# This script loads configuration variables from the central config file

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/config/variables.conf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to load variables from config file
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}ERROR: Configuration file not found: $CONFIG_FILE${NC}" >&2
        return 1
    fi
    
    # Load variables, ignoring comments and empty lines
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^[[:space:]]*# ]] && continue
        [[ -z $key ]] && continue
        
        # Remove leading/trailing whitespace
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Skip if key is empty after trimming
        [[ -z $key ]] && continue
        
        # Export the variable
        export "$key"="$value"
    done < "$CONFIG_FILE"
}

# Function to get a specific variable
get_var() {
    local var_name="$1"
    if [[ -z "$var_name" ]]; then
        echo -e "${RED}ERROR: Variable name required${NC}" >&2
        return 1
    fi
    
    load_config
    echo "${!var_name}"
}

# Function to set a variable
set_var() {
    local var_name="$1"
    local var_value="$2"
    
    if [[ -z "$var_name" || -z "$var_value" ]]; then
        echo -e "${RED}ERROR: Variable name and value required${NC}" >&2
        return 1
    fi
    
    # Create backup
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update or add the variable
    if grep -q "^$var_name=" "$CONFIG_FILE"; then
        # Update existing variable
        sed -i "s|^$var_name=.*|$var_name=$var_value|" "$CONFIG_FILE"
        echo -e "${GREEN}Updated $var_name=$var_value${NC}"
    else
        # Add new variable
        echo "$var_name=$var_value" >> "$CONFIG_FILE"
        echo -e "${GREEN}Added $var_name=$var_value${NC}"
    fi
}

# Function to list all variables
list_vars() {
    echo -e "${BLUE}Homie OS Configuration Variables${NC}"
    echo "================================"
    
    load_config
    
    # Parse and display variables by section
    local current_section=""
    while IFS= read -r line; do
        # Check for section headers
        if [[ $line =~ ^#[[:space:]]*=+[[:space:]]*$ ]]; then
            continue
        elif [[ $line =~ ^#[[:space:]]*([A-Z][A-Z0-9_[:space:]]+)[[:space:]]*$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            echo -e "\n${YELLOW}${current_section}${NC}"
            continue
        elif [[ $line =~ ^#[[:space:]]*=+[[:space:]]*$ ]]; then
            continue
        fi
        
        # Skip regular comments and empty lines for display
        [[ $line =~ ^[[:space:]]*#[^=] ]] && continue
        [[ -z $line ]] && continue
        
        # Display variable
        if [[ $line =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            printf "  %-30s = %s\n" "$key" "$value"
        fi
    done < "$CONFIG_FILE"
}

# Function to validate configuration
validate_config() {
    echo -e "${BLUE}Validating Configuration${NC}"
    echo "========================"
    
    load_config
    
    local errors=0
    
    # Check required variables
    local required_vars=(
        "VERSION"
        "L4T_VERSION"
        "L4T_BASE_IMAGE"
        "CUDA_VERSION"
        "JETPACK_VERSION"
        "TARGET_ARCHITECTURE"
        "TARGET_PLATFORM"
        "RAUC_COMPATIBLE"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            echo -e "${RED}ERROR: Required variable $var is not set${NC}"
            ((errors++))
        else
            echo -e "${GREEN}✓ $var=${!var}${NC}"
        fi
    done
    
    # Validate L4T version format
    if [[ ! $L4T_VERSION =~ ^r[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        echo -e "${RED}ERROR: L4T_VERSION format invalid: $L4T_VERSION (expected: rXX.X or rXX.X.X)${NC}"
        ((errors++))
    fi
    
    # Validate version format
    if [[ ! $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        echo -e "${RED}ERROR: VERSION format invalid: $VERSION (expected: X.Y.Z...)${NC}"
        ((errors++))
    fi
    
    # Check registry format
    if [[ ! $REGISTRY =~ ^[a-z0-9.-]+$ ]]; then
        echo -e "${YELLOW}WARNING: REGISTRY format may be invalid: $REGISTRY${NC}"
    fi
    
    echo ""
    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}✓ Configuration validation passed${NC}"
        return 0
    else
        echo -e "${RED}✗ Configuration validation failed with $errors errors${NC}"
        return 1
    fi
}

# Function to generate environment file for scripts
generate_env() {
    local output_file="${1:-$PROJECT_ROOT/.env}"
    
    echo -e "${BLUE}Generating environment file: $output_file${NC}"
    
    load_config
    
    cat > "$output_file" << 'EOF'
# Generated environment file from Homie OS configuration
# This file is auto-generated - do not edit manually
# Edit config/variables.conf instead

EOF
    
    # Export all variables to the env file
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^[[:space:]]*# ]] && continue
        [[ -z $key ]] && continue
        
        # Clean up key and value
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Skip if key is empty after trimming
        [[ -z $key ]] && continue
        
        echo "export $key=\"$value\"" >> "$output_file"
    done < "$CONFIG_FILE"
    
    echo -e "${GREEN}Environment file generated: $output_file${NC}"
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [COMMAND] [ARGUMENTS]

Homie OS Configuration Variable Manager

COMMANDS:
    load                    Load all configuration variables into environment
    get <VAR_NAME>         Get value of specific variable
    set <VAR_NAME> <VALUE> Set variable to new value
    list                   List all configuration variables
    validate               Validate configuration
    generate-env [FILE]    Generate .env file (default: project root)
    help                   Show this help message

EXAMPLES:
    $0 load                              # Load all variables
    $0 get VERSION                       # Get current version
    $0 set L4T_VERSION r36.3.0          # Update L4T version
    $0 list                              # Show all variables
    $0 validate                          # Validate configuration
    $0 generate-env                      # Generate .env file

CONFIGURATION FILE: $CONFIG_FILE

EOF
}

# Main command handling
case "${1:-help}" in
    load)
        load_config
        echo -e "${GREEN}Configuration loaded${NC}"
        ;;
    get)
        get_var "$2"
        ;;
    set)
        set_var "$2" "$3"
        ;;
    list)
        list_vars
        ;;
    validate)
        validate_config
        ;;
    generate-env)
        generate_env "$2"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo ""
        usage
        exit 1
        ;;
esac

#!/bin/bash
# Version management script for Homie OS

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
RELEASE_TYPE="alpha"
BUMP_TYPE=""
DRY_RUN=false

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Manage versions for Homie OS releases.

OPTIONS:
    -t, --type TYPE       Release type: alpha, beta, rc, release (default: alpha)
    -b, --bump BUMP       Bump type: major, minor, patch
    -d, --dry-run         Show what would be done without making changes
    -h, --help           Show this help message

EXAMPLES:
    $0 --type alpha                    # Create alpha version
    $0 --type beta --bump minor        # Bump minor version and create beta
    $0 --type release --bump patch     # Bump patch version and create release
    $0 --dry-run --type rc            # Show what RC version would be created

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--type)
            RELEASE_TYPE="$2"
            shift 2
            ;;
        -b|--bump)
            BUMP_TYPE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate release type
case $RELEASE_TYPE in
    alpha|beta|rc|release)
        ;;
    *)
        echo "Error: Invalid release type '$RELEASE_TYPE'"
        echo "Valid types: alpha, beta, rc, release"
        exit 1
        ;;
esac

# Validate bump type if provided
if [[ -n "$BUMP_TYPE" ]]; then
    case $BUMP_TYPE in
        major|minor|patch)
            ;;
        *)
            echo "Error: Invalid bump type '$BUMP_TYPE'"
            echo "Valid types: major, minor, patch"
            exit 1
            ;;
    esac
fi

cd "$PROJECT_ROOT"

# Get current version from git tags
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
CURRENT_VERSION=${LATEST_TAG#v}

echo "📋 Current version: $CURRENT_VERSION"

# Parse current version
if [[ $CURRENT_VERSION =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-.*)?$ ]]; then
    MAJOR=${BASH_REMATCH[1]}
    MINOR=${BASH_REMATCH[2]}
    PATCH=${BASH_REMATCH[3]}
    PRERELEASE=${BASH_REMATCH[4]}
else
    echo "Warning: Cannot parse current version, using 0.1.0"
    MAJOR=0
    MINOR=1
    PATCH=0
    PRERELEASE=""
fi

# Apply version bump if requested
if [[ -n "$BUMP_TYPE" ]]; then
    case $BUMP_TYPE in
        major)
            MAJOR=$((MAJOR + 1))
            MINOR=0
            PATCH=0
            ;;
        minor)
            MINOR=$((MINOR + 1))
            PATCH=0
            ;;
        patch)
            PATCH=$((PATCH + 1))
            ;;
    esac
fi

# Generate new version based on release type
BASE_VERSION="${MAJOR}.${MINOR}.${PATCH}"

case $RELEASE_TYPE in
    release)
        NEW_VERSION="$BASE_VERSION"
        ;;
    *)
        DATE=$(date +%Y%m%d)
        SHORT_SHA=$(git rev-parse --short HEAD)
        NEW_VERSION="${BASE_VERSION}-${RELEASE_TYPE}.${DATE}.${SHORT_SHA}"
        ;;
esac

echo "🎯 New version: $NEW_VERSION"
echo "🏷️  Tag: v$NEW_VERSION"

# Show what would be done
if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "🧪 DRY RUN - Would perform these actions:"
    echo "   1. Create git tag: v$NEW_VERSION"
    echo "   2. Update VERSION file"
    if [[ "$RELEASE_TYPE" == "release" ]]; then
        echo "   3. Create GitHub release"
    else
        echo "   3. Create GitHub pre-release"
    fi
    echo ""
    echo "To actually perform these actions, run without --dry-run"
    exit 0
fi

# Update VERSION file
echo "$NEW_VERSION" > VERSION
echo "📝 Updated VERSION file"

# Create git tag
git add VERSION
git commit -m "Bump version to $NEW_VERSION" || true
git tag -a "v$NEW_VERSION" -m "Release $NEW_VERSION"
echo "🏷️  Created git tag: v$NEW_VERSION"

echo ""
echo "✅ Version management completed!"
echo "📦 Version: $NEW_VERSION"
echo "🚀 To trigger build:"
echo "   git push origin main --tags"
echo ""
echo "🎯 Or manually trigger workflow:"
echo "   gh workflow run build-bundle.yml -f version=$NEW_VERSION -f release_type=$RELEASE_TYPE"

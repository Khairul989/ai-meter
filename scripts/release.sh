#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  ./scripts/release.sh v1.43.1 [options]

Options:
  --title "AIMeter 1.43.1"      Override the GitHub release title
  --notes-file PATH             Use a custom release notes file
  --repo OWNER/REPO             Override the GitHub repository slug
  --signing-identity NAME       Override the macOS signing identity
  --allow-dirty                 Allow a dirty git worktree
  --skip-gh-release             Build artifacts but skip `gh release create`
  --skip-sign                   Skip the final codesign step
  --dry-run                     Build artifacts and notes, but skip GitHub release publishing
  -h, --help                    Show this help

Defaults:
  repo             AIMETER_RELEASE_REPO or Khairul989/ai-meter
  signing identity AIMETER_SIGNING_IDENTITY or AIMeter Dev

Behavior:
  - validates the version tag format (`vX.Y.Z`)
  - bumps MARKETING_VERSION and CURRENT_PROJECT_VERSION in AIMeter/project.yml
  - regenerates the Xcode project with xcodegen
  - archives, signs, zips, and generates Sparkle appcast artifacts
  - publishes a GitHub release unless --dry-run or --skip-gh-release is set
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

require_tool() {
    local tool="$1"
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required but was not found"
}

extract_changelog_entry() {
    local semver="$1"
    local changelog_path="$2"

    awk -v header="## [$semver]" '
        index($0, header) == 1 { in_section = 1 }
        /^## \[/ && in_section && index($0, header) != 1 { exit }
        in_section { print }
    ' "$changelog_path"
}

ensure_clean_tree() {
    local repo_dir="$1"

    git -C "$repo_dir" diff --quiet || return 1
    git -C "$repo_dir" diff --cached --quiet || return 1
    [[ -z "$(git -C "$repo_dir" ls-files --others --exclude-standard)" ]] || return 1
}

VERSION=""
TITLE=""
NOTES_FILE=""
REPO="${AIMETER_RELEASE_REPO:-Khairul989/ai-meter}"
SIGNING_IDENTITY="${AIMETER_SIGNING_IDENTITY:-AIMeter Dev}"
ALLOW_DIRTY=0
SKIP_GH_RELEASE=0
SKIP_SIGN=0
DRY_RUN=0

while (($#)); do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --title)
            [[ $# -ge 2 ]] || die "--title requires a value"
            TITLE="$2"
            shift 2
            ;;
        --notes-file)
            [[ $# -ge 2 ]] || die "--notes-file requires a path"
            NOTES_FILE="$2"
            shift 2
            ;;
        --repo)
            [[ $# -ge 2 ]] || die "--repo requires a value"
            REPO="$2"
            shift 2
            ;;
        --signing-identity)
            [[ $# -ge 2 ]] || die "--signing-identity requires a value"
            SIGNING_IDENTITY="$2"
            shift 2
            ;;
        --allow-dirty)
            ALLOW_DIRTY=1
            shift
            ;;
        --skip-gh-release)
            SKIP_GH_RELEASE=1
            shift
            ;;
        --skip-sign)
            SKIP_SIGN=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -*)
            die "Unknown option: $1"
            ;;
        *)
            if [[ -z "$VERSION" ]]; then
                VERSION="$1"
                shift
            else
                die "Unexpected positional argument: $1"
            fi
            ;;
    esac
done

[[ -n "$VERSION" ]] || die "Missing version tag. See --help for usage."
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Version must use the form vX.Y.Z"
SEMVER="${VERSION#v}"

if [[ -z "$TITLE" ]]; then
    TITLE="AIMeter $SEMVER"
fi

if (( DRY_RUN )); then
    SKIP_GH_RELEASE=1
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AIMETER_DIR="$PROJECT_DIR/AIMeter"
PROJ_YML="$AIMETER_DIR/project.yml"
CHANGELOG_PATH="$PROJECT_DIR/CHANGELOG.md"
BUILD_DIR="$PROJECT_DIR/build/release-$VERSION"
ARCHIVE_PATH="$BUILD_DIR/AIMeter.xcarchive"
APP_PATH="$BUILD_DIR/AIMeter.app"
ZIP_NAME="AIMeter-$VERSION.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
APPCAST_DIR="$BUILD_DIR/appcast"
RELEASE_NOTES_PATH="$BUILD_DIR/release-notes.md"
SIGN_UPDATE="$PROJECT_DIR/scripts/sparkle-tools/sign_update"
GENERATE_APPCAST="$PROJECT_DIR/scripts/sparkle-tools/generate_appcast"

[[ -f "$PROJ_YML" ]] || die "Missing project file: $PROJ_YML"
[[ -f "$CHANGELOG_PATH" ]] || die "Missing changelog: $CHANGELOG_PATH"

for tool in "$SIGN_UPDATE" "$GENERATE_APPCAST"; do
    [[ -x "$tool" ]] || die "$tool not found or not executable"
done

require_tool xcodebuild
require_tool xcodegen
require_tool ditto

if (( ! SKIP_SIGN )); then
    require_tool codesign
fi

if (( ! SKIP_GH_RELEASE )); then
    require_tool gh
fi

if (( ! ALLOW_DIRTY )) && ! ensure_clean_tree "$PROJECT_DIR"; then
    die "Git worktree is not clean. Commit or stash changes first, or rerun with --allow-dirty."
fi

if git -C "$PROJECT_DIR" rev-parse -q --verify "refs/tags/$VERSION" >/dev/null 2>&1; then
    die "Git tag already exists: $VERSION"
fi

mkdir -p "$BUILD_DIR"

ORIGINAL_PROJ_YML="$(mktemp "${TMPDIR:-/tmp}/aimeter-project-yml.XXXXXX")"
cp "$PROJ_YML" "$ORIGINAL_PROJ_YML"

cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 && -f "$ORIGINAL_PROJ_YML" ]]; then
        echo "==> Restoring AIMeter/project.yml after failure..."
        cp "$ORIGINAL_PROJ_YML" "$PROJ_YML"
        (
            cd "$AIMETER_DIR"
            xcodegen generate >/dev/null 2>&1 || true
        )
    fi
    rm -f "$ORIGINAL_PROJ_YML"
}
trap cleanup EXIT

CURRENT_BUILD="$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$PROJ_YML")"
[[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]] || die "Could not parse CURRENT_PROJECT_VERSION from $PROJ_YML"
NEW_BUILD=$((CURRENT_BUILD + 1))

echo "==> Bumping version in AIMeter/project.yml..."
sed -i '' "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$SEMVER\"/" "$PROJ_YML"
sed -i '' "s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$NEW_BUILD\"/" "$PROJ_YML"
echo "    MARKETING_VERSION: $SEMVER"
echo "    CURRENT_PROJECT_VERSION: $NEW_BUILD (was $CURRENT_BUILD)"

echo "==> Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Regenerating Xcode project..."
(
    cd "$AIMETER_DIR"
    xcodegen generate
)

echo "==> Preparing release notes..."
if [[ -n "$NOTES_FILE" ]]; then
    [[ -f "$NOTES_FILE" ]] || die "Release notes file not found: $NOTES_FILE"
    cp "$NOTES_FILE" "$RELEASE_NOTES_PATH"
else
    CHANGELOG_ENTRY="$(extract_changelog_entry "$SEMVER" "$CHANGELOG_PATH")"
    if [[ -n "$CHANGELOG_ENTRY" ]]; then
        printf '%s\n' "$CHANGELOG_ENTRY" > "$RELEASE_NOTES_PATH"
    else
        cat > "$RELEASE_NOTES_PATH" <<EOF
## $TITLE

- Release $VERSION
EOF
    fi
fi

cat >> "$RELEASE_NOTES_PATH" <<EOF

## Install

Download $ZIP_NAME, unzip it, and move AIMeter.app to /Applications.
On first launch, right-click the app and choose Open to clear Gatekeeper.
EOF

echo "==> Archiving AIMeter..."
(
    cd "$AIMETER_DIR"
    xcodebuild archive \
        -project AIMeter.xcodeproj \
        -scheme AIMeter \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        | tail -20
)

[[ -d "$ARCHIVE_PATH/Products/Applications/AIMeter.app" ]] || die "Archive did not produce AIMeter.app"

echo "==> Exporting .app from archive..."
cp -R "$ARCHIVE_PATH/Products/Applications/AIMeter.app" "$APP_PATH"

if (( ! SKIP_SIGN )); then
    echo "==> Re-signing with $SIGNING_IDENTITY..."
    codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_PATH"
else
    echo "==> Skipping final codesign (--skip-sign)"
fi

echo "==> Creating zip..."
(
    cd "$BUILD_DIR"
    ditto -c -k --keepParent "AIMeter.app" "$ZIP_NAME"
)

echo "==> Generating appcast..."
mkdir -p "$APPCAST_DIR"
cp "$ZIP_PATH" "$APPCAST_DIR/"
"$GENERATE_APPCAST" \
    --download-url-prefix "https://github.com/$REPO/releases/download/${VERSION}/" \
    "$APPCAST_DIR"

if (( ! SKIP_GH_RELEASE )); then
    echo "==> Creating GitHub release $VERSION..."
    gh release create "$VERSION" \
        --repo "$REPO" \
        --title "$TITLE" \
        --notes-file "$RELEASE_NOTES_PATH" \
        "$ZIP_PATH" \
        "$APPCAST_DIR/appcast.xml"
fi

echo ""
echo "==> Release artifacts ready"
echo "    Version: $VERSION"
echo "    Build:   $NEW_BUILD"
echo "    Zip:     $ZIP_PATH"
echo "    Appcast: $APPCAST_DIR/appcast.xml"
echo "    Notes:   $RELEASE_NOTES_PATH"

if (( SKIP_GH_RELEASE )); then
    if (( DRY_RUN )); then
        echo "    Publish: skipped (--dry-run)"
    else
        echo "    Publish: skipped (--skip-gh-release)"
    fi
else
    echo "    Release: https://github.com/$REPO/releases/tag/$VERSION"
fi

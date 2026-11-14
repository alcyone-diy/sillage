#!/bin/bash
set -euo pipefail

# Find repository root
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Error: Not inside a git repository." >&2
  exit 1
}
cd "$REPO_ROOT"

PBXPROJ="Sillage.xcodeproj/project.pbxproj"
if [ ! -f "$PBXPROJ" ]; then
  echo "Error: $PBXPROJ not found." >&2
  exit 1
fi

DRY_RUN=false
DO_ARCHIVE=true
DO_PUSH=false
ALLOW_DIRTY=false
CUSTOM_BUILD=""

# Help documentation
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [BUILD_NUMBER]

All-in-one script to prepare a TestFlight build:
  1. Increments build number (CURRENT_PROJECT_VERSION) in Xcode project
  2. Creates the release commit locally
  3. Creates an annotated git tag (e.g. v1.0-b2)
  4. Automatically compiles and generates the Xcode archive (.xcarchive)
  5. Opens Xcode Organizer with the archive ready for TestFlight distribution

Arguments:
  BUILD_NUMBER          Target build number (integer). Defaults to current + 1.

Options:
  -n, --dry-run         Show planned actions without modifying files, git, or archiving.
  --no-archive          Update version, commit and tag locally without building archive.
  --push                Push commit and tag to remote repository (default: off).
  --allow-dirty         Allow running even if uncommitted changes exist in working tree.
  -h, --help            Show this help message.

Examples:
  $(basename "$0")              # Increment build (e.g. 1 -> 2), commit, tag, and archive
  $(basename "$0") 5            # Force build number to 5 and archive
  $(basename "$0") --dry-run    # Preview planned actions
EOF
  exit 0
}

# Parse options and arguments
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -n|--dry-run)
      DRY_RUN=true
      shift
      ;;
    --no-archive)
      DO_ARCHIVE=false
      shift
      ;;
    --push)
      DO_PUSH=true
      shift
      ;;
    --allow-dirty)
      ALLOW_DIRTY=true
      shift
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        CUSTOM_BUILD="$1"
        shift
      else
        echo "Error: Unknown argument or invalid build number: $1" >&2
        usage
      fi
      ;;
  esac
done

# Check current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" = "HEAD" ]; then
  echo "Error: You are in a 'detached HEAD' state. Please switch to a branch first." >&2
  exit 1
fi

# Check git status for uncommitted changes
if [ "$DRY_RUN" = false ] && [ "$ALLOW_DIRTY" = false ]; then
  if ! git diff-index --quiet HEAD --; then
    echo "Error: Working directory contains uncommitted changes." >&2
    echo "Please commit or stash your changes before running this script," >&2
    echo "or pass --allow-dirty to ignore." >&2
    exit 1
  fi
fi

# Extract current version and build number
MARKETING_VERSION=$(grep -m1 -E "MARKETING_VERSION = [^;]+" "$PBXPROJ" | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/' | tr -d ' "')
CURRENT_BUILD=$(grep -m1 -E "CURRENT_PROJECT_VERSION = [0-9]+" "$PBXPROJ" | sed -E 's/.*CURRENT_PROJECT_VERSION = ([0-9]+);.*/\1/' | tr -d ' ')

if [ -z "$CURRENT_BUILD" ]; then
  echo "Error: Unable to determine CURRENT_PROJECT_VERSION from $PBXPROJ." >&2
  exit 1
fi

if [ -n "$CUSTOM_BUILD" ]; then
  NEW_BUILD="$CUSTOM_BUILD"
else
  NEW_BUILD=$((CURRENT_BUILD + 1))
fi

TAG_NAME="v${MARKETING_VERSION}-b${NEW_BUILD}"
COMMIT_MSG="Bump build number to ${NEW_BUILD}"
ARCHIVE_DIR="build/Archives"
ARCHIVE_PATH="${ARCHIVE_DIR}/Sillage-v${MARKETING_VERSION}-b${NEW_BUILD}.xcarchive"

echo "=========================================="
echo " Sillage TestFlight Release Prep"
echo "=========================================="
echo " Branch            : ${CURRENT_BRANCH}"
echo " Marketing Version : ${MARKETING_VERSION}"
echo " Current Build     : ${CURRENT_BUILD}"
echo " Target Build      : ${NEW_BUILD}"
echo " Commit Message    : ${COMMIT_MSG}"
echo " Git Tag           : ${TAG_NAME}"
echo " Remote Push       : $( [ "$DO_PUSH" = true ] && echo "Yes (origin/${CURRENT_BRANCH} + ${TAG_NAME})" || echo "Disabled (local only)" )"
echo " Xcode Archive     : $( [ "$DO_ARCHIVE" = true ] && echo "Yes (${ARCHIVE_PATH})" || echo "No" )"
echo "=========================================="

if [ "$DRY_RUN" = true ]; then
  echo "[Dry-run] No changes made."
  exit 0
fi

# Verify tag doesn't already exist
if git rev-parse -q --verify "refs/tags/${TAG_NAME}" >/dev/null; then
  echo "Error: Tag '${TAG_NAME}' already exists in git!" >&2
  exit 1
fi

# 1. Update CURRENT_PROJECT_VERSION in project.pbxproj
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "$PBXPROJ"
echo "✓ 1/3 Xcode project updated (CURRENT_PROJECT_VERSION = ${NEW_BUILD})"

# 2. Git commit
git add "$PBXPROJ"
git commit -m "$COMMIT_MSG"
SHORT_SHA=$(git rev-parse --short HEAD)
echo "✓ 2/3 Commit created: ${SHORT_SHA} - ${COMMIT_MSG}"

# 3. Git tag
git tag -a "$TAG_NAME" -m "TestFlight build ${NEW_BUILD} (${MARKETING_VERSION})"
echo "✓ 3/3 Tag created: ${TAG_NAME}"

# Optional Git push
if [ "$DO_PUSH" = true ]; then
  echo "→ Pushing to origin (${CURRENT_BRANCH} and tag ${TAG_NAME})..."
  git push origin "${CURRENT_BRANCH}" "${TAG_NAME}"
  echo "✓ Push completed successfully!"
fi

# 4. Build Xcode archive
if [ "$DO_ARCHIVE" = true ]; then
  mkdir -p "$ARCHIVE_DIR"
  echo ""
  echo "=========================================="
  echo " Building Xcode Archive..."
  echo "=========================================="
  
  xcodebuild archive \
    -project Sillage.xcodeproj \
    -scheme Sillage \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH"
  
  echo ""
  echo "✓ Archive created successfully at: $ARCHIVE_PATH"
  
  # Open in Xcode Organizer
  echo "→ Opening archive in Xcode Organizer..."
  open "$ARCHIVE_PATH"
fi

echo ""
echo "=========================================="
echo "🎉 Build ${NEW_BUILD} prepared successfully!"
echo "=========================================="
echo "Next steps:"
echo "1. Distribute the archive via Xcode Organizer:"
echo "   ⚠️  Don't forget: click \"Distribute App\" -> \"App Store Connect\" (NOT \"TestFlight Internal Only\")!"
echo "2. When satisfied, push the commit and tag to GitHub:"
echo "   git push origin ${CURRENT_BRANCH} ${TAG_NAME}"
echo "=========================================="

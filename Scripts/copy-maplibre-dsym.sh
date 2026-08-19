#!/bin/bash
set -e

# Only execute when dSYM is being generated / archived
if [ -z "$DWARF_DSYM_FOLDER_PATH" ]; then
  exit 0
fi

# Detect MapLibre version from Package.resolved if available, otherwise default to 6.24.0
RESOLVED_FILE="${SRCROOT}/Sillage.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
VERSION="6.24.0"
if [ -f "$RESOLVED_FILE" ]; then
  DETECTED_VERSION=$(sed -n '/maplibre-gl-native-distribution/,/"version"/p' "$RESOLVED_FILE" | grep '"version"' | head -n 1 | sed -E 's/.*"version" : "([^"]+)".*/\1/')
  if [ -n "$DETECTED_VERSION" ]; then
    VERSION="$DETECTED_VERSION"
  fi
fi

CACHE_DIR="${SRCROOT}/Frameworks/dSYMs/${VERSION}"
mkdir -p "$CACHE_DIR"

DSYM_ZIP="${CACHE_DIR}/MapLibre_ios_device.framework.dSYM.zip"
DSYM_BUNDLE="${CACHE_DIR}/MapLibre.framework.dSYM"

# Download and extract if not already cached
if [ ! -d "$DSYM_BUNDLE" ]; then
  echo "Downloading MapLibre v${VERSION} dSYM..."
  DOWNLOAD_URL="https://github.com/maplibre/maplibre-native/releases/download/ios-v${VERSION}/MapLibre_ios_device.framework.dSYM.zip"
  curl -sSL -o "$DSYM_ZIP" "$DOWNLOAD_URL"
  
  if [ -f "$DSYM_ZIP" ]; then
    unzip -q -o "$DSYM_ZIP" -d "$CACHE_DIR"
    rm -f "$DSYM_ZIP"
    
    # Standardize bundle structure as MapLibre.framework.dSYM
    if [ -d "${CACHE_DIR}/MapLibre_ios_device.framework.dSYM" ]; then
      rm -rf "$DSYM_BUNDLE"
      cp -R "${CACHE_DIR}/MapLibre_ios_device.framework.dSYM" "$DSYM_BUNDLE"
      if [ -f "${DSYM_BUNDLE}/Contents/Resources/DWARF/MapLibre_ios_device" ]; then
        ln -sf "MapLibre_ios_device" "${DSYM_BUNDLE}/Contents/Resources/DWARF/MapLibre"
      fi
    fi
  fi
fi

# Copy dSYM to the archive/build dSYM directory
if [ -d "$DSYM_BUNDLE" ]; then
  echo "Copying MapLibre dSYM (v${VERSION}) to ${DWARF_DSYM_FOLDER_PATH}..."
  mkdir -p "$DWARF_DSYM_FOLDER_PATH"
  cp -R "$DSYM_BUNDLE" "${DWARF_DSYM_FOLDER_PATH}/"
  if [ -d "${CACHE_DIR}/MapLibre_ios_device.framework.dSYM" ]; then
    cp -R "${CACHE_DIR}/MapLibre_ios_device.framework.dSYM" "${DWARF_DSYM_FOLDER_PATH}/"
  fi
  echo "Successfully copied MapLibre dSYM."
else
  echo "Warning: MapLibre dSYM could not be prepared."
fi

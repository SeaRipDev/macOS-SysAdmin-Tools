#!/bin/bash

# Use $4 from Jamf if provided, otherwise default to 3.13
MIN_VERSION="${4:-3.14}"

echo "Listing all Python folders in /Applications:"
ls -d /Applications/Python*.* 2>/dev/null

# Loop through Python folders in /Applications
for dir in /Applications/Python*.*; do
    # Extract version number (e.g., 3.9 from Python 3.9)
    version=$(echo "$dir" | grep -oE '[0-9]+\.[0-9]+')
    if [[ -n "$version" ]]; then
        # Compare versions using sort -V
        if [[ "$(printf '%s\n' "$MIN_VERSION" "$version" | sort -V | head -n1)" == "$version" ]] && [[ "$version" != "$MIN_VERSION" ]]; then
            echo "Deleting $dir (version $version is below $MIN_VERSION)"
            rm -rf "$dir"
        else
            echo "Keeping $dir (version $version is $MIN_VERSION or above)"
        fi
    fi
done
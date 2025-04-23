#!/bin/bash

# Create a script to prepare all files for offline use
echo "Preparing files for offline Toon rooting..."

# Ensure files directory exists
mkdir -p files

# Copy toonstore to files directory
if [ -d "upload_to_toon/toonstore" ]; then
  echo "Creating toonstore archive..."
  tar -czf files/toonstore_files.tar.gz -C upload_to_toon toonstore
else
  echo "WARNING: toonstore directory not found"
fi

# Copy cacert.pem to files directory if it exists
if [ -f "upload_to_toon/cacert.pem" ]; then
  echo "Copying cacert.pem..."
  cp upload_to_toon/cacert.pem files/
else
  echo "WARNING: cacert.pem not found"
fi

# Copy tsc to files directory if it exists
if [ -f "upload_to_toon/tsc" ]; then
  echo "Copying tsc..."
  cp upload_to_toon/tsc files/
else
  echo "WARNING: tsc not found"
fi

echo "Setup complete! All required files are now in the 'files' directory."
echo "You can now run root-toon.sh to root your Toon in offline mode." 
#!/bin/bash

# Script to install libgdiplus dependency for .NET applications
# This library provides GDI+ compatible API for System.Drawing

echo "Installing libgdiplus dependency for .NET applications..."
sudo apt-get update -y
sudo apt-get install -y libgdiplus
echo "libgdiplus has been successfully installed."

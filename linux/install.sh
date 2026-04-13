#!/usr/bin/env bash
# Keel installer for Linux
# Run from inside the extracted keel-linux.tar.gz directory.

set -e

INSTALL_DIR="$HOME/.local/share/keel"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Keel..."

# Create directories
mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$DESKTOP_DIR" "$ICON_DIR"

# Copy application bundle
cp -r "$SCRIPT_DIR"/. "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/keel"

# Symlink binary to PATH
ln -sf "$INSTALL_DIR/keel" "$BIN_DIR/keel"

# Copy icon if present
if [ -f "$INSTALL_DIR/keel.png" ]; then
  cp "$INSTALL_DIR/keel.png" "$ICON_DIR/keel.png"
fi

# Create .desktop entry so Keel appears in the app launcher
cat > "$DESKTOP_DIR/keel.desktop" << EOF
[Desktop Entry]
Name=Keel
Comment=Local-first TPM command centre
Exec=$INSTALL_DIR/keel
Icon=keel
Type=Application
Categories=Office;ProjectManagement;
StartupWMClass=keel
EOF

# Refresh desktop database if available
if command -v update-desktop-database &>/dev/null; then
  update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
fi

echo ""
echo "Keel installed successfully."
echo "  Launch from your app menu, or run: keel"
echo ""
echo "To uninstall, run: $INSTALL_DIR/uninstall.sh"

# Write uninstall script alongside the app
cat > "$INSTALL_DIR/uninstall.sh" << 'UNINSTALL'
#!/usr/bin/env bash
rm -rf "$HOME/.local/share/keel"
rm -f "$HOME/.local/bin/keel"
rm -f "$HOME/.local/share/applications/keel.desktop"
rm -f "$HOME/.local/share/icons/hicolor/256x256/apps/keel.png"
echo "Keel uninstalled. Your data in ~/.local/share/keel-data is preserved."
UNINSTALL
chmod +x "$INSTALL_DIR/uninstall.sh"

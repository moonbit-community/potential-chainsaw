#!/usr/bin/env bash
set -euo pipefail

########
# Node #
########

NODE_VERSION="v22.14.0"
NODE_DIST="node-${NODE_VERSION}-linux-x64"
DOWNLOAD_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_DIST}.tar.xz"
INSTALL_DIR="/home/${_REMOTE_USER}/.local/node"
NODE_PATH="${INSTALL_DIR}/${NODE_DIST}"

# Create installation directory
mkdir -p "${INSTALL_DIR}"

# Download and extract Node.js
echo "Downloading Node.js ${NODE_VERSION}..."
curl -fsSL "${DOWNLOAD_URL}" -o "/tmp/${NODE_DIST}.tar.xz"
echo "Extracting Node.js to ${INSTALL_DIR}..."
tar -xJf "/tmp/${NODE_DIST}.tar.xz" -C "${INSTALL_DIR}"
rm "/tmp/${NODE_DIST}.tar.xz"

# Update bashrc if not already configured
BASHRC_FILE="/home/${_REMOTE_USER}/.bashrc"
NODE_BASHRC_ENTRY="export PATH=\"\${PATH}:${NODE_PATH}/bin\""

if ! grep -q "${NODE_PATH}/bin" "${BASHRC_FILE}"; then
    echo "Updating ${BASHRC_FILE}..."
    echo "" >> "${BASHRC_FILE}"
    echo "# Node.js ${NODE_VERSION}" >> "${BASHRC_FILE}"
    echo "${NODE_BASHRC_ENTRY}" >> "${BASHRC_FILE}"
fi

# Set proper ownership
chown -R "${_REMOTE_USER}:${_REMOTE_USER}" "${INSTALL_DIR}"

echo "Node.js ${NODE_VERSION} has been installed for ${_REMOTE_USER}"
echo "Please restart your shell or run 'source ${BASHRC_FILE}' to use Node.js"

############
# Wasmtime #
############

WASMTIME_VERSION="v30.0.2"
WASMTIME_DIST="wasmtime-${WASMTIME_VERSION}-x86_64-linux"
WASMTIME_DOWNLOAD_URL="https://github.com/bytecodealliance/wasmtime/releases/download/${WASMTIME_VERSION}/${WASMTIME_DIST}.tar.xz"
WASMTIME_INSTALL_DIR="/home/${_REMOTE_USER}/.local/wasmtime"
WASMTIME_PATH="${WASMTIME_INSTALL_DIR}/${WASMTIME_DIST}"

# Create Wasmtime installation directory
mkdir -p "${WASMTIME_INSTALL_DIR}"

# Download and extract Wasmtime
echo "Downloading Wasmtime ${WASMTIME_VERSION}..."
curl -fsSL "${WASMTIME_DOWNLOAD_URL}" -o "/tmp/${WASMTIME_DIST}.tar.xz"
echo "Extracting Wasmtime to ${WASMTIME_INSTALL_DIR}..."
tar -xJf "/tmp/${WASMTIME_DIST}.tar.xz" -C "${WASMTIME_INSTALL_DIR}"
rm "/tmp/${WASMTIME_DIST}.tar.xz"

# Update bashrc if not already configured
WASMTIME_BASHRC_ENTRY="export PATH=\"\${PATH}:${WASMTIME_PATH}/\""

if ! grep -q "${WASMTIME_PATH}" "${BASHRC_FILE}"; then
    echo "Updating ${BASHRC_FILE} for Wasmtime..."
    echo "" >> "${BASHRC_FILE}"
    echo "# Wasmtime ${WASMTIME_VERSION}" >> "${BASHRC_FILE}"
    echo "${WASMTIME_BASHRC_ENTRY}" >> "${BASHRC_FILE}"
fi

# Set proper ownership
chown -R "${_REMOTE_USER}:${_REMOTE_USER}" "${WASMTIME_INSTALL_DIR}"

echo "Wasmtime ${WASMTIME_VERSION} has been installed for ${_REMOTE_USER}"

##############
# Wasm Tools #
##############

WASMTOOLS_VERSION="1.227.1"
WASMTOOLS_DIST="wasm-tools-${WASMTOOLS_VERSION}-x86_64-linux"
WASMTOOLS_DOWNLOAD_URL="https://github.com/bytecodealliance/wasm-tools/releases/download/v${WASMTOOLS_VERSION}/${WASMTOOLS_DIST}.tar.gz"
WASMTOOLS_INSTALL_DIR="/home/${_REMOTE_USER}/.local/wasm-tools"
WASMTOOLS_PATH="${WASMTOOLS_INSTALL_DIR}/${WASMTOOLS_DIST}"

# Create Wasm Tools installation directory
mkdir -p "${WASMTOOLS_INSTALL_DIR}"

# Download and extract Wasm Tools
echo "Downloading Wasm Tools ${WASMTOOLS_VERSION}..."
curl -fsSL "${WASMTOOLS_DOWNLOAD_URL}" -o "/tmp/${WASMTOOLS_DIST}.tar.gz"
echo "Extracting Wasm Tools to ${WASMTOOLS_INSTALL_DIR}..."
tar -xzf "/tmp/${WASMTOOLS_DIST}.tar.gz" -C "${WASMTOOLS_INSTALL_DIR}"
rm "/tmp/${WASMTOOLS_DIST}.tar.gz"

# Update bashrc if not already configured
WASMTOOLS_BASHRC_ENTRY="export PATH=\"\${PATH}:${WASMTOOLS_INSTALL_DIR}/${WASMTOOLS_DIST}\""

if ! grep -q "${WASMTOOLS_PATH}" "${BASHRC_FILE}"; then
    echo "Updating ${BASHRC_FILE} for Wasm Tools..."
    echo "" >> "${BASHRC_FILE}"
    echo "# Wasm Tools ${WASMTOOLS_VERSION}" >> "${BASHRC_FILE}"
    echo "${WASMTOOLS_BASHRC_ENTRY}" >> "${BASHRC_FILE}"
fi

# Set proper ownership
chown -R "${_REMOTE_USER}:${_REMOTE_USER}" "${WASMTOOLS_INSTALL_DIR}"

echo "Wasm Tools ${WASMTOOLS_VERSION} has been installed for ${_REMOTE_USER}"

#######################
# NPM Global Packages #
#######################

echo "Installing global NPM packages using pnpm..."

# Create npm global directory with correct permissions
NPM_GLOBAL_DIR="/home/${_REMOTE_USER}/.local/npm-global"
mkdir -p "${NPM_GLOBAL_DIR}"
chown -R "${_REMOTE_USER}:${_REMOTE_USER}" "${NPM_GLOBAL_DIR}"

# Configure npm to use custom global directory
sudo -u "${_REMOTE_USER}" PATH="${NODE_PATH}/bin:${PATH}" \
    "${NODE_PATH}/bin/npm" config set prefix "${NPM_GLOBAL_DIR}"

# Install global packages
echo "Installing smee-client, @bytecodealliance/jco, and @dotenvx/dotenvx..."
sudo -u "${_REMOTE_USER}" PATH="${NODE_PATH}/bin:${PATH}" \
    "${NODE_PATH}/bin/npm" install -g smee-client @bytecodealliance/jco @dotenvx/dotenvx

# Add npm global bin to PATH
NPM_BIN_PATH="${NPM_GLOBAL_DIR}/bin"
NPM_BASHRC_ENTRY="export PATH=\"\${PATH}:${NPM_BIN_PATH}\""

if ! grep -q "${NPM_BIN_PATH}" "${BASHRC_FILE}"; then
    echo "Updating ${BASHRC_FILE} for npm global packages..."
    echo "" >> "${BASHRC_FILE}"
    echo "# npm global packages" >> "${BASHRC_FILE}"
    echo "${NPM_BASHRC_ENTRY}" >> "${BASHRC_FILE}"
fi

echo "Global NPM packages have been installed for ${_REMOTE_USER}"

########
# just #
########

JUST_VERSION="1.40.0"
JUST_DIST="just-${JUST_VERSION}-x86_64-unknown-linux-musl"
JUST_DOWNLOAD_URL="https://github.com/casey/just/releases/download/${JUST_VERSION}/${JUST_DIST}.tar.gz"
JUST_INSTALL_DIR="/home/${_REMOTE_USER}/.local/just"
JUST_BIN_DIR="/home/${_REMOTE_USER}/.local/bin"

# Create installation directories
mkdir -p "${JUST_INSTALL_DIR}"
mkdir -p "${JUST_BIN_DIR}"

# Download and extract Just
echo "Downloading Just ${JUST_VERSION}..."
curl -fsSL "${JUST_DOWNLOAD_URL}" -o "/tmp/${JUST_DIST}.tar.gz"
echo "Extracting Just to ${JUST_INSTALL_DIR}..."
tar -xzf "/tmp/${JUST_DIST}.tar.gz" -C "${JUST_INSTALL_DIR}"
rm "/tmp/${JUST_DIST}.tar.gz"

# Copy just binary to bin directory
cp "${JUST_INSTALL_DIR}/just" "${JUST_BIN_DIR}/"

# Update bashrc if not already configured
JUST_BASHRC_ENTRY="export PATH=\"\${PATH}:${JUST_BIN_DIR}\""

if ! grep -q "${JUST_BIN_DIR}" "${BASHRC_FILE}"; then
    echo "Updating ${BASHRC_FILE} for Just..."
    echo "" >> "${BASHRC_FILE}"
    echo "# Just ${JUST_VERSION}" >> "${BASHRC_FILE}"
    echo "${JUST_BASHRC_ENTRY}" >> "${BASHRC_FILE}"
fi

# Set proper ownership
chown -R "${_REMOTE_USER}:${_REMOTE_USER}" "${JUST_INSTALL_DIR}"
chown -R "${_REMOTE_USER}:${_REMOTE_USER}" "${JUST_BIN_DIR}"

echo "Just ${JUST_VERSION} has been installed for ${_REMOTE_USER}"

########
# hurl #
########

HURL_VERSION="6.1.0"
HURL_DIST="hurl-${HURL_VERSION}-x86_64-unknown-linux-gnu"
HURL_DOWNLOAD_URL="https://github.com/Orange-OpenSource/hurl/releases/download/${HURL_VERSION}/${HURL_DIST}.tar.gz"
HURL_INSTALL_DIR="/home/${_REMOTE_USER}/.local/hurl"
HURL_BIN_DIR="/home/${_REMOTE_USER}/.local/bin"

# Create installation directories
mkdir -p "${HURL_INSTALL_DIR}"
mkdir -p "${HURL_BIN_DIR}"

# Download and extract Hurl
echo "Downloading Hurl ${HURL_VERSION}..."
curl -fsSL "${HURL_DOWNLOAD_URL}" -o "/tmp/${HURL_DIST}.tar.gz"
echo "Extracting Hurl to ${HURL_INSTALL_DIR}..."
tar -xzf "/tmp/${HURL_DIST}.tar.gz" -C "${HURL_INSTALL_DIR}"
rm "/tmp/${HURL_DIST}.tar.gz"

# Copy hurl binaries to bin directory
cp "${HURL_INSTALL_DIR}/${HURL_DIST}/bin/hurl" "${HURL_BIN_DIR}/"
cp "${HURL_INSTALL_DIR}/${HURL_DIST}/bin/hurlfmt" "${HURL_BIN_DIR}/"

# Update bashrc if not already configured (reusing JUST_BIN_DIR path check since it's the same)
if ! grep -q "${HURL_BIN_DIR}" "${BASHRC_FILE}" || [ "${HURL_BIN_DIR}" != "${JUST_BIN_DIR}" ]; then
    echo "Updating ${BASHRC_FILE} for Hurl..."
    echo "" >> "${BASHRC_FILE}"
    echo "# Hurl ${HURL_VERSION}" >> "${BASHRC_FILE}"
    echo "export PATH=\"\${PATH}:${HURL_BIN_DIR}\"" >> "${BASHRC_FILE}"
fi

# Set proper ownership
chown -R "${_REMOTE_USER}:${_REMOTE_USER}" "${HURL_INSTALL_DIR}"
chown -R "${_REMOTE_USER}:${_REMOTE_USER}" "${HURL_BIN_DIR}"

echo "Hurl ${HURL_VERSION} has been installed for ${_REMOTE_USER}"
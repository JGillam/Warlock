#!/bin/bash
#
# Install ASKA Server
#
# https://github.com/jgillam/ASKA-Installer
#
# Please ensure to run this script as root (or at least with sudo)
#
# @LICENSE AGPLv3
# @AUTHOR  Charlie Powell <cdp1337@bitsnbytes.dev>
# @CATEGORY Game Server
# @TRMM-TIMEOUT 600
# @WARLOCK-TITLE ASKA
# @WARLOCK-IMAGE media/aska-1920x1080.webp
# @WARLOCK-ICON media/aska-128x128.webp
# @WARLOCK-THUMBNAIL media/aska-640x360.webp
#
# Supports:
#   Debian 12, 13
#   Ubuntu 24.04
#
# Requirements:
#   None
#
# TRMM Custom Fields:
#   None
#
# Syntax:
#   --uninstall  - Perform an uninstallation
#   --dir=<path> - Use a custom installation directory instead of the default (optional)
#   --skip-firewall  - Do not install or configure a system firewall
#   --non-interactive  - Run the installer in non-interactive mode (useful for scripted installs)
#   --branch=<str> - Use a specific branch of the management script repository DEFAULT=main
#
# Changelog:
#   20260405 - Initial release

############################################
## Parameter Configuration
############################################

INSTALLER_VERSION="v20260405"
GAME="ASKA"
GAME_DESC="ASKA Dedicated Server"
REPO="jgillam/ASKA-Installer"
WARLOCK_GUID="dd14b58a-d1ac-43dd-aa81-ce0c865a8023"
GAME_USER="aska"
GAME_DIR="/home/${GAME_USER}/${GAME}"

function usage() {
  cat >&2 <<EOD
Usage: $0 [options]

Options:
    --uninstall  - Perform an uninstallation
    --dir=<path> - Use a custom installation directory instead of the default (optional)
    --skip-firewall  - Do not install or configure a system firewall
    --non-interactive  - Run the installer in non-interactive mode (useful for scripted installs)
    --branch=<str> - Use a specific branch of the management script repository DEFAULT=main

https://github.com/jgillam/ASKA-Installer

Please ensure to run this script as root (or at least with sudo)

@LICENSE AGPLv3
EOD
  exit 1
}

# Parse arguments
MODE_UNINSTALL=0
OVERRIDE_DIR=""
SKIP_FIREWALL=0
NONINTERACTIVE=0
BRANCH="main"
while [ "$#" -gt 0 ]; do
	case "$1" in
		--uninstall) MODE_UNINSTALL=1;;
		--dir=*|--dir)
			[ "$1" == "--dir" ] && shift 1 && OVERRIDE_DIR="$1" || OVERRIDE_DIR="${1#*=}"
			[ "${OVERRIDE_DIR:0:1}" == "'" ] && [ "${OVERRIDE_DIR:0-1}" == "'" ] && OVERRIDE_DIR="${OVERRIDE_DIR:1:-1}"
			[ "${OVERRIDE_DIR:0:1}" == '"' ] && [ "${OVERRIDE_DIR:0-1}" == '"' ] && OVERRIDE_DIR="${OVERRIDE_DIR:1:-1}"
			;;
		--skip-firewall) SKIP_FIREWALL=1;;
		--non-interactive) NONINTERACTIVE=1;;
		--branch=*|--branch)
			[ "$1" == "--branch" ] && shift 1 && BRANCH="$1" || BRANCH="${1#*=}"
			[ "${BRANCH:0:1}" == "'" ] && [ "${BRANCH:0-1}" == "'" ] && BRANCH="${BRANCH:1:-1}"
			[ "${BRANCH:0:1}" == '"' ] && [ "${BRANCH:0-1}" == '"' ] && BRANCH="${BRANCH:1:-1}"
			;;
		-h|--help) usage;;
		*) echo "Unknown argument: $1" >&2; usage;;
	esac
	shift 1
done

##
# Simple check to enforce the script to be run as root
if [ $(id -u) -ne 0 ]; then
	echo "This script must be run as root or with sudo!" >&2
	exit 1
fi

##
# Simple wrapper to emulate `which -s`
function cmd_exists() {
	local CMD="$1"
	which "$CMD" &>/dev/null
	return $?
}

##
# Get which firewall is enabled, or "none" if none located
function get_enabled_firewall() {
	if [ "$(systemctl is-active firewalld)" == "active" ]; then
		echo "firewalld"
	elif [ "$(systemctl is-active ufw)" == "active" ]; then
		echo "ufw"
	elif [ "$(systemctl is-active iptables)" == "active" ]; then
		echo "iptables"
	else
		echo "none"
	fi
}

##
# Get which firewall is available on the local system, or "none" if none located
function get_available_firewall() {
	if cmd_exists firewall-cmd; then
		echo "firewalld"
	elif cmd_exists ufw; then
		echo "ufw"
	elif systemctl list-unit-files iptables.service &>/dev/null; then
		echo "iptables"
	else
		echo "none"
	fi
}

##
# Check if the OS is "like" a certain type
function os_like() {
	local OS="$1"
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"
		if [[ "$LIKE" =~ "$OS" ]] || [ "$ID" == "$OS" ]; then
			return 0;
		fi
	fi
	return 1
}

function os_like_debian() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in -q) QUIET=1;; esac
		shift
	done
	if os_like debian || os_like ubuntu; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	fi
	if [ $QUIET -eq 0 ]; then echo 0; fi
	return 1
}

function os_like_ubuntu() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in -q) QUIET=1;; esac
		shift
	done
	if os_like ubuntu; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	fi
	if [ $QUIET -eq 0 ]; then echo 0; fi
	return 1
}

function os_like_rhel() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in -q) QUIET=1;; esac
		shift
	done
	if os_like rhel || os_like fedora || os_like rocky || os_like centos; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	fi
	if [ $QUIET -eq 0 ]; then echo 0; fi
	return 1
}

function os_like_suse() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in -q) QUIET=1;; esac
		shift
	done
	if os_like suse; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	fi
	if [ $QUIET -eq 0 ]; then echo 0; fi
	return 1
}

function os_like_arch() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in -q) QUIET=1;; esac
		shift
	done
	if os_like arch; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	fi
	if [ $QUIET -eq 0 ]; then echo 0; fi
	return 1
}

##
# Get the operating system major version number
function os_version() {
	if [ -f '/etc/os-release' ]; then
		local VERS="$(egrep '^VERSION_ID=' /etc/os-release | sed 's:VERSION_ID=::')"
		if [[ "$VERS" =~ '"' ]]; then VERS="$(echo "$VERS" | sed 's:"::g')"; fi
		if [[ "$VERS" =~ \. ]]; then VERS="${VERS/\.*/}"; fi
		if [[ "$VERS" =~ "v" ]]; then VERS="${VERS/v/}"; fi
		echo "$VERS"
	else
		echo 0
	fi
}

##
# Install a package with the system's package manager
function package_install() {
	echo "package_install: Installing $*..."
	if os_like_debian -q; then
		DEBIAN_FRONTEND="noninteractive" apt-get -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" install -y $*
	elif os_like_rhel -q; then
		if [ "$(os_version)" -ge 9 ]; then
			dnf install -y $*
		else
			yum install -y $*
		fi
	elif os_like_arch -q; then
		pacman -Syu --noconfirm $*
	elif os_like_suse -q; then
		zypper install -y $*
	else
		echo 'package_install: Unsupported or unknown OS' >&2
		exit 1
	fi
}

##
# Add an "allow" rule to the firewall
function firewall_allow() {
	local PORT=""
	local PROTO="tcp"
	local SOURCE="any"
	local FIREWALL=$(get_available_firewall)
	local ZONE="public"
	local COMMENT=""
	while [ $# -ge 1 ]; do
		case $1 in
			--port) shift; PORT=$1;;
			--tcp|--udp) PROTO=${1:2};;
			--proto) shift; PROTO=$1;;
			--source|--from) shift; SOURCE=$1;;
			--zone) shift; ZONE=$1;;
			--comment) shift; COMMENT=$1;;
			*) PORT=$1;;
		esac
		shift
	done

	if [ "$FIREWALL" == "ufw" ]; then
		if [ "$SOURCE" == "any" ]; then
			ufw allow proto $PROTO to any port $PORT comment "$COMMENT"
		else
			ufw allow from $SOURCE proto $PROTO to any port $PORT comment "$COMMENT"
		fi
	elif [ "$FIREWALL" == "firewalld" ]; then
		firewall-cmd --zone=$ZONE --add-port=$PORT/$PROTO --permanent
		firewall-cmd --reload
	elif [ "$FIREWALL" == "iptables" ]; then
		iptables -A INPUT -p $PROTO --dport $PORT -j ACCEPT
		iptables-save > /etc/iptables/rules.v4
	fi
}

##
# Simple download utility (curl or wget)
function download() {
	local SOURCE="$1"
	local DESTINATION="$2"
	local OVERWRITE=1
	local TMP=$(mktemp)
	shift 2
	while [ $# -ge 1 ]; do
		case $1 in --no-overwrite) OVERWRITE=0;; esac
		shift
	done
	if [ -f "$DESTINATION" ] && [ $OVERWRITE -eq 0 ]; then
		return 0
	fi
	if cmd_exists curl; then
		if curl -fsL "$SOURCE" -o "$TMP"; then
			mv $TMP "$DESTINATION"
			return 0
		else
			echo "download: curl failed to download $SOURCE" >&2
			return 1
		fi
	elif cmd_exists wget; then
		if wget -q "$SOURCE" -O "$TMP"; then
			mv $TMP "$DESTINATION"
			return 0
		else
			echo "download: wget failed to download $SOURCE" >&2
			return 1
		fi
	else
		echo "download: Neither curl nor wget is installed!" >&2
		return 1
	fi
}

##
# Install UFW
function install_ufw() {
	package_install ufw
	ufw --force enable
	systemctl enable ufw
	systemctl start ufw
	local TTY_IP="$(who am i | awk '{print $NF}' | sed 's/[()]//g')"
	if [ -n "$TTY_IP" ]; then
		ufw allow from $TTY_IP comment 'Anti-lockout rule based on first install of UFW'
	fi
}

##
# Install firewalld
function install_firewalld() {
	package_install firewalld
	local TTY_IP="$(who am i | awk '{print $NF}' | sed 's/[()]//g')"
	if [ -n "$TTY_IP" ]; then
		firewall-cmd --zone=trusted --add-source=$TTY_IP --permanent
	fi
}

##
# Install the system default firewall
function firewall_install() {
	local FIREWALL
	FIREWALL=$(get_available_firewall)
	if [ "$FIREWALL" != "none" ]; then return; fi
	if os_like_debian -q; then
		install_ufw
	elif os_like_rhel -q; then
		install_firewalld
	elif os_like_suse -q; then
		install_firewalld
	else
		install_ufw
	fi
}

##
# Determine if the current shell session is non-interactive
function is_noninteractive() {
	case "${NONINTERACTIVE:-}${CI:-}" in 1*|true*|TRUE*|True*|*CI* ) return 0 ;; esac
	if [ "${DEBIAN_FRONTEND:-}" = "noninteractive" ]; then return 0; fi
	if [ "${TERM:-}" = "dumb" ]; then return 0; fi
	return 1
}

##
# Prompt user for a yes or no response
function prompt_yn() {
	local TRUE=0
	local YES=1
	local FALSE=1
	local NO=0
	local DEFAULT="n"
	local DEFAULT_CODE=1
	local PROMPT="Yes or no?"
	local RESPONSE=""
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in
			--invert) YES=0; NO=1; TRUE=1; FALSE=0;;
			--default-yes) DEFAULT="y";;
			--default-no) DEFAULT="n";;
			-q) QUIET=1;;
			*) PROMPT="$1";;
		esac
		shift
	done
	echo "$PROMPT" >&2
	if [ "$DEFAULT" == "y" ]; then
		DEFAULT_TEXT="yes"; DEFAULT="$YES"; DEFAULT_CODE=$TRUE
		echo -n "> (Y/n): " >&2
	else
		DEFAULT_TEXT="no"; DEFAULT="$NO"; DEFAULT_CODE=$FALSE
		echo -n "> (y/N): " >&2
	fi
	if is_noninteractive; then
		echo "$DEFAULT_TEXT (default non-interactive)" >&2
		if [ $QUIET -eq 0 ]; then echo $DEFAULT; fi
		return $DEFAULT_CODE
	fi
	read RESPONSE
	case "$RESPONSE" in
		[yY]*) if [ $QUIET -eq 0 ]; then echo $YES; fi; return $TRUE;;
		[nN]*) if [ $QUIET -eq 0 ]; then echo $NO; fi; return $FALSE;;
		"")
			echo "$DEFAULT_TEXT (default choice)" >&2
			if [ $QUIET -eq 0 ]; then echo $DEFAULT; fi
			return $DEFAULT_CODE;;
		*) if [ $QUIET -eq 0 ]; then echo $DEFAULT; fi; return $DEFAULT_CODE;;
	esac
}

##
# Print a header message
function print_header() {
	local header="$1"
	echo "================================================================================"
	printf "%*s\n" $(((${#header}+80)/2)) "$header"
	echo ""
}

##
# Install SteamCMD
function install_steamcmd() {
	echo "Installing SteamCMD..."
	TYPE_DEBIAN="$(os_like_debian)"
	TYPE_UBUNTU="$(os_like_ubuntu)"
	OS_VERSION="$(os_version)"

	if [ "$TYPE_UBUNTU" == 1 ]; then
		add-apt-repository -y multiverse
		dpkg --add-architecture i386
		apt update
		echo steam steam/question select "I AGREE" | debconf-set-selections
		echo steam steam/license note '' | debconf-set-selections
		apt install -y steamcmd
	elif [ "$TYPE_DEBIAN" == 1 ]; then
		dpkg --add-architecture i386
		apt update
		if [ "$OS_VERSION" -le 12 ]; then
			apt install -y software-properties-common apt-transport-https dirmngr ca-certificates lib32gcc-s1
			add-apt-repository -y -U http://deb.debian.org/debian -c non-free-firmware -c non-free
			if [ $? -ne 0 ]; then
				apt-add-repository -y non-free
			fi
		else
			if [ -e /etc/apt/sources.list ]; then
				if ! grep -q ' non-free ' /etc/apt/sources.list; then
					sed -i 's/main/main non-free-firmware non-free contrib/g' /etc/apt/sources.list
				fi
			elif [ -e /etc/apt/sources.list.d/debian.sources ]; then
				if ! grep -q ' non-free ' /etc/apt/sources.list.d/debian.sources; then
					sed -i 's/main/main non-free-firmware non-free contrib/g' /etc/apt/sources.list.d/debian.sources
				fi
			else
				echo "Could not find a sources.list file to enable non-free repos" >&2
				exit 1
			fi
		fi
		download http://repo.steampowered.com/steam/archive/stable/steam.gpg /usr/share/keyrings/steam.gpg
		chmod +r /usr/share/keyrings/steam.gpg
		echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/steam.gpg] http://repo.steampowered.com/steam/ stable steam" > /etc/apt/sources.list.d/steam.list
		echo steam steam/question select "I AGREE" | debconf-set-selections
		echo steam steam/license note '' | debconf-set-selections
		apt update
		apt install -y steamcmd
	else
		echo 'Unsupported or unknown OS' >&2
		exit 1
	fi
}

##
# Install Wine (WineHQ stable) and Xvfb
#
# ASKA ships only as a Windows binary (AskaServer.exe) and requires Wine
# to run on Linux. Xvfb provides the virtual display that Wine expects.
#
# dpkg --add-architecture i386 must be called before apt update that
# references the WineHQ repo, so it's done early here.
#
function install_wine() {
	echo "Installing Wine and Xvfb..."

	TYPE_UBUNTU="$(os_like_ubuntu)"
	TYPE_DEBIAN="$(os_like_debian)"

	if [ "$TYPE_UBUNTU" == 1 ] || [ "$TYPE_DEBIAN" == 1 ]; then
		# i386 is needed for Wine's 32-bit libraries.
		# Must be added before the WineHQ apt source is configured.
		dpkg --add-architecture i386
		apt update

		package_install software-properties-common apt-transport-https ca-certificates

		# Add the WineHQ GPG key
		mkdir -p /etc/apt/keyrings
		download https://dl.winehq.org/wine-builds/winehq.key /tmp/winehq.key
		gpg --dearmor < /tmp/winehq.key > /etc/apt/keyrings/winehq-archive.key
		chmod 0644 /etc/apt/keyrings/winehq-archive.key
		rm -f /tmp/winehq.key

		if [ "$TYPE_UBUNTU" == 1 ]; then
			# Ubuntu 24.04 (noble) requires the Ubuntu-specific WineHQ repo
			. /etc/os-release
			echo "deb [arch=amd64,i386 signed-by=/etc/apt/keyrings/winehq-archive.key] https://dl.winehq.org/wine-builds/ubuntu/ ${UBUNTU_CODENAME:-noble} main" \
				> /etc/apt/sources.list.d/winehq.list
		else
			# Debian 12 (bookworm) or 13 (trixie)
			. /etc/os-release
			echo "deb [arch=amd64,i386 signed-by=/etc/apt/keyrings/winehq-archive.key] https://dl.winehq.org/wine-builds/debian/ ${VERSION_CODENAME} main" \
				> /etc/apt/sources.list.d/winehq.list
		fi

		apt update
		apt install -y --install-recommends winehq-stable
		package_install xvfb
	else
		echo 'install_wine: Unsupported or unknown OS' >&2
		exit 1
	fi
}

##
# Install the management script from the project's repo
#
# Expects the following variables:
#   GAME_USER    - User account to install the game under
#   GAME_DIR     - Directory to install the game into
#
# @param $1 Application Repo Name (e.g., user/repo)
# @param $2 Application Branch Name (default: main)
# @param $3 Warlock Manager version to install (default: release-v2)
#
function install_warlock_manager() {
	print_header "Performing install_management"

	local SRC=""
	local REPO="$1"
	local BRANCH="${2:-main}"
	local MANAGER_BRANCH="${3:-release-v2}"
	local MANAGER_SOURCE
	local MANAGER_SHA

	if [[ "$MANAGER_BRANCH" =~ ^[0-9]+\.[0-9]+$ ]]; then
		MANAGER_SOURCE="pip"
		MANAGER_BRANCH=">=${MANAGER_BRANCH}.0,<=${MANAGER_BRANCH}.9999"
	else
		MANAGER_SOURCE="github"
	fi

	SRC="https://raw.githubusercontent.com/${REPO}/refs/heads/${BRANCH}/dist/manage.py"

	if ! download "$SRC" "$GAME_DIR/manage.py"; then
		echo "Could not download management script!" >&2
		exit 1
	fi

	chown $GAME_USER:$GAME_USER "$GAME_DIR/manage.py"
	chmod +x "$GAME_DIR/manage.py"

	MANAGER_SHA="$(curl -s "https://api.github.com/repos/${REPO}/commits/${BRANCH}" \
		| grep '"sha":' \
		| head -n 1 \
		| sed -E 's/.*"sha": *"([^"]+)".*/\1/')"

	cat > "$GAME_DIR/.manage.json" <<EOF
{
	"source": "github",
	"repo": "${REPO}",
	"branch": "${BRANCH}",
	"commit": "${MANAGER_SHA}"
}
EOF
	chown $GAME_USER:$GAME_USER "$GAME_DIR/.manage.json"

	# Configuration definitions for ASKA's server properties file.
	# PropertiesConfig uses "key" as the exact key written in server properties.txt.
	# The "section" field is unused by PropertiesConfig but required by the schema.
	cat > "$GAME_DIR/configs.yaml" <<'EOF'
game:
  - name: Server Name
    section: ""
    key: Server Name
    default: "ASKA Server"
    type: str
    help: "Display name shown in the server browser."
    group: Basic
  - name: Password
    section: ""
    key: Password
    default: ""
    type: str
    help: "Server password. Leave blank for no password."
    group: Basic
  - name: Steam game port
    section: ""
    key: Steam game port
    default: "27015"
    type: int
    help: "UDP port for game traffic."
    group: Basic
  - name: Steam query port
    section: ""
    key: Steam query port
    default: "27016"
    type: int
    help: "UDP port for Steam server browser queries."
    group: Basic
  - name: Authentication token
    section: ""
    key: Authentication token
    default: ""
    type: str
    help: "Steam Game Server Login Token (GSLT). Required for public server listing."
    group: Basic
  - name: keep server world alive
    section: ""
    key: keep server world alive
    default: "false"
    type: bool
    help: "Keep the server world running when no players are connected."
  - name: Autosave frequency
    section: ""
    key: Autosave frequency
    default: "10 min"
    type: str
    options:
      - morning
      - 5 min
      - 10 min
      - 15 min
      - 20 min
      - disabled
    help: "How often the world is automatically saved."
  - name: Max Players
    section: ""
    key: Max Players
    default: "8"
    type: int
    help: "Maximum number of concurrent players (1-16)."
manager:
  - name: Instance Started (Discord)
    section: Discord
    key: instance_started
    type: str
    default: "{instance} has started! :rocket:"
    help: "Message sent to Discord when the server starts."
  - name: Instance Stopping (Discord)
    section: Discord
    key: instance_stopping
    type: str
    default: ":small_red_triangle_down: {instance} is shutting down"
    help: "Message sent to Discord when the server stops."
  - name: Discord Enabled
    section: Discord
    key: enabled
    type: bool
    default: false
    help: "Enable Discord integration for server status updates."
  - name: Discord Webhook URL
    section: Discord
    key: webhook
    type: str
    help: "Webhook URL for sending server status updates to Discord."
EOF
	chown $GAME_USER:$GAME_USER "$GAME_DIR/configs.yaml"

	touch "$GAME_DIR/.settings.ini"
	chown $GAME_USER:$GAME_USER "$GAME_DIR/.settings.ini"

	sudo -u $GAME_USER python3 -m venv "$GAME_DIR/.venv"
	sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install --upgrade pip
	if [ "$MANAGER_SOURCE" == "pip" ]; then
		sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install "warlock-manager${MANAGER_BRANCH}"
	else
		sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install warlock-manager@git+https://github.com/BitsNBytes25/Warlock-Manager.git@$MANAGER_BRANCH
	fi
}


print_header "$GAME_DESC *unofficial* Installer ${INSTALLER_VERSION}"

############################################
## Installer Actions
############################################

##
# Install the ASKA game server
#
function install_application() {
	print_header "Performing install_application"

	# Create a dedicated game user.
	# No password is set; use 'sudo passwd aska' to set one if needed.
	if [ -z "$(getent passwd $GAME_USER)" ]; then
		useradd -m -U $GAME_USER
	fi

	if [ ! -d "$GAME_DIR" ]; then
		mkdir -p "$GAME_DIR"
		chown $GAME_USER:$GAME_USER "$GAME_DIR"
	fi

	package_install curl sudo python3-venv

	if [ "$FIREWALL" == "1" ]; then
		if [ "$(get_enabled_firewall)" == "none" ]; then
			firewall_install
		fi
	fi

	# Install SteamCMD (needed by manage.py first-run to download game files)
	install_steamcmd

	# Install Wine + Xvfb (required to run ASKA's Windows binary on Linux)
	install_wine

	# Install the management script and warlock-manager pip package
	install_warlock_manager "$REPO" "$BRANCH" "2.1"

	# Keep the installer on disk for uninstallation or manual re-runs
	download "https://raw.githubusercontent.com/${REPO}/refs/heads/${BRANCH}/dist/installer.sh" "$GAME_DIR/installer.sh"
	chmod +x "$GAME_DIR/installer.sh"
	chown $GAME_USER:$GAME_USER "$GAME_DIR/installer.sh"

	if [ -n "$WARLOCK_GUID" ]; then
		[ -d "/var/lib/warlock" ] || mkdir -p "/var/lib/warlock"
		echo -n "$GAME_DIR" > "/var/lib/warlock/${WARLOCK_GUID}.app"
	fi
}

function postinstall() {
	print_header "Performing postinstall"

	# manage.py first-run will:
	#   1. Download ASKA server files via SteamCMD (Windows depot)
	#   2. Initialize the Wine prefix
	#   3. Create a default server properties.txt
	#   4. Create and enable the systemd service unit
	$GAME_DIR/manage.py first-run
}

##
# Uninstall the ASKA game server
#
function uninstall_application() {
	print_header "Performing uninstall_application"

	$GAME_DIR/manage.py remove --confirm

	[ -e "$GAME_DIR/manage.py" ] && rm "$GAME_DIR/manage.py"
	[ -e "$GAME_DIR/configs.yaml" ] && rm "$GAME_DIR/configs.yaml"
	[ -d "$GAME_DIR/.venv" ] && rm -rf "$GAME_DIR/.venv"

	if [ -n "$WARLOCK_GUID" ]; then
		[ -e "/var/lib/warlock/${WARLOCK_GUID}.app" ] && rm "/var/lib/warlock/${WARLOCK_GUID}.app"
	fi
}

############################################
## Pre-exec Checks
############################################

if [ $MODE_UNINSTALL -eq 1 ]; then
	MODE="uninstall"
elif [ -e "$GAME_DIR/AppFiles" ]; then
	MODE="reinstall"
else
	MODE="install"
fi

if [ -e "$GAME_DIR/Environments" ]; then
	for envfile in "$GAME_DIR/Environments/"*.env; do
		SERVICE=$(basename "$envfile" .env)
		if [ "$SERVICE" != "*" ]; then
			if systemctl -q is-active $SERVICE; then
				echo "$GAME_DESC service is currently running, please stop all instances before running this installer."
				echo "You can do this with: sudo systemctl stop $SERVICE"
				exit 1
			fi
		fi
	done
fi

if [ -n "$OVERRIDE_DIR" ]; then
	if [ -e "/var/lib/warlock/${WARLOCK_GUID}.app" ] ; then
		GAME_DIR="$(cat "/var/lib/warlock/${WARLOCK_GUID}.app")"
		if [ "$GAME_DIR" != "$OVERRIDE_DIR" ]; then
			echo "ERROR: $GAME_DESC already installed in $GAME_DIR, cannot override to $OVERRIDE_DIR" >&2
			echo "If you want to move the installation, please uninstall first and then re-install to the new location." >&2
			exit 1
		fi
	fi
	GAME_DIR="$OVERRIDE_DIR"
	echo "Using ${GAME_DIR} as the installation directory based on explicit argument"
elif [ -e "/var/lib/warlock/${WARLOCK_GUID}.app" ]; then
	GAME_DIR="$(cat "/var/lib/warlock/${WARLOCK_GUID}.app")"
	echo "Detected installation directory of ${GAME_DIR} based on service registration"
else
	echo "Using default installation directory of ${GAME_DIR}"
fi

############################################
## Installer
############################################

if [ "$MODE" == "install" ]; then

	if [ $SKIP_FIREWALL -eq 1 ]; then
		echo "Firewall explicitly disabled, skipping installation of a system firewall"
		FIREWALL=0
	elif prompt_yn -q --default-yes "Install system firewall?"; then
		FIREWALL=1
	else
		FIREWALL=0
	fi

	install_application
	postinstall
	print_header "$GAME_DESC Installation Complete"
fi

if [ "$MODE" == "reinstall" ]; then
	FIREWALL=0
	install_application
	postinstall
	print_header "$GAME_DESC Installation Complete"
fi

if [ "$MODE" == "uninstall" ]; then
	if [ $NONINTERACTIVE -eq 0 ]; then
		if prompt_yn -q --invert --default-no "This will remove all game binary content"; then
			exit 1
		fi
		if prompt_yn -q --invert --default-no "This will remove all player and map data"; then
			exit 1
		fi
	fi

	if prompt_yn -q --default-yes "Perform a backup before everything is wiped?"; then
		$GAME_DIR/manage.py backup
	fi

	uninstall_application
fi

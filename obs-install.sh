#!/usr/bin/env bash
LC_ALL=C

function fancy_message() {
    if [ -z "${1}" ] || [ -z "${2}" ]; then
      return
    fi

    local RED="\e[31m"
    local GREEN="\e[32m"
    local YELLOW="\e[33m"
    local RESET="\e[0m"
    local MESSAGE_TYPE=""
    local MESSAGE=""
    MESSAGE_TYPE="${1}"
    MESSAGE="${2}"

    case ${MESSAGE_TYPE} in
      info) echo -e "  [${GREEN}+${RESET}] ${MESSAGE}";;
      warn) echo -e "  [${YELLOW}*${RESET}] WARNING! ${MESSAGE}";;
      error) echo -e "  [${RED}!${RESET}] ERROR! ${MESSAGE}"
             exit 1;;
      *) echo -e "  [?] UNKNOWN: ${MESSAGE}";;
    esac
}

function web_get() {
    local FILE="${2}"
    local URL="${1}"
    if ! wget --quiet --continue "${URL}" -O "${CACHE_DIR}/${FILE}"; then
        fancy_message error "Failed to download ${URL}."
    fi
}

function apt_download() {
    local PACKAGE="${1}"
    local DEB=""
    fancy_message info "Downloading: ${PACKAGE} (apt)"
    cd "${CACHE_DIR}"
    apt-get -q=2 -y download ${PACKAGE} >/dev/null 2>&1
    cd - >/dev/null 2>&1

    DEB=$(find "${CACHE_DIR}/" -name "${PACKAGE}*.deb" -type f | tail -n1)
    apt_install "${DEB}"
}

function apt_install() {
    fancy_message info "Installing: ${1} (apt)"
    apt-get -q=2 -y install ${1} >/dev/null 2>&1
}

function install_deb() {
    local URL="${1}"
    local FILE="${URL##*/}"
    fancy_message info "Installing: ${FILE} (deb)"
    web_get "${URL}" "${FILE}"
    apt-get -q=2 -y install "${CACHE_DIR}/${FILE}" >/dev/null 2>&1
}

function install_exeldro_plugin() {
    local FILE="${2}"
    local URL="${1}"
    fancy_message info "Installing: ${FILE//.zip/} (plugin)"
    web_get "${URL}" "${FILE}"
    unzip -p -qq "${CACHE_DIR}/${FILE}" | tar zxf - -C "${PLUGIN_DIR}"
}

function install_tarball_plugin() {
    local URL="${1}"
    local FILE=""
    if [ -n "${2}" ]; then
        FILE="${2}"
    else
        FILE="${URL##*/}"
    fi
    fancy_message info "Installing: ${FILE} (plugin)"
    web_get "${URL}" "${FILE}"
    tar xf "${CACHE_DIR}/${FILE}" -C "${PLUGIN_DIR}"
    if [[ "${FILE}" == *"text-pango-linux"* ]]; then
        apt_install "libpango-1.0-0 libpangocairo-1.0-0 libpangoft2-1.0-0"
    fi
}

function install_zip_plugin() {
    local URL="${1}"
    local FILE=""
    if [ -n "${2}" ]; then
        FILE="${2}"
    else
        FILE="${URL##*/}"
    fi
    fancy_message info "Installing: ${FILE} (plugin)"
    web_get "${URL}" "${FILE}"

    # Are we extracting a specific folder from the zip?
    if [ -n "${3}" ]; then
        unzip -o -qq "${CACHE_DIR}/${FILE}" "${3}" -d "${PLUGIN_DIR}"
    else
        unzip -o -qq "${CACHE_DIR}/${FILE}" -d "${PLUGIN_DIR}"
    fi

    if [[ "${FILE}" == *"obs-gstreamer"* ]]; then
        mkdir -p "${PLUGIN_DIR}/obs-gstreamer/bin/64bit"
        mv "${PLUGIN_DIR}/linux/obs-gstreamer.so" "${PLUGIN_DIR}/obs-gstreamer/bin/64bit/"
        rm -rf "${PLUGIN_DIR}/linux"
        apt_install "gstreamer1.0-plugins-good libgstreamer-plugins-base1.0-0"
    elif [[ "${FILE}" == *"obs-nvfbc"* ]]; then
        mkdir -p "${PLUGIN_DIR}/nvfbc/bin/64bit"
        mv "${PLUGIN_DIR}/build/nvfbc.so" "${PLUGIN_DIR}/nvfbc/bin/64bit/"
        rm -rf "${PLUGIN_DIR}/build"
    elif [[ "${FILE}" == *"rgb-levels"* ]]; then
        mkdir -p "${PLUGIN_DIR}/obs-rgb-levels-filter/bin/64bit"
        mkdir -p "${PLUGIN_DIR}/obs-rgb-levels-filter/data"
        mv "${PLUGIN_DIR}/usr/lib/obs-plugins/obs-rgb-levels-filter.so" "${PLUGIN_DIR}/obs-rgb-levels-filter/bin/64bit/"
        mv "${PLUGIN_DIR}/usr/share/obs/obs-plugins/obs-rgb-levels-filter/rgb_levels.effect" "${PLUGIN_DIR}/obs-rgb-levels-filter/data/"
        rm -rf "${PLUGIN_DIR}/usr"
    elif [[ "${FILE}" == *"obs-teleport"* ]]; then
        mkdir -p "${PLUGIN_DIR}/obs-teleport/bin/64bit"
        mv "${PLUGIN_DIR}/linux-x86_64/obs-teleport.so" "${PLUGIN_DIR}/obs-teleport/bin/64bit/"
        rm -rf "${PLUGIN_DIR}/linux-x86_64"
    elif [[ "${FILE}" == *"spectralizer"* ]]; then
        apt_install "libfftw3-3"
    elif [[ "${FILE}" == *"streamfx"* ]]; then
        rm -rf "${PLUGIN_DIR}/StreamFX"
        mkdir -p "${PLUGIN_DIR}/StreamFX"
        mv "${PLUGIN_DIR}/plugins/StreamFX/bin" "${PLUGIN_DIR}/StreamFX/"
        mv "${PLUGIN_DIR}/plugins/StreamFX/data" "${PLUGIN_DIR}/StreamFX/"
        rm -rf "${PLUGIN_DIR}/plugins"
    elif [[ "${FILE}" == *"SceneSwitcher"* ]]; then
        rm -rf "${PLUGIN_DIR}/advanced-scene-switcher"
        mv "${PLUGIN_DIR}/SceneSwitcher/Linux/advanced-scene-switcher" "${PLUGIN_DIR}/advanced-scene-switcher"
        rm -rf "${PLUGIN_DIR}/SceneSwitcher"
        apt_install "libxss1 libxtst6 libcurl4"
        #libopencv-imgproc4.5 libopencv-objdetect4.5
    fi
}

function install_theme() {
    local URL="${1}"
    local FILE=""
    if [ -n "${2}" ]; then
        FILE="${2}"
    else
        FILE="${URL##*/}"
    fi
    fancy_message info "Installing: ${FILE} (theme)"
    web_get "${URL}" "${FILE}"
    unzip -o -qq "${CACHE_DIR}/${FILE}" -d "${THEME_DIR}"

    if [[ "${FILE}" == *"cgc_theme"* ]]; then
        mv "${THEME_DIR}/cgc_theme_obs/obs_theme/"* "${THEME_DIR}/"
        rm -rf "${THEME_DIR}/cgc_theme_obs"
    elif [[ "${FILE}" == *"Twitchy"* ]]; then
        mv "${THEME_DIR}/Twitchy (without font)/"* "${THEME_DIR}/"
        rm -rf "${THEME_DIR}/Twitchy (with"*
        rm "${THEME_DIR}/README.md"
    elif [[ "${FILE}" == *"YouTubey"* ]]; then
        mv "${THEME_DIR}/YouTubey (without font)/"* "${THEME_DIR}/"
        rm -rf "${THEME_DIR}/YouTubey (with"*
        rm "${THEME_DIR}/README.md"
    fi
}

echo "Open Broadcaster Software - Installer for Ubuntu & derivatives"

if [ "$(id -u)" -ne 0 ]; then
  fancy_message error "You must use sudo to run this script."
else
  fancy_message info "Running as root."
fi

if [ -z "${SUDO_USER}" ]; then
  fancy_message error "You must use sudo to run this script"
else
  fancy_message info "Called via sudo."
  SUDO_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
fi

if command -v lsb_release 1>/dev/null; then
  fancy_message info "Detected lsb_release."
else
  fancy_message error "lsb_release not detected. Quitting."
fi

OS_ID=$(lsb_release --id --short)
case "${OS_ID}" in
  Elementary) fancy_message info "elementary OS detected.";;
  Linuxmint) fancy_message info "Linux Mint detected.";;
  Neon) fancy_message info "KDE Neon detected.";;
  Pop) fancy_message info "Pop!_OS detected.";;
  Ubuntu) fancy_message info "Ubuntu detected.";;
  Zorin) fancy_message info "Zorin OS detected.";;
  *) fancy_message error "${OS_ID} is not supported.";;
esac

OS_CODENAME=$(lsb_release --codename --short)
if [ -e /etc/os-release ]; then
    UBUNTU_CODENAME=$(grep UBUNTU_CODENAME /etc/os-release | cut -d'=' -f2)
else
    fancy_message fatal "/etc/os-release not found. Quitting"
fi

case "${UBUNTU_CODENAME}" in
    focal|jammy|kinetic) true;;
    *) fancy_message fatal "${OS_ID_PRETTY} ${OS_CODENAME^} is not supported because it is not derived from a supported Ubuntu release.";;
esac

fancy_message info "Updating apt."
add-apt-repository -y --no-update ppa:flexiondotorg/obs-fully-loaded >/dev/null 2>&1
apt-get -q=2 -y update

CACHE_DIR="${SUDO_HOME}/.cache/obs-install"
PLUGIN_DIR="${SUDO_HOME}/.config/obs-studio/plugins"
THEME_DIR="${SUDO_HOME}/.config/obs-studio/themes"
rm -rf "${THEME_DIR}"
mkdir -p "${CACHE_DIR}"
mkdir -p "${PLUGIN_DIR}"
mkdir -p "${THEME_DIR}"

# Cache a copy of the OBS Studio .debs before installing them.
# If a future update breaks compatibility, you can manually rollback.
#   sudo apt -y install ~/.cache/obs-install/libobs0_27.2.3+fullyloaded1-1~jammy22.079.020825_amd64.deb \
#   ~/.cache/obs-install/obs-plugins_27.2.3+fullyloaded1-1~jammy22.079.020825_amd64.deb \
#   ~/.cache/obs-install/obs-studio_27.2.3+fullyloaded1-1~jammy22.079.020825_amd64.deb
apt_download "libobs0"
apt_download "obs-plugins"
apt_download "obs-studio"

# Install .deb plugins to /usr/lib/obs-plugins
install_deb "https://github.com/norihiro/obs-audio-pan-filter/releases/download/0.1.2/obs-audio-pan-filter_1-0.1.2-1_amd64.deb"
install_deb "https://github.com/norihiro/obs-command-source/releases/download/0.2.1/obs-command-source_1-0.2.1-1_amd64.deb"
install_deb "https://github.com/Palakis/obs-ndi/releases/download/4.9.1/libndi4_4.5.1-1_amd64.deb"
install_deb "https://github.com/norihiro/obs-multisource-effect/releases/download/0.1.7/obs-multisource-effect_1-0.1.7-1_amd64.deb"
install_deb "https://github.com/Palakis/obs-ndi/releases/download/4.9.1/obs-ndi_4.9.1-1_amd64.deb"
#install_deb "https://github.com/norihiro/obs-text-pthread/releases/download/1.0.3/obs-text-pthread_1-1.0.3-1_amd64.deb"
install_deb "https://github.com/jbwong05/obs-pulseaudio-app-capture/releases/download/v0.1.0/obs-pulseaudio-app-capture_0.1.0-1_amd64.deb"
install_deb "https://github.com/iamscottxu/obs-rtspserver/releases/download/v2.2.1/obs-rtspserver-v2.2.1-linux.deb"
install_deb "https://github.com/cg2121/obs-soundboard/releases/download/1.0.3/obs-soundboard_1.0.3-1_amd64.deb"
install_deb "https://github.com/norihiro/obs-vnc/releases/download/0.4.0/obs-vnc_1-0.4.0-1_amd64.deb"
# https://github.com/obsproject/obs-websocket/discussions/909#discussioncomment-2144745
install_deb "https://github.com/obsproject/obs-websocket/releases/download/4.9.1/obs-websocket_4.9.1-1_amd64.deb"

# Install Exeldro's plugins to ~/.config/obs-studio/plugins
install_exeldro_plugin "https://obsproject.com/forum/resources/directory-watch-media.801/version/4096/download?file=81705" "dir-watch-media-0.6.0-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/downstream-keyer.1254/version/4225/download?file=83850" "downstream-keyer-0.2.3-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/dynamic-delay.1035/version/4069/download?file=80953" "dynamic-delay-0.1.3-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/freeze-filter.950/version/3026/download?file=65909" "freeze-filter-0.3.2-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/gradient-source.1172/version/3926/download?file=78596" "gradient-source-0.3.0-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/move-transition.913/version/4297/download?file=84808" "move-transition-2.6.1-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/recursion-effect.1008/version/3928/download?file=78616" "recursion-effect-0.0.4-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/replay-source.686/version/4089/download?file=81604" "replay-source-1.6.10-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/scene-collection-manager.1434/version/4229/download?file=83908" "scene-collection-manager-0.0.6-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/scene-notes-dock.1398/version/4036/download?file=80203" "scene-notes-dock-0.0.4-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/source-copy.1261/version/4071/download?file=81023" "source-copy-0.1.4-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/source-dock.1317/version/3987/download?file=79453" "source-dock-0.3.2-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/source-record.1285/version/4081/download?file=81309" "source-record-0.3.0-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/source-switcher.941/version/4046/download?file=80410" "source-switcher-0.4.0-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/time-warp-scan.1167/version/3475/download?file=72760" "time-warp-scan-0.1.6-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/transition-table.1174/version/4048/download?file=80591" "transition-table-0.2.3-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/virtual-cam-filter.1142/version/4031/download?file=80127" "virtual-cam-filter-0.0.5-linux64.tar.gz.zip"

# Install Tarball plugins to ~/.config/obs-studio/plugins
install_tarball_plugin "https://github.com/kkartaltepe/obs-text-pango/releases/download/v1.0/text-pango-linux.tar.gz"
install_tarball_plugin "https://github.com/dimtpap/obs-scale-to-sound/releases/download/1.2.1/obs-scale-to-sound-1.2.1-linux64.tar.gz"

# Install Zipped plugins to ~/.config/obs-studio/plugins
install_zip_plugin "https://github.com/univrsal/dvds3/releases/download/v1.1/dvd-screensaver.v1.1.linux.x64.zip"
install_zip_plugin "https://github.com/fzwoch/obs-gstreamer/releases/download/v0.3.4/obs-gstreamer.zip" "obs-gstreamer-v0.3.4.zip" "linux/*"
install_zip_plugin "https://obsproject.com/forum/resources/obs-nvfbc.796/download" "obs-nvfbc-0.0.6.zip"
install_zip_plugin "https://github.com/fzwoch/obs-teleport/releases/download/0.5.0/obs-teleport.zip" "obs-teleport-0.5.0.zip" "linux-x86_64/*"
install_zip_plugin "https://obsproject.com/forum/resources/rgb-levels.967/download" "rgb-levels-linux.zip"
install_zip_plugin "https://github.com/univrsal/spectralizer/releases/download/v1.3.4/spectralizer.v1.3.4.bin.linux.x64.zip"
install_zip_plugin "https://github.com/Xaymar/obs-StreamFX/releases/download/0.11.1/streamfx-ubuntu-20.04-0.11.1.0-g81a96998.zip"
install_zip_plugin "https://github.com/WarmUpTill/SceneSwitcher/releases/download/1.17.7/SceneSwitcher.zip" "SceneSwitcher-1.17.7.zip" "SceneSwitcher/Linux/advanced-scene-switcher/*"

# Install Zipped theme to ~/.config/obs-studio/themes
install_theme "https://github.com/cssmfc/camgirl-obs/releases/download/1.1.OBS.CGC/cgc_theme_obs.zip"
install_theme "https://github.com/WyzzyMoon/Moonlight/releases/download/v1.0/moonlight.zip"
install_theme "https://github.com/Xaymar/obs-oceanblue/releases/download/0.1/OceanBlue-0.1.zip"
install_theme "https://obsproject.com/forum/resources/twitchy.813/download" "Twitchy.zip"
install_theme "https://obsproject.com/forum/resources/youtubey-wip.817/download" "YouTubey.zip"

chown -R "${SUDO_USER}":"${SUDO_USER}" "${SUDO_HOME}/.config/obs-studio"
chown -R "${SUDO_USER}":"${SUDO_USER}" "${CACHE_DIR}"

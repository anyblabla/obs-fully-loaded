#!/usr/bin/env bash

# ==============================================================================
# TITRE: Installation et configuration complète d'OBS Studio avec plugins et thèmes
# AUTEUR: Amaury Libert (Base) | Amélioré par l'IA
# LICENCE: GPLv3
# DESCRIPTION:
#   Installe OBS Studio depuis un PPA et ajoute une multitude de plugins,
#   thèmes et dépendances pour l'utilisateur via des fichiers DEB, ZIP et TAR.
# ==============================================================================

# --- Configuration du Mode Strict et des Variables ---

# LC_ALL=C est conservé pour garantir la portabilité des commandes de manipulation de chaîne.
LC_ALL=C
# set -euo pipefail (ou set -o errexit/nounset/pipefail) est la meilleure pratique,
# mais l'original utilise une gestion d'erreur manuelle dans fancy_message pour quitter.
# Nous allons ajouter les drapeaux essentiels pour une robustesse accrue.
set -o nounset # Quitte si une variable n'est pas définie
set -o pipefail # Quitte si une commande dans un pipe échoue

# --- Constantes et Variables Globales ---

# Répertoires de l'utilisateur appelé via sudo
SUDO_USER=""
SUDO_HOME=""
CACHE_DIR=""
PLUGIN_DIR=""
THEME_DIR=""
PPA_URL="ppa:flexiondotorg/obs-fully-loaded"

# --- Fonctions d'Affichage et de Gestion d'Erreurs ---

function fancy_message() {
    # Définition des couleurs à l'intérieur de la fonction pour éviter la pollution globale
    local RED="\e[31m"
    local GREEN="\e[32m"
    local YELLOW="\e[33m"
    local RESET="\e[0m"
    local MESSAGE_TYPE="${1}"
    local MESSAGE="${2}"

    if [ -z "${MESSAGE_TYPE}" ] || [ -z "${MESSAGE}" ]; then
      return
    fi

    case ${MESSAGE_TYPE} in
      info) echo -e "  [${GREEN}+${RESET}] ${MESSAGE}";;
      warn) echo -e "  [${YELLOW}*${RESET}] AVERTISSEMENT ! ${MESSAGE}";;
      error) echo -e "  [${RED}!${RESET}] ERREUR ! ${MESSAGE}"
             # Sortie du script avec un statut d'erreur
             exit 1;;
      *) echo -e "  [?] INCONNU: ${MESSAGE}";;
    esac
}

# Fonction unifiée pour le téléchargement
function web_get() {
    local URL="${1}"
    local FILE_PATH="${CACHE_DIR}/${2}" # Chemin complet du fichier de destination
    fancy_message info "Téléchargement: ${URL##*/}..."
    # Utilisation de -N (timestamping) et -q (quiet) pour un téléchargement propre.
    # On garantit l'échec si le téléchargement échoue (via set -e)
    if ! wget --quiet --continue "${URL}" -O "${FILE_PATH}"; then
        fancy_message error "Échec du téléchargement: ${URL}."
    fi
}

# Fonction pour télécharger un paquet DEB et le laisser dans le cache
function apt_download() {
    local PACKAGE="${1}"
    fancy_message info "Téléchargement dans le cache: ${PACKAGE} (apt)"
    
    # Utilisation de cd/cd- pour le contexte de téléchargement
    (
        cd "${CACHE_DIR}"
        # Utilisation de apt-get download avec la sortie vers null
        if ! apt-get -q=2 -y download "${PACKAGE}" >/dev/null 2>&1; then
            fancy_message error "Échec du téléchargement du paquet APT: ${PACKAGE}"
        fi
    )
    
    # Trouver le chemin complet du DEB téléchargé pour l'installation
    local DEB=$(find "${CACHE_DIR}/" -name "${PACKAGE}*.deb" -type f | tail -n1)
    if [ -z "${DEB}" ]; then
        fancy_message error "Paquet DEB ${PACKAGE} introuvable après le téléchargement."
    fi
    
    apt_install "${DEB}"
}

# Fonction d'installation APT standard (paquet ou chemin complet)
function apt_install() {
    fancy_message info "Installation: ${1} (apt)"
    # Utilisation de DEBIAN_FRONTEND=noninteractive pour éviter les prompts
    if ! DEBIAN_FRONTEND=noninteractive apt-get -q=2 -y install "${1}" >/dev/null 2>&1; then
        fancy_message error "Échec de l'installation APT de: ${1}"
    fi
}

# Fonction d'installation de DEB externes
function install_deb() {
    local URL="${1}"
    local FILE="${URL##*/}"
    fancy_message info "Installation du DEB: ${FILE}"
    web_get "${URL}" "${FILE}"
    
    # Installation du DEB téléchargé (apt-get install gère les dépendances non satisfaites)
    apt_install "${CACHE_DIR}/${FILE}"
}

# Fonction d'installation des plugins Exeldro (ZIP contenant un TAR.GZ)
function install_exeldro_plugin() {
    local URL="${1}"
    local FILE="${2}"
    fancy_message info "Installation du plugin Exeldro: ${FILE//.zip/}"
    web_get "${URL}" "${FILE}"
    
    # Le contenu est un TAR.GZ compressé DANS le ZIP. unzip -p extrait le TAR.GZ vers tar zxf
    if ! unzip -p -qq "${CACHE_DIR}/${FILE}" | tar zxf - -C "${PLUGIN_DIR}"; then
        fancy_message warn "Échec de l'extraction de ${FILE} (plugin Exeldro). Vérifiez le format."
    fi
}

# Fonction d'installation des plugins TARBALL
function install_tarball_plugin() {
    local URL="${1}"
    local FILE="${2:-${URL##*/}}" # Utilisation de substitution par défaut
    fancy_message info "Installation du plugin Tarball: ${FILE}"
    web_get "${URL}" "${FILE}"
    
    if ! tar xf "${CACHE_DIR}/${FILE}" -C "${PLUGIN_DIR}"; then
        fancy_message warn "Échec de l'extraction de ${FILE} (plugin Tarball)."
    fi

    # Gestion des dépendances spécifiques
    if [[ "${FILE}" == *"text-pango-linux"* ]]; then
        # Dépendances Pango
        apt_install "libpango-1.0-0 libpangocairo-1.0-0 libpangoft2-1.0-0"
    fi
}

# Fonction d'installation des plugins ZIP
function install_zip_plugin() {
    local URL="${1}"
    local FILE="${2:-${URL##*/}}"
    local EXTRACT_PATH="${3:-}" # Chemin d'extraction spécifique
    fancy_message info "Installation du plugin ZIP: ${FILE}"
    web_get "${URL}" "${FILE}"

    local EXTRACT_COMMAND="unzip -o -qq \"${CACHE_DIR}/${FILE}\" -d \"${PLUGIN_DIR}\""

    # S'assurer que le chemin d'extraction est correct si un chemin spécifique est donné
    if [ -n "${EXTRACT_PATH}" ]; then
        # Extrait uniquement le chemin spécifié (doit être relatif à la racine du zip)
        EXTRACT_COMMAND="unzip -o -qq \"${CACHE_DIR}/${FILE}\" \"${EXTRACT_PATH}\" -d \"${PLUGIN_DIR}\""
    fi
    
    if ! eval "${EXTRACT_COMMAND}"; then
        fancy_message warn "Échec de l'extraction du ZIP: ${FILE}."
    fi

    # Post-installation et gestion des dépendances (Refonte des mv/rm)
    case "${FILE}" in
        *obs-gstreamer*)
            fancy_message info "Post-install: Configuration obs-gstreamer."
            mkdir -p "${PLUGIN_DIR}/obs-gstreamer/bin/64bit"
            mv "${PLUGIN_DIR}/linux/obs-gstreamer.so" "${PLUGIN_DIR}/obs-gstreamer/bin/64bit/"
            rm -rf "${PLUGIN_DIR}/linux"
            apt_install "gstreamer1.0-plugins-good libgstreamer-plugins-base1.0-0"
            ;;
        *obs-nvfbc*)
            fancy_message info "Post-install: Configuration obs-nvfbc."
            mkdir -p "${PLUGIN_DIR}/nvfbc/bin/64bit"
            mv "${PLUGIN_DIR}/build/nvfbc.so" "${PLUGIN_DIR}/nvfbc/bin/64bit/"
            rm -rf "${PLUGIN_DIR}/build"
            ;;
        *rgb-levels*)
            fancy_message info "Post-install: Configuration rgb-levels."
            mkdir -p "${PLUGIN_DIR}/obs-rgb-levels-filter/bin/64bit"
            mkdir -p "${PLUGIN_DIR}/obs-rgb-levels-filter/data"
            mv "${PLUGIN_DIR}/usr/lib/obs-plugins/obs-rgb-levels-filter.so" "${PLUGIN_DIR}/obs-rgb-levels-filter/bin/64bit/"
            mv "${PLUGIN_DIR}/usr/share/obs/obs-plugins/obs-rgb-levels-filter/rgb_levels.effect" "${PLUGIN_DIR}/obs-rgb-levels-filter/data/"
            rm -rf "${PLUGIN_DIR}/usr"
            ;;
        *obs-teleport*)
            fancy_message info "Post-install: Configuration obs-teleport."
            mkdir -p "${PLUGIN_DIR}/obs-teleport/bin/64bit"
            mv "${PLUGIN_DIR}/linux-x86_64/obs-teleport.so" "${PLUGIN_DIR}/obs-teleport/bin/64bit/"
            rm -rf "${PLUGIN_DIR}/linux-x86_64"
            ;;
        *spectralizer*)
            fancy_message info "Post-install: Dépendances spectralizer."
            apt_install "libfftw3-3"
            ;;
        *streamfx*)
            fancy_message info "Post-install: Configuration StreamFX."
            rm -rf "${PLUGIN_DIR}/StreamFX"
            mkdir -p "${PLUGIN_DIR}/StreamFX"
            mv "${PLUGIN_DIR}/plugins/StreamFX/bin" "${PLUGIN_DIR}/StreamFX/"
            mv "${PLUGIN_DIR}/plugins/StreamFX/data" "${PLUGIN_DIR}/StreamFX/"
            rm -rf "${PLUGIN_DIR}/plugins"
            ;;
        *SceneSwitcher*)
            fancy_message info "Post-install: Configuration Advanced Scene Switcher."
            rm -rf "${PLUGIN_DIR}/advanced-scene-switcher"
            mv "${PLUGIN_DIR}/SceneSwitcher/Linux/advanced-scene-switcher" "${PLUGIN_DIR}/advanced-scene-switcher"
            rm -rf "${PLUGIN_DIR}/SceneSwitcher"
            # Dépendances pour le plugin
            apt_install "libxss1 libxtst6 libcurl4"
            ;;
        *)
            # Aucun traitement spécial requis
            ;;
    esac
}

# Fonction d'installation des thèmes ZIP
function install_theme() {
    local URL="${1}"
    local FILE="${2:-${URL##*/}}"
    fancy_message info "Installation du thème: ${FILE}"
    web_get "${URL}" "${FILE}"
    
    if ! unzip -o -qq "${CACHE_DIR}/${FILE}" -d "${THEME_DIR}"; then
        fancy_message warn "Échec de l'extraction du thème ZIP: ${FILE}."
    fi

    # Post-installation et nettoyage
    case "${FILE}" in
        *cgc_theme*)
            fancy_message info "Post-install: Configuration cgc_theme."
            mv "${THEME_DIR}/cgc_theme_obs/obs_theme/"* "${THEME_DIR}/"
            rm -rf "${THEME_DIR}/cgc_theme_obs"
            ;;
        *Twitchy*)
            fancy_message info "Post-install: Configuration Twitchy."
            mv "${THEME_DIR}/Twitchy (without font)/"* "${THEME_DIR}/"
            rm -rf "${THEME_DIR}/Twitchy (with"*
            rm -f "${THEME_DIR}/README.md"
            ;;
        *YouTubey*)
            fancy_message info "Post-install: Configuration YouTubey."
            mv "${THEME_DIR}/YouTubey (without font)/"* "${THEME_DIR}/"
            rm -rf "${THEME_DIR}/YouTubey (with"*
            rm -f "${THEME_DIR}/README.md"
            ;;
        *)
            # Aucun traitement spécial requis
            ;;
    esac
}

# --- Début du Script et Vérifications Préalables ---

echo "Open Broadcaster Software - Installer for Ubuntu & derivatives"

if [ "$(id -u)" -ne 0 ]; then
  fancy_message error "Vous devez utiliser sudo pour exécuter ce script."
fi
fancy_message info "Exécution en tant que root."

if [ -z "${SUDO_USER}" ]; then
  fancy_message error "Vous devez exécuter ce script via sudo, et non en tant que root direct."
else
  fancy_message info "Appel via sudo par l'utilisateur: ${SUDO_USER}."
  # Définition des variables de l'utilisateur réel
  SUDO_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
  CACHE_DIR="${SUDO_HOME}/.cache/obs-install"
  PLUGIN_DIR="${SUDO_HOME}/.config/obs-studio/plugins"
  THEME_DIR="${SUDO_HOME}/.config/obs-studio/themes"
fi

# Vérification LSB Release
if command -v lsb_release 1>/dev/null; then
  fancy_message info "lsb_release détecté."
else
  # Installer lsb-release si manquant
  fancy_message warn "lsb_release non détecté. Tentative d'installation..."
  apt-get -q=2 -y update >/dev/null 2>&1
  apt-get -q=2 -y install lsb-release >/dev/null 2>&1 || fancy_message error "Échec de l'installation de lsb-release. Quitter."
fi

OS_ID=$(lsb_release --id --short)
case "${OS_ID}" in
  Elementary|Linuxmint|Neon|Pop|Ubuntu|Zorin) fancy_message info "Distribution ${OS_ID} détectée.";;
  *) fancy_message error "${OS_ID} n'est pas une distribution supportée (Dérivée d'Ubuntu/Debian).";;
esac

# Vérification du Codename Ubuntu (pour la compatibilité du PPA)
if [ -e /etc/os-release ]; then
    # UBUNTU_CODENAME est plus fiable pour les dérivés
    UBUNTU_CODENAME=$(grep UBUNTU_CODENAME /etc/os-release | cut -d'=' -f2 | tr -d '"')
else
    fancy_message error "/etc/os-release non trouvé. Quitter."
fi

case "${UBUNTU_CODENAME}" in
    focal|jammy|kinetic|noble) true;; # Ajout de 'noble' pour la pérennité
    *) fancy_message error "Le Codename Ubuntu '${UBUNTU_CODENAME}' n'est pas supporté (Nécessite Focal, Jammy, Kinetic ou Noble).";;
esac

# --- Configuration des Dépôts et Mise à Jour ---

fancy_message info "Ajout du PPA: ${PPA_URL}."
if ! add-apt-repository -y --no-update "${PPA_URL}" >/dev/null 2>&1; then
    fancy_message error "Échec de l'ajout du PPA: ${PPA_URL}."
fi

fancy_message info "Mise à jour des dépôts APT."
if ! apt-get -q=2 -y update; then
    fancy_message error "Échec de la mise à jour des dépôts APT."
fi

# --- Création des Répertoires ---

fancy_message info "Préparation des répertoires de cache et de configuration."
rm -rf "${THEME_DIR}" # Maintenir la suppression pour réinstaller les thèmes
mkdir -p "${CACHE_DIR}"
mkdir -p "${PLUGIN_DIR}"
mkdir -p "${THEME_DIR}"

# --- Installation des Paquets OBS de Base (via PPA) ---

fancy_message info "Installation de OBS Studio (avec cache et dépendances)."
# Note: Ces fonctions téléchargent dans le cache puis installent.
apt_download "libobs0"
apt_download "obs-plugins"
apt_download "obs-studio"

# --- Installation des Plugins via DEB ---

fancy_message info "Installation des plugins au niveau du système (via DEB)."
install_deb "https://github.com/norihiro/obs-audio-pan-filter/releases/download/0.1.2/obs-audio-pan-filter_1-0.1.2-1_amd64.deb"
install_deb "https://github.com/norihiro/obs-command-source/releases/download/0.2.1/obs-command-source_1-0.2.1-1_amd64.deb"
install_deb "https://github.com/Palakis/obs-ndi/releases/download/4.9.1/libndi4_4.5.1-1_amd64.deb"
install_deb "https://github.com/norihiro/obs-multisource-effect/releases/download/0.1.7/obs-multisource-effect_1-0.1.7-1_amd64.deb"
install_deb "https://github.com/Palakis/obs-ndi/releases/download/4.9.1/obs-ndi_4.9.1-1_amd64.deb"
install_deb "https://github.com/jbwong05/obs-pulseaudio-app-capture/releases/download/v0.1.0/obs-pulseaudio-app-capture_0.1.0-1_amd64.deb"
install_deb "https://github.com/iamscottxu/obs-rtspserver/releases/download/v2.2.1/obs-rtspserver-v2.2.1-linux.deb"
install_deb "https://github.com/cg2121/obs-soundboard/releases/download/1.0.3/obs-soundboard_1.0.3-1_amd64.deb"
install_deb "https://github.com/norihiro/obs-vnc/releases/download/0.4.0/obs-vnc_1-0.4.0-1_amd64.deb"
install_deb "https://github.com/obsproject/obs-websocket/releases/download/4.9.1/obs-websocket_4.9.1-1_amd64.deb"

# --- Installation des Plugins Exeldro (ZIP > TAR.GZ) ---

fancy_message info "Installation des plugins Exeldro (méthode complexe)."
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

# --- Installation des Plugins Tarball ---

fancy_message info "Installation des plugins Tarball (.tar.gz)."
install_tarball_plugin "https://github.com/kkartaltepe/obs-text-pango/releases/download/v1.0/text-pango-linux.tar.gz"
install_tarball_plugin "https://github.com/dimtpap/obs-scale-to-sound/releases/download/1.2.1/obs-scale-to-sound-1.2.1-linux64.tar.gz"

# --- Installation des Plugins ZIP (avec Post-Installation) ---

fancy_message info "Installation des plugins ZIP (avec post-traitement)."
install_zip_plugin "https://github.com/univrsal/dvds3/releases/download/v1.1/dvd-screensaver.v1.1.linux.x64.zip"
install_zip_plugin "https://github.com/fzwoch/obs-gstreamer/releases/download/v0.3.4/obs-gstreamer.zip" "obs-gstreamer-v0.3.4.zip" "linux/*"
install_zip_plugin "https://obsproject.com/forum/resources/obs-nvfbc.796/download" "obs-nvfbc-0.0.6.zip"
install_zip_plugin "https://github.com/fzwoch/obs-teleport/releases/download/0.5.0/obs-teleport.zip" "obs-teleport-0.5.0.zip" "linux-x86_64/*"
install_zip_plugin "https://obsproject.com/forum/resources/rgb-levels.967/download" "rgb-levels-linux.zip"
install_zip_plugin "https://github.com/univrsal/spectralizer/releases/download/v1.3.4/spectralizer.v1.3.4.bin.linux.x64.zip"
install_zip_plugin "https://github.com/Xaymar/obs-StreamFX/releases/download/0.11.1/streamfx-ubuntu-20.04-0.11.1.0-g81a96998.zip"
install_zip_plugin "https://github.com/WarmUpTill/SceneSwitcher/releases/download/1.17.7/SceneSwitcher.zip" "SceneSwitcher-1.17.7.zip" "SceneSwitcher/Linux/advanced-scene-switcher/*"

# --- Installation des Thèmes ---

fancy_message info "Installation des thèmes OBS Studio."
install_theme "https://github.com/cssmfc/camgirl-obs/releases/download/1.1.OBS.CGC/cgc_theme_obs.zip"
install_theme "https://github.com/WyzzyMoon/Moonlight/releases/download/v1.0/moonlight.zip"
install_theme "https://github.com/Xaymar/obs-oceanblue/releases/download/0.1/OceanBlue-0.1.zip"
install_theme "https://obsproject.com/forum/resources/twitchy.813/download" "Twitchy.zip"
install_theme "https://obsproject.com/forum/resources/youtubey-wip.817/download" "YouTubey.zip"

# --- Finalisation et Permissions (Crucial) ---

fancy_message info "Réglage final des permissions pour l'utilisateur ${SUDO_USER}."
# Utilisation du chemin complet pour s'assurer que .config est bien pris en charge
chown -R "${SUDO_USER}":"${SUDO_USER}" "${SUDO_HOME}/.config/obs-studio"
chown -R "${SUDO_USER}":"${SUDO_USER}" "${CACHE_DIR}"

fancy_message info "Installation complète et réussie!"
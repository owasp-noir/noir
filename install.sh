#!/usr/bin/env bash

_help() {
  cat <<END

USAGE

    $ ./install.sh [--version=<crystal-version>] [--channel=stable|unstable|nightly]

  - crystal-version: "latest", or a minor release version like 1.0 or 1.1 (Default: latest)
  - channel: "stable", "unstable", "nightly" (Default: stable)

REQUIREMENTS

  - Run as root
  - The following packages need to be installed already:
    - gnupg ca-certificates apt-transport-https (on Debian/Ubuntu)

NOTES

  The following files may be updated:

  - /etc/apt/sources.list.d/crystal.list (on Debian/Ubuntu)
  - /etc/yum.repos.d/crystal.repo (on CentOS/Fedora)

  The following packages may be installed:

  - wget (on Debian/Ubuntu when missing)
  - curl (on openSUSE when missing)
  - yum-utils (on CentOS/Fedora when using --version=x.y.z)

  This script source and issue-tracker can be found at:

  - https://github.com/crystal-lang/distribution-scripts/tree/master/packages/scripts/install.sh

END
}

set -eu

OBS_PROJECT=${OBS_PROJECT:-"devel:languages:crystal"}
DISTRO_REPO=${DISTRO_REPO:-}
CRYSTAL_VERSION=${CRYSTAL_VERSION:-"latest"}
CHANNEL="stable"

_error() {
  echo >&2 "ERROR: $*"
}

_warn() {
  echo >&2 "WARNING: $*"
}

_check_version_id() {
  if [[ -z "${VERSION_ID}" ]]; then
    _error "Unable to identify distribution repository for ${ID}. Please, report to https://forum.crystal-lang.org/c/help-support/11"
    exit 1
  fi
}

_discover_distro_repo() {
  if [[ -r /etc/os-release ]]; then
    source /etc/os-release
  elif [[ -r /usr/lib/os-release ]]; then
    source /usr/lib/os-release
  else
    _error "Unable to identify distribution. Please, report to https://forum.crystal-lang.org/c/help-support/11"
    exit 1
  fi

  case "$ID" in
    debian)
      if [[ -z "${VERSION_ID:-}" ]]; then
        VERSION_ID="Unstable"
      elif [[ "$VERSION_ID" == "9" ]]; then
        VERSION_ID="$VERSION_ID.0"
      fi
      _check_version_id

      DISTRO_REPO="Debian_${VERSION_ID}"
      ;;
    ubuntu)
      _check_version_id
      DISTRO_REPO="xUbuntu_${VERSION_ID}"
      ;;
    fedora)
      _check_version_id
      if [[ "${VERSION}" == *"Prerelease"* ]]; then
        DISTRO_REPO="Fedora_Rawhide"
      else
        DISTRO_REPO="Fedora_${VERSION_ID}"
      fi
      ;;
    centos)
      _check_version_id
      DISTRO_REPO="CentOS_${VERSION_ID}"
      ;;
    rhel)
      _check_version_id
      DISTRO_REPO="RHEL_${VERSION_ID}"
      ;;
    opensuse-tumbleweed)
      DISTRO_REPO="openSUSE_Tumbleweed"
      ;;
    opensuse-leap)
      _check_version_id
      DISTRO_REPO="${VERSION_ID}"
      ;;
    "")
      _error "Unable to identify distribution. You may specify one with environment variable DISTRO_REPO"
      _error "Please, report to https://forum.crystal-lang.org/c/help-support/11"
      exit 1
      ;;
    *)
      # If there's no dedicated repository for the distro, try to figure out
      # if the distro is apt, dnf or rpm based and use a default repository.
      _discover_package_manager

      case "$PACKAGE_MANAGER" in
      apt)
        DISTRO_REPO="Debian_Unstable"
        ;;
      dnf)
        DISTRO_REPO="Fedora_Rawhide"
        ;;
      yum)
        DISTRO_REPO="RHEL_7"
        ;;
      unsupported_package_manager)
        _error "Unable to identify distribution type ($ID). You may specify a repository with the environment variable DISTRO_REPO"
        _error "Please, report to https://forum.crystal-lang.org/c/help-support/11"
        exit 1
        ;;
      esac
  esac
}

_discover_package_manager() {
  [[ $(command -v apt-get) ]] && PACKAGE_MANAGER="apt" && return
  [[ $(command -v dnf) ]]     && PACKAGE_MANAGER="dnf" && return
  [[ $(command -v yum) ]]     && PACKAGE_MANAGER="yum" && return
  PACKAGE_MANAGER="unsupported_package_manager"
}

if [[ $EUID -ne 0 ]]; then
  _error "This script must be run as root"
  exit 1
fi

# Parse --version=<VERSION> and --channel=<CHANNEL> arguments

for i in "$@"
do
case $i in
    --crystal=*)
    CRYSTAL_VERSION="${i#*=}"
    shift
    echo "The argument --crystal= has been deprecated, please use --version= instead." >&2
    ;;
    --version=*)
    CRYSTAL_VERSION="${i#*=}"
    shift
    ;;
    --channel=*)
    CHANNEL="${i#*=}"
    shift
    ;;
    --help)
    _help
    exit 0
    shift
    ;;
    *)
    _warn "Invalid option $i"
    ;;
esac
done

case $CHANNEL in
  stable)
    ;;
  nightly | unstable)
    OBS_PROJECT="${OBS_PROJECT}:${CHANNEL}"
    ;;
  *)
    _error "Unsupported channel $CHANNEL"
    exit 1
    ;;
esac

if [[ -z "${DISTRO_REPO}" ]]; then
  _discover_distro_repo
fi

_install_apt() {
  if ! command -v wget &> /dev/null || ! command -v gpg &> /dev/null; then
    [[ -f /etc/apt/sources.list.d/crystal.list ]] && rm -f /etc/apt/sources.list.d/crystal.list
    apt-get update
    apt-get install -y wget gpg
  fi

  # Add repo signign key
  wget -qO- https://download.opensuse.org/repositories/${OBS_PROJECT//:/:\/}/${DISTRO_REPO}/Release.key | gpg --dearmor | tee /etc/apt/trusted.gpg.d/devel_languages_crystal.gpg > /dev/null
  echo "deb http://download.opensuse.org/repositories/${OBS_PROJECT//:/:\/}/${DISTRO_REPO}/ /" | tee /etc/apt/sources.list.d/crystal.list
  apt-get update

  if [[ "$CRYSTAL_VERSION" == "latest" ]]; then
    apt-get install -y crystal
  else
    apt-get install -y "crystal${CRYSTAL_VERSION}"
  fi
}

_install_rpm_key() {
  rpm --verbose --import https://build.opensuse.org/projects/${OBS_PROJECT}/signing_keys/download?kind=gpg
}

_add_yum_repo() {
  cat > /etc/yum.repos.d/crystal.repo <<EOF
[crystal]
name=Crystal (${DISTRO_REPO})
type=rpm-md
baseurl=https://download.opensuse.org/repositories/${OBS_PROJECT//:/:\/}/${DISTRO_REPO}/
gpgcheck=1
gpgkey=https://download.opensuse.org/repositories/${OBS_PROJECT//:/:\/}/${DISTRO_REPO}/repodata/repomd.xml.key
enabled=1
EOF
}

_install_yum() {
  _install_rpm_key
  _add_yum_repo

  if [[ "$CRYSTAL_VERSION" == "latest" ]]; then
    yum install -y crystal
  else
    yum install -y "crystal${CRYSTAL_VERSION}"
  fi
}

_install_dnf() {
  _install_rpm_key
  _add_yum_repo

  if [[ "$CRYSTAL_VERSION" == "latest" ]]; then
    dnf install -y crystal
  else
    dnf install -y "crystal${CRYSTAL_VERSION}"
  fi
}

_install_zypper() {
  if ! command -v curl &> /dev/null; then
    zypper refresh
    zypper install -y curl
  fi

  _install_rpm_key
  zypper --non-interactive addrepo https://download.opensuse.org/repositories/${OBS_PROJECT//:/:\/}/$DISTRO_REPO/${OBS_PROJECT}.repo
  zypper --non-interactive refresh

  if [[ "$CRYSTAL_VERSION" == "latest" ]]; then
    zypper --non-interactive install crystal
  else
    zypper --non-interactive install "crystal${CRYSTAL_VERSION}"
  fi
}

# Add repo
case $DISTRO_REPO in
  Debian*)
    _install_apt
    ;;
  xUbuntu*)
    _install_apt
    ;;
  Fedora*)
    _install_dnf
    ;;
  RHEL*)
    _install_yum
    ;;
  CentOS*)
    _install_yum
    ;;
  15.* | openSUSE*)
    _install_zypper
    ;;
  *)
    _error "Unable to install for $DISTRO_REPO. Please, report to https://forum.crystal-lang.org/c/help-support/11"
    exit 1
    ;;
esac

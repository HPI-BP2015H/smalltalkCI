################################################################################
# This file provides Squeak support for smalltalkCI. It is used in the context
# of a smalltalkCI build and it is not meant to be executed by itself.
################################################################################

readonly BASE_DOWNLOAD="https://www.hpi.uni-potsdam.de/hirschfeld/artefacts/\
smalltalkci"
readonly IMAGE_DOWNLOAD="${BASE_DOWNLOAD}"
readonly VM_DOWNLOAD="${BASE_DOWNLOAD}/vms"

################################################################################
# Select Squeak image. Exit with '1' if smalltalk_name is unsupported.
# Arguments:
#   Smalltalk image name
# Prints:
#   Image filename string
################################################################################
squeak::get_image_filename() {
  local smalltalk_name=$1

  case "${smalltalk_name}" in
    "Squeak-trunk"|"Squeak-Trunk"|"SqueakTrunk")
      echo "Squeak-Trunk.tar.gz"
      ;;
    "Squeak-5.0"|"Squeak5.0")
      echo "Squeak-5.0.tar.gz"
      ;;
    "Squeak-4.6"|"Squeak4.6")
      echo "Squeak-4.6.tar.gz"
      ;;
    "Squeak-4.5"|"Squeak4.5")
      echo "Squeak-4.5.tar.gz"
      ;;
    *)
      echo ""
      ;;
  esac
}

################################################################################
# Download image if necessary and extract it.
# Globals:
#   IMAGE_DOWNLOAD
#   SMALLTALK_CI_CACHE
#   SMALLTALK_CI_BUILD
#   SMALLTALK_CI_IMAGE
# Arguments:
#   smalltalk_name
################################################################################
squeak::prepare_image() {
  local smalltalk_name=$1
  local image_filename
  local download_url
  local target

  image_filename=$(squeak::get_image_filename "${smalltalk_name}")
  download_url="${IMAGE_DOWNLOAD}/${image_filename}"
  target="${SMALLTALK_CI_CACHE}/${image_filename}"

  if is_empty "${image_filename}"; then
    print_error_and_exit "Unsupported Squeak version '${smalltalk_name}'."
  fi

  if ! is_file "${target}"; then
    travis_fold start download_image "Downloading ${smalltalk_name} testing image..."
      timer_start

      set +e
      download_file "${download_url}" > "${target}"
      if [[ ! $? -eq 0 ]]; then
        rm -f "${target}"
        print_error_and_exit "Download failed."
      fi
      set -e

      timer_finish
    travis_fold end download_image
  fi

  print_info "Extracting image..."
  tar xzf "${target}" -C "${SMALLTALK_CI_BUILD}"

  if ! is_file "${SMALLTALK_CI_IMAGE}"; then
    print_error_and_exit "Unable to prepare image at '${SMALLTALK_CI_IMAGE}'."
  fi
}

################################################################################
# Get vm filename and path according to build environment. Exit with '1' if
# environment is not supported.
# Globals:
#   SMALLTALK_CI_IMAGE
# Arguments:
#   os_name
#   require_spur: '1' for Spur support
# Prints:
#   'vm_filename|vm_path' string
################################################################################
squeak::get_vm_details() {
  local os_name=$1
  local require_spur=$2
  local vm_filename
  local vm_path

  case "${os_name}" in
    "Linux")
      if [[ "${require_spur}" -eq 1 ]]; then
        vm_filename="cogspurlinux-15.33.3427.tgz"
        vm_path="${SMALLTALK_CI_VMS}/cogspurlinux/squeak"
      else
        vm_filename="coglinux-15.33.3427.tgz"
        vm_path="${SMALLTALK_CI_VMS}/coglinux/squeak"
      fi
      ;;
    "Darwin")
      if [[ "${require_spur}" -eq 1 ]]; then
        vm_filename="CogSpur.app-15.33.3427.tgz"
        vm_path="${SMALLTALK_CI_VMS}/CogSpur.app/Contents/MacOS/Squeak"
      else
        vm_filename="Cog.app-15.33.3427.tgz"
        vm_path="${SMALLTALK_CI_VMS}/Cog.app/Contents/MacOS/Squeak"
      fi
      ;;
    *)
      print_error_and_exit "Unsupported platform '${os_name}'."
      ;;
  esac

  return_vars "${vm_filename}" "${vm_path}"
}

################################################################################
# Download and extract vm if necessary.
# Globals:
#   VM_DOWNLOAD
#   SMALLTALK_CI_CACHE
#   SMALLTALK_CI_VMS
################################################################################
squeak::prepare_vm() {
  local require_spur=0
  local vm_details
  local vm_filename
  local vm_path
  local download_url
  local target

  is_spur_image "${SMALLTALK_CI_IMAGE}" && require_spur=1
  vm_details=$(squeak::get_vm_details "$(uname -s)" "${require_spur}")
  set_vars vm_filename vm_path "${vm_details}"
  download_url="${VM_DOWNLOAD}/${vm_filename}"
  target="${SMALLTALK_CI_CACHE}/${vm_filename}"
  squeakssl_target="${SMALLTALK_CI_CACHE}/squeakssl.zip"
  squeakssl_bin="${SMALLTALK_CI_CACHE}/linux32/SqueakSSL"

  export SMALLTALK_CI_VM="${vm_path}"

  if ! is_file "${target}"; then
    travis_fold start download_vm "Downloading virtual machine..."
      timer_start

      set +e
      download_file "${download_url}" > "${target}"
      if [[ ! $? -eq 0 ]]; then
        rm -f "${target}"
        print_error_and_exit "Download failed."
      fi
      set -e

      timer_finish
    travis_fold end download_vm
  fi

  if ! is_file "${SMALLTALK_CI_VM}"; then
    print_info "Extracting virtual machine..."
    tar xzf "${target}" -C "${SMALLTALK_CI_VMS}"
    if ! is_file "${SMALLTALK_CI_VM}"; then
      print_error_and_exit "Unable to set vm up at '${SMALLTALK_CI_VM}'."
    fi
  fi

  travis_fold start display_vm_version "Cog VM Information"
    "${SMALLTALK_CI_VM}" -version
  travis_fold end display_vm_version
}

################################################################################
# Load project and save image.
# Locals:
#   config_headless
#   config_project_home
#   config_ston
# Globals:
#   SMALLTALK_CI_IMAGE
#   SMALLTALK_CI_VM
# Returns:
#   Status code of build
################################################################################
squeak::load_and_test_project() {
  local cog_vm_flags=""
  local status=0

  travis_fold start load_and_test "Loading and testing project..."
    timer_start

    if is_travis_build || [[ "${config_headless}" = "true" ]]; then
      case "$(uname -s)" in
        "Linux")
          cog_vm_flags="-nosound -nodisplay"
          ;;
        "Darwin")
          cog_vm_flags="-headless"
          ;;
      esac
    fi

    cat >"${SMALLTALK_CI_BUILD}/run.st" <<EOL
  [ Metacello new
    baseline: 'SmalltalkCI';
    repository: 'filetree://${SMALLTALK_CI_HOME}/repository';
    onConflict: [:ex | ex pass];
    load ] on: Warning do: [:w | w resume ].
  SmalltalkCI runCIFor: '${config_project_home}/${config_ston}'
EOL

    "${SMALLTALK_CI_VM}" ${cog_vm_flags} "${SMALLTALK_CI_IMAGE}" \
        "${SMALLTALK_CI_BUILD}/run.st" || status=$?

    printf "\n" # Squeak exit msg is missing a linebreak

    timer_finish
  travis_fold end load_and_test

  return "${status}"
}

################################################################################
# Main entry point for Squeak builds.
# Returns:
#   Status code of build
################################################################################
run_build() {
  local exit_status=0

  squeak::prepare_image "${config_smalltalk}"
  squeak::prepare_vm
  squeak::load_and_test_project || exit_status=$?

  return "${exit_status}"
}

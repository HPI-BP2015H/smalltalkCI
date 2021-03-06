#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

readonly DEFAULT_STON_CONFIG="smalltalk.ston"
readonly INSTALL_TARGET_OSX="/usr/local/bin"

################################################################################
# Determine $SMALLTALK_CI_HOME and load helpers.
################################################################################
initialize() {
  local base_path="${BASH_SOURCE[0]}"

  trap interrupted INT

  if [[ -z "${SMALLTALK_CI_HOME:-}" ]]; then
    # Resolve symlink if necessary and fail if OS is not supported
      case "$(uname -s)" in
        "Linux")
          base_path="$(readlink -f "${base_path}")" || true
          ;;
        "Darwin")
          base_path="$(readlink "${base_path}")" || true
          ;;
        *)
          echo "Unsupported platform '$(uname -s)'." 1>&2
          exit 1
          ;;
      esac

      SMALLTALK_CI_HOME="$(cd "$(dirname "${base_path}")" && pwd)"
      source "${SMALLTALK_CI_HOME}/env_vars"
  fi

  if [[ ! -f "${SMALLTALK_CI_HOME}/run.sh" ]]; then
    echo "smalltalkCI could not be initialized." 1>&2
    exit 1
  fi

  # Load helpers
  source "${SMALLTALK_CI_HOME}/helpers.sh"
}

################################################################################
# Print notice on interrupt.
################################################################################
interrupted() {
  print_notice $'\nsmalltalkCI has been interrupted. Exiting...'
  exit 1
}

################################################################################
# Set and verify $config_project_home and $config_ston if applicable.
# Locals:
#   config_project_home
#   config_ston
# Globals:
#   TRAVIS_BUILD_DIR
# Arguments:
#   Custom project home path
################################################################################
determine_project() {
  local custom_ston="${1:-}"

  if ! is_empty "${custom_ston}" && is_file "${custom_ston}" && \
      [[ ${custom_ston: -5} == ".ston" ]]; then
    config_ston=$(basename "${custom_ston}")
    config_project_home="$(dirname "${custom_ston}")"
  else
    if is_travis_build; then
      config_project_home="${TRAVIS_BUILD_DIR}"
    else
      config_project_home="$(pwd)"
    fi
    locate_ston_config
  fi

  # Convert to absolute path if necessary
  if [[ "${config_project_home:0:1}" != "/" ]]; then
    config_project_home="$(cd "${config_project_home}" && pwd)"
  fi

  if ! is_dir "${config_project_home}"; then
    print_error_and_exit "Project home cannot be found."
  fi
}

################################################################################
# Allow STON config filename to start with a dot.
# Locals:
#   config_project_home
#   config_ston
################################################################################
locate_ston_config() {
  if ! is_file "${config_project_home}/${config_ston}"; then
    if is_file "${config_project_home}/.${config_ston}"; then
      config_ston=".${config_ston}"
    else
      print_error_and_exit "No STON file named '${config_ston}' found
                            in ${config_project_home}."
    fi
  fi
}

################################################################################
# Select Smalltalk image interactively if not already selected.
# Locals:
#   config_smalltalk
################################################################################
select_smalltalk() {
  local images="Squeak-trunk Squeak-5.0 Squeak-4.6 Squeak-4.5
                Pharo-stable Pharo-alpha Pharo-5.0 Pharo-4.0 Pharo-3.0
                GemStone-3.3.0 GemStone-3.2.12 GemStone-3.1.0.6"

  if is_not_empty "${config_smalltalk}" || is_travis_build; then
    return
  fi

  PS3="Choose Smalltalk image: "
  select selection in $images; do
    case "${selection}" in
      Squeak*|Pharo*|GemStone*)
        config_smalltalk="${selection}"
        break
        ;;
      *)
        print_error_and_exit "No Smalltalk image selected."
        ;;
    esac
  done
}

################################################################################
# Validate options and exit with '1' if an option is invalid.
# Locals:
#   config_smalltalk
################################################################################
validate_configuration() {
  if is_empty "${config_smalltalk}"; then
    print_error_and_exit "Smalltalk image is not defined."
  fi
  if is_empty "${config_ston}"; then
    print_error_and_exit "No STON file found."
  elif ! is_file "${config_ston}"; then
    print_error_and_exit "STON file at '${config_ston}' does not exist."
  fi
  if is_empty "${config_project_home}"; then
    print_error_and_exit "Project home not defined."
  elif ! is_dir "${config_project_home}"; then
    print_error_and_exit "Project home at '${config_project_home}' does not
                          exist."
  fi
}

################################################################################
# Handle user-defined options.
# Locals:
#   config_clean
#   config_debug
#   config_headless
#   config_smalltalk
#   config_verbose
# Arguments:
#   All positional parameters
################################################################################
parse_options() {
  while :
  do
    case "${1:-}" in
    --clean)
      config_clean="true"
      shift
      ;;
    -d | --debug)
      config_debug="true"
      shift
      ;;
    --gs-*)
      # Reserved namespace for GemStone options
      shift
      ;;
    -h | --help)
      print_help
      exit 0
      ;;
    --headfull)
      config_headless="false"
      shift
      ;;
    --install)
      install_script
      exit 0
      ;;
    -s | --smalltalk)
      config_smalltalk="${2:-}"
      shift 2
      ;;
    --uninstall)
      uninstall_script
      exit 0
      ;;
    -v | --verbose)
      config_verbose="true"
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      print_error_and_exit "Unknown option: $1"
      ;;
    *)
      break
      ;;
    esac
  done
}

################################################################################
# Make sure all required folders exist, create build folder and symlink project.
# Locals:
#   config_project_home
# Globals:
#   SMALLTALK_CI_CACHE
#   SMALLTALK_CI_BUILD_BASE
#   SMALLTALK_CI_VMS
#   SMALLTALK_CI_BUILD
#   SMALLTALK_CI_GIT
################################################################################
prepare_folders() {
  print_info "Preparing folders..."
  is_dir "${SMALLTALK_CI_CACHE}" || mkdir "${SMALLTALK_CI_CACHE}"
  is_dir "${SMALLTALK_CI_BUILD_BASE}" || mkdir "${SMALLTALK_CI_BUILD_BASE}"
  is_dir "${SMALLTALK_CI_VMS}" || mkdir "${SMALLTALK_CI_VMS}"

  # Create folder for this build
  if is_dir "${SMALLTALK_CI_BUILD}"; then
    print_info "Build folder already exists at ${SMALLTALK_CI_BUILD}."
  else
    mkdir "${SMALLTALK_CI_BUILD}"
  fi

  # Link project folder to git_cache
  ln -s "${config_project_home}" "${SMALLTALK_CI_GIT}"
}

################################################################################
# Run cleanup if requested by user.
# Locals:
#   config_clean
################################################################################
check_clean_up() {
  local user_input
  local question1="Are you sure you want to clear builds and cache? (y/N): "
  local question2="Continue with build progress? (y/N): "
  if [[ "${config_clean}" = "true" ]]; then
    print_info "cache at '${SMALLTALK_CI_CACHE}'."
    print_info "builds at '${SMALLTALK_CI_BUILD_BASE}'."
    read -p "${question1}" user_input
    if [[ "${user_input}" = "y" ]]; then
      clean_up
    fi
    if is_empty "${config_smalltalk}" || is_empty "${config_ston}"; then
      exit  # User did not supply enough arguments to continue
    fi
    read -p "${question2}" user_input
    [[ "${user_input}" != "y" ]] && exit 0
  fi
  return 0
}

################################################################################
# Remove all builds and clear cache.
# Globals:
#   SMALLTALK_CI_CACHE
#   SMALLTALK_CI_BUILD_BASE
################################################################################
clean_up() {
  if is_dir "${SMALLTALK_CI_CACHE}" || \
      is_dir "${SMALLTALK_CI_BUILD_BASE}"; then
    print_info "Cleaning up..."
    print_info "Removing the following directories:"
    if is_dir "${SMALLTALK_CI_CACHE}"; then
      print_info "  ${SMALLTALK_CI_CACHE}"
      rm -rf "${SMALLTALK_CI_CACHE}"
    fi
    if is_dir "${SMALLTALK_CI_BUILD_BASE}"; then
      print_info "  ${SMALLTALK_CI_BUILD_BASE}"
      # Make sure read-only files (e.g. some GemStone files) can be removed
      chmod -fR +w "${SMALLTALK_CI_BUILD_BASE}"
      rm -rf "${SMALLTALK_CI_BUILD_BASE}"
    fi
    print_info "Done."
  else
    print_notice "Nothing to clean up."
  fi
}

################################################################################
# Install 'smalltalkCI' command by symlinking current instance.
# Globals:
#   INSTALL_TARGET_OSX
################################################################################
install_script() {
  local target

  case "$(uname -s)" in
    "Linux")
      print_notice "Not yet implemented."
      ;;
    "Darwin")
      target="${INSTALL_TARGET_OSX}"
      if ! is_dir "${target}"; then
        local message = "'${target}' does not exist. Do you want to create it?
                         (y/N): "
        read -p "${message}" user_input
        if [[ "${user_input}" = "y" ]]; then
          sudo mkdir "target"
        else
          print_error_and_exit "'${target}' has not been created."
        fi
      fi
      if ! is_file "${target}/smalltalkCI"; then
        ln -s "${SMALLTALK_CI_HOME}/run.sh" "${target}/smalltalkCI"
        print_info "The command 'smalltalkCI' has been installed successfully."
      else
        print_error_and_exit "'${target}/smalltalkCI' already exists."
      fi
      ;;
  esac
}

################################################################################
# Uninstall 'smalltalkCI' command by removing any symlink to smalltalkCI.
# Globals:
#   INSTALL_TARGET_OSX
################################################################################
uninstall_script() {
  local target

  case "$(uname -s)" in
    "Linux")
      print_notice "Not yet implemented."
      ;;
    "Darwin")
      target="${INSTALL_TARGET_OSX}"
      if is_file "${target}/smalltalkCI"; then
        rm -f "${target}/smalltalkCI"
        print_info "The command 'smalltalkCI' has been uninstalled
                    successfully."
      else
        print_error_and_exit "'${target}/smalltalkCI' does not exists."
      fi
      ;;
  esac
}

################################################################################
# Load platform-specific package and run the build.
# Locals:
#   config_smalltalk
# Returns:
#   Status code of build
################################################################################
run() {
  case "${config_smalltalk}" in
    Squeak*)
      print_info "Starting Squeak build..."
      source "${SMALLTALK_CI_HOME}/squeak/run.sh"
      ;;
    Pharo*)
      print_info "Starting Pharo build..."
      source "${SMALLTALK_CI_HOME}/pharo/run.sh"
      ;;
    GemStone*)
      print_info "Starting GemStone build..."
      source "${SMALLTALK_CI_HOME}/gemstone/run.sh"
      ;;
    *)
      print_error_and_exit "Unknown Smalltalk version '${config_smalltalk}'."
      ;;
  esac

  if debug_enabled; then
    travis_fold start display_config "Current configuration"
      for var in ${!config_@}; do
        echo "${var}=${!var}"
      done
    travis_fold end display_config
  fi

  run_build "$@"
  return $?
}

################################################################################
# Main entry point. Exit with build status code.
# Arguments:
#   All positional parameters
################################################################################
main() {
  local config_smalltalk="${TRAVIS_SMALLTALK_VERSION:-}"
  local config_ston="${TRAVIS_SMALLTALK_CONFIG:-$DEFAULT_STON_CONFIG}"
  local config_project_home
  local config_builder_ci_fallback="false"
  local config_clean="false"
  local config_debug="false"
  local config_headless="true"
  local config_verbose="false"
  local exit_status=0

  initialize
  parse_options "$@"
  [[ "${config_verbose}" = "true" ]] && set -o xtrace
  determine_project "${!#}"  # Use last argument for custom STON
  check_clean_up
  select_smalltalk
  validate_configuration

  prepare_folders
  run "$@" || exit_status=$?
  if [[ "${exit_status}" -ne 0 ]]; then
    print_error "Failed to load and test project."
    exit ${exit_status}
  fi

  if is_travis_build; then
    python "${SMALLTALK_CI_HOME}/lib/coveralls_notifier.py" \
        "${SMALLTALK_CI_BUILD}"
  fi

  print_results "${SMALLTALK_CI_BUILD}" || exit_status=$?
  
  exit ${exit_status}
}

# Run main if script is not being tested
if [[ "$(basename -- "$0")" != *"test"* ]]; then
  main "$@"
fi

#!/bin/bash

set -e

readonly BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE}/helpers.sh"

if ! is_travis_build; then
  print_error_and_exit "This test needs to run on Travis."
fi

case "${TRAVIS_SMALLTALK_VERSION}" in
  GemStone*)
	if [[ "$(uname -s)" = "Darwin" ]]; then
	  print_notice "Not running fail test for GemStone on OS X."
	  exit 0
	fi
    ;;
esac

if is_empty "${SMALLTALK_CI_HOME}" || is_empty "${SMALLTALK_CI_BUILD}"; then
  print_error_and_exit "SMALLTALK_CI_HOME or SMALLTALK_CI_BUILD not set."
fi

if is_dir "${SMALLTALK_CI_BUILD}"; then
  print_info "Removing old build folder at ${SMALLTALK_CI_BUILD} ..."
  chmod -R +w "${SMALLTALK_CI_BUILD}"
  rm -rf "${SMALLTALK_CI_BUILD}"
fi

print_info "Starting second pass to check that smalltalkCI can fail..."
exit_status=0
export TRAVIS_SMALLTALK_CONFIG=".smalltalk_fail.ston"
export SMALLTALK_CI_TRAVIS_FOLD_PREFIX="p2_"
$SMALLTALK_CI_HOME/run.sh --debug || exit_status=$?

if [[ "${exit_status}" -eq 0 ]]; then
  print_error_and_exit "smalltalkCI passed unexpectedly."
fi

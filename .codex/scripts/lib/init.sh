#!/bin/bash

LIB_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./logging.sh
source "$LIB_ROOT/logging.sh"
# shellcheck source=./time.sh
source "$LIB_ROOT/time.sh"
# shellcheck source=./github.sh
source "$LIB_ROOT/github.sh"
# shellcheck source=./plan.sh
source "$LIB_ROOT/plan.sh"

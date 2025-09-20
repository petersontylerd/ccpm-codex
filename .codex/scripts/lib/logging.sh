#!/bin/bash

log_info() {
  printf '[INFO] %s\n' "$1"
}

log_warn() {
  printf '[WARN] %s\n' "$1"
}

log_error() {
  printf '[ERROR] %s\n' "$1" 1>&2
}

log_fatal() {
  printf '[FATAL] %s\n' "$1" 1>&2
  exit 1
}

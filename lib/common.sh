#!/usr/bin/env bash

LPD_NAME="Linux Performance Detective"
LPD_VERSION="0.2.0-rc1"

if [[ -t 1 && "${NO_COLOR:-0}" != "1" ]]; then
    GREEN="\033[32m"
    YELLOW="\033[33m"
    RED="\033[31m"
    BLUE="\033[34m"
    BOLD="\033[1m"
    RESET="\033[0m"
else
    GREEN=""
    YELLOW=""
    RED=""
    BLUE=""
    BOLD=""
    RESET=""
fi


print_banner() {
    printf "${BOLD}%s${RESET}\n" "$LPD_NAME"
    printf "Version: %s\n\n" "$LPD_VERSION"
}


section() {
    printf "\n${BOLD}=== %s ===${RESET}\n" "$1"
}


ok() {
    printf "${GREEN}[OK]${RESET} %s\n" "$1"
}


info() {
    printf "${BLUE}[INFO]${RESET} %s\n" "$1"
}


warn() {
    printf "${YELLOW}[WARNING]${RESET} %s\n" "$1"
}


fail() {
    printf "${RED}[ERROR]${RESET} %s\n" "$1"
}


command_exists() {
    command -v "$1" >/dev/null 2>&1
}

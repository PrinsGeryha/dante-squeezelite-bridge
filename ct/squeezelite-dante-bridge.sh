#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2026 Marcus Isdahl
# Author: Marcus Isdahl
# License: MIT
# Source: https://github.com/marcusisdahl/squeezelite-dante-bridge

APP="Squeezelite-Dante-Bridge"
var_tags="${var_tags:-audio;dante;music-assistant;squeezelite}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-0}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f "/opt/squeezelite-dante-bridge/info.txt" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  msg_info "Updating System Packages"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated System Packages"

  msg_info "Updating Statime"
  if [[ -d /opt/statime ]]; then
    cd /opt/statime
    $STD git pull
    $STD cargo build --release
  else
    $STD git clone --recurse-submodules -b inferno-dev https://github.com/teodly/statime.git /opt/statime
    cd /opt/statime
    $STD cargo build --release
  fi
  msg_ok "Updated Statime"

  msg_info "Updating Inferno ALSA Plugin"
  if [[ -d /opt/inferno ]]; then
    cd /opt/inferno
    $STD git pull
  else
    $STD git clone --recursive https://github.com/teodly/inferno.git /opt/inferno
  fi

  cd /opt/inferno/alsa_pcm_inferno
  $STD cargo build --release

  ALSA_PLUGIN_DIR="/usr/lib/x86_64-linux-gnu/alsa-lib"
  mkdir -p "$ALSA_PLUGIN_DIR"

  if [[ -f /opt/inferno/target/release/libasound_module_pcm_inferno.so ]]; then
    cp /opt/inferno/target/release/libasound_module_pcm_inferno.so "$ALSA_PLUGIN_DIR/"
  elif [[ -f /opt/inferno/alsa_pcm_inferno/target/release/libasound_module_pcm_inferno.so ]]; then
    cp /opt/inferno/alsa_pcm_inferno/target/release/libasound_module_pcm_inferno.so "$ALSA_PLUGIN_DIR/"
  else
    msg_error "Could not find libasound_module_pcm_inferno.so"
    exit 1
  fi
  msg_ok "Updated Inferno ALSA Plugin"

  msg_info "Restarting Services"
  systemctl restart statime.service
  systemctl restart squeezelite-*.service
  msg_ok "Restarted Services"

  msg_ok "Updated ${APP}"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Dante transmitter should appear in Dante Controller after the container finishes booting.${CL}"
echo -e "${INFO}${YW} Add the Squeezelite player in Music Assistant and use WAV at 48 kHz.${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Container IP: ${IP}${CL}"

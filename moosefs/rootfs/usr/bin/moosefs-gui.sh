#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Add-on: MooseFS
# Run the MooseFS GUI server in the foreground for s6 supervision.
# ==============================================================================

set -euo pipefail

main() {
    bashio::log.info "Starting MooseFS GUI on 127.0.0.1:9425"
    exec /usr/sbin/mfsgui -f -c /etc/mfs/mfsgui.cfg start
}
main "$@"

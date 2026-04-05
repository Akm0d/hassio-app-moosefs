#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Add-on: MooseFS
# Run the ingress/web proxy in the foreground.
# ==============================================================================

set -euo pipefail

main() {
    bashio::log.info "Starting lighttpd reverse proxy on 0.0.0.0:8099"
    exec /usr/sbin/lighttpd -D -f /etc/lighttpd/lighttpd.conf
}
main "$@"

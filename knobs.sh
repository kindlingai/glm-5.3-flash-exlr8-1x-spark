# The recipe's MENTAT knob as gr8's options, sourced by entrypoint.sh and bin/gr8 so every gr8 command sees the same.
#   MENTAT=0 (default): this box on its own, PEERS=127.0.0.1. Nothing is announced.
#   MENTAT=1: find this box through the host's mentat daemon (gr8's MENTAT=localhost) and announce the API in the mentat
#             cluster, in group GROUP (gr8-glm53f-1x by default, so the box never joins a multi-box Flash cluster).
case "${MENTAT:-0}" in
  0) unset MENTAT; export PEERS=${PEERS:-127.0.0.1} ;;
  1) unset PEERS; export MENTAT=localhost ;;
  localhost) unset PEERS ;;
  *) echo "MENTAT=$MENTAT: want 0 (this box alone) or 1 (register with the mentat cluster)" >&2; exit 2 ;;
esac

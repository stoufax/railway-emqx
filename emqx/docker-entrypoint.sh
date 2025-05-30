#!/usr/bin/env bash

## Shell setting
if [[ -n "$DEBUG" ]]; then
    set -ex
else
    set -e
fi

shopt -s nullglob

# Print the container's hostname for debugging
hostname

## Local IP address setting

LOCAL_IPS=($(hostname --ip-address))
LOCAL_IP=$(hostname -i | grep -o -E '([0-9a-f]{1,4}:){7}[0-9a-f]{1,4}|([0-9a-f]{1,4}:){1,7}:|([0-9a-f]{1,4}:){1,6}:[0-9a-f]{1,4}|([0-9a-f]{1,4}:){1,5}(:[0-9a-f]{1,4}){1,2}|([0-9a-f]{1,4}:){1,4}(:[0-9a-f]{1,4}){1,3}|([0-9a-f]{1,4}:){1,3}(:[0-9a-f]{1,4}){1,4}|([0-9a-f]{1,4}:){1,2}(:[0-9a-f]{1,4}){1,5}|[0-9a-f]{1,4}:((:[0-9a-f]{1,4}){1,6})|:((:[0-9a-f]{1,4}){1,7}|:)')

export EMQX_NAME="${EMQX_NAME:-emqx}"

## EMQX_NODE_NAME or EMQX_NODE__NAME to indicate the full node name to be used by EMQX
## If both are set EMQX_NODE_NAME takes higher precedence than EMQX_NODE__NAME
if [[ -z "${EMQX_NODE_NAME:-}" ]] && [[ -z "${EMQX_NODE__NAME:-}" ]]; then
    # No node name is provide from environment variables
    # try to resolve from other settings
    if [[ -z "$EMQX_HOST" ]]; then
        if [[ "$EMQX_CLUSTER__DISCOVERY_STRATEGY" == "dns" ]] && \
            [[ "$EMQX_CLUSTER__DNS__RECORD_TYPE" == "srv" ]] && \
            grep -q "$(hostname).$EMQX_CLUSTER__DNS__NAME" /etc/hosts; then
                EMQX_HOST="$(hostname).$EMQX_CLUSTER__DNS__NAME"
        elif [[ "$EMQX_CLUSTER__DISCOVERY_STRATEGY" == "k8s" ]] && \
            [[ "$EMQX_CLUSTER__K8S__ADDRESS_TYPE" == "dns" ]] && \
            [[ -n "$EMQX_CLUSTER__K8S__NAMESPACE" ]]; then
                EMQX_CLUSTER__K8S__SUFFIX=${EMQX_CLUSTER__K8S__SUFFIX:-"pod.cluster.local"}
                EMQX_HOST="${LOCAL_IP//./-}.$EMQX_CLUSTER__K8S__NAMESPACE.$EMQX_CLUSTER__K8S__SUFFIX"
        elif [[ "$EMQX_CLUSTER__DISCOVERY_STRATEGY" == "k8s" ]] && \
            [[ "$EMQX_CLUSTER__K8S__ADDRESS_TYPE" == 'hostname' ]] && \
            [[ -n "$EMQX_CLUSTER__K8S__NAMESPACE" ]]; then
                EMQX_CLUSTER__K8S__SUFFIX=${EMQX_CLUSTER__K8S__SUFFIX:-'svc.cluster.local'}
                EMQX_HOST=$(grep -h "^$LOCAL_IP" /etc/hosts | grep -o "$(hostname).*.$EMQX_CLUSTER__K8S__NAMESPACE.$EMQX_CLUSTER__K8S__SUFFIX")
        else
            EMQX_HOST="$LOCAL_IP"
        fi
        export EMQX_HOST
    fi
    export EMQX_NODE_NAME="$EMQX_NAME@$EMQX_HOST"
fi


# The default rpc port discovery 'stateless' is mostly for clusters
# having static node names. So it's trouble-free for multiple emqx nodes
# running on the same host.
# When start emqx in docker, it's mostly one emqx node in one container
# i.e. use port 5369 (or per tcp_server_port | ssl_server_port config) for gen_rpc
export EMQX_RPC__PORT_DISCOVERY="${EMQX_RPC__PORT_DISCOVERY:-manual}"

isIPv6() {
  local colons="${1//[^:]}"
  test "${#colons}" -gt 1
}

check() {
  local host="$1"
  echo "Checking $host ..."
  if emqx_ctl status && curl -fsL "http://$host/status"; then
    echo
    echo "Service is healthy."
  	exit 0
  fi
  echo "Service is not healthy!"
  exit 1
}

if isIPv6 "$LOCAL_IPS"; then
  endpoint="[$LOCAL_IPS]:$ADMIN_PORT"
else
  endpoint="$LOCAL_IPS:$ADMIN_PORT"
fi

( sleep 15; check "$endpoint") &

exec "$@"

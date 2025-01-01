#!/bin/bash
# scripts/test-vars.sh

# WARNING: Do not put TOKEN_PASSWORD in this file. Set it locallly for local
# testing, or provide it as a secret in GitHub Actions.

# NOTE: The LINODE_ID variable is provided by default in the stackscript
# environment, but that is not the case with local testing or CI environment.
# You will also have to set this separately.

declare -A UDF_VARS
UDF_VARS["KAFKA_VERSION"]="3.8.0"
UDF_VARS["SUDO_USERNAME"]="admin"
UDF_VARS["CLIENT_COUNT"]="3"
UDF_VARS["CLUSTER_SIZE"]="3"
UDF_VARS["CLUSTERHEADER"]="Yes" 
UDF_VARS["ADD_SSH_KEYS"]="yes" 
UDF_VARS["SSLHEADER"]="Yes" 
UDF_VARS["COUNTRY_NAME"]="US" 
UDF_VARS["STATE_OR_PROVINCE_NAME"]="Pennsylvania"
UDF_VARS["LOCALITY_NAME"]="Philadelphia"
UDF_VARS["ORGANIZATION_NAME"]="Akamai Technologies"
UDF_VARS["EMAIL_ADDRESS"]="webmaster@example.com"
UDF_VARS["CA_COMMON_NAME"]="Kafka RootCA"

github_env() {
  local KEY="$1"
  local VALUE="$2"
  if [ -n "$GITHUB_ENV" ]; then
    echo "$KEY=$VALUE" | tee -a $GITHUB_ENV
  fi
}

set_vars() {
  for key in "${!UDF_VARS[@]}"; do
    export "${key}"="${UDF_VARS[$key]}"
    github_env "${key}" "${UDF_VARS[$key]}"
  done
}

# main
build_dict
set_vars

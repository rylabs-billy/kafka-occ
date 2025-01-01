#!/bin/bash 
set -e
DEBUG="NO"
if [ "${DEBUG}" == "NO" ]; then
  trap "cleanup $? $LINENO" EXIT
fi

# controller temp sshkey
function controller_sshkey {
    ssh-keygen -o -a 100 -t ed25519 -C "ansible" -f "${HOME}/.ssh/id_ansible_ed25519" -q -N "" <<<y >/dev/null
    export ANSIBLE_SSH_PUB_KEY=$(cat ${HOME}/.ssh/id_ansible_ed25519.pub)
    export ANSIBLE_SSH_PRIV_KEY=$(cat ${HOME}/.ssh/id_ansible_ed25519)
    export SSH_KEY_PATH="${HOME}/.ssh/id_ansible_ed25519"
    chmod 700 ${HOME}/.ssh
    chmod 600 ${SSH_KEY_PATH}
    eval $(ssh-agent)
    ssh-add ${SSH_KEY_PATH}
}

# build instance vars before cluster deployment
function build {
  if [ "${CHECK_MODE}" ]; then
    local LINODE_PARAMS=("${INSTANCE_PREFIX}" "g6-standard-8" "us-ord" "linode/ubuntu22.04")
    local LINODE_TAGS="test"
  else
    local LINODE_PARAMS=($(curl -sH "Authorization: Bearer ${TOKEN_PASSWORD}" "https://api.linode.com/v4/linode/instances/${LINODE_ID}" | jq -r .label,.type,.region,.image))
    local LINODE_TAGS=$(curl -sH "Authorization: Bearer ${TOKEN_PASSWORD}" "https://api.linode.com/v4/linode/instances/${LINODE_ID}" | jq -r .tags)
  fi
  local KAFKA_VERSION="${KAFKA_VERSION}"
  local group_vars="${WORK_DIR}/group_vars/kafka/vars"
  local TEMP_ROOT_PASS=$(openssl rand -base64 32)

  controller_sshkey

  cat << EOF >> ${group_vars}
# user vars
sudo_username: ${SUDO_USERNAME}
token: ${TOKEN_PASSWORD}
# deployment vars
uuid: ${UUID}
ssh_keys: ${ANSIBLE_SSH_PUB_KEY}
instance_prefix: ${INSTANCE_PREFIX}
type: ${LINODE_PARAMS[1]}
region: ${LINODE_PARAMS[2]}
image: ${LINODE_PARAMS[3]}
linode_tags: ${LINODE_TAGS}
root_pass: ${TEMP_ROOT_PASS}
kafka_version: ${KAFKA_VERSION}
cluster_size: ${CLUSTER_SIZE}
controller_count: 3
client_count: ${CLIENT_COUNT}
add_ssh_keys: '${ADD_SSH_KEYS}'

# ssl config
country_name: ${COUNTRY_NAME}
state_or_province_name: ${STATE_OR_PROVINCE_NAME}
locality_name: ${LOCALITY_NAME}
organization_name: ${ORGANIZATION_NAME}
email_address: ${EMAIL_ADDRESS}
ca_common_name: ${CA_COMMON_NAME}
EOF
}

function test_instance_info {
  # for provision.yml in check mode
  cat <<EOF > info.yml
info:
  results:
    - {"instance": {"ipv4": ["127.1.0.100", "127.2.0.100"]}}
    - {"instance": {"ipv4": ["127.1.0.101", "127.2.0.102"]}}
    - {"instance": {"ipv4": ["127.1.0.103", "127.2.0.103"]}}
EOF
}

function deploy { 
    echo "[info] running ansible playbooks"
    ansible-playbook -v -i hosts provision.yml && ansible-playbook -v -i hosts site.yml
}

function test {
  echo "[info] running ansible playbooks in check mode"
  build

  # dry run provision.yml
  test_instance_info
  ansible-playbook -vvv -i hosts provision.yml --check --extra-vars "@info.yml"

  # let provision playbook write to vars and hosts files as it does...
  ansible-playbook -vvv -i hosts provision.yml --tags test_vars --extra-vars "@info.yml"
  # then dry run site.yml
  ansible-playbook -vvv -u $(whoami) -i hosts site.yml -b --become-user $(whoami) --check --extra-vars "@info.yml"
}

## cleanup ##
function cleanup {
  if [ "$?" != "0" ]; then
    if [ -n "$GITHUB_ENV" ]; then
      echo "PLAYBOOK_FAILED=1" | tee -a $GITHUB_ENV
    fi
    echo "PLAYBOOK FAILED. See /var/log/stackscript.log for details."
    rm ${HOME}/.ssh/id_ansible_ed25519{,.pub}
    destroy
    exit 1
  fi
}

function destroy {
  echo "[info] destroying instances except provisioner node" 
  ansible-playbook destroy.yml
}

# main
case $1 in
    build) "$@"; exit;;
    deploy) "$@"; exit;;
    test) "$@"; exit;;
esac

#!/bin/bash

# scripts/app-deps.sh
# configures test environment for ansible check mode

function playbook_deps {
  echo "[info] Installing playbook dependencies"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  brew install yq
  # required files from apt install
  apt install fail2ban -y
}

function kafka_deps {
  echo "[info] Configure Kafka dependencies"
  defaults="roles/kafka/defaults/main.yml"

  # add kafka user and group
  useradd --system -s /usr/bin/nologin -m $(cat $defaults | yq .kafka_data_directory)

  # write dirs and vars from roles/kafka/defaults/main.yml
  kafka_file_list=($(
    cat $defaults \
    | grep -Ev '#|---' \
    | IFS='\n' awk '{print $2}' \
    | tr '\n' ' '
    ))

  for file in "${kafka_file_list[@]}"; do
    [[ "$file" == *"kafka"* ]] && mkdir -p $file || export kafka_version="$file"
  done

  curl -s -o "/tmp/kafka_2.13-${kafka_version}.tgz" \
    "https://downloads.apache.org/kafka/${kafka_version}/kafka_2.13-${kafka_version}.tgz"
}

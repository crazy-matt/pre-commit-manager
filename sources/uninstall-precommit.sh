#!/usr/bin/env bash
# shellcheck disable=SC2143
set -e

installer_location="$HOME/.local/var/pre-commit-manager"


answer=n
if [[ "$1" != "y" ]]; then
  read -r -p 'Do you want to remove the pre-commit hooks deployer cron jobs [y/N]: ' answer
else
  answer=y
fi

if [[ "${answer}" == "y" ]]; then
  # Delete the 1st job definition
  croncmd="/bin/bash '${installer_location}/deploy_hooks.sh'"
  if [[ -n "$(crontab -l | grep "$croncmd")" ]]; then
    ( crontab -l | grep -v -F "$croncmd" ) | crontab -
    echo -e "\033[1;32m[✓]\033[0m Hooks deployer cron job removed"
  fi

  # Delete the 2nd job
  croncmd="pre-commit gc"
  if [[ -n "$(crontab -l | grep "$croncmd")" ]]; then
    ( crontab -l | grep -v -F "$croncmd" ) | crontab -
    echo -e "\033[1;32m[✓]\033[0m pre-commit cache cleanup job removed"
  fi
fi


answer=n; answer2=n
if [[ "$1" != "y" ]]; then
  read -r -p 'Do you want to remove the pre-commit hooks from all your repositories [y/N]: ' answer
  read -r -p 'Do you also want to remove all pre-commit baseline configs (.yaml) [y/N]: ' answer2
else
  answer=y; answer2=y
fi

if [[ "${answer}" == "y" ]]; then
  repo_list=$(eval "find $HOME -type d -not \( -path '/Users/${USER}/Library' -prune \
    -o -path '/Users/${USER}/Pictures' -prune \
    -o -path '/Users/${USER}/.*' -prune \
    -o -path '*.terraform/*' -prune \
    -o -path '*.terragrunt-cache/*' -prune \
    -o -path '*.history/*' -prune \) -iname '.git' -prune")

  for repo in ${repo_list}; do
    repo_path="${repo%/.git}"
    if [[ "${answer2}" == "y" ]]; then
      rm -f "${repo_path}/.pre-commit-config.yaml"
      echo -e "\033[1;32m[✓]\033[0m pre-commit baseline config removed from repo \033[1;34m${repo_path}\033[0m"
    fi
    if [[ -f "${repo_path}/.git/hook/pre-push" || -f "${repo_path}/.git/hook/commit-msg" ]]; then
      cd "${repo_path}"
      pre-commit uninstall >/dev/null 2>&1
      rm -f "${repo_path}/.git/hooks/pre-push" >/dev/null 2>&1
      rm -f "${repo_path}/.git/hooks/pre-commit" >/dev/null 2>&1
      rm -f "${repo_path}/.git/hooks/commit-msg" >/dev/null 2>&1
      echo -e "\033[1;32m[✓]\033[0m pre-commit hooks removed from repo \033[1;34m${repo_path}\033[0m"
      cd - &>/dev/null
    fi
  done
fi

# Clean out cached pre-commit files
pre-commit clean

answer=n
if [[ "$1" != "y" ]]; then
  read -r -p 'Do you want to uninstall the pre-commit framework binaries (pre-commit itself) [y/N]: ' answer
else
  answer=y
fi

if [[ "${answer}" == "y" ]]; then
  uname_out=$(uname -s)
  case ${uname_out} in
    Linux*)     MACHINE=linux;;
    Darwin*)    MACHINE=darwin;;
    *)          MACHINE="UNKNOWN:${uname_out}";;
  esac;
  
  if [[ "${MACHINE}" == "darwin" ]]; then
    brew uninstall pre-commit
  elif [[ "${MACHINE}" == "linux" ]]; then
    [[ -n "$(command -v yum)" ]] && MACHINE=redhat
    [[ -n "$(command -v apt-get)" ]] && MACHINE=debian
    
    if [[ "${MACHINE}" == "redhat" ]]; then
      yum remove pre-commit
    elif [[ "${MACHINE}" == "debian" ]]; then
      apt-get remove pre-commit
    else
      echo -e "ERROR - OS unsupported"
      exit 1
    fi
  else
    echo -e "ERROR - OS unsupported"
    exit 1
  fi
  echo -e "\033[1;32m[✓]\033[0m pre-commit framework binaries uninstalled"
fi


answer=n
if [[ "$1" != "y" ]]; then
  read -r -p 'Do you want to remove the pre-commit manager sources [y/N]: ' answer
else
  answer=y
fi

if [[ "${answer}" == "y" ]]; then
  rm -rf "${installer_location}"
  echo -e "\033[1;32m[✓]\033[0m Nuked everything. You can sleep like a log..."
fi

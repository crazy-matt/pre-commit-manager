#!/usr/bin/env bash
# shellcheck disable=SC2143
set -e

installer_location="$HOME/.local/var/pre-commit-manager"
precommit_manager_ssh_url="git@github.com:crazy-matt/pre-commit-manager.git"
cronjob_frequency_mins=${PRECOMMIT_UPDATE_FREQUENCY_MINS:-20}


uname_out=$(uname -s)
case ${uname_out} in
  Linux*)     MACHINE=linux;;
  Darwin*)    MACHINE=darwin;;
  *)          MACHINE="UNKNOWN:${uname_out}";;
esac;

if [[ "${MACHINE}" == "darwin" ]]; then
  brew update && brew install pre-commit
elif [[ "${MACHINE}" == "linux" ]]; then
  [[ -n "$(command -v yum)" ]] && MACHINE=redhat
  [[ -n "$(command -v apt-get)" ]] && MACHINE=debian

  if [[ "${MACHINE}" == "redhat" ]]; then
    yum update -y && yum install -y pre-commit
  elif [[ "${MACHINE}" == "debian" ]]; then
    apt-get update -y && apt-get install -y pre-commit
  else
    echo -e "ERROR - OS unsupported"
    exit 1
  fi
else
  echo -e "ERROR - OS unsupported"
  exit 1
fi
echo -e "\033[1;32m[✓]\033[0m pre-commit framework binaries installed"

mkdir -p "${installer_location}"

pre-commit clean
echo -e "\033[1;32m[✓]\033[0m pre-commit cache cleaned up"

# Creating the script in charge of scanning the disk for any git repository and deploying the hooks
rm -rf "${installer_location}"
mkdir -p "${installer_location}"
touch "${installer_location}/deploy_hooks.sh"
cat > "${installer_location}/deploy_hooks.sh" <<WITH_INTERPOLATION
#!/usr/bin/env bash
# shellcheck disable=SC2002
set -e

installer_location="${installer_location}"
precommit_manager_ssh_url="${precommit_manager_ssh_url}"
WITH_INTERPOLATION

cat >> "${installer_location}/deploy_hooks.sh" <<'WITHOUT_INTERPOLATION'
baseline_precommit_config_file=${PRECOMMIT_BASELINE:-"sources/baseline.yaml"}


if [[ ! -d "${installer_location}/repository" ]]; then
  git clone -n "${precommit_manager_ssh_url}" --depth 1 "${installer_location}/repository"
fi
cd "${installer_location}/repository" || exit 1
git fetch --tags --prune -f
latest_tag="$(git tag | sort -V | tail -n1)"
if [[ -z "${latest_tag}" ]]; then
  echo -e "\033[1;37m\033[41mThe source repository does not offer any release. Hooks deployment interrupted.\033[0m"
  exit 1
fi
previous_tag="$(git tag | sort -V | tail -n2 | head -n1)"

# Get the previous release config file byte count to compare it later on with the one in repos
if [[ "${latest_tag}" != "${previous_tag}" && "${previous_tag}" != "" ]]; then
  git checkout "${previous_tag}" "${baseline_precommit_config_file}" 2>/dev/null
  previous_config_byte_count=$(cat "${baseline_precommit_config_file}" | sort -u | wc -c)
else
  previous_config_byte_count=0
fi
git checkout "${latest_tag}" "${baseline_precommit_config_file}"

echo -e "\033[1;32m[✓]\033[0m Baseline config latest release downloaded"

# Build the find parameters to exclude/include any folders declared in the bash environment variables
custom_exclusion_filter=""
for pattern in ${PRECOMMIT_EXCLUDE//,/ }; do
  custom_exclusion_filter="$custom_exclusion_filter -o -path '$pattern' -prune"
done

custom_inclusion_filter=""
for pattern in ${PRECOMMIT_INCLUDE//,/ }; do
  pattern="${pattern}/.git"
  if [[ "${custom_inclusion_filter}" == "" ]]; then
    custom_inclusion_filter="-path '$pattern'"
  else
    custom_inclusion_filter="$custom_inclusion_filter -o -path '$pattern'"
  fi
done

# Build the git repo list located on the hard drive under the HOME directory
repo_exclusion_list=$(eval "find $HOME -type d \
  -not \( \
    -path '${HOME}/Library' -prune \
    -o -path '${HOME}/Pictures' -prune \
    -o -path '${HOME}/.*' -prune \
    -o -path '*.terraform/*' -prune \
    -o -path '*.terragrunt-cache/*' -prune \
    -o -path '*.history/*' -prune \
    ${custom_exclusion_filter} \
  \) \
  -iname '.git' -prune" \
)

if [[ -n "${PRECOMMIT_INCLUDE}" ]]; then
  repo_inclusion_list=$(eval "find $HOME -type d \
    -not \( \
      -path '${HOME}/Library' -prune \
      -o -path '${HOME}/Pictures' -prune \
      -o -path '${HOME}/.*' -prune \
      -o -path '*.terraform/*' -prune \
      -o -path '*.terragrunt-cache/*' -prune \
      -o -path '*.history/*' -prune \
    \) \
    \( ${custom_inclusion_filter} \) \
    -prune" \
  )
fi

repo_list="$(sort -u <(printf '%s\n' "${repo_exclusion_list}") <(printf '%s\n' "${repo_inclusion_list}"))"

total_count=0
updated_count=0

for repo in ${repo_list}; do
  repo_path="${repo%/.git}"
  change=false
  ((total_count+=1))
  echo -e "\033[1;32m[✓]\033[0m repo \033[1;34m${repo_path}\033[0m"

  if [[ -f "${repo_path}/.pre-commit-config.yaml" ]]; then
    current_config_byte_count=$(cat "${repo_path}/.pre-commit-config.yaml" | sort -u | wc -c)
  else
    unset current_config_byte_count
  fi

  # Baseline config deployed if no config exists or if the config in repo matches exactly the release just before.
  # In that former case, we push the upgrade, because if the config has not been updated manually,
  # then the user is potentially interested in staying in a "managed" mode
  if [[ ! -f "${repo_path}/.pre-commit-config.yaml" ]] || [[ ${current_config_byte_count} == "${previous_config_byte_count}" ]]; then
    cp -f "${installer_location}/repository/${baseline_precommit_config_file}" "${repo_path}/.pre-commit-config.yaml"
    echo -e "   * pre-commit manager baseline config deployed..."
    change=true
  else
    echo -e "   * pre-commit manager baseline config already in repo..."
  fi

  # If nothing has been deployed already, then deploy 2 hooks: pre-push & commit-msg
  if [[ ! -f "${repo_path}/.git/hook/pre-push" || ! -f "${repo_path}/.git/hook/commit-msg" ]]; then
    cd "${repo_path}"
    git config --unset-all core.hooksPath && echo -e "   * Reset of the git core.hooksPath variable..."
    printf '%s\n' "   * $(pre-commit install)"
    printf '%s\n' "   * $(pre-commit install --hook-type pre-push)"
    printf '%s\n' "   * $(pre-commit install --hook-type commit-msg)"
    printf '%s\n' "   * $(pre-commit autoupdate)"
    printf '%s\n' "   * pre-commit hooks deployed..."
    change=true
  fi
  if [[ "$change" == true ]]; then
    ((updated_count+=1))
  fi

  echo -e "\033[1;33m   ${updated_count}/${total_count} repositories updated\033[0m"
done

WITHOUT_INTERPOLATION

chmod +x "${installer_location}/deploy_hooks.sh"
echo -e "\033[1;32m[✓]\033[0m Hooks deployer script created: ${installer_location}/deploy_hooks.sh"

# Install a Cron job which deploys the pre-commit baseline config on the local repositories being scanned
croncmd="/bin/bash '${installer_location}/deploy_hooks.sh'"
cronjob="*/${cronjob_frequency_mins} * * * * ${croncmd}"
if [[ -z "$(crontab -l | grep "${croncmd}")" ]]; then
  ( crontab -l | grep -v -F "${croncmd}" ; echo -e "${cronjob}" ) | crontab -
  echo -e "\033[1;32m[✓]\033[0m Hooks deployer cron job created to be run every ${cronjob_frequency_mins} mins"
fi

# Install a Cron job which cleans unused hooks cache
# pre-commit keeps a cache of installed hook repositories which grows over time.
# This command can be run periodically to clean out unused repos from the cache directory.
croncmd="pre-commit gc"
cronjob="0 13 * * * ${croncmd}"
if [[ -z "$(crontab -l | grep "${croncmd}")" ]]; then
  ( crontab -l | grep -v -F "${croncmd}" ; echo -e "${cronjob}" ) | crontab -
  echo -e "\033[1;32m[✓]\033[0m pre-commit cache cleanup job deployed to be run every day at 13:00"
fi

"${installer_location}/deploy_hooks.sh"

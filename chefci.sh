#!/usr/bin/env bash
set +x
CHEF_REPO_PATH='chef_repo'
ROLES_PATH="${CHEF_REPO_PATH}/roles"
SECRET_KEY_PATH='/tmp/secret'

ROLES=()
RECIPES=()

# For using roles and data bags in our tests, we have to clone irrigate-chef-repo
CHEF_REPO='https://github.com/gallantra/irrigate-chef-repo.git'
rm -rf chef_repo
git clone ${CHEF_REPO} ${CHEF_REPO_PATH}

git diff --name-only origin/master

# Determine which recipes were changed (could be list)
# recipe files in PR
REPO_NAME=$(basename -s .git `git config --get remote.origin.url`)
CHANGED_RECIPES=$(basename -s .rb `git diff --name-only origin/master | grep recipes || echo "false"`)

if [ "${CHANGED_RECIPES}" == "false" ]; then
  echo "No recipes were changed, exiting..."
  exit 0
fi

for file in ${CHANGED_RECIPES}; do
  for role in $(grep "recipe\[${REPO_NAME}::${file}" -lir ${ROLES_PATH}); do
    role_file=$(basename ${role})
    role_name=${role_file%%.*}
    ROLES+=(${role_name})
    for recipe in $(egrep -h 'recipe\[irrigate' ${ROLES_PATH}/${role_file} | egrep -o 'irrigate-\w+::\w+'); do
      RECIPES+=(${recipe})
    done
  done
done

COOKBOOKS=($(echo ${RECIPES[@]} | egrep -o 'irrigate-\w+' | sort | uniq))



mkdir cookbooks
cd cookbooks
for cookbook in ${COOKBOOKS[@]}; do
  git clone -v https://github.com/gallantra/${cookbook}.git
  echo "cookbook '${cookbook}', path: 'cookbooks/${cookbook}'" >> ../Berksfile
done

cd ../

cat > .kitchen.yml << EOF
driver:
  name: docker

provisioner:
  name: chef_zero
  always_update_cookbooks: true

verifier:
  name: inspec

transport:
  username: 'kitchen'
  password: 'kitchen'

platforms:
  - name: centos-7.3
    driver_config:
      dockerfile: test/Dockerfile
      privileged: true # Needed by systemd to access cgroups
      run_command: /usr/sbin/init # Start systemd as root process
      use_sudo: false
    attributes:
      chefci_testing: true
      authorization:
        sudo:
          users:
            - 'kitchen'
            - 'vagrant'

suites:
EOF

for role in ${ROLES}; do
  recipes_in_role=$(egrep -h 'recipe\[irrigate' ${ROLES_PATH}/${role}.json | egrep -o 'irrigate-\w+::\w+')
  cat >> .kitchen.yml << EOF
    - name: ${role}
      data_bags_path: "${CHEF_REPO_PATH}/data_bags"
      encrypted_data_bag_secret_key_path: "${SECRET_KEY_PATH}"
      roles_path: "${CHEF_REPO_PATH}/roles"
      run_list:
        - role[${role}]
      verifier:
        inspec_tests:
EOF
  for recipe in ${recipes_in_role}; do
    test_file="cookbooks/${recipe%::*}/test/smoke/${recipe##*::}"
    if [ -d ${test_file} ]; then
      cat >> .kitchen.yml << EOF
          - ${test_file}
EOF
    elif [ -f "${test_file}.rb" ]; then
      cat >> .kitchen.yml << EOF
          - ${test_file}.rb
EOF
    else
      echo "${test_file} does not exist"
    fi
  done
done

echo "time to fire kitchen test"
cat .kitchen.yml

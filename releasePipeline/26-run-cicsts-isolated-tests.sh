#! /usr/bin/env bash 

#
# Copyright contributors to the Galasa project
#
# SPDX-License-Identifier: EPL-2.0
#
#-----------------------------------------------------------------------------------------                   
#
# Objectives: Run CICS tests with the Isolated zip.
#
# Environment variable over-rides:
# 
#-----------------------------------------------------------------------------------------                   

# Where is this script executing from ?
BASEDIR=$(dirname "$0");pushd $BASEDIR 2>&1 >> /dev/null ;BASEDIR=$(pwd);popd 2>&1 >> /dev/null
# echo "Running from directory ${BASEDIR}"
export ORIGINAL_DIR=$(pwd)
# cd "${BASEDIR}"

cd "${BASEDIR}/.."
WORKSPACE_DIR=$(pwd)


#-----------------------------------------------------------------------------------------                   
#
# Set Colors
#
#-----------------------------------------------------------------------------------------                   
bold=$(tput bold)
underline=$(tput sgr 0 1)
reset=$(tput sgr0)
red=$(tput setaf 1)
green=$(tput setaf 76)
white=$(tput setaf 7)
tan=$(tput setaf 202)
blue=$(tput setaf 25)

#-----------------------------------------------------------------------------------------                   
#
# Headers and Logging
#
#-----------------------------------------------------------------------------------------                   
underline() { printf "${underline}${bold}%s${reset}\n" "$@" ;}
h1() { printf "\n${underline}${bold}${blue}%s${reset}\n" "$@" ;}
h2() { printf "\n${underline}${bold}${white}%s${reset}\n" "$@" ;}
debug() { printf "${white}%s${reset}\n" "$@" ;}
info() { printf "${white}➜ %s${reset}\n" "$@" ;}
success() { printf "${green}✔ %s${reset}\n" "$@" ;}
error() { printf "${red}✖ %s${reset}\n" "$@" ;}
warn() { printf "${tan}➜ %s${reset}\n" "$@" ;}
bold() { printf "${bold}%s${reset}\n" "$@" ;}
note() { printf "\n${underline}${bold}${blue}Note:${reset} ${blue}%s${reset}\n" "$@" ;}

#-----------------------------------------------------------------------------------------                   
# Main logic.
#-----------------------------------------------------------------------------------------   

mkdir -p temp

function set_kubernetes_context {
    h1 "Setting the kubernetes context to be cicsk8s, using namespace galasa-build"
    kubectl config set-context cicsk8s --namespace=galasa-build
    rc=$?
    if [[ "${rc}" != "0" ]]; then 
        error "Failed. rc=${rc}"
        exit 1
    fi
    
}

function get_galasa_version_to_be_released {
    h1 "Working out the version of Galasa to test and release."

    url="https://development.galasa.dev/main/maven-repo/obr/dev/galasa/dev.galasa.uber.obr/"
    curl $url > temp/galasa-version.txt -s
    rc=$?; 
    if [[ "${rc}" != "0" ]]; then 
      error "Failed to get galasa version"
      exit 1
    fi

    # Note: We take the 2nd line which has an "<a href" string on... hopefully it won't change...
    galasa_version=$(cat temp/galasa-version.txt | grep "<a href" | head -2 | tail -1 | cut -f2 -d'"' | cut -f1 -d'/')

    success "Galasa version to be tested and released is ${galasa_version}"
    export galasa_version
}

function get_current_boot_version {
    h1 "Working out the current galasa-boot version."

    url="https://development.galasa.dev/main/maven-repo/obr/dev/galasa/galasa-boot/"
    curl $url > temp/galasa-boot.txt -s
    rc=$?; 
    if [[ "${rc}" != "0" ]]; then 
      error "Failed to get galasa boot"
      exit 1
    fi

    # Note: We take the 2nd line which has an "<a href" string on... hopefully it won't change...
    boot_version=$(cat temp/galasa-boot.txt | grep "<a href" | head -2 | tail -1 | cut -f2 -d'"' | cut -f1 -d'/')

    success "Current boot version is ${boot_version}"
    export boot_version
}


function run_cics_isolated {
    h1 "Trying to kick off CICS tests with the Isolated zip..."

    yaml_file="run_cics_isolated.yaml"

    rm -f temp/${yaml_file}
    cat << EOF > temp/${yaml_file}
#
# Copyright contributors to the Galasa project 
#
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: run-cicsts-isolated-tests-
  namespace: galasa-build
  annotations:
    argocd.argoproj.io/compare-options: IgnoreExtraneous
    argocd.argoproj.io/sync-options: Prune=false
spec:
  pipelineRef:
    name: cicsts-isolated-tests
  serviceAccountName: galasa-build-bot
  podTemplate:
    volumes:
    - name: test-cps-and-creds
      secret:
        secretName: test-cps-and-creds
  workspaces:
  - name: git-workspace
    volumeClaimTemplate:
      spec:
        storageClassName: longhorn-temp
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 20Gi
EOF

    output=$(kubectl -n galasa-build create -f temp/${yaml_file})
    # Outputs a line of text like this: 
    # pipelinerun.tekton.dev/delete-branches-galasa-8cbj8 created
    rc=$?
    if [[ "${rc}" != "0" ]]; then
        error "Failed to run CICS isolated tests. rc=$?"
        exit 1
    fi
    info "kubectl create pipeline run output: $output"


    success "cicsts-isolated-tests kicked off."
    bold "Now use the Tekton dashboard to monitor it to see that they all work."
    note "If any fail, you will need to re-run these tests."
}

set_kubernetes_context
get_galasa_version_to_be_released
get_current_boot_version
run_cics_isolated
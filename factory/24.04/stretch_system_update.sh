#!/bin/bash
set -o pipefail

repos_dir="$HOME/repos"
mkdir -p "$repos_dir"

echo "Updating repositories in $repos_dir..."

function update_repo {
    local repo_name=$1
    local branch_name=$2

    if [ ! -d "$repos_dir/$repo_name" ]; then
        echo "Cloning $repo_name..."
        if ! git clone "https://github.com/hello-robot/$repo_name.git" "$repos_dir/$repo_name"; then
            echo "Failed to clone $repo_name. Skipping."
            return
        fi
    fi

    echo "Updating $repo_name to $branch_name..."
    cd "$repos_dir/$repo_name"

    # Determine actual branch name if main/master is requested
    local actual_branch="$branch_name"
    if [ "$branch_name" = "master/main" ]; then
        if git show-ref --verify --quiet refs/heads/main; then
            actual_branch="main"
        elif git show-ref --verify --quiet refs/heads/master; then
            actual_branch="master"
        elif git ls-remote --heads origin main | grep -q 'refs/heads/main'; then
            actual_branch="main"
        else
            actual_branch="master"
        fi
    fi

    git checkout "$actual_branch" || true
    git pull || true
}

update_repo "stretch_firmware_ii" "develop"
update_repo "stretch_production_tools_ii" "master/main"
update_repo "stretch_fleet_ii" "master/main"
update_repo "stretch_production_data_ii" "master/main"
update_repo "stretch4_pyhesai_wrapper" "master/main"

echo "Updating Stretch pip packages..."
pip install -U hello-robot-stretch4-body
pip install -U hello-robot-stretch4-urdf
pip install -U hello-robot-stretch4-flying-gripper
pip install -U hello-robot-stretch4-tray

echo "Repository updates and pip package installations completed."
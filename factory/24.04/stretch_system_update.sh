#!/bin/bash
set -o pipefail

repos_dir="$HOME/repos"
if [ ! -d "$repos_dir" ]; then
    echo "Repos directory not found at $repos_dir"
    exit 1
fi

echo "Updating repositories in $repos_dir..."

function update_repo {
    local repo_name=$1
    local branch_name=$2
    echo "Updating $repo_name to $branch_name..."
    if [ -d "$repos_dir/$repo_name" ]; then
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
    else
        echo "Repository $repo_name not found in $repos_dir. Skipping."
    fi
}

update_repo "stretch4_body" "main"
update_repo "stretch_firmware_ii" "develop"
update_repo "stretch_production_tools_ii" "master/main"
update_repo "stretch_fleet_ii" "master/main"
update_repo "stretch4_install" "master/main"
update_repo "stretch4_urdf" "master/main"
update_repo "stretch4_ai" "master/main"
update_repo "stretch_production_data_ii" "master/main"
update_repo "stretch_tray" "master/main"

echo "Repository updates completed."
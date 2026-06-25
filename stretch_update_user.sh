#!/bin/bash

# Define the target repositories
REPOS=(
    "$HOME/repos/stretch4_body"
    "$HOME/repos/stretch4_urdf"
    "$HOME/repos/stretch_tray"
    "$HOME/ament_ws/src/stretch4_ros2"
)

# Function to handle the release process
create_release() {
    echo "--- Preparing Release Environment ---"
    mkdir -p /tmp/stretch_release

    # 1. Clone or pull into /tmp/stretch_release
    for repo_path in "${REPOS[@]}"; do
        repo_name=$(basename "$repo_path")
        tmp_repo="/tmp/stretch_release/$repo_name"
        
        if [ -d "$tmp_repo" ]; then
            echo "Repository $repo_name already exists in /tmp/stretch_release. Pulling latest..."
            git -C "$tmp_repo" pull
        else
            echo "Cloning $repo_name to /tmp/stretch_release..."
            if [ -d "$repo_path" ]; then
                # Get remote origin URL from local repository to clone properly
                remote_url=$(git -C "$repo_path" config --get remote.origin.url)
                git clone "$remote_url" "$tmp_repo"
            else
                echo "Error: Local repository $repo_path not found. Cannot determine remote URL to clone."
                exit 1
            fi
        fi
    done

    # 2. Determine Tag Name (release.month_day_year.revision)
    date_str=$(date +"%b_%d_%y" | tr '[:upper:]' '[:lower:]')
    
    # Use stretch4_body as the reference point to check for existing revisions today
    ref_repo="/tmp/stretch_release/stretch4_body"
    latest_rev=$(git -C "$ref_repo" tag -l "release.${date_str}.*" | awk -F. '{print $3}' | sort -n | tail -1)
    
    if [ -z "$latest_rev" ]; then
        rev=1
    else
        rev=$((latest_rev + 1))
    fi
    
    tag_name="release.${date_str}.${rev}"

    echo ""
    echo "=================================================="
    echo " Target Tag: $tag_name"
    echo "=================================================="
    
    # 3. Prompt user
    read -p "Do you want to continue creating and pushing this tag for all repos? [Y/n] " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        echo "Release aborted by user."
        exit 0
    fi

    # 4. Tag and Push
    for repo_path in "${REPOS[@]}"; do
        repo_name=$(basename "$repo_path")
        tmp_repo="/tmp/stretch_release/$repo_name"
        
        echo "Tagging and pushing $repo_name..."
        git -C "$tmp_repo" tag "$tag_name"
        git -C "$tmp_repo" push origin "$tag_name"
    done
    
    echo "Release $tag_name created successfully!"
}

# Function to handle the update process
update_repos() {
    echo "--- Updating Local Repositories ---"

    # Activate virtual environment if present
    if [ -f "$HOME/stretch_user/stretch_venv/bin/activate" ]; then
        source "$HOME/stretch_user/stretch_venv/bin/activate"
    fi

    # Update the uv virtual environment dependencies if the repo configuration changed
    if [ -d "$HOME/stretch_user/stretch_venv" ]; then
        echo " -> Updating uv virtual environment dependencies..."
        export PATH="${HOME}/.local/bin:${PATH}"
        export UV_PROJECT_ENVIRONMENT="$HOME/stretch_user/stretch_venv"
        SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
        if [ -d "$SCRIPT_DIR/stretch_venv" ]; then
            (cd "$SCRIPT_DIR/stretch_venv" && uv sync --frozen)
        fi
    fi
    
    # 1. Fail early if any existing repository has uncommitted changes
    for repo_path in "${REPOS[@]}"; do
        if [ -d "$repo_path" ]; then
            if [ -n "$(git -C "$repo_path" status --porcelain)" ]; then
                echo "ERROR: Uncommitted changes found in $repo_path."
                echo "Please commit, stash, or revert them before attempting an update."
                exit 1
            fi
        fi
    done

    echo "All existing repositories are clean. Proceeding..."
    
    # 2. Fetch tags and get the latest tag from stretch4_body
    body_repo="$HOME/repos/stretch4_body"
    if [ ! -d "$body_repo" ]; then
        echo "Error: $body_repo is missing. Cannot determine the latest tags."
        exit 1
    fi
    
    git -C "$body_repo" fetch --tags --quiet
    
    # Get top 5 most recent tags matching "release.*"
    mapfile -t latest_tags < <(git -C "$body_repo" tag --sort=-creatordate | grep '^release\.' | head -n 5)
    
    if [ ${#latest_tags[@]} -eq 0 ]; then
        echo "No release tags found in $body_repo!"
        exit 1
    fi

    target_tag="${latest_tags[0]}"

    # 3. Prompt the user
    echo ""
    read -p "The latest tag is ** $target_tag **. Do you want to checkout this tag? [Y/n] " confirm_tag
    
    if [[ "$confirm_tag" =~ ^[Nn] ]]; then
        echo ""
        echo "Please select from the last 5 available tags:"
        select selected_tag in "${latest_tags[@]}"; do
            if [ -n "$selected_tag" ]; then
                target_tag="$selected_tag"
                break
            else
                echo "Invalid selection. Please enter a number from 1 to ${#latest_tags[@]}."
            fi
        done
    fi

    echo "Selected tag: $target_tag"
    echo "Checking out $target_tag across all repositories and installing/building..."
    
    FAILED_REPOS=()
    SUCCESSFUL_REPOS=()

    # 4. Checkout the selected tag and build/install in the user's actual workspace
    for repo_path in "${REPOS[@]}"; do
        repo_name=$(basename "$repo_path")
        echo " -> Updating $repo_name"
        
        # Track if any step fails during the build/install process
        repo_failed=0

        # Check if directory exists first
        if [ ! -d "$repo_path" ]; then
            echo "    [!] ERROR: Directory $repo_path does not exist."
            FAILED_REPOS+=("$repo_name (directory not found)")
            continue
        fi

        if ! git -C "$repo_path" fetch --tags --quiet; then
            echo "    [!] ERROR: Failed to fetch tags for $repo_name"
            FAILED_REPOS+=("$repo_name (fetch failed)")
            continue
        fi

        if ! git -C "$repo_path" checkout "$target_tag" --quiet; then
            echo "    [!] ERROR: Failed to checkout $target_tag in $repo_name"
            FAILED_REPOS+=("$repo_name (checkout failed)")
            continue
        fi

        # Run build/install commands based on the repository
        if [ "$repo_name" = "stretch4_body" ]; then
            echo "    -> Running: uv pip install -p \"$UV_PROJECT_ENVIRONMENT\" -e ./src"
            if ! (cd "$repo_path" && uv pip install -p "$UV_PROJECT_ENVIRONMENT" -e ./src); then
                echo "    [!] ERROR: uv pip install failed for $repo_name"
                FAILED_REPOS+=("$repo_name (uv pip install failed)")
                repo_failed=1
            fi
        elif [ "$repo_name" = "stretch4_ros2" ]; then
            echo "    -> Running colcon build for workspace..."
            # Run the colcon build in a subshell so we can safely exit on failure without killing the whole script
            if ! (
                cd "$HOME/ament_ws" || exit 1
                echo "Starting colcon build..."
                export MAKEFLAGS="-j 4"
                colcon build --allow-overriding nav2_costmap_2d --executor sequential --symlink-install || exit 1
                unset MAKEFLAGS
            ); then
                echo "    [!] ERROR: colcon build failed for $repo_name / ament_ws"
                FAILED_REPOS+=("$repo_name (colcon build failed)")
                repo_failed=1
            else
                # Source the bashrc in the current shell context
                source ~/.bashrc
                echo "Build finished and environment sourced."
            fi
        else
            # Check for standard Python packaging files before running pip install
            if [ -f "$repo_path/setup.py" ] || [ -f "$repo_path/pyproject.toml" ]; then
                echo "    -> Running: uv pip install -p \"$UV_PROJECT_ENVIRONMENT\" -e ."
                if ! (cd "$repo_path" && uv pip install -p "$UV_PROJECT_ENVIRONMENT" -e .); then
                    echo "    [!] ERROR: uv pip install failed for $repo_name"
                    FAILED_REPOS+=("$repo_name (uv pip install failed)")
                    repo_failed=1
                fi
            fi
        fi

        # If it made it through everything without triggering the fail flag, it's a success
        if [ $repo_failed -eq 0 ]; then
            SUCCESSFUL_REPOS+=("$repo_name")
        fi
    done
    # Ensure ~/.bashrc is updated with the unified virtualenv and ROS sourcing block
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    bash "$SCRIPT_DIR/stretch_venv/update_bashrc.sh"

    # 5. Summary Output
    echo ""
    echo "=================================================="
    echo "Update Summary:"
    echo "--------------------------------------------------"
    
    echo "Successfully updated:"
    if [ ${#SUCCESSFUL_REPOS[@]} -eq 0 ]; then
        echo " - None"
    else
        for success in "${SUCCESSFUL_REPOS[@]}"; do
            echo " - $success"
        done
    fi

    if [ ${#FAILED_REPOS[@]} -gt 0 ]; then
        echo ""
        echo "WARNING: Failed updates:"
        for failed in "${FAILED_REPOS[@]}"; do
            echo " - $failed"
        done
        echo ""
        echo "Please check the console output above for specific error messages."
    fi
    echo "=================================================="
}

# --- Main Argument Parsing ---
# Default to update
ACTION="update"

for arg in "$@"; do
    case $arg in
        --create_release)
            ACTION="release"
            shift
            ;;
        --update)
            ACTION="update"
            shift
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--create_release | --update]"
            exit 1
            ;;
    esac
done

# Execute based on requested action
if [ "$ACTION" = "release" ]; then
    create_release
else
    update_repos
fi
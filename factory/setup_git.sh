#!/bin/bash
set -e

echo "Would you like to set up your git profile and SSH key for GitHub? [y/N]"
read -p "Response: " setup_ssh
if [[ "$setup_ssh" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Please enter your Git Name (e.g., Hello Robot):"
    read -p "Name: " git_name
    
    echo "Please enter your Git Email (e.g., user@email.com):"
    read -p "Email: " git_email
    
    if [ -n "$git_name" ]; then
        git config --global user.name "$git_name"
    fi
    if [ -n "$git_email" ]; then
        git config --global user.email "$git_email"
    fi

    if [ ! -f ~/.ssh/id_ed25519 ]; then
        echo "Generating a new SSH key..."
        mkdir -p ~/.ssh
        if [ -n "$git_email" ]; then
            ssh-keygen -t ed25519 -C "$git_email" -f ~/.ssh/id_ed25519 -N "" -q
        else
            ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q
        fi
    else
        echo "SSH key already exists at ~/.ssh/id_ed25519"
        read -p "Would you like to overwrite it? [y/N] " overwrite_key
        if [[ "$overwrite_key" =~ ^[Yy]$ ]]; then
            echo "Generating a new SSH key..."
            rm -f ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub
            if [ -n "$git_email" ]; then
                ssh-keygen -t ed25519 -C "$git_email" -f ~/.ssh/id_ed25519 -N "" -q
            else
                ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q
            fi
        fi
    fi
    # Ensure known hosts has github
    mkdir -p ~/.ssh
    ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts 2>/dev/null
    
    echo ""
    echo "======================================================================"
    echo "Please copy the following SSH public key:"
    echo ""
    cat ~/.ssh/id_ed25519.pub
    echo ""
    echo "Navigate to https://github.com/settings/keys in your browser."
    echo "Click 'New SSH key', give it a title, and paste the key above."
    echo "======================================================================"
    echo ""
    
    while true; do
        read -p "Press 'y' to confirm you have added the key to your GitHub account: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            break
        else
            echo "Please add the key and confirm with 'y' to continue, or press Ctrl+C to abort."
        fi
    done
    
    echo "Testing GitHub SSH connection..."
    ssh -T git@github.com || true


    echo "Would you like to configure git to automatically use SSH for GitHub instead of HTTPS? [y/N]"
    read -p "Response: " config_ssh
    if [[ "$config_ssh" =~ ^[Yy]$ ]]; then
        echo "Configuring git to use SSH for GitHub instead of HTTPS..."
        git config --global url."git@github.com:".insteadOf "https://github.com/"
    fi

fi
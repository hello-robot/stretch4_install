#!/bin/bash
set -e

REDIRECT_LOGDIR="$HOME/stretch_user/log"
if getopts ":l:" opt && [[ $opt == "l" && -d $OPTARG ]]; then
    REDIRECT_LOGDIR=$OPTARG
fi
REDIRECT_LOGFILE="$REDIRECT_LOGDIR/stretch_install_dev_tools.`date '+%Y%m%d%H%M'`_redirected.txt"

if [ ! -f "$HOME/stretch_user/stretch_venv/bin/activate" ]; then
    echo "ERROR: The virtual environment ~/stretch_user/stretch_venv does not exist."
    echo "Please run the setup script to generate it:"
    if [ -d "$HOME/stretch4_install" ]; then
        echo "    ~/stretch4_install/stretch_venv/setup_venv.sh"
    else
        echo "    ~/stretch_install/stretch_venv/setup_venv.sh"
    fi
    echo "Exiting."
    exit 1
fi

source "$HOME/stretch_user/stretch_venv/bin/activate"

echo "#############################################"
echo "INSTALLATION OF DEV TOOLS FOR HELLO ROBOT INTERNAL PRODUCTION"
echo "#############################################"

echo "Install gh"
function install_gh {
    type -p curl >/dev/null || (sudo apt update && sudo apt install curl -y)
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && sudo apt update \
    && sudo apt install gh -y
}
install_gh &>> $REDIRECT_LOGFILE

echo "Install Typora"
sudo snap install typora >> $REDIRECT_LOGFILE

echo "Install PyCharm"
sudo snap install pycharm-community --classic >> $REDIRECT_LOGFILE

echo "Install VS Code"
sudo snap install code --classic >> $REDIRECT_LOGFILE

echo "Install tools for system QC and bringup"
export PATH="${HOME}/.local/bin:${PATH}"
uv pip install -q twine &>> $REDIRECT_LOGFILE
uv pip install -q gspread &>> $REDIRECT_LOGFILE
uv pip install -q gspread-formatting &>> $REDIRECT_LOGFILE
uv pip install -q oauth2client rsa==3.4 &>> $REDIRECT_LOGFILE
uv pip install -q mkdocs mkdocs-material mkdocstrings==0.17.0 pytkdocs[numpy-style] jinja2==3.0.3 &>> $REDIRECT_LOGFILE

echo "Cloning repos"
cd ~/repos/
rm -rf ./stretch4_install
git clone https://github.com/hello-robot/stretch4_install.git >> $REDIRECT_LOGFILE
rm -rf ./stretch4_urdf
git clone https://github.com/hello-robot/stretch4_urdf.git >> $REDIRECT_LOGFILE
rm -rf ./stretch4_body
git clone https://github.com/hello-robot/stretch4_body.git >> $REDIRECT_LOGFILE
rm -rf ./stretch_firmware_ii
git clone https://github.com/hello-robot/stretch_firmware_ii.git >> $REDIRECT_LOGFILE
rm -rf ./stretch_fleet_ii
git clone https://github.com/hello-robot/stretch_fleet_ii.git >> $REDIRECT_LOGFILE
rm -rf ./stretch_production_tools_ii
git clone https://github.com/hello-robot/stretch_production_tools_ii.git >> $REDIRECT_LOGFILE
rm -rf ./stretch_production_data_ii
git clone https://github.com/hello-robot/stretch_production_data_ii.git >> $REDIRECT_LOGFILE

echo "Install stretch_production_tools"
cd stretch_production_tools_ii/python
uv pip install -e . >> $REDIRECT_LOGFILE
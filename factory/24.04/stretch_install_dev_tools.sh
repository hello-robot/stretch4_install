#!/bin/bash
set -e

REDIRECT_LOGDIR="$HOME/stretch_user/log"
if getopts ":l:" opt && [[ $opt == "l" && -d $OPTARG ]]; then
    REDIRECT_LOGDIR=$OPTARG
fi
REDIRECT_LOGFILE="$REDIRECT_LOGDIR/stretch_install_dev_tools.`date '+%Y%m%d%H%M'`_redirected.txt"

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
export PIP_BREAK_SYSTEM_PACKAGES=1
pip3 install -q --no-warn-script-location twine &>> $REDIRECT_LOGFILE
pip3 install -q --no-warn-script-location gspread &>> $REDIRECT_LOGFILE
pip3 install -q --no-warn-script-location gspread-formatting &>> $REDIRECT_LOGFILE
pip3 install -q --no-warn-script-location oauth2client rsa==3.4 &>> $REDIRECT_LOGFILE
pip3 install -q --no-warn-script-location mkdocs mkdocs-material mkdocstrings==0.17.0 pytkdocs[numpy-style] jinja2==3.0.3 &>> $REDIRECT_LOGFILE

#!/usr/bin/env bash
# setup Cloud VPS instance with initial server etc.

# these can be changed but most other variables should be left alone
APP_LBL='api-endpoint'  # descriptive label for endpoint-related directories
REPO_LBL='ml-article-desc'  # directory where repo code will go
GIT_CLONE_HTTPS='https://github.com/geohci/transformers-modified'  # for `git clone`

ETC_PATH="/etc/${APP_LBL}"  # app config info, scripts, ML models, etc.
SRV_PATH="/srv/${APP_LBL}"  # application resources for serving endpoint
TMP_PATH="/tmp/${APP_LBL}"  # store temporary files created as part of setting up app (cleared with every update)
LOG_PATH="/var/log/uwsgi"  # application log data
LIB_PATH="/var/lib/${APP_LBL}"  # where virtualenv will sit
MOD_PATH="/srv/model-25lang-all/"  # where the model binary is stored

echo "Updating the system..."
apt-get update
apt-get install -y build-essential  # gcc (c++ compiler) necessary for fasttext
apt-get install -y nginx  # handles incoming requests, load balances, and passes to uWSGI to be fulfilled
apt-get install -y python3-pip  # install dependencies
apt-get install -y python3-wheel  # make sure dependencies install correctly even when missing wheels
apt-get install -y python3-venv  # for building virtualenv
apt-get install -y python3-dev
apt-get install -y uwsgi
apt-get install -y uwsgi-plugin-python3
# potentially add: apt-get install -y git python3 libpython3.7 python3-setuptools

echo "Setting up paths..."
rm -rf ${TMP_PATH}
mkdir -p ${TMP_PATH}
mkdir -p ${SRV_PATH}/sock
mkdir -p ${ETC_PATH}
mkdir -p ${ETC_PATH}/resources
mkdir -p ${LOG_PATH}
mkdir -p ${LIB_PATH}
#mkdir -p /var/www/.cache/huggingface/transformers  # cache for model code

echo "Setting up virtualenv..."
python3 -m venv ${LIB_PATH}/p3env
source ${LIB_PATH}/p3env/bin/activate

echo "Cloning repositories..."

# The simpler process is to just install dependencies per a requirements.txt file
# With updates, however, the packages could change, leading to unexpected behavior or errors
git clone ${GIT_CLONE_HTTPS} ${TMP_PATH}/${REPO_LBL}

echo "Installing repositories..."
pip install wheel
pip install -r ${TMP_PATH}/${REPO_LBL}/versions.txt

echo "Setting up ownership..."  # makes www-data (how nginx is run) owner + group for all data etc.
chown -R www-data:www-data ${ETC_PATH}
chown -R www-data:www-data ${SRV_PATH}
chown -R www-data:www-data ${LOG_PATH}
chown -R www-data:www-data ${LIB_PATH}
chown -R www-data:www-data /var/www/.cache

echo "Copying configuration files..."
cp -r ${TMP_PATH}/${REPO_LBL}/artdescapi ${ETC_PATH}
cp ${TMP_PATH}/${REPO_LBL}/config/model.nginx ${ETC_PATH}
cp ${TMP_PATH}/${REPO_LBL}/config/model.service ${ETC_PATH}
cp ${TMP_PATH}/${REPO_LBL}/config/uwsgi.ini ${ETC_PATH}
cp ${TMP_PATH}/${REPO_LBL}/config/flask_config.yaml ${ETC_PATH}
cp ${ETC_PATH}/model.nginx /etc/nginx/sites-available/model
if [[ -f "/etc/nginx/sites-enabled/model" ]]; then
    unlink /etc/nginx/sites-enabled/model
fi
ln -s /etc/nginx/sites-available/model /etc/nginx/sites-enabled/
cp ${ETC_PATH}/model.service /etc/systemd/system/

echo "Enabling and starting services..."
systemctl enable model.service  # uwsgi starts when server starts up
systemctl daemon-reload  # refresh state

systemctl restart model.service  # start up uwsgi
systemctl restart nginx  # start up nginx
#!/bin/bash

# Plivo Installation script for CentOS 5.5/5.6
# and Debian based distros (Debian 5.0 , Ubuntu 10.04 and above)
# Copyright (c) 2011 Plivo Team. See LICENSE for details.


PLIVO_CONF_PATH=https://github.com/plivo/plivo/raw/master/src/config/default.conf
PLIVO_GIT_REPO=git://github.com/samof76/plivo.git

#####################################################
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
PLIVO_ENV=$1

CENTOS_PYTHON_VERSION=2.7.2

# Check if Install Directory Present
if [ ! $1 ] || [ -z "$1" ] ; then
    echo ""
    echo "Usage: $(basename $0) <Install Directory Path>"
    echo ""
    exit 1
fi

# Set full path
echo "$PLIVO_ENV" |grep '^/' -q && REAL_PATH=$PLIVO_ENV || REAL_PATH=$PWD/$PLIVO_ENV

# Identify Linix Distribution type
if [ -f /etc/debian_version ] ; then
    DIST='DEBIAN'
elif [ -f /etc/redhat-release ] ; then
    DIST='CENTOS'
else
    echo ""
    echo "This Installer should be run on a CentOS or a Debian based system"
    echo ""
    exit 1
fi

clear
if [ -d $PLIVO_ENV ] ; then
    echo ""
    echo "$PLIVO_ENV already exists!"
    echo "Press any key to continue to update the existing environment or CTRL-C to exit"
    echo ""
    ACTION='UPDATE'
else
    echo ""
    echo "Plivo Framework will be installed at \"$REAL_PATH\""
    echo "Press any key to continue or CTRL-C to exit"
    echo ""
    ACTION='INSTALL'
fi
read INPUT

declare -i PY_MAJOR_VERSION
declare -i PY_MINOR_VERSION
PY_MAJOR_VERSION=$(python -V 2>&1 |sed -e 's/Python[[:space:]]\+\([0-9]\)\..*/\1/')
PY_MINOR_VERSION=$(python -V 2>&1 |sed -e 's/Python[[:space:]]\+[0-9]\+\.\([0-9]\+\).*/\1/')

if [ $PY_MAJOR_VERSION -ne 2 ] || [ $PY_MINOR_VERSION -lt 4 ]; then
    echo ""
    echo "Python version supported between 2.4.X - 2.7.X"
    echo "Please install a compatible version of python."
    echo ""
    exit 1
fi

echo "Setting up Prerequisites and Dependencies"
case $DIST in
    'DEBIAN')
        DEBIAN_VERSION=$(cat /etc/debian_version |cut -d'.' -f1)
        if [ "$DEBIAN_VERSION" = "5" ]; then
            echo "deb http://backports.debian.org/debian-backports lenny-backports main" >> /etc/apt/sources.list
            apt-get -y update
            apt-get -y install git-core python-setuptools python-dev build-essential
            apt-get -y install -t lenny-backports libevent-1.4-2 libevent-dev
        else
            apt-get -y update
            apt-get -y install git-core python-setuptools python-dev build-essential libevent-dev
        fi
        easy_install virtualenv
        easy_install pip
    ;;
    'CENTOS')
        yum -y update
        yum -y install python-setuptools python-tools gcc python-devel libevent libevent-devel zlib-devel readline-devel

        which git &>/dev/null
        if [ $? -ne 0 ]; then
            #install the RPMFORGE Repository
            if [ ! -f /etc/yum.repos.d/rpmforge.repo ];
            then
                # Install RPMFORGE Repo
                rpm --import http://apt.sw.be/RPM-GPG-KEY.dag.txt
echo '
[rpmforge]
name = Red Hat Enterprise $releasever - RPMforge.net - dag
mirrorlist = http://apt.sw.be/redhat/el5/en/mirrors-rpmforge
enabled = 0
protect = 0
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rpmforge-dag
gpgcheck = 1
' > /etc/yum.repos.d/rpmforge.repo
            fi
            yum -y --enablerepo=rpmforge install git-core
        fi

        # Setup Env
        mkdir -p $REAL_PATH/deploy
        DEPLOY=$REAL_PATH/deploy
        cd $DEPLOY
        cd $REAL_PATH/deploy

        # Install Isolated copy of python
        mkdir source
        cd source
        wget http://www.python.org/ftp/python/$CENTOS_PYTHON_VERSION/Python-$CENTOS_PYTHON_VERSION.tgz
        tar -xvf Python-$CENTOS_PYTHON_VERSION.tgz
        cd Python-$CENTOS_PYTHON_VERSION
        ./configure --prefix=$DEPLOY
        make && make install
        # This is what does all the magic by setting upgraded python
        export PATH=$DEPLOY/bin:$PATH

        # Install easy_install
        cd $DEPLOY/source
        wget --no-check-certificate https://github.com/plivo/plivo/raw/master/scripts/ez_setup.py
        $DEPLOY/bin/python ez_setup.py

        EASY_INSTALL=$(which easy_install)
        $DEPLOY/bin/python $EASY_INSTALL --prefix $DEPLOY virtualenv
        $DEPLOY/bin/python $EASY_INSTALL --prefix $DEPLOY pip
    ;;
esac


# Setup virtualenv
virtualenv --no-site-packages $REAL_PATH
source $REAL_PATH/bin/activate

pip install -e git+${PLIVO_GIT_REPO}#egg=plivo


if [ $ACTION = 'INSTALL' ]; then
    mkdir -p $REAL_PATH/etc/plivo &>/dev/null
    wget --no-check-certificate $PLIVO_CONF_PATH -O $REAL_PATH/etc/plivo/default.conf
fi

$REAL_PATH/bin/plivo-postinstall &>/dev/null

# Install Complete
#clear
echo ""
echo ""
echo ""
echo "**************************************************************"
echo "Congratulations, Plivo Framework is now installed in $REAL_PATH"
echo "**************************************************************"
echo
echo "* Configure plivo :"
echo "    The default config is $REAL_PATH/etc/plivo/default.conf"
echo "    Here you can add/remove/modify config files to run mutiple plivo instances"
echo
echo "* To Start Plivo :"
echo "    $REAL_PATH/bin/plivo start"
echo
echo "**************************************************************"
echo ""
echo ""
echo "Visit http://www.plivo.org for documentation and examples"
exit 0

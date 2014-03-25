#!/usr/bin/env bash

host="$1"
ip="$2"
vbox_hostname="$3"

homedir=~
projbase="/vagrant"

# ensure that the script will fail, if any commands fail
set -e

#
# don't run, if the provisioning script hasn't changed since last time
#
fingerprint_file="${homedir}/.last-provisioning-fingerprint"

if [ -f "${fingerprint_file}" ] ; then
  last_fingerprint=$(cat ${fingerprint_file})
  echo "found provisioning fingerprint \"${last_fingerprint}\", checking..."
  if (echo $last_fingerprint && cat "$0") | shasum -sc - ; then
    echo 
    echo "no changes to provisioning script since last provisioning run. skipping..."
    echo "(to force provisioning without modifying the script, delete \"${fingerprint_file}\" in the VM)"
    echo
    exit 0
  fi
fi

#
# create a tmp space for working
#
tmp=$(mktemp -dt "bootstrap.XXXXXXXXXX")


#
# copy in all files from vagrant/copyall
#
echo
echo "copying all files from \"vagrant/copyall\" ..."
( cd ${projbase}/vagrant/copyall && tar -cf - . ) | ( cd / && tar -xkvf - --overwrite )
echo

# Save the vm host name to use later
echo VBOX_HOSTNAME=${vbox_hostname} >> /etc/environment

mkdir -p /var/log/vagrant_provision

function aptget() {
  # this function ensures that apt-get runs non-interactively
  # all defaults are accepted automatically

  DEBIAN_FRONTEND=noninteractive \
    apt-get -y --force-yes \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    $@
}

aptget update
aptget install python-software-properties

#
# update apt and install latest upgrades from ubuntu, if any
#
aptget install debian-archive-keyring
add-apt-repository -y ppa:ondrej/php5

# Add 10gen to apt's sources list and update apt
echo 'deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen' | \
	tee /etc/apt/sources.list.d/10gen.list
add-apt-repository -y ppa:chris-lea/node.js

aptget update

#
# the following PPA is safe (ondrej is one of the debian/ubuntu package engineers)
# it provides latest php (currently 5.5), and more recent apache (currently 2.4?).
#
aptget install python-software-properties

#
# setup mdns, so we can call this eg. "<hostname>.local", from Host operating system
# (we have to edit allow-interfaces in avahi-daemon.conf, to prevent avahi from
# announcing on eth0 which is used as vagrant's control channel only).
#
echo && echo "setting up mdns..."
aptget install -y --force-yes libnss-mdns
cat /etc/avahi/avahi-daemon.conf | sed s/'^#allow-interfaces=.*$'/'allow-interfaces=eth1'/ \
  > "${tmp}/avahi-daemon.conf"
mv "${tmp}/avahi-daemon.conf" /etc/avahi/avahi-daemon.conf

service avahi-daemon restart

aptget install nginx 

# nginx needs sendfile=off in order to pick up changes to files on the "/vagrant" virtualbox share.
sed -i 's/sendfile on/sendfile off/g' /etc/nginx/nginx.conf

#
# PHP5 (needs >= 5.5)
#
aptget install php5-fpm php5-cli php5-curl php-apc php5-intl

# build-essential is required in order for pear/pecl to do its thing
aptget install php-pear php5-dev build-essential  

# `pecl upgrade` works like `pecl install` but doesn't fail when the pkg is already intalled
pecl upgrade mongo  
php5enmod mongo

echo env[VBOX_HOSTNAME]="lwdev-${vbox_hostname}" >> /etc/php5/fpm/php-fpm.conf

#
# MongoDB
#

# Remove previous versions, if necessary
aptget remove mongodb-clients
aptget remove mongodb-server
aptget remove mongodb
aptget autoremove

# Import the 10gen GPG key
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10

# Install latest package
aptget install mongodb-10gen

# seems that `mongoimport` can't immediately connect to mongo after mongo starts
# so, let's ensure mongo is started, then sleep briefly to ensure that mongoimport
# doesn't fail.
service mongodb restart

# Install Java
aptget install default-jre

# Install Node & modules
aptget install -y --force-yes python-software-properties python g++ make

aptget install nodejs

npm config set loglevel warn

#
# dev tools
#
aptget install libgconf2-4
npm install -g bower
aptget install curl
aptget install git
aptget install vim
aptget install git-flow

if ! which composer ; then
  curl -sS https://getcomposer.org/installer | php -- --install-dir=${tmp}
  mv ${tmp}/composer.phar /usr/local/bin/composer
fi

#
# composer install
#

( cd "${projbase}" && composer install )

# install Browser support
aptget install x11-xkb-utils xfonts-100dpi xfonts-75dpi
aptget install xfonts-scalable xserver-xorg-core
aptget install dbus-x11
aptget install libfontconfig1-dev

sudo su - vagrant bash -c "echo '[url \"https://\"]' >> ~/.gitconfig"
sudo su - vagrant bash -c "echo '    insteadOf = git://' >> ~/.gitconfig"
#sudo su - vagrant bash -c "cd /vagrant/client ; ./scripts/init.sh ; ./scripts/build.sh"

service php5-fpm restart
service nginx restart

/etc/init.d/vboxadd setup

#
# store our script fingerprint, so we can avoid re-running this
# in the future, if it's not necessary to do so.
#
new_fingerprint=$(cat "$0" | shasum -p -)
echo "$new_fingerprint" > "${fingerprint_file}"
echo
echo "wrote provisioning fingerprint: \"${new_fingerprint}\", to ${fingerprint_file}"
echo

exit 0;

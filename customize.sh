#!/bin/sh

# Use multiverse
perl -pi -e 's%(universe)$%$1 multiverse%' \
  /etc/ec2-init/templates/sources.list.tmpl
# Add Alestic PPA for runurl package (handy in user-data scripts)
echo "deb http://ppa.launchpad.net/alestic/ppa/ubuntu karmic main" |
  tee /etc/apt/sources.list.d/alestic-ppa.list
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys BE09C571

# Add ubuntu-on-ec2/ec2-tools PPA for updated ec2-ami-tools
echo "deb http://ppa.launchpad.net/ubuntu-on-ec2/ec2-tools/ubuntu karmic main" |
  sudo tee /etc/apt/sources.list.d/ubuntu-on-ec2-ec2-tools.list
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 9EE6D873

# Add Opscode PPA
echo "deb http://apt.opscode.com/ karmic universe" |
  sudo tee /etc/apt/sources.list.d/opscode.list
curl http://apt.opscode.com/packages@opscode.com.gpg.key | sudo apt-key add -

# Install packages
sudo apt-get update
sudo apt-get install -y runurl ec2-ami-tools
sudo apt-get install -y ruby ruby1.8-dev libopenssl-ruby1.8 rdoc ri irb build-essential wget ssl-cert

# Install rubygems from source
wget http://rubyforge.org/frs/download.php/69365/rubygems-1.3.6.tgz &&
  tar zxf rubygems-1.3.6.tgz &&
  sudo ruby rubygems-1.3.6/setup.rb &&
  sudo ln -sfv /usr/bin/gem1.8 /usr/bin/gem &&
  rm -rf rubygems-1.3.6*

# Install chef
sudo gem install chef --no-ri --no-rdoc

# Download cookbooks
wget -O- http://github.com/mikehale/cookbooks/tarball/master > cookbooks.tar.gz
  tar zxf cookbooks.tar.gz &&
  mv mikehale-cookbooks* cookbooks &&
  tar -zcf cookbooks.tar.gz cookbooks &&
  rm -rf cookbooks

# Create json configuration
echo '{ "recipes": ["bootstrap::solo"] }' > bootstrap.json

# Bootstrap chef
sudo chef-solo -r cookbooks.tar.gz -j bootstrap.json -l debug
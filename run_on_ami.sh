export DEBIAN_FRONTEND=noninteractive
echo "deb http://ppa.launchpad.net/ubuntu-on-ec2/ec2-tools/ubuntu karmic main" |
  sudo tee /etc/apt/sources.list.d/ubuntu-on-ec2-ec2-tools.list &&
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 9EE6D873 &&
sudo apt-get update &&
sudo -E apt-get upgrade -y &&
sudo -E apt-get install -y python-vm-builder-ec2

source /mnt/access_keys
export EC2_CERT=$(echo /mnt/cert-*.pem)
export EC2_PRIVATE_KEY=$(echo /mnt/pk-*.pem)

bucket=resources.halethegeek.com
codename=karmic
release=9.10
tag=server
if [ $(uname -m) = 'x86_64' ]; then
  arch=x86_64
  arch2=amd64
  pkgopts="--addpkg=libc6-i386"
  kernelopts="--ec2-kernel=aki-fd15f694 --ec2-ramdisk=ari-c515f6ac"
  ebsopts="--kernel=aki-fd15f694 --ramdisk=ari-c515f6ac"
  ebsopts="$ebsopts --block-device-mapping /dev/sdb=ephemeral0"
else
  arch=i386
  arch2=i386
  pkgopts=
  kernelopts="--ec2-kernel=aki-5f15f636 --ec2-ramdisk=ari-0915f660"
  ebsopts="--kernel=aki-5f15f636 --ramdisk=ari-0915f660"
  ebsopts="$ebsopts --block-device-mapping /dev/sda2=ephemeral0"
fi
cat > part-i386.txt <<EOM
root 10240 a1
/mnt 1 a2
swap 1024 a3
EOM
cat > part-x86_64.txt <<EOM
root 10240 a1
/mnt 1 b
EOM

cat > ec2-firstboot.sh <<EOM
#!/bin/bash## Regenerate the ssh host key#

rm -f /etc/ssh/ssh_host_*_key*

ssh-keygen -f /etc/ssh/ssh_host_rsa_key -t rsa -N '' | logger -s -t "ec2"
ssh-keygen -f /etc/ssh/ssh_host_dsa_key -t dsa -N '' | logger -s -t "ec2"

# This allows user to get host keys securely through console log
# For example: ec2-get-console-output <instanceid> |grep "BEGIN SSH HOST KEY" -A 2|tail -n2|awk '{ print $3 }'
echo "-----BEGIN SSH HOST KEY FINGERPRINTS-----" | logger -s -t "ec2"
ssh-keygen -l -f /etc/ssh/ssh_host_rsa_key.pub | logger -s -t "ec2"
ssh-keygen -l -f /etc/ssh/ssh_host_dsa_key.pub | logger -s -t "ec2"
echo "-----END SSH HOST KEY FINGERPRINTS-----" | logger -s -t "ec2"

depmod -a

exit 0
EOM

cat > setup-server <<'EOM'
#!/bin/bash -ex
imagedir=$1
# fix what I consider to be bugs in vmbuilder
perl -pi -e "s%^127.0.1.1.*\n%%" $imagedir/etc/hosts
rm -f $imagedir/etc/hostname

# Use multiverse
perl -pi -e 's%(universe)$%$1 multiverse%' \
  $imagedir/etc/ec2-init/templates/sources.list.tmpl
# Add Alestic PPA for runurl package (handy in user-data scripts)
echo "deb http://ppa.launchpad.net/alestic/ppa/ubuntu karmic main" |
  tee $imagedir/etc/apt/sources.list.d/alestic-ppa.list
chroot $imagedir \
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys BE09C571
# Add ubuntu-on-ec2/ec2-tools PPA for updated ec2-ami-tools
echo "deb http://ppa.launchpad.net/ubuntu-on-ec2/ec2-tools/ubuntu karmic main" |
  sudo tee $imagedir/etc/apt/sources.list.d/ubuntu-on-ec2-ec2-tools.list
chroot $imagedir \
  sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 9EE6D873
# Add Opscode PPA
echo "deb http://apt.opscode.com/ karmic universe" |
  sudo tee $imagedir/etc/apt/sources.list.d/opscode.list
chroot $imagedir \
  curl http://apt.opscode.com/packages@opscode.com.gpg.key | sudo apt-key add -

# Install packages
chroot $imagedir apt-get update
chroot $imagedir apt-get install -y runurl
chroot $imagedir apt-get install -y ec2-ami-tools

#Install Chef
chroot $imagedir apt-get install -y ruby ruby1.8-dev libopenssl-ruby1.8 rdoc ri irb build-essential wget ssl-cert

#TODO: this stuff needs to run in chroot
cd /tmp
wget http://rubyforge.org/frs/download.php/69365/rubygems-1.3.6.tgz
tar zxf rubygems-1.3.6.tgz
cd rubygems-1.3.6
sudo ruby setup.rb
sudo ln -sfv /usr/bin/gem1.8 /usr/bin/gem

chroot $imagedir sudo gem install chef --no-ri --no-rdoc
EOM
chmod 755 setup-server

cat > solo.rb <<'EOM'
# Chef Client Config File
# Automatically grabs configuration from ohai ec2 metadata.

require 'ohai'
require 'json'

o = Ohai::System.new
o.all_plugins
chef_config = JSON.parse(o[:ec2][:userdata] || "{}")
if chef_config.kind_of?(Array)
  chef_config = chef_config[o[:ec2][:ami_launch_index]]
end

log_level        :info
log_location     STDOUT
node_name        o[:ec2][:instance_id]

if chef_config.has_key?("attributes")
  File.open("/etc/chef/client-config.json", "w") do |f|
    f.print(JSON.pretty_generate(chef_config["attributes"]))
  end
  json_attribs "/etc/chef/client-config.json"
end

file_cache_path    "/var/chef"
cookbook_path      ["/var/chef/site-cookbooks", "/var/chef/cookbooks"]

Mixlib::Log::Formatter.show_time = true
EOM

sudo mkdir -p $imagedir/etc/chef
sudo mv solo.rb $imagedir/etc/chef/

#create init.d script that runs chef-solo against a url as a daemon
# sudo chef-solo -r `cat /etc/chef/cookbooks_url` -d

/usr/bin/ruby -e "\
  require 'rubygems'; require 'json' ; require 'open-uri';\
  userdata = nil;\
  begin;\
    userdata = JSON.parse(open('http://169.254.169.254/2009-04-04/user-data').read);\
  rescue OpenURI::HTTPError; end;\
  print userdata['recipes_url'] if userdata && userdata.has_key?('recipes_url')
" > cookbooks_url
sudo mv cookbooks_url $imagedir/etc/chef/

now=$(date +%Y%m%d-%H%M)
dest=/mnt/dest-$codename-$now
prefix=ubuntu-$release-$codename-$arch-$tag-$now
description="Ubuntu $release $codename $arch $tag $now"
sudo vmbuilder xen ubuntu                 \
  --suite=$codename                       \
  --arch=$arch2                           \
  --dest=$dest                            \
  --tmp=/mnt                              \
  --ec2                                   \
  --ec2-version="$description"            \
  --manifest=$prefix.manifest             \
  --lock-user                             \
  --firstboot=ec2-firstboot.sh            \
  --part=part-$arch.txt                   \
  $kernelopts                             \
  $pkgopts                                \
  --execscript ./setup-server             \
  --debug                                 \
  --ec2-bundle                            \
  --ec2-upload                            \
  --ec2-register                          \
  --ec2-bucket=$bucket                    \
  --ec2-prefix=$prefix                    \
  --ec2-user=$AWS_USER_ID                 \
  --ec2-cert=$EC2_CERT                    \
  --ec2-key=$EC2_PRIVATE_KEY              \
  --ec2-access-key=$AWS_ACCESS_KEY_ID     \
  --ec2-secret-key=$AWS_SECRET_ACCESS_KEY \

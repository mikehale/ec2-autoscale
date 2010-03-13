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
# perl -pi -e "s%^127.0.1.1.*\n%%" $imagedir/etc/hosts
# rm -f $imagedir/etc/hostname

# Use multiverse
perl -pi -e 's%(universe)$%$1 multiverse%' $imagedir/etc/ec2-init/templates/sources.list.tmpl

# Add Alestic PPA for runurl package (handy in user-data scripts)
echo "deb http://ppa.launchpad.net/alestic/ppa/ubuntu karmic main" |
  tee $imagedir/etc/apt/sources.list.d/alestic-ppa.list
chroot $imagedir apt-key adv --keyserver keyserver.ubuntu.com --recv-keys BE09C571

# Add ubuntu-on-ec2/ec2-tools PPA for updated ec2-ami-tools
echo "deb http://ppa.launchpad.net/ubuntu-on-ec2/ec2-tools/ubuntu karmic main" |
  tee $imagedir/etc/apt/sources.list.d/ubuntu-on-ec2-ec2-tools.list
chroot $imagedir apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 9EE6D873

# Add Opscode PPA
echo "deb http://apt.opscode.com/ karmic universe" | tee $imagedir/etc/apt/sources.list.d/opscode.list
chroot $imagedir curl http://apt.opscode.com/packages@opscode.com.gpg.key | apt-key add -

# Install packages
chroot $imagedir apt-get update
chroot $imagedir apt-get install -y runurl ec2-ami-tools
chroot $imagedir apt-get install -y ruby ruby1.8-dev libopenssl-ruby1.8 rdoc ri irb build-essential wget ssl-cert

# Install rubygems from source
wget http://rubyforge.org/frs/download.php/69365/rubygems-1.3.6.tgz
tar zxf rubygems-1.3.6.tgz
mv rubygems-1.3.6 $imagedir
chroot $imagedir ruby rubygems-1.3.6/setup.rb
chroot $imagedir ln -sfv /usr/bin/gem1.8 /usr/bin/gem
rm -rf $imagedir/rubygems-1.3.6

# Install chef
chroot $imagedir gem install chef --no-ri --no-rdoc

# Grab latest cookbooks and rebuild the tar.gz to have a cookbooks prefix
wget -O- http://github.com/mikehale/cookbooks/tarball/master > cookbooks.tar.gz
  tar zxf cookbooks.tar.gz &&
  mv mikehale-cookbooks* cookbooks &&
  tar -zcf cookbooks.tar.gz cookbooks &&
  rm -rf cookbooks &&
  mv cookbooks.tar.gz $imagedir/cookbooks.tar.gz

# Create json
echo '{ "recipes": ["bootstrap::solo"] }' | tee $imagedir/bootstrap.json

# Bootstrap chef solo
chroot $imagedir chef-solo -r cookbooks.tar.gz -j bootstrap.json

# Cleanup
rm $imagedir/bootstrap.json $imagedir/cookbooks.tar.gz

bash -i
EOM
chmod 755 setup-server

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

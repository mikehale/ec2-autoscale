export DEBIAN_FRONTEND=noninteractive
echo "deb http://ppa.launchpad.net/ubuntu-on-ec2/ec2-tools/ubuntu karmic main" |
  sudo tee /etc/apt/sources.list.d/ubuntu-on-ec2-ec2-tools.list &&
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 9EE6D873 &&
sudo apt-get update &&
sudo -E apt-get upgrade -y &&
sudo -E apt-get install -y \
  python-vm-builder ec2-ami-tools ec2-api-tools bzr python-vm-builder-ec2

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
# Install packages
chroot $imagedir apt-get update
chroot $imagedir apt-get install -y runurl
chroot $imagedir apt-get install -y ec2-ami-tools
EOM
chmod 755 setup-server


now=$(date +%Y%m%d-%H%M)
dest=/mnt/dest-$codename-$now
prefix=ubuntu-$release-$codename-$arch-$tag-$now
description="Ubuntu $release $codename $arch $tag $now"
sudo vmbuilder xen ubuntu       \
  --suite=$codename                       \
  --arch=$arch2                           \
  --dest=$dest                            \
  --tmp=/mnt                              \
  --ec2                                   \
  --ec2-version="$description"            \
  --manifest=$prefix.manifest             \
  --lock-user                             \
  --firstboot=/usr/share/doc/python-vm-builder-ec2/examples/ec2-firstboot.sh            \
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

#!/usr/bin/env bash

set -e
base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash
source $base_dir/lib/prelude_bosh.bash

mkdir -p $chroot/etc/sv
cp -a $assets_dir/runit/agent $chroot/etc/sv/agent
cp -a $assets_dir/runit/monit $chroot/etc/sv/monit
mkdir -p $chroot/var/vcap/monit/svlog

# Set up agent and monit with runit
run_in_bosh_chroot $chroot "
chmod +x /etc/sv/agent/run /etc/sv/agent/log/run
rm -f /etc/service/agent
ln -s /etc/sv/agent /etc/service/agent

chmod +x /etc/sv/monit/run /etc/sv/monit/log/run
rm -f /etc/service/monit
ln -s /etc/sv/monit /etc/service/monit
"

# Alerts for monit config
cp -a $assets_dir/alerts.monitrc $chroot/var/vcap/monit/alerts.monitrc
cd $assets_dir

os_type="$(get_os_type)"
if [ "${os_type}" == "ubuntu" ] && [ "${DISTRIB_CODENAME}" == "trusty" ]; then
  if is_ppc64le; then
    curl -L -o bosh-agent "https://s3.amazonaws.com/bosh-toronto-bag/bosh-registry-removal/bosh-agent/bosh-agent-2.67.16-linux-ppc64le"
    echo "617b1fdf4ee0e025362ea4ccf29348a12366f477e3a9ce088bbc4a3368267d81  bosh-agent" | shasum -a 256 -c -
  else
    curl -L -o bosh-agent "https://s3.amazonaws.com/bosh-toronto-bag/bosh-registry-removal/bosh-agent/bosh-agent-2.67.16-linux-amd64"
    echo "71a9c9cbd5554d9edd4faca18fd33ea6c8e47a3fe4861e73e00f2f0385419b79  bosh-agent" | shasum -a 256 -c -
  fi
else
  if is_ppc64le; then
    curl -L -o bosh-agent "https://s3.amazonaws.com/bosh-toronto-bag/bosh-registry-removal/bosh-agent/bosh-agent-2.67.16-linux-ppc64le"
    echo "617b1fdf4ee0e025362ea4ccf29348a12366f477e3a9ce088bbc4a3368267d81  bosh-agent" | shasum -a 256 -c -
  else
    curl -L -o bosh-agent "https://s3.amazonaws.com/bosh-toronto-bag/bosh-registry-removal/bosh-agent/bosh-agent-2.67.16-linux-amd64"
    echo "71a9c9cbd5554d9edd4faca18fd33ea6c8e47a3fe4861e73e00f2f0385419b79  bosh-agent" | shasum -a 256 -c -
  fi
fi

mv bosh-agent $chroot/var/vcap/bosh/bin/

cp $assets_dir/bosh-agent-rc $chroot/var/vcap/bosh/bin/bosh-agent-rc
cp $assets_dir/mbus/agent.{cert,key} $chroot/var/vcap/bosh/

# Download CLI source or release from github into assets directory
cd $assets_dir
rm -rf davcli
mkdir davcli
current_version=0.0.26
curl -L -o davcli/davcli https://s3.amazonaws.com/davcli/davcli-${current_version}-linux-amd64
echo "cd75e886b4f5d27ce41841d5cc902fe64bab7b78 davcli/davcli" | sha1sum -c -
mv davcli/davcli $chroot/var/vcap/bosh/bin/bosh-blobstore-dav
chmod +x $chroot/var/vcap/bosh/bin/bosh-blobstore-dav


chmod +x $chroot/var/vcap/bosh/bin/bosh-agent
chmod +x $chroot/var/vcap/bosh/bin/bosh-agent-rc
chmod +x $chroot/var/vcap/bosh/bin/bosh-blobstore-dav
chmod 600 $chroot/var/vcap/bosh/agent.key

# Setup additional permissions
run_in_chroot $chroot "
rm -f /etc/cron.deny
rm -f /etc/at.deny

chmod 0770 /var/lock
chown -h root:vcap /var/lock
chown -LR root:vcap /var/lock

echo 'vcap' > /etc/cron.allow
echo 'vcap' > /etc/at.allow

chmod -f og-rwx /etc/at.allow /etc/cron.allow /etc/crontab /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.d
chown -f root:root /etc/at.allow /etc/cron.allow /etc/crontab /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.d

chmod -R 0700 /etc/sv/agent
chown -R root:root /etc/sv/agent

# monit processes will inherit this directory as the default $PWD, so make sure processes can read/list
# some scripts/packages might do this during startup and would potentially fail
chmod -R 0755 /etc/sv/monit
chown -R root:root /etc/sv/monit

chmod 0600 /var/vcap/monit/alerts.monitrc
chown root:root /var/vcap/monit/alerts.monitrc
"

# Since go agent is always specified with -C provide empty conf.
# File will be overwritten in whole by infrastructures.
echo '{}' > $chroot/var/vcap/bosh/agent.json

# this directory is utilized by the agent/init/create-env
# https://github.com/cloudfoundry/bosh-agent/blob/1a6b1e11acd941e65c4f4155c22ff9a8f76098f9/micro/https_handler.go#L119
mkdir -p $chroot/$bosh_dir/../micro_bosh/data/cache

name             'openstack-dashboard'
maintainer       'openstack-chef'
maintainer_email 'openstack-dev@lists.openstack.org'
license          'Apache-2.0'
description      'Installs/Configures the OpenStack Dashboard (Horizon)'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '16.0.0'

%w(ubuntu redhat centos).each do |os|
  supports os
end

depends 'openstack-common', '>= 16.0.0'
depends 'openstack-identity', '>= 16.0.0'
depends 'apache2'
depends 'poise-python'

issues_url 'https://launchpad.net/openstack-chef' if respond_to?(:issues_url)
source_url 'https://github.com/openstack/cookbook-openstack-dashboard' if respond_to?(:source_url)
chef_version '>= 12.5' if respond_to?(:chef_version)

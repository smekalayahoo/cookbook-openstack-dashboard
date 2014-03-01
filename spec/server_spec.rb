# encoding: UTF-8
require_relative 'spec_helper'

describe 'openstack-dashboard::server' do

  describe 'ubuntu' do

    let(:runner) { ChefSpec::Runner.new(UBUNTU_OPTS) }
    let(:node) { runner.node }
    let(:chef_run) do
      runner.converge(described_recipe)
    end

    let(:chef_run_session_sql) do
      node.set['openstack']['dashboard']['session_backend'] = 'sql'
      runner.converge(described_recipe)
    end

    include_context 'non_redhat_stubs'
    include_context 'dashboard_stubs'

    it 'does not execute set-selinux-permissive' do
      cmd = '/sbin/setenforce Permissive'
      expect(chef_run).not_to run_execute(cmd)
    end

    it 'installs apache packages' do
      expect(chef_run).to include_recipe('apache2')
      expect(chef_run).to include_recipe('apache2::mod_wsgi')
      expect(chef_run).to include_recipe('apache2::mod_rewrite')
      expect(chef_run).to include_recipe('apache2::mod_ssl')
    end

    it 'does not execute set-selinux-enforcing' do
      cmd = '/sbin/setenforce Enforcing ; restorecon -R /etc/httpd'
      expect(chef_run).not_to run_execute(cmd)
    end

    it 'installs packages' do
      expect(chef_run).to upgrade_package('lessc')
      expect(chef_run).to upgrade_package('openstack-dashboard')
      expect(chef_run).to upgrade_package('python-mysqldb')
    end

    describe 'local_settings.py' do
      let(:file) { chef_run.template('/etc/openstack-dashboard/local_settings.py') }

      it 'has proper owner' do
        expect(file.owner).to eq('root')
        expect(file.group).to eq('root')
      end

      it 'has proper modes' do
        expect(sprintf('%o', file.mode)).to eq('644')
      end

      it 'has the customer banner' do
        expect(chef_run).to render_file(file.name).with_content('autogenerated')
      end

      it 'has the memcached servers' do
        expect(chef_run).to render_file(file.name).with_content('hostA')
      end

      it 'does not configure caching when backend == memcache and no servers provided' do
        Chef::Recipe.any_instance.stub(:memcached_servers)
          .and_return(nil)

        expect(chef_run).not_to render_file(file.name)
        .with_content('django.core.cache.backends.memcached.MemcachedCache')
      end

      it 'does not configure caching when memcache_servers is empty' do
        Chef::Recipe.any_instance.stub(:memcached_servers)
          .and_return([])

        expect(chef_run).not_to render_file(file.name)
        .with_content('django.core.cache.backends.memcached.MemcachedCache')
      end

      it 'has some plugins enabled' do
        node.set['openstack']['dashboard']['plugins'] = ['testPlugin1']
        expect(chef_run).to render_file(file.name).with_content('testPlugin1')
      end

      it 'has some allowed hosts set' do
        node.set['openstack']['dashboard']['allowed_hosts'] = ['dashboard.example.net']
        expect(chef_run).to render_file(file.name).with_content(/^ALLOWED_HOSTS = \["dashboard.example.net"\]/)
      end

      it 'has configurable secret_key_path setting' do
        secret_key_path = '/some/random/path'
        content = "SECRET_KEY = secret_key.generate_or_read_from_file(os.path.realpath('#{secret_key_path}')"
        node.set['openstack']['dashboard']['secret_key_path'] = secret_key_path

        expect(chef_run).to render_file(file.name).with_content(content)
      end

      it 'notifies apache2 restart' do
        expect(file).to notify('service[apache2]').to(:restart)
      end

      it 'does not configure ssl proxy when ssl_offload is false' do
        expect(chef_run).not_to render_file(file.name).with_content('SECURE_PROXY_SSL_HEADER')
      end

      it 'configures ssl proxy when ssl_offload is set to true' do
        node.set['openstack']['dashboard']['ssl_offload'] = true
        expect(chef_run).to render_file(file.name).with_content('SECURE_PROXY_SSL_HEADER')
      end

      it 'has a help_url' do
        expect(chef_run).to render_file(file.name).with_content('docs.openstack.org')
      end

      it 'configures CSRF_COOKIE_SECURE & SESSION_COOKIE_SECURE when use_ssl is true' do
        expect(chef_run).to render_file(file.name).with_content('CSRF_COOKIE_SECURE = True')
        expect(chef_run).to render_file(file.name).with_content('SESSION_COOKIE_SECURE = True')
      end

      it 'sets the allowed hosts' do
        expect(chef_run).to render_file(file.name).with_content(/^ALLOWED_HOSTS = \["\*"\]/)
      end

      it 'has default enable_lbaas setting' do
        expect(chef_run).to render_file(file.name).with_content('\'enable_lb\': False')
      end

      it 'has configurable enable_lbaas setting' do
        node.set['openstack']['dashboard']['neutron']['enable_lb'] = true
        expect(chef_run).to render_file(file.name).with_content('\'enable_lb\': True')
      end

      it 'has default enable_quotas setting' do
        expect(chef_run).to render_file(file.name).with_content('\'enable_quotas\': True')
      end

      it 'has configurable enable_quotas setting' do
        node.set['openstack']['dashboard']['neutron']['enable_quotas'] = false
        expect(chef_run).to render_file(file.name).with_content('\'enable_quotas\': False')
      end

      it 'has default password_autocomplete setting' do
        content = 'HORIZON_CONFIG["password_autocomplete"] = "on"'
        expect(chef_run).to render_file(file.name).with_content(content)
      end

      it 'has default password_autocomplete setting' do
        content = 'HORIZON_CONFIG["password_autocomplete"] = "off"'
        node.set['openstack']['dashboard']['password_autocomplete'] = 'off'
        expect(chef_run).to render_file(file.name).with_content(content)
      end

      it 'enables simple ip management' do
        node.set['openstack']['dashboard']['simple_ip_management'] = true
        expect(chef_run).to render_file(file.name).with_content('HORIZON_CONFIG["simple_ip_management"] = True')
      end

      it 'disables simple ip management' do
        expect(chef_run).to render_file(file.name).with_content('HORIZON_CONFIG["simple_ip_management"] = False')
      end
    end

    describe 'openstack-dashboard syncdb' do
      sync_db_cmd = 'python manage.py syncdb --noinput'
      sync_db_environment = {
        'PYTHONPATH' => '/etc/openstack-dashboard:' \
                        '/usr/share/openstack-dashboard:' \
                        '$PYTHONPATH'
      }

      it 'does not execute when session_backend is not sql' do
        expect(chef_run).not_to run_execute(sync_db_cmd).with(
          cwd: node['openstack']['dashboard']['django_path'],
          environment: sync_db_environment
          )
      end

      it 'executes when session_backend is sql' do
        expect(chef_run_session_sql).to run_execute(sync_db_cmd).with(
          cwd: node['openstack']['dashboard']['django_path'],
          environment: sync_db_environment
          )
      end

      it 'does not execute when the migrate attribute is set to false' do
        node.set['openstack']['db']['dashboard']['migrate'] = false
        expect(chef_run_session_sql).not_to run_execute(sync_db_cmd).with(
          cwd: node['openstack']['dashboard']['django_path'],
          environment: sync_db_environment
          )
      end
    end

    describe 'certs' do
      let(:crt) { chef_run.cookbook_file('/etc/ssl/certs/horizon.pem') }
      let(:key) { chef_run.cookbook_file('/etc/ssl/private/horizon.key') }

      it 'has proper owner' do
        expect(crt.owner).to eq('root')
        expect(crt.group).to eq('root')
        expect(key.owner).to eq('root')
        expect(key.group).to eq('ssl-cert')
      end

      it 'has proper modes' do
        expect(sprintf('%o', crt.mode)).to eq('644')
        expect(sprintf('%o', key.mode)).to eq('640')
      end

      it 'notifies restore-selinux-context' do
        expect(crt).to notify('execute[restore-selinux-context]').to(:run)
        expect(key).to notify('execute[restore-selinux-context]').to(:run)
      end
    end

    it 'creates .blackhole dir with proper owner' do
      dir = '/usr/share/openstack-dashboard/openstack_dashboard/.blackhole'

      expect(chef_run.directory(dir).owner).to eq('root')
    end

    describe 'openstack-dashboard virtual host' do
      let(:file) { chef_run.template('/etc/apache2/sites-available/openstack-dashboard') }

      it 'has proper owner' do
        expect(file.owner).to eq('root')
        expect(file.group).to eq('root')
      end

      it 'has proper modes' do
        expect(sprintf('%o', file.mode)).to eq('644')
      end

      it 'has the default banner' do
        expect(chef_run).to render_file(file.name).with_content('autogenerated')
      end

      it 'has the default DocRoot' do
        expect(chef_run).to render_file(file.name)
        .with_content('DocumentRoot /usr/share/openstack-dashboard/openstack_dashboard/.blackhole/')
      end

      it 'sets the ServerName directive ' do
        node.set['openstack']['dashboard']['server_hostname'] = 'spec-test-host'

        expect(chef_run).to render_file(file.name).with_content('spec-test-host')
      end

      it 'uses the apache default http port' do
        node.set['openstack']['dashboard']['http_port'] = 80

        expect(chef_run).not_to render_file(file.name).with_content('Listen *:80')
        expect(chef_run).not_to render_file(file.name).with_content('NameVirtualHost *:80')
        expect(chef_run).to render_file(file.name).with_content('<VirtualHost *:80>')
      end

      it 'uses the apache default https port' do
        node.set['openstack']['dashboard']['https_port'] = 443

        expect(chef_run).not_to render_file(file.name).with_content('Listen *:443')
        expect(chef_run).not_to render_file(file.name).with_content('NameVirtualHost *:443')
        expect(chef_run).to render_file(file.name).with_content('<VirtualHost *:443>')
      end

      it 'sets the http port' do
        node.set['openstack']['dashboard']['http_port'] = 8080

        expect(chef_run).to render_file(file.name).with_content('Listen *:8080')
        expect(chef_run).to render_file(file.name).with_content('NameVirtualHost *:8080')
        expect(chef_run).to render_file(file.name).with_content('<VirtualHost *:8080>')
      end

      it 'sets the https port' do
        node.set['openstack']['dashboard']['https_port'] = 4430

        expect(chef_run).to render_file(file.name).with_content('Listen *:4430')
        expect(chef_run).to render_file(file.name).with_content('NameVirtualHost *:4430')
        expect(chef_run).to render_file(file.name).with_content('<VirtualHost *:4430>')
      end

      it 'notifies restore-selinux-context' do
        expect(file).to notify('execute[restore-selinux-context]').to(:run)
      end

      it 'sets the right Alias path for /static' do
        expect(chef_run).to render_file(file.name).with_content(
          %r{^\s+Alias /static /usr/share/openstack-dashboard/static$})
      end

      it 'sets the WSGI daemon user' do
        node.set['openstack']['dashboard']['horizon_user'] = 'somerandomuser'
        expect(chef_run).to render_file(file.name).with_content('WSGIDaemonProcess dashboard user=somerandomuser')
      end

      it 'sets the WSGI daemon user to attribute default' do
        expect(chef_run).to render_file(file.name).with_content('WSGIDaemonProcess dashboard user=horizon')
      end
    end

    describe 'secret_key_path file' do
      secret_key_path = '/var/lib/openstack-dashboard/secret_key'
      let(:file) { chef_run.file(secret_key_path) }

      it 'has correct ownership' do
        expect(file.owner).to eq('horizon')
        expect(file.group).to eq('horizon')
      end

      it 'has correct mode' do
        expect(file.mode).to eq(00600)
      end

      it 'does not notify apache2 restart' do
        expect(file).not_to notify('service[apache2]').to(:restart)
      end

      it 'has configurable path and ownership settings' do
        node.set['openstack']['dashboard']['secret_key_path'] = 'somerandompath'
        node.set['openstack']['dashboard']['horizon_user'] = 'somerandomuser'
        node.set['openstack']['dashboard']['horizon_group'] = 'somerandomgroup'
        file = chef_run.file('somerandompath')
        expect(file.owner).to eq('somerandomuser')
        expect(file.group).to eq('somerandomgroup')
      end

      describe 'secret_key_content set' do
        before do
          node.set['openstack']['dashboard']['secret_key_content'] = 'somerandomcontent'
        end

        it 'has configurable secret_key_content setting' do
          expect(chef_run).to render_file(file.name).with_content('somerandomcontent')
        end

        it 'notifies apache2 restart when secret_key_content set' do
          expect(file).to notify('service[apache2]').to(:restart)
        end
      end
    end

    it 'does not delete openstack-dashboard.conf' do
      file = '/etc/httpd/conf.d/openstack-dashboard.conf'

      expect(chef_run).not_to delete_file(file)
    end

    it 'removes openstack-dashboard-ubuntu-theme package' do
      expect(chef_run).to purge_package('openstack-dashboard-ubuntu-theme')
    end

    it 'calls apache_site to disable 000-default virtualhost' do

      resource = chef_run.find_resource('execute',
                                        'a2dissite 000-default').to_hash
      expect(resource).to include(
        action: 'run',
        params: {
          enable: false,
          name: '000-default'
        }
      )
    end

    it 'calls apache_site to enable openstack-dashboard virtualhost' do

      resource = chef_run.find_resource('execute',
                                        'a2ensite openstack-dashboard').to_hash
      expect(resource).to include(
        action: 'run',
        params: {
          enable: true,
          notifies: [:reload, 'service[apache2]', :immediately],
          name: 'openstack-dashboard'
        }
      )
    end

    it 'notifies apache2 restart' do
      pending 'TODO: how to test when tied to an LWRP'
    end

    it 'does not execute restore-selinux-context' do
      cmd = 'restorecon -Rv /etc/httpd /etc/pki; chcon -R -t httpd_sys_content_t /usr/share/openstack-dashboard || :'

      expect(chef_run).not_to run_execute(cmd)
    end

    it 'has group write mode on path' do
      path = chef_run.directory("#{chef_run.node['openstack']['dashboard']['dash_path']}/local")
      expect(path.mode).to eq(02770)
      expect(path.group).to eq(chef_run.node['openstack']['dashboard']['horizon_group'])
    end
  end
end

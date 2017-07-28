# chocolatey_server - Host your own Chocolatey package repository
#
# @author Rob Reynolds and puppet-chocolatey_server contributors
#
# @example Default - install the server
#   include chocolatey_server
#
# @example Use a different port
#   class {'chocolatey_server':
#     port => '8080',
#   }
#
# @example Use an internal source for installing the `chocolatey.server` package
#   class {'chocolatey_server':
#     server_package_source => 'http://someinternal/nuget/odatafeed',
#   }
#
# @example Use a local file source for the `chocolatey.server` package
#   class {'chocolatey_server':
#     server_package_source => 'c:/folder/containing/packages',
#   }
#
# @param [String] port The port for the server website. Defaults to '80'.
#
# @param [String] server_package_source The chocolatey source that contains
#   the `chocolatey.server` package. Defaults to
#   'https://chocolatey.org/api/v2/'.
#
# @param [String] server_install_location The location to that the chocolatey
#   server will be installed.  This is can be used if you are controlling
#   the location that chocolatey packages are being installed via some other
#   means. e.g. environment variable ChocolateyBinRoot.  Defaults to
#   'C:\tools\chocolatey.server'
class chocolatey_server (
  $allow_package_override = $::chocolatey_server::params::allow_package_override,
  $apikey = $::chocolatey_server::params::apikey,
  $chocolatey_server_app_pool_name = $::chocolatey_server::params::chocolatey_server_app_pool_name,
  $chocolatey_server_ensure = $::chocolatey_server::params::chocolatey_server_ensure,
  $disable_default_website = $::chocolatey_server::params::disable_default_website,
  $max_file_size_bytes = $::chocolatey_server::params::max_file_size_bytes,
  $packages_folder = $::chocolatey_server::params::packages_folder,
  $packages_folder_permissions = $::chocolatey_server::params::packages_folder_permissions,
  $port = $::chocolatey_server::params::service_port,
  $require_apikey = $::chocolatey_server::params::require_apikey,
  $server_package_source = $::chocolatey_server::params::server_package_source,
  $server_install_location = $::chocolatey_server::params::server_install_location,
) inherits ::chocolatey_server::params {
  require chocolatey

  $_chocolatey_server_location      = $server_install_location
  $_chocolatey_server_app_pool_name = $chocolatey_server_app_pool_name
  $_chocolatey_server_app_port      = $port
  $_server_package_url              = $server_package_source
  $_is_windows_2008 = $::kernelmajversion ? {
    '6.1'   => true,
    default => false
  }
  $_install_management_tools = $_is_windows_2008 ? {
    true    => false,
    default => true
  }
  $_web_asp_net = $_is_windows_2008 ? {
    true    => 'Web-Asp-Net',
    default => 'Web-Asp-Net45'
  }

  # package install
  package {'chocolatey.server':
    ensure   => $chocolatey_server_ensure,
    provider => chocolatey,
    source   => $_server_package_url,
  }

  # add windows features
  windowsfeature { 'Web-WebServer':
    ensure => present,
    installmanagementtools => $_install_management_tools,
  } ->
  windowsfeature { "${_web_asp_net}":
    ensure => present,
  } ->

  # remove default web site
  dsc_xwebsite{'Default Web Site':
    dsc_ensure       => 'Absent',
    dsc_name         => 'Default Web Site',
    dsc_applicationpool => 'DefaultAppPool',
    require   => Windowsfeature['Web-WebServer'],
  } ->

  # application in iis
  dsc_xwebapppool { "${_chocolatey_server_app_pool_name}":
    dsc_ensure => 'Present',
    dsc_name => $_chocolatey_server_app_pool_name,
    dsc_enable32bitapponwin64 => true,
    dsc_managedruntimeversion => 'v4.0',
  } ->

  dsc_xwebsite{'chocolatey.server':
    dsc_ensure       => 'Present',
    dsc_name         => 'chocolatey.server',
    dsc_physicalpath => $_chocolatey_server_location,
    dsc_applicationpool => $_chocolatey_server_app_pool_name,
    dsc_bindinginfo => [
      {
        protocol => 'http',
        port => $_chocolatey_server_app_port,
        ipaddress => '*',
      }
    ],
    require   => Package['chocolatey.server'],
  } ->

  # lock down web directory
  acl { "${_chocolatey_server_location}":
    purge                      => true,
    inherit_parent_permissions => false,
    permissions                => [
      { identity => 'Administrators',
      rights     => ['full'] },
      { identity => 'IIS_IUSRS',
      rights     => ['read'] },
      { identity => 'IUSR',
      rights     => ['read'] },
      { identity => "IIS APPPOOL\\${_chocolatey_server_app_pool_name}",
      rights     => ['read'] }
    ],
    require                    => [Dsc_xwebsite['chocolatey.server'],
                                  Package['chocolatey.server']],
  }

  # configure chocolatey server settings
  file { "${_chocolatey_server_location}/web.config":
    ensure  => file,
    content => template('chocolatey_server/web.config.erb'),
    require => Package['chocolatey.server'],
  }

  # only set permissions if an alternate package folder is undefined
  unless $packages_folder {
    # ensure app_data folder is created
    file { "${_chocolatey_server_location}/App_Data":
      ensure  => directory,
      require => Package['chocolatey.server'],
    }

    # ensure packages folder is created
    file { "${_chocolatey_server_location}/App_Data/Packages":
      ensure  => directory,
      require => File["${_chocolatey_server_location}/App_Data"],
    }

    acl { "${_chocolatey_server_location}/App_Data":
      permissions => $packages_folder_permissions,
      require     => [Dsc_xwebsite['chocolatey.server'],
                      File["${_chocolatey_server_location}/App_Data"],
                      Package['chocolatey.server']],
    }
    # technically you may only need IIS_IUSRS but I have not tested this yet.
  }

  # if a different folder for packages is specified, create a symlink
  if $packages_folder {
    # ensure app_data folder is created
    file { "${_chocolatey_server_location}/App_Data":
      ensure => directory,
    }

    # ensure packages folder is created
    file { "${packages_folder}":
      ensure => directory,
    }

    # create a symlink to the new packages folder, replacing the existing
    # app_data folder
    file { "${_chocolatey_server_location}/App_Data/Packages":
      ensure  => link,
      force   => true,
      target  => $packages_folder,
      require => File["${packages_folder}"],
    }

    # set permissions on the new packages folder
    acl { "${packages_folder}":
      permissions => $packages_folder_permissions,
      require     => File["${packages_folder}"],
    }
  }

}

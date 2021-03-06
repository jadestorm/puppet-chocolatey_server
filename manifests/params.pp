# chocolatey_server::params
#
# This class is meant to be called from chocolatey_server.
# It sets variables according to platform.
class chocolatey_server::params {
  case $::osfamily {
    'windows': {
      $allow_package_override = false
      $apikey = 'chocolateyrocks'
      $chocolatey_server_app_pool_name = 'chocolatey.server'
      $chocolatey_server_ensure = 'installed'
      $disable_default_website = true
      $max_file_size_bytes = '51200'
      $packages_folder = undef
      $packages_folder_permissions = [
        { identity => "IIS APPPOOL\\${chocolatey_server_app_pool_name}", rights => ['modify'] },
        { identity => 'IIS_IUSRS', rights => ['modify'] }
      ]
      $require_apikey = true
      $service_port = '80'
      $server_package_source = 'https://chocolatey.org/api/v2/'
      $server_install_location = 'C:\tools\chocolatey.server'
    }
    default: {
      fail("${::operatingsystem} not supported")
    }
  }
}

################################################################################
# Time-stamp: <Mon 2019-10-07 23:36 svarrette>
#
# File::      <tt>pmix/build.pp</tt>
# Author::    UL HPC Team (hpc-sysadmins@uni.lu)
# Copyright:: Copyright (c) 2019 UL HPC Team
# License::   Apache-2.0
#
# ------------------------------------------------------------------------------
# = Defines: slurm::build
#
# This definition takes care of building PMIx sources into RPMs using 'rpmbuild'.
# It expect to get as resource name the PMIx version to build
# This assumes the sources have been downloaded using slurm::pmix::download
#
#
# @param ensure  [String]  Default: 'present'
#          Ensure the presence (or absence) of building
# @param srcdir  [String] Default: '/usr/local/src'
#          Where the [downloaded] Slurm sources are located
# @param dir     [String] Default: '/root/rpmbuild' on redhat systems
#          Top directory of the sources builds (i.e. RPMs, debs...)
#          For instance, built RPMs will be placed under
#          <dir>/RPMS/${::architecture}
#
# @example Building version 3.1.4 (latest at the time of writing)  of PMIx
#
#     slurm::pmix::build { '3.1.4':
#       ensure => 'present',
#       srcdir => '/usr/local/src',
#       dir    => '/root/rpmbuild',
#   }
#
# NOTE: on purpose, this definition will build separate RPMs in ${dir}/RPMS/${::architecture}:
#  1. pmix-<version>-*.rpm: the main package
#  2. pmix-libmpi-<version>-*.rpm: PMI-1 and PMI-2 compatibility libraries (i.e.
#  libpmi and libpmi2 libraries) that provide the respective APIs and a copy of
#  the PMIx library –  each API is translated into its PMIx equivalent. This
#  package conflicts with slurm-libpmi, which provides its own, incompatible
#  versions of libpmi.so and libpmi2.so.
#
# In particular, ONLY THE FIRST RPM will be installed (to avoid the conflict
# with slurm-libmpi).
#
define slurm::pmix::build(
  String  $ensure  = $slurm::params::ensure,
  String  $srcdir  = $slurm::params::srcdir,
  String  $dir     = $slurm::params::builddir,
)
{
  include ::slurm::params
  validate_legacy('String',  'validate_re',   $ensure, ['^present', '^absent'])
  validate_legacy('String',  'validate_re',   $name,   [ '\d+[\.-]?' ])

  # $name is provided at define invocation
  $version = $name

  # Path to the PMIx sources
  $src = "${srcdir}/pmix-${version}.tar.bz2"

  # Label for the exec
  $buildname = $ensure ? {
    'absent'  => "uninstall-pmix-${version}",
    default   => "build-pmix-${version}",
    }

  case $::osfamily {
    'Redhat': {
      include ::epel
      include ::yum
      if !defined(Yum::Group[$slurm::params::groupinstall]) {
        yum::group { $slurm::params::groupinstall:
          ensure  => 'present',
          timeout => 600,
          require => Class['::epel'],
        }
      }
      if !defined(Package['libevent-devel']) {
        package { 'libevent-devel':
          ensure => 'present',
        }
      }
      Yum::Group[$slurm::params::groupinstall] -> Exec[$buildname]
      Package['libevent-devel'] -> Exec[$buildname]

      $rpmdir = "${dir}/RPMS/${::architecture}"
      $rpms = prefix(suffix($slurm::params::pmix_rpms, "-${version}*.rpm"), "${rpmdir}/")
      # the below command should typically produce the following RPMs
      # pmix[-libpmi]-<version>-1.el7.x86_64.rpm
      case $ensure {
        'absent': {
          $cmd          = "rm -f ${rpmdir}/pmix*-${version}*.rpm"
          $check_onlyif = "test -n \"$(ls ${rpms[0]} 2>/dev/null)\""
          $check_unless = undef
        }
        default: {
          $cmd          = "rpmbuild -ta --define \"_topdir ${dir}\" --define \"install_in_opt 1\" --define \"build_all_in_one_rpm 0\" ${src}"
          $check_onlyif = undef
          $check_unless = suffix(prefix($rpms, 'test -n "$(ls '), ' 2>/dev/null)"')
          #"test -n \"$(ls ${main_rpm} 2>/dev/null)\""
        }
      }
    }
    default: {
      fail("Module ${module_name} is not supported on ${::operatingsystem}")
    }
  }

  #notice($cmd)
  exec { $buildname:
    path    => '/sbin:/usr/bin:/usr/sbin:/bin',
    command => $cmd,
    cwd     => '/root',
    user    => 'root',
    timeout => 600,
    onlyif  => $check_onlyif,
    unless  => $check_unless,
  }

}

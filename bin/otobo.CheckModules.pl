#!/usr/bin/env perl
# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2020 Rother OSS GmbH, https://otobo.de/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

use strict;
use warnings;
use feature qw(say);

use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);
use lib dirname($RealBin) . '/Kernel/cpan-lib';
use lib dirname($RealBin) . '/Custom';

use Kernel::System::Environment;
use Kernel::System::VariableCheck qw( :all );

use ExtUtils::MakeMaker;
use File::Path;
use Getopt::Long;
use Term::ANSIColor;

my %InstTypeToCMD = (

    # [InstType] => {
    #    CMD       => '[cmd to install module]',
    #    UseModule => 1/0,
    # }
    # Set UseModule to 1 if you want to use the
    # cpan module name of the package as replace string.
    # e.g. yum install "perl(Date::Format)"
    # If you set it 0 it will use the name
    # for the InstType of the module
    # e.g. apt-get install -y libtimedate-perl
    # and as fallback the default cpan install command
    # e.g. cpan DBD::Oracle
    aptget => {
        CMD       => 'apt-get install -y %s',
        UseModule => 0,
    },
    emerge => {
        CMD       => 'emerge %s',
        UseModule => 0,
    },
    ppm => {
        CMD       => 'ppm install %s',
        UseModule => 0,
    },
    yum => {
        CMD       => 'yum install "%s"',
        SubCMD    => 'perl(%s)',
        UseModule => 1,
    },
    zypper => {
        CMD       => 'zypper install %s',
        UseModule => 0,
    },
    ports => {
        CMD       => 'cd /usr/ports %s',
        SubCMD    => ' && make -C %s install clean',
        UseModule => 0,
    },
    default => {
        CMD => 'cpan %s',
    },
);

my %DistToInstType = (

    # apt-get
    debian => 'aptget',
    ubuntu => 'aptget',

    # emerge
    # for reasons unknown, some environments return "gentoo" (incl. the quotes)
    '"gentoo"' => 'emerge',
    gentoo     => 'emerge',

    # yum
    centos => 'yum',
    fedora => 'yum',
    rhel   => 'yum',
    redhat => 'yum',

    # zypper
    suse => 'zypper',

    # FreeBSD
    freebsd => 'ports',
);

# Used for the generation of a cpanfile.
my %FeatureDescription = (
    mysql        => 'Support for database MySQL',
    odbc         => 'Support for database access via ODBC',
    oracle       => 'Support for database Oracle',
    postgresql   => 'Support for database PostgreSQL',
    docker       => 'Optional modules that are included in the Docker image',
    optional     => 'Modules that are not required',
);

my $OSDist;
eval {
    require Linux::Distribution;    ## nofilter(TidyAll::Plugin::OTOBO::Perl::Require)
    import Linux::Distribution;
    $OSDist = Linux::Distribution::distribution_name() || '';
};
$OSDist //= $^O;

my $DoPrintAllModules;
my $DoPrintPackageList;
my $DoPrintCpanfile;
my $DoPrintHelp;
GetOptions(
    all       => \$DoPrintAllModules,
    list      => \$DoPrintPackageList,
    cpanfile  => \$DoPrintCpanfile,
    'help|h'  => \$DoPrintHelp,
);

# check needed params
if ($DoPrintHelp) {
    print "\n";
    print "Print all required and optional packages of OTOBO.\n";
    print "Optionally limit to the required but missing packages or modules.\n";
    print "\n";
    print "Usage:\n";
    print "  otobo.CheckModules.pl [-help|-list|-cpanfile|-all]\n";
    print "\n";
    print "Options:\n";
    printf " %-22s - %s\n", '[-help]',     'Print this help message.';
    printf " %-22s - %s\n", '[-h]',        'Same as -help.';
    printf " %-22s - %s\n", '[-list]',     'Print an install command with all required packages that are missing.';
    printf " %-22s - %s\n", '[-cpanfile]', 'Print a cpanfile with the required modules regardless whether they are already available.';
    printf " %-22s - %s\n", '[-all]',      'Print all required, optional and bundled packages of OTOBO.';
    print "\n";

    exit 1;
}

my $Options = shift || '';
my $NoColors;

if ( $DoPrintCpanfile || $ENV{nocolors} || $Options =~ m{\A nocolors}msxi ) {
    $NoColors = 1;
}

my $ExitCode = 0;    # success

# This is the reference for Perl modules that are required by OTOBO.
# Modules that are required are marked by setting 'Required' to 1.
# Dependent packages can be declared by setting 'Depends' to a ref to an array of hash refs.
# The key 'Features' is only used for supporting features when creating a cpanfile.
#
# ATTENTION: when makeing changes here then make sure that you also regenerate the cpanfile
#           bin/otobo.CheckModules.pl --cpanfile > cpanfile
my @NeededModules = (
    {
        Module    => 'Apache::DBI',
        Required  => 0,
        Comment   => 'Improves Performance on Apache webservers with mod_perl enabled.',
        InstTypes => {
            aptget => 'libapache-dbi-perl',
            emerge => 'dev-perl/Apache-DBI',
            zypper => 'perl-Apache-DBI',
            ports  => 'www/p5-Apache-DBI',
        },
    },
    {
        Module    => 'Apache2::Reload',
        Required  => 0,
        Comment   => 'Avoids web server restarts on mod_perl.',
        InstTypes => {
            aptget => 'libapache2-mod-perl2',
            emerge => 'dev-perl/Apache-Reload',
            zypper => 'apache2-mod_perl',
            ports  => 'www/mod_perl2',
        },
    },
    {
        Module    => 'Archive::Tar',
        Required  => 1,
        Comment   => 'Required for compressed file generation (in perlcore).',
        InstTypes => {
            emerge => 'perl-core/Archive-Tar',
            zypper => 'perl-Archive-Tar',
            ports  => 'archivers/p5-Archive-Tar',
        },
    },
    {
        Module    => 'Archive::Zip',                               # Rother OSS / TODO required for OTOBOCommunity
        Required  => 1,
        Comment   => 'Required for compressed file generation.',
        InstTypes => {
            aptget => 'libarchive-zip-perl',
            emerge => 'dev-perl/Archive-Zip',
            zypper => 'perl-Archive-Zip',
            ports  => 'archivers/p5-Archive-Zip',
        },
    },
    {
        Module    => 'CGI::Emulate::PSGI',
        Required  => 0,
        Features   => ['plack'],
        Comment   => 'Support old fashioned CGI in a PSGI application',
        InstTypes => {
            aptget => undef,
            emerge => undef,
            zypper => undef,
            ports  => undef,
        },
    },
    {
        Module    => 'CGI::PSGI',
        Required  => 0,
        Features   => ['plack'],
        Comment   => 'Adapt CGI.pm to the PSGI protocol',
        InstTypes => {
            aptget => undef,
            emerge => undef,
            zypper => undef,
            ports  => undef,
        },
    },
    {
        Module    => 'Crypt::Eksblowfish::Bcrypt',
        Required  => 0,
        Comment   => 'For strong password hashing.',
        Features   => ['docker'],
        InstTypes => {
            aptget => 'libcrypt-eksblowfish-perl',
            emerge => 'dev-perl/Crypt-Eksblowfish',
            zypper => 'perl-Crypt-Eksblowfish',
            ports  => 'security/p5-Crypt-Eksblowfish',
        },
    },
    {
        Module    => 'Date::Format',
        Required  => 1,
        InstTypes => {
            aptget => 'libtimedate-perl',
            emerge => 'dev-perl/TimeDate',
            zypper => 'perl-TimeDate',
            ports  => 'devel/p5-TimeDate',
        },
    },
    {
        Module    => 'DateTime',
        Required  => 1,
        InstTypes => {
            aptget => 'libdatetime-perl',
            emerge => 'dev-perl/DateTime',
            zypper => 'perl-DateTime',
            ports  => 'devel/p5-TimeDate',
        },
        Depends => [
            {
                Module              => 'DateTime::TimeZone',
                Comment             => 'Olson time zone database, required for correct time calculations.',
                VersionsRecommended => [
                    {
                        Version => '2.20',
                        Comment => 'This version includes recent time zone changes for Chile.',
                    },
                ],
            },
        ],
    },
    {
        Module    => 'DBI',
        Required  => 1,
        InstTypes => {
            aptget => 'libdbi-perl',
            emerge => 'dev-perl/DBI',
            zypper => 'perl-DBI',
            ports  => 'databases/p5-DBI',
        },
    },
    {
        Module    => 'DBD::mysql',
        Required  => 0,
        Comment   => 'Required to connect to a MySQL database.',
        Features  => ['mysql'],
        InstTypes => {
            aptget => 'libdbd-mysql-perl',
            emerge => 'dev-perl/DBD-mysql',
            zypper => 'perl-DBD-mysql',
            ports  => 'databases/p5-DBD-mysql',
        },
    },
    {
        Module               => 'DBD::ODBC',
        Required             => 0,
        VersionsNotSupported => [
            {
                Version => '1.23',
                Comment =>
                    'This version is broken and not useable! Please upgrade to a higher version.',
            },
        ],
        Comment   => 'Required to connect to a MS-SQL database.',
        Features  => ['odbc'],
        InstTypes => {
            aptget => 'libdbd-odbc-perl',
            emerge => undef,
            yum    => undef,
            zypper => undef,
            ports  => 'databases/p5-DBD-ODBC',
        },
    },
    {
        Module    => 'DBD::Oracle',
        Required  => 0,
        Comment   => 'Required to connect to a Oracle database.',
        Features  => ['oracle'],
        InstTypes => {
            aptget => undef,
            emerge => undef,
            yum    => undef,
            zypper => undef,
            ports  => undef,
        },
    },
    {
        Module    => 'DBD::Pg',
        Required  => 0,
        Comment   => 'Required to connect to a PostgreSQL database.',
        Features  => ['postgresql'],
        InstTypes => {
            aptget => 'libdbd-pg-perl',
            emerge => 'dev-perl/DBD-Pg',
            zypper => 'perl-DBD-Pg',
            ports  => 'databases/p5-DBD-Pg',
        },
    },
    {
        Module    => 'DBIx::Connector',
        Required  => 0,
        Features   => ['plack'],
        Comment   => 'Sane persistent database connection',
        InstTypes => {
            aptget => undef,
            emerge => undef,
            zypper => undef,
            ports  => undef,
        },
    },
    {
        Module    => 'Digest::SHA',    # Supposed to be in perlcore, but seems to be missing on some distributions.
        Required  => 1,
        InstTypes => {
            aptget => 'libdigest-sha-perl',
            emerge => 'dev-perl/Digest-SHA',
            zypper => 'perl-Digest-SHA',
            ports  => 'security/p5-Digest-SHA'
        },
    },
    {
        Module          => 'Encode::HanExtra',
        VersionRequired => '0.23',
        Required        => 0,
        Comment         => 'Required to handle mails with several Chinese character sets.',
        InstTypes       => {
            aptget => 'libencode-hanextra-perl',
            emerge => 'dev-perl/Encode-HanExtra',
            zypper => 'perl-Encode-HanExtra',
            ports  => 'chinese/p5-Encode-HanExtra',
        },
    },
    {
        Module    => 'Gazelle',
        Required  => 0,
        Features   => ['plack'],
        Comment   => 'High-performance preforking PSGI/Plack web server',
        InstTypes => {
            aptget => undef,
            emerge => undef,
            zypper => undef,
            ports  => undef,
        },
    },
    {
        Module              => 'IO::Socket::SSL',
        Required            => 0,
        Comment             => 'Required for SSL connections to web and mail servers.',
        VersionsRecommended => [
            {
                Version => '2.066',
                Comment => 'This version fixes email sending (bug#14357).',
            },
        ],
        InstTypes => {
            aptget => 'libio-socket-ssl-perl',
            emerge => 'dev-perl/IO-Socket-SSL',
            zypper => 'perl-IO-Socket-SSL',
            ports  => 'security/p5-IO-Socket-SSL',
        },
    },
    {
        Module    => 'JSON::XS',
        Required  => 0,
        Comment   => 'Recommended for faster AJAX/JavaScript handling.',
        Features   => ['docker'],
        InstTypes => {
            aptget => 'libjson-xs-perl',
            emerge => 'dev-perl/JSON-XS',
            zypper => 'perl-JSON-XS',
            ports  => 'converters/p5-JSON-XS',
        },
    },
    {
        Module    => 'Linux::Inotify2',
        Required  => 0,
        Features   => ['plack'],
        Comment   => 'Used with the -R option of plackup. Restart the server when files have changed.',
        InstTypes => {
            aptget => undef,
            emerge => undef,
            zypper => undef,
            ports  => undef,
        },
    },
    {
        Module   => 'List::Util::XS',
        Required => 1,
        Comment =>
            "Do a 'force install Scalar::Util' via cpan shell to fix this problem. Please make sure to have an c compiler and make installed before.",
        InstTypes => {
            aptget => 'libscalar-list-utils-perl',
            emerge => 'perl-core/Scalar-List-Utils',
            zypper => 'perl-Scalar-List-Utils',
            ports  => 'lang/p5-Scalar-List-Utils',
        },
    },
    {
        Module    => 'LWP::UserAgent',
        Required  => 1,
        InstTypes => {
            aptget => 'libwww-perl',
            emerge => 'dev-perl/libwww-perl',
            zypper => 'perl-libwww-perl',
            ports  => 'www/p5-libwww',
        },
    },
    {
        Module          => 'Mail::IMAPClient',
        VersionRequired => '3.22',
        Comment         => 'Required for IMAP TLS connections.',
        Required        => 0,
        Features        => ['docker'],
        InstTypes       => {
            aptget => 'libmail-imapclient-perl',
            emerge => 'dev-perl/Mail-IMAPClient',
            zypper => 'perl-Mail-IMAPClient',
            ports  => 'mail/p5-Mail-IMAPClient',
        },
        Depends => [
            {
                Module              => 'IO::Socket::SSL',
                Required            => 0,
                Comment             => 'Required for SSL connections to web and mail servers.',
                VersionsRecommended => [
                    {
                        Version => '2.066',
                        Comment => 'This version fixes email sending (bug#14357).',
                    },
                ],
                InstTypes => {
                    aptget => 'libio-socket-ssl-perl',
                    emerge => 'dev-perl/IO-Socket-SSL',
                    zypper => 'perl-IO-Socket-SSL',
                    ports  => 'security/p5-IO-Socket-SSL',
                },
            },
            {
                Module    => 'Authen::SASL',
                Required  => 0,
                Comment   => 'Required for MD5 authentication mechanisms in IMAP connections.',
                Features  => ['docker'],
                InstTypes => {
                    aptget => 'libauthen-sasl-perl',
                    emerge => 'dev-perl/Authen-SASL',
                    zypper => 'perl-Authen-SASL',
                },
            },
            {
                Module    => 'Authen::NTLM',
                Required  => 0,
                Comment   => 'Required for NTLM authentication mechanism in IMAP connections.',
                InstTypes => {
                    aptget => 'libauthen-ntlm-perl',
                    emerge => 'dev-perl/Authen-NTLM',
                    zypper => 'perl-Authen-NTLM',
                },
            },
        ],
    },
    {
        Module    => 'ModPerl::Util',
        Required  => 0,
        Comment   => 'Improves Performance on Apache webservers dramatically.',
        InstTypes => {
            aptget => 'libapache2-mod-perl2',
            emerge => 'www-apache/mod_perl',
            zypper => 'apache2-mod_perl',
            ports  => 'www/mod_perl2',
        },
    },
    {
        Module    => 'Mojolicious',
        Required  => 0,
        Features   => ['mojo'],
        Comment   => 'a web framework that makes web development fun again',
        InstTypes => {
            aptget => undef,
            emerge => undef,
            zypper => undef,
            ports  => undef,
        },
    },
    {
        Module    => 'Mojolicious::Plugin::DBViewer',
        Required  => 0,
        Features   => ['mojo'],
        Comment   => 'Mojolicious plugin to display database information on browser',
        InstTypes => {
            aptget => undef,
            emerge => undef,
            zypper => undef,
            ports  => undef,
        },
    },
    {
        Module    => 'Moo',
        Required  => 0,
        Features   => ['plack'],
        Comment   => 'Required by Math::Random::Secure in Kernel/cpan-lib',
        InstTypes => {
            aptget => undef,
            emerge => undef,
            zypper => undef,
            ports  => undef,
        },
    },
    {
        Module               => 'Net::DNS',
        Required             => 1,
        VersionsNotSupported => [
            {
                Version => '0.60',
                Comment =>
                    'This version is broken and not useable! Please upgrade to a higher version.',
            },
        ],
        InstTypes => {
            aptget => 'libnet-dns-perl',
            emerge => 'dev-perl/Net-DNS',
            zypper => 'perl-Net-DNS',
            ports  => 'dns/p5-Net-DNS',
        },
    },
    {
        Module    => 'Net::LDAP',
        Required  => 0,
        Comment   => 'Required for directory authentication.',
        Features  => ['docker'],
        InstTypes => {
            aptget => 'libnet-ldap-perl',
            emerge => 'dev-perl/perl-ldap',
            zypper => 'perl-ldap',
            ports  => 'net/p5-perl-ldap',
        },
    },
    {
        Module              => 'Net::SMTP',
        Required            => 0,
        Comment             => 'Simple Mail Transfer Protocol Client.',
        VersionsRecommended => [
            {
                Version => '3.11',
                Comment => 'This version fixes email sending (bug#14357).',
            },
        ],
        InstTypes => {
            aptget => undef,
            emerge => undef,
            zypper => undef,
            ports  => undef,
        },
    },
    {
        Module    => 'Path::Class',
        Required  => 0,
        Features  => ['plack'],
        Comment   => 'Neater path manipulation and some utils',
        InstTypes => {
            aptget => undef,
            emerge => undef,
            zypper => undef,
            ports  => undef,
        },
    },
    {
        Module    => 'Plack',
        Required  => 0,
        Features   => ['plack'],
        Comment   => 'Perl Superglue for Web frameworks and Web Servers (PSGI toolkit)',
        InstTypes => {
            aptget => undef,
            emerge => undef,
            zypper => undef,
            ports  => undef,
        },
    },
    {
        Module    => 'Plack::App::File',
        Required  => 0,
        Features   => ['plack'],
        Comment   => 'Serve static files',
        InstTypes => {
            aptget => undef,
            emerge => undef,
            zypper => undef,
            ports  => undef,
        },
    },
    {
        Module    => 'Plack::Middleware::ForceEnv',
        Required  => 0,
        Features   => ['plack'],
        Comment   => 'Set environment variables',
        InstTypes => {
            aptget => undef,
            emerge => undef,
            zypper => undef,
            ports  => undef,
        },
    },
    {
        Module    => 'Plack::Middleware::Header',
        Required  => 0,
        Features   => ['plack'],
        Comment   => 'Set HTTP headers',
        InstTypes => {
            aptget => undef,
            emerge => undef,
            zypper => undef,
            ports  => undef,
        },
    },
    {
        Module    => 'Plack::Middleware::Rewrite',
        Required  => 0,
        Features   => ['plack'],
        Comment   => 'Set environment variables',
        InstTypes => {
            aptget => undef,
            emerge => undef,
            zypper => undef,
            ports  => undef,
        },
    },
    {
        Module    => 'SOAP::Transport::HTTP::Plack',
        Required  => 0,
        Features   => ['plack'],
        Comment   => 'PSGI SOAP adapter',
        InstTypes => {
            aptget => undef,
            emerge => undef,
            zypper => undef,
            ports  => undef,
        },
    },
    {
        Module    => 'Template::Toolkit',
        Required  => 1,
        Comment   => 'Template::Toolkit, the rendering engine of OTOBO.',
        InstTypes => {
            aptget => 'libtemplate-perl',
            emerge => 'dev-perl/Template-Toolkit',
            zypper => 'perl-Template-Toolkit',
            ports  => 'www/p5-Template-Toolkit',
        },
    },
    {
        Module    => 'Template::Stash::XS',
        Required  => 1,
        Comment   => 'The fast data stash for Template::Toolkit.',
        InstTypes => {
            aptget => 'libtemplate-perl',
            emerge => 'dev-perl/Template-Toolkit',
            zypper => 'perl-Template-Toolkit',
            ports  => 'www/p5-Template-Toolkit',
        },
    },
    {
        Module    => 'Text::CSV_XS',
        Required  => 0,
        Comment   => 'Recommended for faster CSV handling.',
        Features  => ['docker'],
        InstTypes => {
            aptget => 'libtext-csv-xs-perl',
            emerge => 'dev-perl/Text-CSV_XS',
            zypper => 'perl-Text-CSV_XS',
            ports  => 'textproc/p5-Text-CSV_XS',
        },
    },
    {
        Module    => 'Time::HiRes',
        Required  => 1,
        Comment   => 'Required for high resolution timestamps.',
        InstTypes => {
            aptget => 'perl',
            emerge => 'perl-core/Time-HiRes',
            zypper => 'perl-Time-HiRes',
            ports  => 'devel/p5-Time-HiRes',
        },
    },
    {
        Module    => 'XML::LibXML',
        Required  => 1,
        Comment   => 'Required for XML processing.',
        InstTypes => {
            aptget => 'libxml-libxml-perl',
            zypper => 'perl-XML-LibXML',
            ports  => 'textproc/p5-XML-LibXML',
        },
    },
    {
        Module    => 'XML::LibXSLT',
        Required  => 0,
        Comment   => 'Required for Generic Interface XSLT mapping module.',
        Features  => ['docker'],
        InstTypes => {
            aptget => 'libxml-libxslt-perl',
            zypper => 'perl-XML-LibXSLT',
            ports  => 'textproc/p5-XML-LibXSLT',
        },
    },
    {
        Module    => 'XML::Parser',
        Required  => 0,
        Comment   => 'Recommended for XML processing.',
        InstTypes => {
            aptget => 'libxml-parser-perl',
            emerge => 'dev-perl/XML-Parser',
            zypper => 'perl-XML-Parser',
            ports  => 'textproc/p5-XML-Parser',
        },
    },
    {
        Module   => 'YAML::XS',
        Required => 1,
        Comment  => 'Required for fast YAML processing.',

        # Example of how to use VersionsRecommended option.
        # VersionsRecommended => [
        #     {
        #         Version => '5.0.1',
        #         Comment => 'This version fixes a bug.',
        #     },
        #     {
        #         Version => '6.0.1',
        #         Comment => 'This version fixes a critical issue.',
        #     },
        # ],
        InstTypes => {
            aptget => 'libyaml-libyaml-perl',
            emerge => 'dev-perl/YAML-LibYAML',
            zypper => 'perl-YAML-LibYAML',
            ports  => 'textproc/p5-YAML-LibYAML',
        },
    },
    {
        Module    => 'Redis',
        Required  => 0,
        Comment   => 'For usage with Redis Cache Server.',
        InstTypes => {
            aptget => 'libredis-perl',
            emerge => 'dev-perl/Redis',
            yum    => 'perl-Redis',
            zypper => 'perl-Redis',
            ports  => 'databases/p5-Redis',
        },
    },
    {
        Module    => 'Redis::Fast',
        Required  => 0,
        Comment   => 'Recommended for usage with Redis Cache Server. (it`s compatible with `Redis`, but **~2x faster**)',
        InstTypes => {
            aptget => 'libredis-fast-perl',
            emerge => undef,
            yum    => undef,
            zypper => undef,
            ports  => undef,
        },
    },
);

if ($DoPrintCpanfile) {
    say <<'END_HEADER';
# Do not change this file manually.
# Instead adapt bin/otobo.CheckModules.pl and call
#    ./bin/otobo.CheckModules.pl --cpanfile > cpanfile
END_HEADER

    PrintCpanfile( \@NeededModules, 1, 1 );
}
elsif ($DoPrintPackageList) {
    my %PackageList = CollectPackageInfo( \@NeededModules );

    if ( IsArrayRefWithData( $PackageList{Packages} ) ) {

        my $CMD = $PackageList{CMD};

        for my $Package ( @{ $PackageList{Packages} } ) {
            if ( $PackageList{SubCMD} ) {
                $Package = sprintf $PackageList{SubCMD}, $Package;
            }
        }
        printf $CMD, join( ' ', @{ $PackageList{Packages} } );
        print "\n";
    }
}
else {
    # try to determine module version number
    my $Depends = 0;

    for my $Module (@NeededModules) {
        Check( $Module, $Depends, $NoColors );
    }

    if ($DoPrintAllModules) {
        print "\nBundled modules:\n\n";

        my %PerlInfo = Kernel::System::Environment->PerlInfoGet(
            BundledModules => 1,
        );

        for my $Module ( sort keys %{ $PerlInfo{Modules} } ) {
            Check(
                {
                    Module   => $Module,
                    Required => 1,
                },
                $Depends,
                $NoColors
            );
        }
    }
}

sub Check {
    my ( $Module, $Depends, $NoColors ) = @_;

    print "  " x ( $Depends + 1 );
    print "o $Module->{Module}";
    my $Length = 33 - ( length( $Module->{Module} ) + ( $Depends * 2 ) );
    print '.' x $Length;

    my $Version = Kernel::System::Environment->ModuleVersionGet( Module => $Module->{Module} );
    if ($Version) {

        # cleanup version number
        my $CleanedVersion = CleanVersion(
            Version => $Version,
        );

        my $ErrorMessage;

        # Test if all module dependencies are installed by requiring the module.
        #   Don't do this for Net::DNS as it seems to take very long (>20s) in a
        #   mod_perl environment sometimes.
        my %DontRequire = (
            'Net::DNS'        => 1,
            'Email::Valid'    => 1,    # uses Net::DNS internally
            'Apache2::Reload' => 1,    # is not needed / working on systems without mod_perl (like Plack etc.)
        );

        ## no critic
        if ( !$DontRequire{ $Module->{Module} } && !eval "require $Module->{Module}" ) {
            $ErrorMessage .= 'Not all prerequisites for this module correctly installed. ';
        }
        ## use critic

        if ( $Module->{VersionsNotSupported} ) {

            my $VersionsNotSupported = 0;
            ITEM:
            for my $Item ( @{ $Module->{VersionsNotSupported} } ) {

                # cleanup item version number
                my $ItemVersion = CleanVersion(
                    Version => $Item->{Version},
                );

                if ( $CleanedVersion == $ItemVersion ) {
                    $VersionsNotSupported = $Item->{Comment};
                    last ITEM;
                }
            }

            if ($VersionsNotSupported) {
                $ErrorMessage .= "Version $Version not supported! $VersionsNotSupported ";
            }
        }

        my $AdditionalText = '';

        if ( $Module->{VersionsRecommended} ) {

            my $VersionsRecommended = 0;
            ITEM:
            for my $Item ( @{ $Module->{VersionsRecommended} } ) {

                my $ItemVersion = CleanVersion(
                    Version => $Item->{Version},
                );

                if ( $CleanedVersion < $ItemVersion ) {
                    $AdditionalText
                        .= "    Please consider updating to version $Item->{Version} or higher: $Item->{Comment}\n";
                }
            }
        }

        if ( $Module->{VersionRequired} ) {

            # cleanup item version number
            my $RequiredModuleVersion = CleanVersion(
                Version => $Module->{VersionRequired},
            );

            if ( $CleanedVersion < $RequiredModuleVersion ) {
                $ErrorMessage
                    .= "Version $Version installed but $Module->{VersionRequired} or higher is required! ";
            }
        }

        if ($ErrorMessage) {
            if ($NoColors) {
                print "FAILED! $ErrorMessage\n";
            }
            else {
                print color('red') . 'FAILED!' . color('reset') . " $ErrorMessage\n";
            }
            $ExitCode = 1;    # error
        }
        else {
            my $OutputVersion = $Version;

            if ( $OutputVersion =~ m{ [0-9.] }xms ) {
                $OutputVersion = 'v' . $OutputVersion;
            }

            if ($NoColors) {
                print "ok ($OutputVersion)\n$AdditionalText";
            }
            else {
                print color('green') . 'ok'
                    . color('reset')
                    . " ($OutputVersion)\n"
                    . color('yellow')
                    . "$AdditionalText"
                    . color('reset');
            }
        }
    }
    else {
        my $Comment  = $Module->{Comment} ? ' - ' . $Module->{Comment} : '';
        my $Required = $Module->{Required};
        my $Color    = 'yellow';

        # OS Install Command
        my %InstallCommand = GetInstallCommand($Module);

        # create example installation string for module
        my $InstallText = '';
        if ( IsHashRefWithData( \%InstallCommand ) ) {
            my $CMD = $InstallCommand{CMD};
            if ( $InstallCommand{SubCMD} ) {
                $CMD = sprintf $InstallCommand{CMD}, $InstallCommand{SubCMD};
            }

            $InstallText = " To install, you can use: '" . sprintf( $CMD, $InstallCommand{Package} ) . "'.";
        }

        if ($Required) {
            $Required = 'required';
            $Color    = 'red';
            $ExitCode = 1;            # error
        }
        else {
            $Required = 'optional';
        }
        if ($NoColors) {
            print "Not installed! ($Required $Comment)\n";
        }
        else {
            print color($Color)
                . 'Not installed!'
                . color('reset')
                . "$InstallText ($Required$Comment)\n";
        }
    }

    if ( $Module->{Depends} ) {
        for my $ModuleSub ( @{ $Module->{Depends} } ) {
            Check( $ModuleSub, $Depends + 1, $NoColors );
        }
    }

    return 1;
}

sub CollectPackageInfo {
    my ($PackageList) = @_;

    my $CMD;
    my $SubCMD;
    my @Packages;
    my @MissingModules;

    # if we're on Windows we don't need to see Apache + mod_perl modules
    MODULE:
    for my $Module ( @{$PackageList} ) {

        my $Required = $Module->{Required};
        my $Version  = Kernel::System::Environment->ModuleVersionGet( Module => $Module->{Module} );
        if ( !$Version ) {
            my %InstallCommand = GetInstallCommand($Module);

            if ( $Module->{Depends} ) {

                MODULESUB:
                for my $ModuleSub ( @{ $Module->{Depends} } ) {
                    my $Required          = $Module->{Required};
                    my %InstallCommandSub = GetInstallCommand($ModuleSub);

                    next MODULESUB if !IsHashRefWithData( \%InstallCommandSub );
                    next MODULESUB if !$Required;

                    push @Packages, $InstallCommandSub{Package};
                }
            }

            next MODULE if !IsHashRefWithData( \%InstallCommand );
            next MODULE if !$Required;

            $CMD    = $InstallCommand{CMD};
            $SubCMD = $InstallCommand{SubCMD};
            push @Packages, $InstallCommand{Package};
            push @MissingModules, $Module;
        }
    }

    return (
        CMD            => $CMD,
        SubCMD         => $SubCMD,
        Packages       => \@Packages,
        MissingModules => \@MissingModules,
    );
}

sub CleanVersion {
    my (%Param) = @_;

    return 0 if !$Param{Version};
    return 0 if $Param{Version} eq 'undef';

    # replace all special characters with an dot
    $Param{Version} =~ s{ [_-] }{.}xmsg;

    my @VersionParts = split q{\.}, $Param{Version};

    my $CleanedVersion = '';
    for my $Count ( 0 .. 4 ) {
        $VersionParts[$Count] ||= 0;
        $CleanedVersion .= sprintf "%04d", $VersionParts[$Count];
    }

    return int $CleanedVersion;
}

sub GetInstallCommand {
    my ($Module) = @_;
    my $CMD;
    my $SubCMD;
    my $Package;

    # returns the installation type e.g. ppm
    my $InstType     = $DistToInstType{$OSDist};
    my $OuputInstall = 1;

    if ($InstType) {

        # gets the install command for installation type
        # e.g. ppm install %s
        # default is the cpan install command
        # e.g. cpan %s
        $CMD    = $InstTypeToCMD{$InstType}->{CMD};
        $SubCMD = $InstTypeToCMD{$InstType}->{SubCMD};

        # gets the target package
        if (
            exists $Module->{InstTypes}->{$InstType}
            && !defined $Module->{InstTypes}->{$InstType}
            )
        {
            # if we a hash key for the installation type but a undefined value
            # then we prevent the output for the installation command
            $OuputInstall = 0;
        }
        elsif ( $InstTypeToCMD{$InstType}->{UseModule} ) {

            # default is the cpan module name
            $Package = $Module->{Module};
        }
        else {
            # if the package name is defined for the installation type
            # e.g. ppm then we use this as package name
            $Package = $Module->{InstTypes}->{$InstType};
        }
    }

    return if !$OuputInstall;

    if ( !$CMD || !$Package ) {
        $CMD     = $InstTypeToCMD{default}->{CMD};
        $SubCMD  = $InstTypeToCMD{default}->{SubCMD};
        $Package = $Module->{Module};
    }

    return (
        CMD     => $CMD,
        SubCMD  => $SubCMD,
        Package => $Package,
    );
}

sub PrintCpanfile {
    my ($NeededModules, $FilterRequired, $HandleFeatures) = @_;

    # Indent the statements in the feature sections
    my $Indent = $FilterRequired ? '' : '    ';

    # print the required modules
    # collect the modules per feature
    my %ModulesForFeature;
    MODULE:
    for my $Module ( $NeededModules->@* ) {

        # put all not required modules into 'optional'
        if ( $FilterRequired && ! $Module->{Required} ) {
            my $Feature = 'optional';
            $ModulesForFeature{$Feature} //= [];
            push $ModulesForFeature{$Feature}->@*, $Module;
        }

        # print out the requirements, either because it is required, or because it is a feature
        if ( ! $FilterRequired || $Module->{Required} ) {
            my $Comment = $Module->{Comment};
            if ( $Comment ) {
                $Comment =~ s/\n/\n$Indent\#/g;
                say $Indent, "# $Comment";
            }
            say $Indent, "requires '$Module->{Module}';";

            next MODULE;
        }

        next MODULE unless $HandleFeatures;
        next MODULE unless $Module->{Features};
        next MODULE unless $Module->{Features};
        next MODULE unless ref $Module->{Features} eq 'ARRAY';

        for my $Feature ( $Module->{Features}->@* ) {
            $ModulesForFeature{$Feature} //= [];
            push $ModulesForFeature{$Feature}->@*, $Module;
        }
    }

    # now print out the features
    for my $Feature ( sort keys %ModulesForFeature ) {
        my $Desc = $FeatureDescription{$Feature} // "Suppport for $Feature";
        say '';
        say "feature '$Feature', '$Desc' => sub {";
        PrintCpanfile( $ModulesForFeature{$Feature}, 0, 0 );
        say '};';
    }

    return;
}

exit $ExitCode;

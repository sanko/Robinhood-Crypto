requires perl => v5.38.0;
requires 'MIME::Base64';
requires 'HTTP::Tiny';
requires 'JSON::Tiny';
requires 'UUID::Tiny';
requires 'Try::Tiny';
recommends 'Math::BigInt::GMP';    # https://github.com/FGasper/p5-Crypt-Perl/issues/12
requires 'Crypt::Perl::Ed25519::PrivateKey';
requires 'MIME::Base64';
requires 'URI';
requires 'Data::Dump';
requires 'Time::Moment';

on configure => sub {
    requires 'Archive::Tar';
    requires 'CPAN::Meta';
    requires 'Devel::CheckBin';
    requires 'ExtUtils::Config'  => 0.003;
    requires 'ExtUtils::Helpers' => 0.020;
    requires 'ExtUtils::Install';
    requires 'ExtUtils::InstallPaths' => 0.002;
    requires 'File::Basename';
    requires 'File::Find';
    requires 'File::Path';
    requires 'File::Spec::Functions';
    requires 'Getopt::Long' => 2.36;

    #requires 'HTTP::Tiny';
    #requires 'IO::Socket::SSL' => 1.42;
    requires 'IO::Uncompress::Unzip';
    requires 'JSON::PP' => 2;
    requires 'Module::Build::Tiny';

    #requires 'Net::SSLeay' => 1.49;
    requires 'Path::Tiny' => 0.144;
};

on build=>sub{};
on test => sub {
    requires 'Test2::V0';
};
on runtime=>sub{};

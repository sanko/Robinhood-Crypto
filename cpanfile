requires perl => v5.38.0;
requires 'MIME::Base64';
requires 'HTTP::Tiny';
requires 'JSON::Tiny';
requires 'UUID::Tiny';
requires 'Math::BigInt::GMP';    # https://github.com/FGasper/p5-Crypt-Perl/issues/12
requires 'Crypt::Perl::Ed25519::PrivateKey';
requires 'MIME::Base64';
requires 'URI';
requires 'Data::Dump';

on configure =>sub{};
on build=>sub{};
on test => sub {
    requires 'Test2::V0';
};
on configure=>sub{};
on runtime=>sub{};

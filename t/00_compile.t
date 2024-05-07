use Test2::V0;
use lib './lib', '../lib';
use Robinhood::Crypto;
#
diag $Robinhood::Crypto::VERSION;
#
subtest classes => sub {
    subtest 'Robinhood::Crypto::Account' => sub {
        isa_ok my $account = Robinhood::Crypto::Account->new(
            account_number        => 'totally fake',
            status                => 'active',
            buying_power          => 0,
            buying_power_currency => 'USD'
            ),
            ['Robinhood::Crypto::Account'];
        like(
            warning {
                Robinhood::Crypto::Account->new(
                    account_number        => 'totally fake',
                    status                => 'wrong',
                    buying_power          => 0,
                    buying_power_currency => 'USD'
                )
            },
            qr[Unknown account status: wrong],
            'unknown account status: wrong'
        );
    };
};

# From Robinhood's documentation
my $rh = Robinhood::Crypto->new(
    api_key     => 'e3bb245e-a45c-4729-8a9b-10201756f8cc',
    private_key => 'aVhXn8ghC9YqSz5RyFuKc6SsDC6SuPIqSW3IXH76ZlMCjOxkazBQjQFucJLk3uNorpBt6TbYpo/D1lHA7s4+hQ=='
);
is $rh->sign(
    'POST',
    '/api/v1/crypto/trading/orders/',
    q[{'client_order_id': '131de903-5a9c-4260-abc1-28d562a5dcf0', 'side': 'buy', 'symbol': 'BTC-USD', 'type': 'market', 'market_order_config': {'asset_quantity': '0.1'}}],
    '1698708981'
    ),
    'BhLJyRXPE0T1KA29wopPuTIe+gl1DUc7lGVC9vz4BfohPCLN7UgCcloBPGt+/65xlWngDinGqjZeEqIAaIgOAQ==', 'signature';
#
done_testing;

package Robinhood::Crypto v1.0.0 {
    use v5.38;
    use feature 'class';
    no warnings 'experimental::class', 'experimental::builtin', 'experimental::for_list';    # Be quiet.

    class Robinhood::Crypto {
        $Carp::Internal{ (__PACKAGE__) }++;
        use MIME::Base64 qw[decode_base64 encode_base64];
        use HTTP::Tiny;
        use JSON::Tiny qw[encode_json decode_json];
        use UUID::Tiny ':std';
        use Try::Tiny;

        #~ use Math::BigInt::GMP;    # https://github.com/FGasper/p5-Crypt-Perl/issues/12
        use Crypt::Perl::Ed25519::PrivateKey;
        use MIME::Base64 qw[decode_base64 encode_base64];
        use URI;
        use Data::Dump;
        #
        field $api_key : param;
        field $private_key : param;
        field $http : param //= HTTP::Tiny->new(
            agent           => sprintf( 'Robinhood::Crypto/%s;Perl/%s; ', $Robinhood::Crypto::VERSION, $^V ),
            default_headers => { 'Content-Type' => 'application/json; charset=utf-8' }
        );
        field $base = 'https://trading.robinhood.com';
        #
        ADJUST {
            $private_key = Crypt::Perl::Ed25519::PrivateKey->new( MIME::Base64::decode( substr $private_key, 0, 43 ) )
                unless builtin::blessed $private_key;
        }
        #
        method account() {
            my $res = $self->get('/api/v1/crypto/trading/accounts/');
            $res ? Robinhood::Crypto::Account->new(%$res) : $res;
        }

        method quote(@symbols) {
            my $uri = URI->new('/api/v1/crypto/marketdata/best_bid_ask/');
            $uri->query_form_hash( symbol => \@symbols );
            my $res = $self->get( $uri->as_string );
            $res ? map { Robinhood::Crypto::Quote->new(%$_) } @{ $res->{results} } : $res;
        }

        method price( $symbol, $side, $quantity ) {
            my $uri = URI->new('/api/v1/crypto/marketdata/estimated_price/');
            $uri->query_form_hash( symbol => $symbol, side => $side, quantity => $quantity );
            my $res = $self->get( $uri->as_string );
            return $res unless $res;
            my $return;
            $return->{ $_->{symbol} }{ $_->{side} }{ $_->{quantity} } = Robinhood::Crypto::Price->new(%$_) for ( @{ $res->{results} } );
            $return;
        }

        method pairs(%args) {
            my $uri = URI->new('/api/v1/crypto/trading/trading_pairs/');
            $uri->query_form_hash(%args);
            my $res = $self->get( $uri->as_string );
            return $res unless $res;
            $res->{results} = [ map { Robinhood::Crypto::Pair->new(%$_) } @{ $res->{results} } ];
            $res->{$_} = URI->new( $res->{$_} )->query_form_hash for qw[next previous];
            $res;
        }

        method holdings(%args) {
            my $uri = URI->new('/api/v1/crypto/trading/holdings/');
            $uri->query_form_hash(%args);
            my $res = $self->get( $uri->as_string );
            return $res unless $res;
            $res->{results} = [ map { Robinhood::Crypto::Holdings->new(%$_) } @{ $res->{results} } ];
            $res->{$_} = URI->new( $res->{$_} )->query_form_hash for qw[next previous];
            $res;
        }

        method orders(%args) {
            my $uri = URI->new('/api/v1/crypto/trading/orders/');
            $uri->query_form_hash(%args);
            ddx \%args;
            my $res = $self->get( $uri->as_string );
            return $res unless $res;

            # Robinhood keeps changing what data is part of an order
            $res->{results} = [
                map {
                    my $whoa = $_;
                    try {
                        Robinhood::Crypto::Order->new(%$_)
                    }
                    catch {
                        Carp::cluck "caught error: $_";
                        $whoa
                    };
                } @{ $res->{results} }
            ];
            $res->{$_} = URI->new( $res->{$_} )->query_form_hash for qw[next previous];
            $res;
        }

        # TODO: Buy with a dollar amount
        method market_order( $side, $symbol, $quantity, $uuid //= () ) {
            Carp::croak 'Order side must be "buy" or "sell"' unless $side =~ m[^buy|sell$];
            my $uri  = URI->new('/api/v1/crypto/trading/orders/');
            my %args = ( symbol => $symbol, side => $side, type => 'market', market_order_config => { asset_quantity => $quantity } );

            # I can fill in this blank.
            $args{client_order_id} = $uuid // uuid_to_string( create_uuid( UUID_MD5, rand(time) . encode_json \%args ) );

            #~ $uri->query_form_hash(%args);
            ddx \%args;
            my $res = $self->post( $uri->as_string, \%args );
            return $res unless $res;
            Robinhood::Crypto::Order->new(%$res);
        }

        method limit_order( $side, $symbol, $quantity, $limit_price, $time_in_force //= 'gtc', $uuid //= () ) {
            Carp::croak 'Order side must be "buy" or "sell"'                  unless $side          =~ m[^buy|sell$];
            Carp::croak 'Time-in-force must be "gtc", "gfd", "gfw", or "gfm"' unless $time_in_force =~ m[^gtc|gfd|gfw|gfm];
            my $uri  = URI->new('/api/v1/crypto/trading/orders/');
            my %args = (
                symbol             => $symbol,
                side               => $side,
                type               => 'limit',
                limit_order_config => {
                    asset_quantity => $quantity,

                    #~ quote_amount => $quote_amount,
                    limit_price   => $limit_price,
                    time_in_force => $time_in_force
                }
            );

            # I can fill in this blank.
            $args{client_order_id} = $uuid // uuid_to_string( create_uuid( UUID_MD5, rand(time) . encode_json \%args ) );

            #~ $uri->query_form_hash(%args);
            #~ ddx \%args;
            my $res = $self->post( $uri->as_string, \%args );
            return $res unless $res;
            Robinhood::Crypto::Order->new(%$res);
        }

        method stop_loss_order( $side, $symbol, $quantity, $stop_price, $time_in_force, $uuid //= () ) {
            Carp::croak 'Order side must be "buy" or "sell"'                  unless $side          =~ m[^buy|sell$];
            Carp::croak 'Time-in-force must be "gtc", "gfd", "gfw", or "gfm"' unless $time_in_force =~ m[^gtc|gfd|gfw|gfm];
            my $uri  = URI->new('/api/v1/crypto/trading/orders/');
            my %args = (
                symbol                 => $symbol,
                side                   => $side,
                type                   => 'stop_loss',
                stop_loss_order_config => {
                    asset_quantity => $quantity,

                    #quote_amount => $quote_amount,
                    stop_price    => $stop_price,
                    time_in_force => $time_in_force
                }
            );

            # I can fill in this blank.
            $args{client_order_id} = $uuid // uuid_to_string( create_uuid( UUID_MD5, rand(time) . encode_json \%args ) );

            #~ $uri->query_form_hash(%args);
            ddx \%args;
            my $res = $self->post( $uri->as_string, \%args );
            return $res unless $res;
            Robinhood::Crypto::Order->new(%$res);
        }

        method stop_limit_order( $side, $symbol, $quantity, $stop_price, $limit_price, $time_in_force, $uuid //= () ) {
            Carp::croak 'Order side must be "buy" or "sell"'                  unless $side          =~ m[^buy|sell$];
            Carp::croak 'Time-in-force must be "gtc", "gfd", "gfw", or "gfm"' unless $time_in_force =~ m[^gtc|gfd|gfw|gfm];
            my $uri  = URI->new('/api/v1/crypto/trading/orders/');
            my %args = (
                symbol                  => $symbol,
                side                    => $side,
                type                    => 'stop_limit',
                stop_limit_order_config => {
                    asset_quantity => $quantity,

                    #~ quote_amount   => $quote_amount,
                    stop_price    => $stop_price,
                    limit_price   => $limit_price,
                    time_in_force => $time_in_force
                }
            );

            # I can fill in this blank.
            $args{client_order_id} = $uuid // uuid_to_string( create_uuid( UUID_MD5, rand(time) . encode_json \%args ) );

            #~ $uri->query_form_hash(%args);
            #~ ddx \%args;
            my $res = $self->post( $uri->as_string, \%args );
            return $res unless $res;
            Robinhood::Crypto::Order->new(%$res);
        }

        method cancel_order($id) {
            my $uri = URI->new( sprintf '/api/v1/crypto/trading/orders/%s/cancel/', $id );
            my $res = $self->post( $uri->as_string );
            $res;    # returns plain text on succes according to docs
        }

        # Utils
        method get( $path, $timestamp //= time ) {
            my $res = $http->get(
                $base . $path,
                { headers => { 'x-api-key' => $api_key, 'x-timestamp' => $timestamp, 'x-signature' => $self->sign( 'GET', $path, '', $timestamp ) } }
            );
            $res->{content} = decode_json $res->{content} if defined $res->{content} && $res->{headers}{'content-type'} =~ m[application/json];
            return $res->{content} if $res->{success};
            return Robinhood::Crypto::Error->new(
                status => $res->{status},
                ref $res->{content} eq 'HASH' ? %{ $res->{content} } : ( type => 'unknown', errors => [] )
            );
        }

        method post( $path, $args, $timestamp //= time ) {
            my $body = encode_json $args;
            my $res = $http->post(
                $base . $path,
                {   content => $body,
                    headers =>
                        { 'x-api-key' => $api_key, 'x-timestamp' => $timestamp, 'x-signature' => $self->sign( 'POST', $path, $body, $timestamp ) }
                }
            );
            $res->{content} = decode_json $res->{content} if defined $res->{content} && $res->{headers}{'content-type'} =~ m[application/json];
            return $res->{content}                        if $res->{success};
            #~ ddx $res;
            return Robinhood::Crypto::Error->new(
                status => $res->{status},
                ref $res->{content} eq 'HASH' ? %{ $res->{content} } : ( type => 'unknown', errors => [] )
            );
        }

        method sign( $method, $path, $body, $timestamp ) {
            encode_base64( $private_key->sign( $api_key . $timestamp . $path . $method . ( ref $body ? encode_json($body) : $body ) ), '' );
        }
    };

    class Robinhood::Crypto::Account {
        $Carp::Internal{ (__PACKAGE__) }++;
        field $account_number : param;
        field $status : param;
        field $buying_power : param;
        field $buying_power_currency : param;
        #
        ADJUST {
            require Carp && Carp::carp 'Unknown account status: ' . $status unless $status =~ m[^active|deactivated|sell_only$];
        }

        # Waiting for perl 5.40...
        method account_number()        {$account_number}
        method status ()               {$status}
        method buying_power()          {$buying_power}
        method buying_power_currency() {$buying_power_currency}
    }

    class Robinhood::Crypto::Quote {
        $Carp::Internal{ (__PACKAGE__) }++;
        use Time::Moment;
        #
        field $ask_price : param;
        field $bid_price : param;
        field $symbol : param;
        field $timestamp : param;
        #
        ADJUST {
            return if builtin::blessed $timestamp;
            $timestamp = $timestamp =~ /T/ ? Time::Moment->from_string($timestamp) : Time::Moment->from_epoch($timestamp);
        }

        # Waiting for perl 5.40...
        method ask_price() {$ask_price}
        method bid_price() {$bid_price}
        method symbol()    {$symbol}
        method timestamp() {$timestamp}
    };

    class Robinhood::Crypto::Price {
        $Carp::Internal{ (__PACKAGE__) }++;
        use Time::Moment;
        #
        field $price : param;
        field $quantity : param;
        field $side : param;
        field $symbol : param;
        field $updated_at : param;
        #
        ADJUST {
            return if builtin::blessed $updated_at;
            $updated_at = $updated_at =~ /T/ ? Time::Moment->from_string($updated_at) : Time::Moment->from_epoch($updated_at);
        }

        # Waiting for perl 5.40...
        method price()      {$price}
        method quantity()   {$quantity}
        method side()       {$side}
        method symbol()     {$symbol}
        method updated_at() {$updated_at}
    };

    class Robinhood::Crypto::Pair {
        $Carp::Internal{ (__PACKAGE__) }++;
        field $asset_code : param;
        field $quote_code : param;
        field $quote_increment : param;
        field $asset_increment : param;
        field $max_order_size : param;
        field $min_order_size : param;
        field $status : param;
        field $symbol : param;

        # Waiting for perl 5.40...
        method asset_code()      {$asset_code}
        method quote_code()      {$quote_code}
        method quote_increment() {$quote_increment}
        method asset_increment() {$asset_increment}
        method max_order_size()  {$max_order_size}
        method min_order_size()  {$min_order_size}
        method status()          {$status}
        method symbol()          {$symbol}
    };

    class Robinhood::Crypto::Holdings {
        $Carp::Internal{ (__PACKAGE__) }++;
        field $account_number : param;
        field $asset_code : param;
        field $total_quantity : param;
        field $quantity_available_for_trading : param;

        # Waiting for perl 5.40...
        method account_number()                 {$account_number}
        method asset_code()                     {$asset_code}
        method total_quantity()                 {$total_quantity}
        method quantity_available_for_trading() {$quantity_available_for_trading}
    };

    class Robinhood::Crypto::Order {
        $Carp::Internal{ (__PACKAGE__) }++;
        use overload '""' => sub { shift->id };
        #
        field $account_number : param;
        field $average_price : param;
        field $client_order_id : param;
        field $created_at : param;
        field $executions : param;
        field $filled_asset_quantity : param;
        field $id : param;
        field $market_order_config : param     //= ();
        field $limit_order_config : param      //= ();
        field $stop_loss_order_config : param  //= ();
        field $stop_limit_order_config : param //= ();
        field $side : param;
        field $state : param;
        field $symbol : param;
        field $type : param;
        field $updated_at : param;
        #
        ADJUST {
            $created_at = $created_at =~ /T/ ? Time::Moment->from_string($created_at) : Time::Moment->from_epoch($created_at)
                unless builtin::blessed $created_at;
            $executions = [ map { builtin::blessed $_ ? $_ : Robinhood::Crypto::Order::Execution->new(%$_) } @$executions ];
            if ( $type eq 'limit' ) {
                $limit_order_config = Robinhood::Crypto::Order::LimitConfig->new(%$limit_order_config) unless builtin::blessed $limit_order_config;
            }
            elsif ( $type eq 'market' ) {
                $market_order_config = Robinhood::Crypto::Order::MarketConfig->new(%$market_order_config)
                    unless builtin::blessed $market_order_config;
            }
            elsif ( $type eq 'stop_limit' ) {
                $stop_limit_order_config = Robinhood::Crypto::Order::StopLimitConfig->new(%$stop_limit_order_config)
                    unless builtin::blessed $stop_limit_order_config;
            }
            elsif ( $type eq 'stop_loss' ) {
                $stop_loss_order_config = Robinhood::Crypto::Order::StopLossConfig->new(%$stop_loss_order_config)
                    unless builtin::blessed $stop_loss_order_config;
            }
            else { Carp::confess 'Unknown order type: ' . $type }
            $updated_at = $updated_at =~ /T/ ? Time::Moment->from_string($updated_at) : Time::Moment->from_epoch($updated_at)
                unless builtin::blessed $updated_at;
        }

        # Waiting for perl 5.40...
        method id() {$id}
    };

    class Robinhood::Crypto::Order::Execution {
        $Carp::Internal{ (__PACKAGE__) }++;
        field $effective_price : param;
        field $quantity : param;
        field $timestamp : param;
        ADJUST {
            $timestamp = $timestamp =~ /T/ ? Time::Moment->from_string($timestamp) : Time::Moment->from_epoch($timestamp)
                unless builtin::blessed $timestamp;
        }
    };

    class Robinhood::Crypto::Order::MarketConfig {
        $Carp::Internal{ (__PACKAGE__) }++;
        field $asset_quantity : param //= ();
        field $quote_amount : param   //= ();    # Not in docs but found in my history
    };

    class Robinhood::Crypto::Order::LimitConfig {
        $Carp::Internal{ (__PACKAGE__) }++;
        field $quote_amount : param //= ();
        field $asset_quantity : param;
        field $limit_price : param;
        field $time_in_force : param //= ();
    };

    class Robinhood::Crypto::Order::StopLossConfig {
        $Carp::Internal{ (__PACKAGE__) }++;
        field $quote_amount : param //= ();
        field $asset_quantity : param;
        field $stop_price : param;
        field $time_in_force : param //= ();
    };

    class Robinhood::Crypto::Order::StopLimitConfig {
        $Carp::Internal{ (__PACKAGE__) }++;
        field $quote_amount : param //= ();
        field $asset_quantity : param;
        field $limit_price : param;
        field $stop_price : param;
        field $time_in_force : param //= ();
    };

    class Robinhood::Crypto::Error {
        $Carp::Internal{ (__PACKAGE__) }++;
        use overload
            bool => sub { !1 },
            '""' => sub {
            join ', ', map { $_->{detail} } @{ shift->errors };
            };
        #
        field $status : param;
        field $type : param;
        field $errors : param;

        # Waiting for perl 5.40
        method status() {$status}
        method type()   {$type}
        method errors() {$errors}
    }
};
1;

=encoding utf-8

=head1 NAME

Robinhood::Crypto - Wrapper for Robinhood's new Public Crypto API

=head1 SYNOPSIS

    use Robinhood::Crypto;
    my $rh = Robinhood::Crypto->new(
        api_key     => 'abcdef12-3333-cccc-aaaa-000000000000',
        private_key => 'jfkJKLfjsdi9oKofsdaj8fi9sdamifkooa00weafmioko0pIJkjJ890RH&98fJIOKMASDDFHAKDFhksljfppah=='
    );
    $rh->market_order( 'buy', 'ETH-USD', 0.1 );

=head1 DESCRIPTION

Robinhood::Crypto is brand new, baby!

=head1 Methods

Robinhood::Crypto makes use of perl's new class syntax.

=head2 C<new( ... )>

    my $rh = Robinhood::Crypto->new(
        api_key     => 'abcdef12-3333-cccc-aaaa-000000000000',
        private_key => 'jfkJKLfjsdi9oKofsdaj8fi9sdamifkooa00weafmioko0pIJkjJ890RH&98fJIOKMASDDFHAKDFhksljfppah=='
    );

This constructor expects the following arguments:

=over

=item C<api_key>

To use the Crypto Trading API, you must visit the
L<Robinhood API Credentials Portal|https://robinhood.com/account/crypto> to
create credentials. After creating credentials, you will receive the API key
associated with the credential. You can modify, disable, and delete credentials
you created at any time.

=item C<private_key>

Private key paired with the public key submitted to Robinhood in the API key
generation process.

=back

=for docs https://docs.robinhood.com/crypto/trading/#tag/Account/operation/api_v1_crypto_trading_account_Details

=head1 Rate Limits

With their new API, Robinhood is allowing many more requests from clients. For
now, managing rate limits is left up to you, but this may change as
Robinhood::Crypto matures.

See L<https://docs.robinhood.com/crypto/trading/#section/Rate-Limiting>.

=head1 Error Responses

On success, most Robinhood::Crypto methods return objects wrapping the data.
When requests fail, a Robinhood::Crypto::Error object is generated and returned;
these error objects have a false boolean value and stringifies for display so
code such as:

    my $order = $rh->limit_order('buy', 'BTC-USD', 1);
    warn $order unless $order;

...would print out the error (not enough cash, etc.).

=head1 LICENSE

This software is Copyright (c) 2024 by Sanko Robinson <sanko@cpan.org>.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

See L<http://www.perlfoundation.org/artistic_license_2_0>.

=head1 AUTHOR

Sanko Robinson <sanko@cpan.org>

=begin stopwords


=end stopwords

=cut


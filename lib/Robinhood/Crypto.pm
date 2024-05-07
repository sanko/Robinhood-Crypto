package Robinhood::Crypto v1.0.0 {
    use v5.38;
    use feature 'class';
    no warnings 'experimental::class', 'experimental::builtin', 'experimental::for_list';    # Be quiet.

    class Robinhood::Crypto {
        our @CARP_NOT;
        use MIME::Base64 qw[decode_base64 encode_base64];
        use HTTP::Tiny;
        use JSON::Tiny qw[encode_json decode_json];
        use UUID::Tiny ':std';
        use Math::BigInt::GMP;    # https://github.com/FGasper/p5-Crypt-Perl/issues/12
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
            ddx $res;
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
            $res->{results} = [ map { Robinhood::Crypto::Order->new(%$_) } @{ $res->{results} } ];
            $res->{$_} = URI->new( $res->{$_} )->query_form_hash for qw[next previous];
            $res;
        }

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

        # Utils
        method get( $path, $timestamp //= time ) {
            my $res = $http->get(
                $base . $path,
                { headers => { 'x-api-key' => $api_key, 'x-timestamp' => $timestamp, 'x-signature' => $self->sign( 'GET', $path, '', $timestamp ) } }
            );
            return decode_json $res->{content} if $res->{success};
            ddx decode_json $res->{content};
            return Robinhood::Crypto::Error->new(
                status => $res->{status},
                defined $res->{content} &&
                    $res->{headers}{'content-type'} =~ m[application/json] ? %{ decode_json $res->{content} } : ( type => 'unknown', errors => [] )
            );
        }

        method post( $path, $args, $timestamp //= time ) {
            my $body = encode_json $args;
            my $res  = $http->post(
                $base . $path,
                {   content => $body,
                    headers =>
                        { 'x-api-key' => $api_key, 'x-timestamp' => $timestamp, 'x-signature' => $self->sign( 'POST', $path, $body, $timestamp ) }
                }
            );
            return decode_json $res->{content} if $res->{success};
            ddx decode_json $res->{content};
            return Robinhood::Crypto::Error->new(
                status => $res->{status},
                defined $res->{content} &&
                    $res->{headers}{'content-type'} =~ m[application/json] ? %{ decode_json $res->{content} } : ( type => 'unknown', errors => [] )
            );
        }

        method sign( $method, $path, $body //= '', $timestamp //= time ) {
            encode_base64( $private_key->sign( $api_key . $timestamp . $path . $method . ( ref $body ? encode_json($body) : $body ) ), '' );
        }
    };

    class Robinhood::Crypto::Account {
        our @CARP_NOT;
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

            # TODO: coerce executions
            # TODO: make sure xxx_order_config matches order $type
            $updated_at = $updated_at =~ /T/ ? Time::Moment->from_string($updated_at) : Time::Moment->from_epoch($updated_at)
                unless builtin::blessed $updated_at;
        }

        # Waiting for perl 5.40...
    };

    class Robinhood::Crypto::Order::Execution {
        field $effective_price : param;
        field $quantity : param;
        field $timestamp : param;
        ADJUST {
            $timestamp = $timestamp =~ /T/ ? Time::Moment->from_string($timestamp) : Time::Moment->from_epoch($timestamp)
                unless builtin::blessed $timestamp;
        }
    };

    class Robinhood::Crypto::Error {
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

Robinhood::Crypto - Spankin' New Code

=head1 SYNOPSIS

    use Robinhood::Crypto;

=head1 DESCRIPTION

Robinhood::Crypto is brand new, baby!

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


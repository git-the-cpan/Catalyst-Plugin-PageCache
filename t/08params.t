#!perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use Test::More;
use File::Path;

BEGIN {
    eval "use Catalyst::Plugin::Cache::FileCache";
    plan $@
        ? ( skip_all => 'needs Catalyst::Plugin::Cache::FileCache for testing' )
        : ( tests => 8 );
}

# remove previous cache
rmtree 't/var' if -d 't/var';

use Catalyst::Test 'TestApp';

# This test file tests that the cache handles URI parameters properly

# cache a page using normal params
ok( my $res = request('http://localhost/cache/count?a=1&b=2&c=3'), 'request ok' );
is( $res->content, 1, 'count is 1' );

# page will be served from cache even though params are different order
ok( $res = request('http://localhost/cache/count?c=3&b=2&a=1'), 'request ok' );
is( $res->content, 1, 'count is still 1 from cache' );

# test duplicate params
ok( $res = request('http://localhost/cache/count?a=1&a=2&a=3&b=4&c=5'), 'request ok' );
is( $res->content, 2, 'count is 2' );

# page will be served from cache even though params are different order
ok( $res = request('http://localhost/cache/count?b=4&c=5&a=2&a=3&a=1'), 'request ok' );
is( $res->content, 2, 'count is still 2 from cache' );



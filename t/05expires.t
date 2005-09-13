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
        : ( tests => 6 );
}

# remove previous cache
rmtree 't/var' if -d 't/var';

use Catalyst::Test 'TestApp';

# add config option
TestApp->config->{page_cache}->{expires} = 2;

# cache a page
ok( my $res = request('http://localhost/cache/count'), 'request ok' );
is( $res->content, 1, 'count is 1' );

# page will be served from cache
ok( $res = request('http://localhost/cache/count'), 'request ok' );
is( $res->content, 1, 'count is still 1 from cache' );

# wait...
sleep 3;

# cache should have expired
ok( $res = request('http://localhost/cache/count'), 'request ok' );
is( $res->content, 2, 'count after cache expired is 2' );

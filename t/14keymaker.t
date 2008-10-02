#!perl

use strict;
use warnings;
no warnings 'redefine';

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

# This test that options can be passed to cache.

# remove previous cache
rmtree 't/var' if -d 't/var';

use Catalyst::Test 'TestApp';

# add config option
# cannot call TestApp->config() because TestApp has already called setup
TestApp->config->{'Plugin::PageCache'}->{key_maker} = sub {
    my ($c) = @_;
    return $c->req->base . q{/} . $c->req->path;
};

# cache a page
ok( my $res = request('http://host1/cache/count'), 'request ok' );
is( $res->content, 1, 'count is 1' );

# page will be served from cache
ok( $res = request('http://host1/cache/count'), 'request ok' );
is( $res->content, 1, 'count is still 1 from cache' );

# page will not be served from cache
ok( $res = request('http://host2/cache/count'), 'request ok' );
is( $res->content, 2, 'count is 2 from cache' );

# page will be served from cache
ok( $res = request('http://host2/cache/count'), 'request ok' );
is( $res->content, 2, 'count is still 2 from cache' );

#!perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use Test::More;
use File::Path;
use Time::HiRes qw(time sleep);

BEGIN {
    eval "use Catalyst::Plugin::Cache";
    if ( $@ ) {
        plan skip_all => 'needs Catalyst::Plugin::Cache for testing';
    }
}

plan $^O =~ /Win32/
    ? ( skip_all => 'Cannot run this test on Windows' )
    : ( tests => 4 );

use Catalyst::Test 'TestApp';

TestApp->config->{'Plugin::PageCache'}->{busy_lock} = 5;

# Request a slow page once, to cache it
ok( my $res = request('http://localhost/cache/busy'), 'request ok' );

# Wait for it to expire
sleep 1;

# Fork, parent requests slow page.  After parent requests, child
# requests, and gets cached page while parent is rebuilding cache
if ( my $pid = fork ) {
    # parent
    my $start = time();
    ok( $res = request('http://localhost/cache/busy'), 'parent request ok' );
    cmp_ok( time() - $start, '>=', 1, 'slow parent response ok' );
    
    # Get status from child, since it can't print 'ok' messages without
    # confusing Test::More
    wait;
    is( $? >> 8, 0, 'fast child response ok' );
}
else {
    # child
    sleep 0.1;
    my $start = time();
    request('http://localhost/cache/busy');
    if ( time() - $start < 1 ) {
        exit 0;
    }
    else {
        exit 1;
    }
}

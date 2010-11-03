package TestApp;

use strict;
use Catalyst;
use File::Path qw(make_path remove_tree);

our $VERSION = '0.01';

my $cache_root = 't/var';
remove_tree($cache_root);
make_path($cache_root);

TestApp->config(
    name => 'TestApp',
    counter => 0,
    'Plugin::Cache' => {
        disable_index => 0,
        backend => {
            class => 'Cache::FileCache',
            cache_root => $cache_root,
        },
    },
);

TestApp->setup( qw/Cache PageCache/ );

1;

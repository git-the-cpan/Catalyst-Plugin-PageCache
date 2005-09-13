package TestApp;

use strict;
use Catalyst;
use Data::Dumper;

our $VERSION = '0.01';

TestApp->config(
    name => 'TestApp',
    cache => {
        storage => 't/var',
    },
    counter => 0,
);

TestApp->setup( qw/Cache::FileCache PageCache/ );

sub default : Private {
    my ( $self, $c ) = @_;
    
}

1;

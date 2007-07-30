package TestAppI18N;

use strict;
use Catalyst;
use Data::Dumper;

our $VERSION = '0.01';

TestAppI18N->config(
    name => 'TestApp-I18N',
    cache => {
        storage => 't/var',
    },
    counter => 0,
);

TestAppI18N->setup( qw/Cache::FileCache I18N PageCache/ );

sub default : Private {
    my ( $self, $c ) = @_;
    
}

1;

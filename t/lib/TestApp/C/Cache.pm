package TestApp::C::Cache;

use strict;
use base 'Catalyst::Base';

sub auto : Private {
    my ( $self, $c ) = @_;
    
    $c->config->{counter}++;
    
    return 1;
}

sub count : Local {
    my ( $self, $c, $expires ) = @_;
    
    $c->cache_page( $expires );
    
    $c->res->output( $c->config->{counter} );
}

sub auto_count : Local {
    my ( $self, $c ) = @_;
    
    $c->res->output( $c->config->{counter} );
}

sub another_auto_count : Local {
    my ( $self, $c ) = @_;
    
    $c->forward( 'auto_count' );
}

sub clear_cache : Local {
    my ( $self, $c ) = @_;
    
    $c->clear_cached_page( '/cache/count' );
    
    $c->res->output( 'ok' );
}

sub clear_cache_regex : Local {
    my ( $self, $c ) = @_;
    
    $c->clear_cached_page( '/cache/.*' );
    
    $c->res->output( 'ok' );
}

1;

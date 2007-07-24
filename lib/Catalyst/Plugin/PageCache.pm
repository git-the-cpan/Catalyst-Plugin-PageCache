package Catalyst::Plugin::PageCache;

use strict;
use base qw/Class::Accessor::Fast/;
use NEXT;

our $VERSION = '0.16';

# Do we need to cache the current page?
__PACKAGE__->mk_accessors('_cache_page');

# Keeps track of whether the current request was served from cache
__PACKAGE__->mk_accessors('_page_cache_used');

# Keeps a safe copy of the initial request parameters, in case the
# user changes them during processing
__PACKAGE__->mk_accessors('_page_cache_key');

sub cache_page {
    my ( $c, @args ) = @_;

    # Parameters passed in?

    if ( ref($args[0]) eq 'HASH' || @args > 1 ) {
        my $options = ref( $args[0] ) ? shift : { @args };

        $options->{cache_seconds} = $c->config->{page_cache}->{expires}
            unless exists $options->{cache_seconds};

        $c->_cache_page( $options );
        return;
    }

    my $expires = shift @args;

    # Allow specific end time
    $expires = $expires->epoch - time
        if ref($expires) && $expires->isa('DateTime');


    $expires ||= $c->config->{page_cache}->{expires};

    # mark the page for caching during finalize
    if ( $expires > 0 ) {
        $c->_cache_page( { cache_seconds => $expires } );
    }
}

sub clear_cached_page {
    my ( $c, $uri ) = @_;

    return unless ( $c->can( 'cache' ) );

    my $removed = 0;

    my $index = $c->cache->get( "_page_cache_index" ) || {};

    foreach my $key ( keys %{$index} ) {
        if ( $key =~ /^$uri$/xms ) {
            $c->cache->remove( $key );
            delete $index->{$key};
            $removed++;
            $c->log->debug( "Removed $key from page cache" )
                if ( $c->config->{page_cache}->{debug} );
        }
    }
    $c->cache->set( "_page_cache_index", $index,
        $c->config->{page_cache}->{no_expire} ) if ( $removed );
}

sub dispatch {
    my $c = shift;

    # never serve POST request pages from cache
    return $c->NEXT::dispatch(@_) if ( $c->req->method eq "POST" );

    return $c->NEXT::dispatch(@_) if ( 
	$c->config->{page_cache}->{auto_check_user} && 
	$c->can('user_exists') && 
        $c->user_exists );

    # check the page cache for a cached copy of this page
    return $c->NEXT::dispatch(@_)
        unless my $key = $c->_get_page_cache_key;

    return $c->NEXT::dispatch(@_)
        unless my $data = $c->cache->get( $key );

    # Time to remove page from cache?

    if ( $data->{expire_time} and $data->{expire_time} <= time ) {
        $c->log->debug( "Expiring $key from page cache" )
            if ( $c->config->{page_cache}->{debug} );

        $c->cache->remove( $key );

        my $index = $c->cache->get( "_page_cache_index" ) || {};
        delete $index->{$key};
        $c->cache->set( "_page_cache_index", $index,
            $c->config->{page_cache}->{no_expire} );

        return $c->NEXT::dispatch(@_);
    }

    $c->log->debug( "Serving $key from page cache, expires in " .
        ( $data->{expire_time} - time ) . " seconds" )
        if ( $c->config->{page_cache}->{debug} );

    $c->_page_cache_used( 1 );


    # Check If-Modified-Since headers
    return 1 if $c->_page_cache_not_modified( $data );



    # Serve cached page

    $c->res->body( $data->{body} );

    $c->res->content_type( join '; ', @{$data->{content_type}} )
        if $data->{content_type};


    $c->res->content_encoding( $data->{content_encoding} )
        if $data->{content_encoding};


    $c->_set_page_cache_headers( $data );

    $c->res->header('X-PageCache', 'Catalyst');

}

# See if request matches last_modified date in cache
# and return true if so.

sub _page_cache_not_modified {
    my ( $c, $data ) = @_;

    if ( $c->req->headers->if_modified_since ) {

        if ( $c->req->headers->if_modified_since == $data->{create_time} ) {
            $c->res->status(304); # Not Modified
            $c->res->headers->remove_content_headers;
            $c->_set_page_cache_headers( $data );
            $c->res->body( '' );
            return 1;
        }
    }

    return;
}


# Sets cache headers for the page if set_http_headers is true.

sub _set_page_cache_headers {
    my ( $c, $data ) = @_;

    return unless $c->config->{page_cache}->{set_http_headers};


    if ( exists $data->{expires} ) {

        # page cache but not client cache
        if ( !$data->{expires} ) {
            $c->res->headers->header( 'Cache-Control' => 'no-cache' );
            $c->res->headers->header( 'Pragma' => 'no-cache' );
            return;
        }

        $c->res->headers->header( 'Cache-Control' =>
            "max-age=" . $data->{expires} );

        $c->res->headers->expires( time + $data->{expires} );

    } else {

        $c->res->headers->header( 'Cache-Control' =>
            "max-age=" . ( $data->{expire_time} - time ) );

        $c->res->headers->expires( $data->{expire_time} );
    }

    $c->res->headers->last_modified( $data->{create_time} )
        unless $c->res->status && $c->res->status == 304;
}

sub finalize {
    my $c = shift;

    # never cache POST requests
    return $c->NEXT::finalize(@_) if ( $c->req->method eq "POST" );
    return $c->NEXT::finalize(@_) if ( 
	$c->config->{page_cache}->{auto_check_user} && 
	$c->can('user_exists') && 
        $c->user_exists );
    return $c->NEXT::finalize(@_) if ( scalar @{ $c->error } );

    # if we already served the current request from cache, we can skip the
    # rest of this method
    return $c->NEXT::finalize(@_) if ( $c->_page_cache_used );

    if ( !$c->_cache_page && scalar @{ $c->config->{page_cache}->{auto_cache} } ) {
        # is this page part of the auto_cache list?
        my $path = "/" . $c->req->path;
		# For performance, this should be moved to setup, and generate a hash.
        AUTO_CACHE:
        foreach my $auto ( @{ $c->config->{page_cache}->{auto_cache} } ) {
			next if $auto =~ m/^\d$/;
            if ( $path =~ /^$auto$/ ) {
                $c->log->debug( "Auto-caching page $path" )
                    if ( $c->config->{page_cache}->{debug} );
                $c->cache_page;
                last AUTO_CACHE;
            }
        }
    }

    if ( my $options = $c->_cache_page ) {
        my $key = $c->_get_page_cache_key;

        my $now = time;


        $c->log->debug( "Caching page $key for $options->{cache_seconds} seconds" )
            if ( $c->config->{page_cache}->{debug} );

        # Cache some additional metadata along with the content
        # Some caches don't support expirations, so we do it manually
        my $data = {
            body => $c->res->body || undef,
            content_type => [ $c->res->content_type ] || undef,
            content_encoding => $c->res->content_encoding || undef,
            create_time => $options->{last_modified} || $c->res->headers->last_modified || $now,
            expire_time => $now + $options->{cache_seconds},
        };

        $data->{expires} = $options->{expires} if exists $options->{expires};

        $c->cache->set( $key, $data );

        $c->_set_page_cache_headers( $data );  # don't forget the first time


        # Keep an index cache of all pages that have been cached, for use
        # with clear_cached_page

        my $index = $c->cache->get( "_page_cache_index" ) || {};
        $index->{$key} = 1;

        # Save date in cache
        $c->cache->set( "_page_cache_index", $index,
            $c->config->{page_cache}->{no_expire} );

        # Check for If-Modified-Since
        $c->_page_cache_not_modified( $data );
    }

    return $c->NEXT::finalize(@_);
}

sub setup {
    my $c = shift;

    $c->NEXT::setup(@_);

    $c->config->{page_cache}->{auto_cache} ||= [];
    $c->config->{page_cache}->{expires} ||= 60 * 5;
    $c->config->{page_cache}->{set_http_headers} ||= 0;
    $c->config->{page_cache}->{debug} ||= $c->debug;

    # detect the cache plugin being used and set appropriate
    # never-expires syntax
    if ( $c->can('cache') ) {
	
        # Newer C::P::Cache, cannot call $c->cache as a package method
        if ( $c->isa('Catalyst::Plugin::Cache') ) {
            return;
        }
		
		# Older Cache plugins
        if ( $c->cache->isa('Cache::FileCache') ) {
            $c->config->{page_cache}->{no_expire} = "never";
        }
        elsif ( $c->cache->isa('Cache::Memcached') ||
                  $c->cache->isa('Cache::FastMmap') ) {
          # Memcached defaults to 'never' when not given an expiration
          # In FastMmap, it's not possible to set an expiration
          $c->config->{page_cache}->{no_expire} = undef;
        }
    }
    else {
        die __PACKAGE__ . " requires a Catalyst::Plugin::Cache plugin.";
    }
}

sub _get_page_cache_key {
    my $c = shift;

    # We can't rely on the params after the user's code has run, so
    # use the key created during the initial dispatch phase
    return $c->_page_cache_key if ( $c->_page_cache_key );

    my $key = "/" . $c->req->path;
    if ( scalar $c->req->param ) {
        my @params;
        foreach my $arg ( sort keys %{ $c->req->params } ) {
            if ( ref $c->req->params->{$arg} ) {
                my $list = $c->req->params->{$arg};
                push @params, map { "$arg=" . $_  } sort @{$list};
            }
            else {
                push @params, "$arg=" . $c->req->params->{$arg};
            }
        }
        $key .= '?' . join( '&', @params );
    }
    elsif ( my $query = $c->req->uri->query ) {
        $key .= '?' . $query;
    }

    $c->_page_cache_key( $key );

    return $key;
}

1;
__END__

=head1 NAME

Catalyst::Plugin::PageCache - Cache the output of entire pages

=head1 SYNOPSIS

    use Catalyst;
    MyApp->setup( qw/Cache::FileCache PageCache/ );

    MyApp->config->{page_cache} = {
        expires => 300,
        set_http_headers => 1,
        auto_cache => [
            '/view/.*',
            '/list',
        ],
        debug => 1,
    };

    # in a controller method
    $c->cache_page( '3600' );

    $c->clear_cached_page( '/list' );


    # Expire at a specific time
    $c->cache_page( $datetime_object );


    # Fine control
    $c->cache_page(
        last_modified   => $last_modified,
        cache_seconds   => 24 * 60 * 60,    # once a day
        expires         => 300,             # allow client caching
    );

=head1 DESCRIPTION

Many dynamic websites perform heavy processing on most pages, yet this information
may rarely change from request to request.  Using the PageCache plugin, you can
cache the full output of different pages so they are served to your visitors as
fast as possible.  This method of caching is very useful for withstanding a
Slashdotting, for example.

This plugin requires that you also load a Cache plugin.  Please see the Known Issues
when choosing a cache backend.

=head1 WARNINGS

PageCache should be placed at the end of your plugin list.

You should only use the page cache on pages which have NO user-specific or
customized content.  Also, be careful if caching a page which may forward to another
controller.  For example, if you cache a page behind a login screen, the logged-in
version may be cached and served to unauthenticated users.

Note that pages that result from POST requests will never be cached.

=head1 PERFORMANCE

On my Athlon XP 1800+ Linux server, a cached page is served in 0.008 seconds when
using the HTTP::Daemon server and any of the Cache plugins.

=head1 CONFIGURATION

Configuration is optional.  You may define the following configuration values:

    expires => $seconds

This will set the default expiration time for all page caches.  If you do not specify
this, expiration defaults to 300 seconds (5 minutes).

    set_http_headers => 1

Enabling this value will cause Catalyst to set the correct HTTP headers to allow
browsers and proxy servers to cache your page.  This will further reduce the load on
your server.  The headers are set in such a way that the browser/proxy cache will
expire at the same time as your cache.  The Last-Modified header will be preserved
if you have already specified it.


    auto_cache => [
        $uri,
    ]

To automatically cache certain pages, or all pages, you can specify auto-cache URIs as
an array reference.  Any controller within your application that matches one of the
auto_cache URIs will be cached using the default expiration time.  URIs may be specified
as absolute: '/list' or as a regex: '/view/.*'

    debug => 1

This will print additional debugging information to the Catalyst log.  You will need to
have -Debug enabled to see these messages.
You can also specify an optional config parameter auto_check_user. If this
option is enabled, automatic caching is disabled for logged in users.

=head1 METHODS

=head2 cache_page

Call cache_page in any controller method you wish to be cached.

    $c->cache_page( $expire );

The page will be cached for $expire seconds.  Every user who visits the URI(s)
referenced by that controller will receive the page directly from cache.  Your
controller will not be processed again until the cache expires.  You can set this
value to as low as 60 seconds if you have heavy traffic to greatly improve site
performance.

Pass in a DateTime object to make the cache expire at a given point in time.

    $two_hours = DateTime->now->add( hours => 2 );
    $c->cache_page( $two_hours );

The page will be stored in the page cache until this time.

If set_http_headers is set then Expires and Cache-Control headers will
also be set to expire at the given date as well

Pass in a list or hash reference for finer control.

    $c->cache_page(
        last_modified   => $last_modified,
        cache_seconds   => 24 * 60 * 60,
        expires         => 30,
    );

This allows separate control of the page cache and the header cache
values sent to the client.

Possible options are:

=over 4

=item last_modified

Last modified time in epoch seconds.  If not set will use either the
current Last-Modified header, or if not set, the current time.

=item cache_seconds

This is the number of seconds to keep the page in the page cache, which may be
different (normally longer) than the time that client caches may store the page.

=item expires

This is the lenght of time in seconds that a client may cache the page
before revalidating (by asking the server if the document has changed).

Unlike above, this is a fixed setting that each client will see.  Regardless of
how much longer the page will be cached in the page cache the client still sees
the same expires time.

Setting zero (0) for expires will result in the page being cached, but headers
will be sent telling the client to not cache the page.  Allows caching expensive
content to generate, but any changes will be seen right away.



=back


To make the cache expire at a given point in time, pass in a DateTime object.

    $two_hours = DateTime->now->add( hours => 2 );
    $c->cache_page( $two_hours );

If set_http_headers is set then Expires and Cache-Control headers will
be set to expire at the given date.

Pass in a list or hash reference for finer control.

    $c->cache_page(
        last_modified   => $last_modified,
        cache_seconds   => 24 * 60 * 60,
        expires         => 30,
    );

Possible options are:

=over 4

=item last_modified

Last modified time in epoch seconds.  If not set will use either the
current Last-Modified header or the current time.

=item cache_seconds

This is the number of seconds to keep the page in the page cache, which may be 
different (normally longer) then the time that client caches may use the page.

=item expires

This is the lenght of time in seconds that a client may cache the page
before revalidating (by asking the server if the document has changed).

Unlike the "expires" setting above



=back


=head2 clear_cached_page

To clear the cached value for a URI, you may call clear_cached_page.

    $c->clear_cached_page( '/view/userlist' );
    $c->clear_cached_page( '/view/.*' );

This method takes an absolute path or regular expression.  For obvious reasons, this
must be called from a different controller than the cached controller. You may for
example wish to build an admin page that lets you clear page caches.

=head1 INTERNAL EXTENDED METHODS

=head2 dispatch

C<dispatch> decides whether or not to serve a particular request from the cache.

=head2 finalize

C<finalize> caches the result of the current request if needed.

=head2 setup

C<setup> initializes all default values.

=head1 KNOWN ISSUES

It is not currently possible to cache pages served from the Static plugin.  If you're concerned
enough about performance to use this plugin, you should be serving static files directly from
your web server anyway.

Cache::FastMmap does not have the ability to specify different expiration times for cached
data.  Therefore, if your MyApp->config->{cache}->{expires} value is set to anything other
than 0, you may experience problems with the clear_cached_page method, because the cache
index may be removed.  For best results, you may wish to use Cache::FileCache or Cache::Memcached
as your cache backend.

=head1 SEE ALSO

L<Catalyst>, L<Catalyst::Plugin::Cache::FastMmap>, L<Catalyst::Plugin::Cache::FileCache>,
L<Catalyst::Plugin::Cache::Memcached>

=head1 AUTHOR

Andy Grundman, <andy@hybridized.org>

=head1 THANKS

Bill Moseley, <mods@hank.org>, for many patches and tests.

=head1 COPYRIGHT

This program is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

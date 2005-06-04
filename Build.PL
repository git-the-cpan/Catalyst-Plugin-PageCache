use strict;
use Module::Build;

my $build = Module::Build->new(
    create_makefile_pl => 'passthrough',
    license            => 'perl',
    module_name        => 'Catalyst::Plugin::PageCache',
    requires           => { 'Catalyst' => '5.23' },
    create_makefile_pl => 'passthrough',
    test_files   => [
        glob('t/*.t') 
    ]
);
$build->create_build_script;

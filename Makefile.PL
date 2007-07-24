use inc::Module::Install 0.65;

name 'Catalyst-Plugin-PageCache';
all_from 'lib/Catalyst/Plugin/PageCache.pm';

requires 'Catalyst::Runtime' => '0';
requires 'Test::More';

auto_install;
WriteAll;

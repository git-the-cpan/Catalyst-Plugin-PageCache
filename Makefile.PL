use inc::Module::Install 0.87;

name 'Catalyst-Plugin-PageCache';
all_from 'lib/Catalyst/Plugin/PageCache.pm';

requires 'Catalyst::Runtime' => '0';
requires 'Test::More';
requires 'MRO::Compat' => '0.10';
requires 'Digest::SHA1' => '0';
test_requires 'Cache::FileCache' => 0;

auto_install;
resources repository => 'http://dev.catalyst.perl.org/repos/Catalyst/trunk/Catalyst-Plugin-PageCache/';

WriteAll;

#!perl -T

use 5.014;
use Test::More tests => 1;

BEGIN {
    use_ok( 'WWW::PipeViewer' ) || print "Bail out!\n";
}

diag( "Testing WWW::PipeViewer $WWW::PipeViewer::VERSION, Perl $], $^X" );

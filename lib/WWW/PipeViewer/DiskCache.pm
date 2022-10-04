package WWW::PipeViewer::DiskCache;

use 5.016;
use warnings;

use Carp        qw(carp);
use Digest::MD5 qw(md5_hex);
use File::Path  qw(make_path);
use File::stat  qw(stat);

sub new {
    my ($class, $path, $ext) = @_;
    -d $path
      or eval { make_path($path) }
      or carp "[!] Can't create path <<$path>>: $!";
    return
      bless {
             cache_dir => $path,
             ext       => $ext,
            }, $class;
}

sub path {
    my ($self, $url) = @_;
    my $digest = md5_hex($url // return);
    return "$self->{cache_dir}/$digest$self->{ext}";
}

sub clean {
    my ($self, $cutoff) = @_;
    return unless $cutoff;
    $cutoff = time - $cutoff;
    for my $path (glob "$self->{cache_dir}/*$self->{ext}") {
        my $mtime = (stat $path)->mtime();
        unless (defined $mtime) {
            warn "[!] Can't stat path <<$path>>: $!";
            next;
        }
        next if $mtime >= $cutoff;
        unlink $path
          or warn "[!] Can't unlink path <<$path>>: $!";
    }
    return;
}

1;

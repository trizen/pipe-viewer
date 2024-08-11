package WWW::PipeViewer::Worker;

use 5.016;
use warnings;

use Carp       qw(carp croak);
use Fcntl      ();
use IO::Handle ();
use JSON       ();
use Socket     ();

use WWW::PipeViewer;

my $_serializer = JSON->new->utf8();

sub _dump {
    my ($value) = @_;
    require JSON::PP;
    state $dumper = JSON::PP->new->canonical->indent_length(2)->pretty();
    my $dump = $dumper->encode($value);
    chomp $dump;
    return $dump;
}

sub _send_message {
    my ($self, %msg) = @_;
    my $data   = $_serializer->encode(\%msg);
    my $header = pack('L', length $data);
    if ($self->{_debug} > 1) {
        printf "[worker] sending header+message (4+%u bytes):\n%s %s\n", length($data), _dump($header), _dump($data);
    }
    $data = $header . $data;
    syswrite($self->{_stdout}, $data, length $data)
      or croak "[!] sending message failed: $!";
    return;
}

sub _recv_message {
    my ($self) = @_;
    sysread($self->{_stdin}, my $header, 4);
    if ($self->{_debug} > 1) {
        printf "[worker] received header (%u bytes):\n%s\n", length $header, _dump($header);
    }
    if (length($header) != 4) {
        carp '[worker] ignoring truncated header';
        return;
    }
    my $size = (unpack 'L', $header)[0];
    my $data = q{};
    while (length($data) < $size and sysread($self->{_stdin}, $data, $size, length $data)) { }
    if ($self->{_debug} > 1) {
        printf "[worker] received message (%u bytes):\n%s\n", length $data, _dump($data);
    }
    if (length($data) != $size) {
        carp '[worker] ignoring truncated message';
        return;
    }
    return $_serializer->decode($data);
}

sub _recv_message_noblock {
    my ($self) = @_;
    my $rin = q{};
    (vec $rin, fileno $self->{_stdin}, 1) = 1;
    return ((select $rin, undef, undef, 0) ? _recv_message($self) : undef);
}

sub _handle_abort {
    my ($self, $request) = @_;
    my %aborted          = map  { $_ => 1 } @{$request->{args}};
    my @pending_requests = grep { not exists($aborted{$_->{id}}) } @{$self->{_pending_requests}};
    if ($self->{_debug}) {
        my $culled = @{$self->{_pending_requests}} - @pending_requests;
        printf "[worker] aborted %u requests\n", $culled if $culled;
    }
    $self->{_pending_requests} = \@pending_requests;
    return;
}

#<<<
sub _handle_fetch_multiple_thumbnails {
    my ($self, $request) = @_;
    my $id           = $request->{id};
    my $thumbs       = $request->{args};
    my $keep_alive   = @$thumbs;
    my @new_requests = map {
        scalar {
                id         => $id,
                priority   => $request->{priority},
                method     => 'fetch_one_thumbnail',
                args       => @$thumbs[$_],
                keep_alive => --$keep_alive,
               }
    } 0 .. $keep_alive - 1;
    unshift @{$self->{_pending_requests}}, @new_requests;
    return;
}
#>>>

sub _handle_fetch_one_thumbnail {
    my ($self, $request) = @_;
    my $thumb = $request->{args};
    my $data  = $self->{_yv_obj}->lwp_get($thumb->{url});
    if ($data) {
        my $tmppath = "$thumb->{path}.$$";
        open(my $fp, '>:raw', $tmppath)
          or carp "[!] Can't open <<$tmppath>>: $!";
        (syswrite $fp, $data) == length($data)
          or carp "[!] Short write to <<$tmppath>>";
        close $fp
          or carp "[!] Can't close <<$tmppath>>: $!";
        rename($tmppath, $thumb->{path})
          or carp "[!] Can't rename <<$tmppath>> to <<$thumb->{path}>: $!";
    }
    $self->_send_message(
                         id         => $request->{id},
                         keep_alive => $request->{keep_alive},
                         result     => $thumb->{url},
                        );
    return;
}

# Create the `_handle_fetch_uploads`, `_handle_fetch_streams` and `_handle_fetch_shorts` methods.
#<<<
foreach my $method ('uploads', 'streams', 'shorts') {
    no strict 'refs';
    *{__PACKAGE__ . '::' . '_handle_fetch_' . $method} = sub {
        my ($self, $request) = @_;
        my $id           = $request->{id};
        my $channels     = $request->{args};
        my $keep_alive   = @$channels;
        my @new_requests = map {
            scalar {
                    id         => $id,
                    priority   => $request->{priority},
                    method     => $method,
                    args       => [@$channels[$_]],
                    keep_alive => --$keep_alive,
                }
        } 0 .. $keep_alive - 1;
        unshift @{$self->{_pending_requests}}, @new_requests;
        return;
    };
}
#>>>

sub _handle_fetch_streaming_urls {
    my ($self, $request) = @_;

    my ($video_id, $options) = @{$request->{args}};
    my ($urls, $captions, $info) = $self->{_yv_obj}->get_streaming_urls($video_id);

    if (not defined $urls) {
        $self->_send_message(id     => $request->{id},
                             result => {},);
        return;
    }

    # Download the closed-captions
    my $srt_file;
    if (ref($captions) eq 'ARRAY' and @$captions and $options->{get_captions}) {
        require WWW::PipeViewer::GetCaption;
        my $yv_cap = WWW::PipeViewer::GetCaption->new(
                                                      auto_captions => $options->{auto_captions},
                                                      captions_dir  => $options->{captions_dir},
                                                      captions      => $captions,
                                                      languages     => $options->{srt_languages},
                                                      yv_obj        => $self->{_yv_obj},
                                                     );
        $srt_file = $yv_cap->save_caption($video_id);
    }

    require WWW::PipeViewer::Itags;
    state $yv_itags = WWW::PipeViewer::Itags->new();

    my ($streaming, $resolution) = $yv_itags->find_streaming_url(
        urls       => $urls,
        resolution => $options->{resolution},

        hfr        => $options->{hfr},
        ignore_av1 => $options->{ignore_av1},

        split         => $options->{split_videos},
        prefer_m4a    => $options->{prefer_m4a},
        audio_quality => $options->{audio_quality},
        dash          => $options->{dash},

        ignored_projections => $options->{ignored_projections},
    );

    $self->_send_message(
                         id     => $request->{id},
                         result => {
                                    streaming  => $streaming,
                                    srt_file   => $srt_file,
                                    info       => $info,
                                    resolution => $resolution,
                                   },
                        );

    return;
}

sub _handle_setup {
    my ($self, $request) = @_;
    my $config = $request->{args};
    $self->{_yv_obj} = WWW::PipeViewer->new(%$config);
    $self->_send_message(id => $request->{id});
    return;
}

sub __handle_yv_method {
    my ($self, $request, $code) = @_;
    my $config = $request->{options}{config} // {};
    while (my ($key, $val) = each %$config) {
        my $setter = "set_$key";
        $self->{_yv_obj}->$setter($val);
    }
    my $result = $code->($self->{_yv_obj}, @{$request->{args}});
    if ($self->{_debug} > 1) {
        printf "[worker] yv_obj->%s() returned:\n%s\n", $request->{method}, _dump($result);
    }
    $self->_send_message(
                         id         => $request->{id},
                         keep_alive => $request->{keep_alive},
                         result     => $result,
                        );
    return;
}

sub _work {
    my ($self) = @_;
    while (1) {
        my $request;

        # Fetch new requests.
        while (defined($request = $self->_recv_message_noblock())) {

            # Insert last request into the pending queue according to priority.
            my $pending = $self->{_pending_requests};
            my $index   = scalar @$pending;
            while ($index-- and $request->{priority} < $pending->[$index]{priority}) { }
            splice @$pending, $index + 1, 0, $request;
        }

        # Unqueue the next request.
        $request = shift @{$self->{_pending_requests}};
        $request //= $self->_recv_message();
        if ($self->{_debug}) {
            printf "[worker] processing request (%u pending):\n%s\n", scalar @{$self->{_pending_requests}}, _dump($request);
        }

        # Stop on EOF or explicit "stop" request.
        if (!defined($request) || $request->{method} eq 'stop') {
            last;
        }

        # Process the request.
        my $code;
        if ($code = $self->can("_handle_$request->{method}")) {
            eval { $code->($self, $request) };
        }
        elsif ($code = $self->{_yv_obj}->can($request->{method})) {
            eval { $self->__handle_yv_method($request, $code) };
        }
        else {
            carp "[worker] unsupported method: $request->{method}";
            next;
        }
        if ($@) {
            carp "[worker] `$request->{method}` method execution failed: $@";
        }
    }
    printf "[worker] stopping\n" if $self->{_debug};
    return;
}

sub _new_child {
    my ($class, $debug, $read_from_parent, $write_to_parent) = @_;
    $write_to_parent->autoflush(1);
    binmode STDOUT, ':utf8';
    STDOUT->autoflush(1);
    my $self = bless {
                      _debug            => $debug,
                      _stdin            => $read_from_parent,
                      _stdout           => $write_to_parent,
                      _pending_requests => [],
                     }, $class;
    eval { $self->_work; 1 }
      or carp "[worker] process crashed: $@";
    close $read_from_parent
      or carp "[worker] close failed: $!";
    close $write_to_parent
      or carp "[worker] close failed: $!";
    exit;
}

sub new {
    my ($class, $debug, @only_child) = @_;

    $debug //= 0;

    if (@only_child) {
        my ($read_from_parent_fd, $write_to_parent_fd) = @only_child;

        # Re-open file descriptors.
        my $read_from_parent = IO::Handle->new();
        $read_from_parent->fdopen($read_from_parent_fd, 'r')
          or croak "[!] fdopen($read_from_parent_fd) failed: $!";
        my $write_to_parent = IO::Handle->new();
        $write_to_parent->fdopen($write_to_parent_fd, 'w')
          or croak "[!] fdopen($write_to_parent_fd) failed: $!";

        # Run the child to completion.
        _new_child($class, $debug, $read_from_parent, $write_to_parent);
    }

    socketpair(my $read_from_child, my $write_to_parent, Socket::AF_UNIX, Socket::SOCK_STREAM, Socket::PF_UNSPEC)
      or croak "[!] socketpair failed: $!";
    socketpair(my $read_from_parent, my $write_to_child, Socket::AF_UNIX, Socket::SOCK_STREAM, Socket::PF_UNSPEC)
      or croak "[!] socketpair failed: $!";

    my $child_pid = fork;
    if (!$child_pid) {

        # In the child process.
        close $read_from_child
          or carp "[worker] close failed: $!";
        close $write_to_child
          or carp "[worker] close failed: $!";

        # Disable close on exec for those handles we want to keep.
        for my $fh ($read_from_parent, $write_to_parent) {
            my $flags = fcntl $fh, Fcntl::F_GETFD, 0
              or carp "[worker] fcntl failed: $!";
            fcntl $fh, Fcntl::F_SETFD, $flags & ~Fcntl::FD_CLOEXEC
              or carp "[worker] fcntl failed: $!";
        }

        # Determine include path for using self.
        my $package = __PACKAGE__;
        $package =~ s{::}{/}g;
        $package .= '.pm';
        my $inc = $INC{$package};
        $inc =~ s{$package\z}{};

#<<<
        # Spawn another perl interpreter.
        my $script = sprintf('use WWW::PipeViewer::Worker; WWW::PipeViewer::Worker->new(%d, %d, %d)',
                             $debug,
                             fileno($read_from_parent),
                             fileno($write_to_parent));
#>>>

        exec {$^X} $0, '-I', $inc, '-e', $script
          or carp "[!] exec failed: $!";
    }

    # In the parent process.
    close $read_from_parent
      or carp "[!] close failed: $!";
    close $write_to_parent
      or carp "[!] close failed: $!";
    binmode $read_from_child;
    binmode $write_to_child;
    $write_to_child->autoflush(1);
    return
      bless {
             _debug           => $debug,
             _child_pid       => $child_pid,
             _stdin           => $read_from_child,
             _stdout          => $write_to_child,
             _last_request_id => 0,
             _requests        => {},
            }, $class;
}

sub fileno {
    my ($self) = @_;
    return fileno $self->{_stdin};
}

sub abort_requests {
    my ($self, @requests) = @_;
    my @aborted = grep { defined($_) and delete($self->{_requests}{$_}) } @requests;
    if (@aborted) {
        $self->_send_message(
                             id       =>  0,
                             priority => -1,
                             method   => 'abort',
                             args     => \@aborted,
                            );
    }
    return;
}

sub send_request {
    my ($self, $callback, $method, $args, %options) = @_;
    my %request = (
                   id       => (($self->{_last_request_id} + 1) & 0xffffffff) || 1,
                   priority => delete($options{priority}) // 0,
                   method   => $method,
                   args     => $args,
                   options  => \%options,
                  );

    # Note: don't forward the callback
    # as it's not serializable by JSON.
    $self->_send_message(%request);
    $request{callback}               = $callback;
    $self->{_last_request_id}        = $request{id};
    $self->{_requests}{$request{id}} = \%request;
    return $request{id};
}

sub process_next_reply {
    my ($self) = @_;
    my $reply = $self->_recv_message();
    if ($self->{_debug}) {
        printf "[worker] processing reply:\n%s\n", _dump($reply);
    }

    # The request may have been aborted why the reply was in transit.
    if (exists $self->{_requests}{$reply->{id}}) {
        my $request;
        if ($reply->{keep_alive}) {
            $request = $self->{_requests}{$reply->{id}};
            $request->{keep_alive} = 1;
        }
        else {
            $request = delete $self->{_requests}{$reply->{id}};
            delete $request->{keep_alive};
        }
        $request->{callback}->($reply->{result}, $request);
    }
    if ($self->{_debug}) {
        printf "[worker] %u active requests\n", scalar %{$self->{_requests}};
    }
    return;
}

sub stop {
    my ($self) = @_;
    $self->_send_message(
                         id       =>  0,
                         priority => -2,
                         method   => 'stop',
                        );
    waitpid $self->{_child_pid}, 0;
    return;
}

1;

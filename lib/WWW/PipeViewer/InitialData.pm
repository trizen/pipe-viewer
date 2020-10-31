package WWW::PipeViewer::InitialData;

use utf8;
use 5.014;
use warnings;

=head1 NAME

WWW::PipeViewer::InitialData - Extract initial data.

=head1 SYNOPSIS

    use WWW::PipeViewer;
    my $obj = WWW::PipeViewer->new(%opts);

=head1 SUBROUTINES/METHODS

=cut

sub _time_to_seconds {
    my ($time) = @_;

    my ($hours, $minutes, $seconds) = (0, 0, 0);

    if ($time =~ /(\d+):(\d+):(\d+)/) {
        ($hours, $minutes, $seconds) = ($1, $2, $3);
    }
    elsif ($time =~ /(\d+):(\d+)/) {
        ($minutes, $seconds) = ($1, $2);
    }
    elsif ($time =~ /(\d+)/) {
        $seconds = $1;
    }

    $hours * 3600 + $minutes * 60 + $seconds;
}

sub _human_number_to_int {
    my ($text) = @_;

    if ($text =~ /([\d,.]+)/) {
        my $v = $1;
        $v =~ tr/.,//d;
        return $v;
    }

    return 0;
}

sub _thumbnail_quality {
    my ($width, $height) = @_;

    $width  // return 'medium';
    $height // return 'medium';

    if ($width == 1280 and $height == 720) {
        return "maxres";
    }

    if ($width == 640 and $height == 480) {
        return "sddefault";
    }

    if ($width == 480 and $height == 360) {
        return 'high';
    }

    if ($width == 320 and $height == 180) {
        return 'medium';
    }

    if ($width == 120 and $height == 90) {
        return 'default';
    }

    return 'medium';
}

sub _fix_url_protocol {
    my ($url) = @_;

    $url // return undef;

    if ($url =~ m{^https://}) {    # ok
        return $url;
    }
    if ($url =~ s{^.*?//}{}) {
        return "https://" . $url;
    }
    if ($url =~ /^\w+\./) {
        return "https://" . $url;
    }

    return $url;
}

sub _extract_youtube_mix {
    my ($self, $data) = @_;

    my $info   = eval { $data->{callToAction}{watchCardHeroVideoRenderer} } || return;
    my $header = eval { $data->{header}{watchCardRichHeaderRenderer} };

    my %mix;

    $mix{type} = 'playlist';

    $mix{title} =
      eval    { $header->{title}{runs}[0]{text} }
      // eval { $info->{accessibility}{accessibilityData}{label} }
      // eval { $info->{callToActionButton}{callToActionButtonRenderer}{label}{runs}[0]{text} } // 'Youtube Mix';

    $mix{playlistId} = eval { $info->{navigationEndpoint}{watchEndpoint}{playlistId} } || return;

    $mix{playlistThumbnail} = eval { _fix_url_protocol($header->{avatar}{thumbnails}[0]{url}) }
      // eval { _fix_url_protocol($info->{heroImage}{collageHeroImageRenderer}{leftThumbnail}{thumbnails}[0]{url}) };

    $mix{author}   = eval { $header->{title}{runs}[0]{text} }                              // "YouTube";
    $mix{authorId} = eval { $header->{titleNavigationEndpoint}{browseEndpoint}{browseId} } // "youtube";

    return \%mix;
}

sub _extract_itemSection_entry {
    my ($self, $data, %args) = @_;

    # Album
    if ($args{type} eq 'all' and exists $data->{horizontalCardListRenderer}) {    # TODO
        return;
    }

    # Video
    if (exists $data->{compactVideoRenderer}) {

        my %video;
        my $info = $data->{compactVideoRenderer};

        $video{type} = 'video';

        $video{title} =
          eval { $info->{title}{runs}[0]{text} } // eval { $info->{title}{accessibility}{accessibilityData}{label} } // return;

        $video{videoId} = eval { $info->{navigationEndpoint}{watchEndpoint}{videoId} } // $info->{videoId} // return;
        $video{author}  = eval { $info->{longBylineText}{runs}[0]{text} } // eval { $info->{shortBylineText}{runs}[0]{text} };
        $video{authorId}      = eval { $info->{channelId} };
        $video{publishedText} = eval { $info->{publishedTimeText}{runs}[0]{text} };
        $video{viewCountText} = eval { $info->{shortViewCountText}{runs}[0]{text} };

        $video{videoThumbnails} = eval {
            [
             map {
                 my %thumb = %$_;
                 $thumb{quality} = _thumbnail_quality($thumb{width}, $thumb{height});
                 $thumb{url}     = _fix_url_protocol($thumb{url});
                 \%thumb;
             } @{$info->{thumbnail}{thumbnails}}
            ]
        };

        # FIXME: this is not the video description
        $video{description} = eval { $info->{title}{accessibility}{accessibilityData}{label} };
        $video{lengthSeconds} = _time_to_seconds(
            eval {
                $info->{thumbnailOverlays}[0]{thumbnailOverlayTimeStatusRenderer}{text}{runs}[0]{text};
              } // 0
        );
        $video{title}     = eval { $info->{title}{runs}[0]{text} };
        $video{viewCount} = _human_number_to_int(eval { $info->{viewCountText}{runs}[0]{text} } // 0);

        return \%video;
    }

    # Playlist
    if (exists $data->{compactPlaylistRenderer}) {

        my %playlist;
        my $info = $data->{compactPlaylistRenderer};

        $playlist{type} = 'playlist';

        $playlist{title} =
          eval { $info->{title}{runs}[0]{text} } // eval { $info->{title}{accessibility}{accessibilityData}{label} } // return;

        $playlist{playlistId} = $info->{playlistId};
        $playlist{videoCount} = _human_number_to_int(eval { $info->{videoCountShortText}{runs}[0]{text} }
                                                     // eval { $info->{videoCountText}{runs}[0]{text} } // 0);

        $playlist{playlistThumbnail} =
          eval { _fix_url_protocol($info->{thumbnailRenderer}{playlistVideoThumbnailRenderer}{thumbnail}{thumbnails}[0]{url}) }
          // eval { _fix_url_protocol($info->{thumbnail}{thumbnails}[0]{url}) };

        return \%playlist;
    }

    return;
}

sub _parse_itemSection {
    my ($self, $entry, %args) = @_;

    eval { ref($entry->{contents}) eq 'ARRAY' } || return;

    my @results;

    foreach my $entry (@{$entry->{contents}}) {

        my $item = $self->_extract_itemSection_entry($entry, %args);

        if (defined($item)) {
            push @results, $item;
        }
    }

    return @results;
}

sub _extract_sectionList_results {
    my ($self, $data, %args) = @_;

    eval { ref($data->{contents}) eq 'ARRAY' } or return;

    my @results;

    foreach my $entry (@{$data->{contents}}) {

        # Playlists
        if (eval { ref($entry->{shelfRenderer}{content}{verticalListRenderer}{items}) eq 'ARRAY' }) {
            push @results,
              $self->_parse_itemSection({contents => $entry->{shelfRenderer}{content}{verticalListRenderer}{items}}, %args);
        }

        # YouTube Mix
        if ($args{type} eq 'all' and exists $entry->{universalWatchCardRenderer}) {

            my $mix = $self->_extract_youtube_mix($entry->{universalWatchCardRenderer});

            if (defined($mix)) {
                push(@results, $mix);
            }
        }

        # Search results
        if (exists $entry->{itemSectionRenderer}) {
            push @results, $self->_parse_itemSection($entry->{itemSectionRenderer}, %args);
        }

        # Continuation page
        if (exists $entry->{continuationItemRenderer}) {    # TODO
            ## ...
        }
    }

    return @results;
}

sub _add_author_to_results {
    my ($self, $data, $results, %args) = @_;

    my $header = eval { $data->{header}{c4TabbedHeaderRenderer} };

    my $channel_id   = eval { $header->{channelId} };
    my $channel_name = eval { $header->{title} };

    foreach my $result (@$results) {
        if (ref($result) eq 'HASH') {
            $result->{author}   = $channel_name if defined($channel_name);
            $result->{authorId} = $channel_id   if defined($channel_id);
        }
    }

    return 1;
}

sub _extract_channel_uploads {
    my ($self, $data, %args) = @_;

    my @results = $self->_extract_sectionList_results(
        eval {
            $data->{contents}{singleColumnBrowseResultsRenderer}{tabs}[1]{tabRenderer}{content}{sectionListRenderer};
        },
        %args
                                                     );
    $self->_add_author_to_results($data, \@results, %args);
    return @results;
}

sub _extract_channel_playlists {
    my ($self, $data, %args) = @_;

    my @results = $self->_extract_sectionList_results(
        eval {
            $data->{contents}{singleColumnBrowseResultsRenderer}{tabs}[2]{tabRenderer}{content}{sectionListRenderer};
        },
        %args
                                                     );
    $self->_add_author_to_results($data, \@results, %args);
    return @results;
}

sub _get_initial_data {
    my ($self, $url) = @_;

    my $content = $self->lwp_get($url);

    if ($content =~ m{<div id="initial-data"><!--(.*?)--></div>}is) {
        my $json = $1;
        my $hash = $self->parse_utf8_json_string($json);
        return $hash;
    }

    return;
}

sub _youtube_search {
    my ($self, %args) = @_;

    my $url = $self->get_m_youtube_url . "/results?search_query=$args{q}";

    # TODO: add support for various search parameters

    my $hash = $self->_get_initial_data($url) // return;
    $self->_extract_sectionList_results(eval { $hash->{contents}{sectionListRenderer} }, %args);
}

sub _channel_data {
    my ($self, $channel, %args) = @_;

    state $yv_utils = WWW::PipeViewer::Utils->new();

    my $url = $self->get_m_youtube_url;

    if ($yv_utils->is_channelID($channel)) {
        $url .= "/channel/$channel/$args{type}";
    }
    else {
        $url .= "/c/$channel/$args{type}";
    }

    $self->_get_initial_data($url);
}

sub _channel_uploads {
    my ($self, $channel, %args) = @_;
    my $hash = $self->_channel_data($channel, type => 'videos') // return;
    $self->_extract_channel_uploads($hash, %args, type => 'video');
}

sub _channel_playlists {
    my ($self, $channel, %args) = @_;
    my $hash = $self->_channel_data($channel, type => 'playlists') // return;
    $self->_extract_channel_playlists($hash, %args, type => 'playlist');
}

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::PipeViewer::InitialData


=head1 LICENSE AND COPYRIGHT

Copyright 2013-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::PipeViewer::InitialData

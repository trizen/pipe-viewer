package WWW::PipeViewer::Search;

use utf8;
use 5.014;
use warnings;

use WWW::PipeViewer::ParseJSON;

my %_ORDER = (
              'relevance'   => 'relevance',
              'rating'      => 'rating',
              'upload_date' => 'date',
              'view_count'  => 'views',
             );

=head1 NAME

WWW::PipeViewer::Search - Search for stuff on YouTube

=head1 SYNOPSIS

    use WWW::PipeViewer;
    my $obj = WWW::PipeViewer->new(%opts);
    $obj->search_videos(@keywords);

=head1 SUBROUTINES/METHODS

=cut

sub _make_search_url {
    my ($self, %opts) = @_;

    my @features = @{$self->get_features || []};

    return $self->_make_feed_url(
        'search',

        region   => $self->get_region,
        sort     => $_ORDER{$self->get_order // 'relevance'},
        date     => $self->get_date,
        page     => $self->page_token,
        duration => $self->get_videoDuration,

        (@features ? (features => join(',', @features)) : ()),

        %opts,
    );
}

=head2 search_for($types,$keywords;\%args)

Search for a list of types (comma-separated).

=cut

sub search_for {
    my ($self, $type, $keywords, $args) = @_;

    if (ref($args) ne 'HASH') {
        $args = {};
    }

    $keywords //= [];

    if (ref($keywords) ne 'ARRAY') {
        $keywords = [split ' ', $keywords];
    }

    $keywords = $self->escape_string(join(' ', @{$keywords}));

    # Search in a channel's videos
    if (defined(my $channel_id = $self->get_channelId)) {

        $self->set_channelId();    # clear the channel ID

        if (my $results = $self->yt_channel_search($channel_id, q => $keywords, type => $type, %$args)) {
            return $results;
        }

        my $url = $self->_make_feed_url("channels/search/$channel_id", q => $keywords);
        return $self->_get_results($url);
    }

    if (my $results = $self->yt_search(q => $keywords, type => $type, %$args)) {
        return $results;
    }

    my $url = $self->_make_search_url(
                                      type => $type,
                                      q    => $keywords,
                                      %$args
                                     );
    return $self->_get_results($url);
}

{
    no strict 'refs';

    foreach my $pair (
                      {
                       name => 'videos',
                       type => 'video',
                      },
                      {
                       name => 'playlists',
                       type => 'playlist',
                      },
                      {
                       name => 'channels',
                       type => 'channel',
                      },
                      {
                       name => 'movies',
                       type => 'movie',
                      },
                      {
                       name => 'all',
                       type => 'all',
                      }
      ) {
        *{__PACKAGE__ . '::' . "search_$pair->{name}"} = sub {
            my $self = shift;
            $self->search_for($pair->{type}, @_);
        };
    }
}

=head2 search_videos($keywords;\%args)

Search and return the found video results.

=cut

=head2 search_playlists($keywords;\%args)

Search and return the found playlists.

=cut

=head2 search_channels($keywords;\%args)

Search and return the found channels.

=cut

=head2 search_all($keywords;\%args)

Search and return the results.

=cut

=head2 related_to_videoID($id)

Retrieves a list of videos that are related to the video
that the parameter value identifies. The parameter value must
be set to a YouTube video ID.

=cut

sub related_to_videoID {
    my ($self, $videoID) = @_;

    my $watch_next_response = parse_json_string($self->_get_video_next_info($videoID) // return {results => []});
    my $related             = eval { $watch_next_response->{contents}{singleColumnWatchNextResults}{results}{results}{contents} } // return {results => []};

    my @results;

    foreach my $entry (map { @{$_->{itemSectionRenderer}{contents} // []} } @$related) {

        my $info  = $entry->{videoWithContextRenderer} // next;
        my $title = $info->{headline}{runs}[0]{text}   // next;

        my $viewCount = 0;

        if (($info->{shortViewCountText}{runs}[0]{text} // '') =~ /^(\S+) views/) {
            $viewCount = WWW::PipeViewer::InitialData::_human_number_to_int($1);
        }
        elsif (($info->{shortViewCountText}{runs}[0]{text} // '') =~ /Recommended for you/i) {
            next;    # filter out recommended videos from related videos
        }

        my $lengthSeconds = 0;

        if (($info->{lengthText}{runs}[0]{text} // '') =~ /([\d:]+)/) {
            $lengthSeconds = WWW::PipeViewer::InitialData::_time_to_seconds($1);
        }

        my $published = undef;

        # FIXME: this code no longer works
        if (exists $info->{publishedTimeText} and $info->{publishedTimeText}{simpleText} =~ /(\d+)\s+(\w+)\s+ago/) {

            my $quantity = $1;
            my $period   = $2;

            $period =~ s/s\z//;    # make it singural

            my %table = (
                         year   => 31556952,      # seconds in a year
                         month  => 2629743.83,    # seconds in a month
                         week   => 604800,        # seconds in a week
                         day    => 86400,         # seconds in a day
                         hour   => 3600,          # seconds in a hour
                         minute => 60,            # seconds in a minute
                         second => 1,             # seconds in a second
                        );

            if (exists $table{$period}) {
                $published = int(time - $quantity * $table{$period});
            }
            else {
                warn "BUG: cannot parse: <<$quantity $period>>";
            }
        }

        push @results, {
            type     => "video",
            title    => $title,
            videoId  => $info->{videoId},
            author   => $info->{shortBylineText}{runs}[0]{text},
            authorId => $info->{shortBylineText}{runs}[0]{navigationEndpoint}{browseEndpoint}{browseId},

            description     => $info->{accessibility}{accessibilityData}{label},
            descriptionHtml => undef,
            viewCount       => $viewCount,
            published       => $published,
            publishedText   => $info->{publishedTimeText}{simpleText},
            lengthSeconds   => $lengthSeconds,
            liveNow         => ($lengthSeconds == 0),                              # maybe it's live if lengthSeconds == 0?
            paid            => 0,
            premium         => 0,

#<<<
            videoThumbnails => [
                map {
                    scalar {
                            quality => 'medium',
                            url     => ($_->{url} =~ s{/hqdefault\.jpg}{/mqdefault.jpg}r),
                            width   => $_->{width},
                            height  => $_->{height},
                           }
                } @{$info->{thumbnail}{thumbnails}}
            ],
#>>>
        };
    }

    return
      scalar {
              url     => undef,
              results => \@results,
             };
}

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::PipeViewer::Search


=head1 LICENSE AND COPYRIGHT

Copyright 2013-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<https://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::PipeViewer::Search

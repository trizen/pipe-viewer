package WWW::PipeViewer::Search;

use utf8;
use 5.014;
use warnings;

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

    my @features;

    if (defined(my $vd = $self->get_videoDefinition)) {
        if ($vd eq 'high') {
            push @features, 'hd';
        }
    }

    if (defined(my $vc = $self->get_videoCaption)) {
        if ($vc eq 'true' or $vc eq '1') {
            push @features, 'subtitles';
        }
    }

    if (defined(my $vd = $self->get_videoDimension)) {
        if ($vd eq '3d') {
            push @features, '3d';
        }
    }

    if (defined(my $license = $self->get_videoLicense)) {
        if ($license eq 'creative_commons') {
            push @features, 'creative_commons';
        }
    }

    return $self->_make_feed_url(
        'search',

        region   => $self->get_region,
        sort_by  => $self->get_order,
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

        my $url = $self->_make_feed_url("channels/search/$channel_id", q => $keywords);

        if (my $results = $self->yt_channel_search($channel_id, q => $keywords, type => $type, url => $url, %$args)) {
            return $results;
        }

        return $self->_get_results($url);
    }

    my $url = $self->_make_search_url(
                                      type => $type,
                                      q    => $keywords,
                                      %$args,
                                     );

    #if ($type eq 'video' and $url =~ /\?q=[^&]+&type=video\z/) {
    if (my $results = $self->yt_search(q => $keywords, type => $type, url => $url, %$args)) {
        return $results;
    }

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

    my %info                = $self->_get_video_info($videoID);
    my $watch_next_response = $self->parse_json_string($info{watch_next_response});

    my $related =
      eval { $watch_next_response->{contents}{twoColumnWatchNextResults}{secondaryResults}{secondaryResults}{results} }
      // return {results => []};

    #use Data::Dump qw(pp);
    #pp $related;

    my @results;

    foreach my $entry (@$related) {

        my $info  = $entry->{compactVideoRenderer} // next;
        my $title = $info->{title}{simpleText}     // next;

        my $viewCount = 0;

        if (($info->{viewCountText}{simpleText} // '') =~ /^([\d,]+) views/) {
            $viewCount = ($1 =~ tr/,//dr);
        }
        elsif (($info->{viewCountText}{simpleText} // '') =~ /Recommended for you/i) {
            next;    # filter out recommended videos from related videos
        }

        my $lengthSeconds = 0;

        if (($info->{lengthText}{simpleText} // '') =~ /([\d:]+)/) {
            my $time   = $1;
            my @fields = split(/:/, $time);

            my $seconds = pop(@fields) // 0;
            my $minutes = pop(@fields) // 0;
            my $hours   = pop(@fields) // 0;

            $lengthSeconds = 3600 * $hours + 60 * $minutes + $seconds;
        }

        my $published = 0;
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
            author   => $info->{longBylineText}{runs}[0]{text},
            authorId => $info->{longBylineText}{runs}[0]{navigationEndpoint}{browseEndpoint}{browseId},

            #authorUrl => $info->{longBylineText}{runs}[0]{navigationEndpoint}{browseEndpoint}{browseId},

            description     => $info->{accessibility}{accessibilityData}{label},
            descriptionHtml => undef,
            viewCount       => $viewCount,
            published       => $published,
            publishedText   => $info->{publishedTimeText}{simpleText},
            lengthSeconds   => $lengthSeconds,
            liveNow         => ($lengthSeconds == 0),                              # maybe it's live if lengthSeconds == 0?
            paid            => 0,
            premium         => 0,

            videoThumbnails => [
                map {
                    scalar {
                            quality => 'medium',
                            url     => $_->{url},
                            width   => $_->{width},
                            height  => $_->{height},
                           }
                } @{$info->{thumbnail}{thumbnails}}
            ],
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

See L<http://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::PipeViewer::Search

package WWW::PipeViewer::Videos;

use utf8;
use 5.014;
use warnings;

=head1 NAME

WWW::PipeViewer::Videos - videos handler.

=head1 SYNOPSIS

    use WWW::PipeViewer;
    my $obj = WWW::PipeViewer->new(%opts);
    my $info = $obj->video_details($videoID);

=head1 SUBROUTINES/METHODS

=cut

sub _make_videos_url {
    my ($self, %opts) = @_;
    return $self->_make_feed_url('videos', %opts);
}

{
    no strict 'refs';
    foreach my $part (
                      qw(
                      id
                      snippet
                      contentDetails
                      fileDetails
                      player
                      liveStreamingDetails
                      processingDetails
                      recordingDetails
                      statistics
                      status
                      suggestions
                      topicDetails
                      )
      ) {
        *{__PACKAGE__ . '::' . 'video_' . $part} = sub {
            my ($self, $id) = @_;
            return $self->_get_results($self->_make_videos_url(id => $id, part => $part));
        };
    }
}

=head2 trending_videos_from_category($category_id)

Get popular videos from a category ID.

=cut

sub trending_videos_from_category {
    my ($self, $category) = @_;

    if (defined($category) and $category eq 'popular') {
        return $self->popular_videos;
    }

    if (defined($category) and $category eq 'trending') {
        $category = undef;
    }

    return $self->_get_results($self->_make_feed_url('trending', (defined($category) ? (type => $category) : ())));
}

=head2 my_likes()

Get the videos liked by the authenticated user.

=cut

sub my_likes {
    my ($self) = @_;
    $self->get_access_token() // return;
    $self->_get_results($self->_make_videos_url(myRating => 'like', pageToken => $self->page_token));
}

=head2 my_dislikes()

Get the videos disliked by the authenticated user.

=cut

sub my_dislikes {
    my ($self) = @_;
    $self->get_access_token() // return;
    $self->_get_results($self->_make_videos_url(myRating => 'dislike', pageToken => $self->page_token));
}

=head2 send_rating_to_video($videoID, $rating)

Send rating to a video. $rating can be either 'like' or 'dislike'.

=cut

sub send_rating_to_video {
    my ($self, $video_id, $rating) = @_;

    if ($rating eq 'none' or $rating eq 'like' or $rating eq 'dislike') {
        my $url = $self->_simple_feeds_url('videos/rate', id => $video_id, rating => $rating);
        return defined($self->lwp_post($url, $self->_auth_lwp_header()));
    }

    return;
}

=head2 like_video($videoID)

Like a video. Returns true on success.

=cut

sub like_video {
    my ($self, $video_id) = @_;
    $self->send_rating_to_video($video_id, 'like');
}

=head2 dislike_video($videoID)

Dislike a video. Returns true on success.

=cut

sub dislike_video {
    my ($self, $video_id) = @_;
    $self->send_rating_to_video($video_id, 'dislike');
}

=head2 videos_details($id, $part)

Get info about a videoID, such as: channelId, title, description,
tags, and categoryId.

Available values for I<part> are: I<id>, I<snippet>, I<contentDetails>
I<player>, I<statistics>, I<status> and I<topicDetails>.

C<$part> string can contain more values, comma-separated.

Example:

    part => 'snippet,contentDetails,statistics'

When C<$part> is C<undef>, it defaults to I<snippet>.

=cut

sub _invidious_video_details {
    my ($self, $id, $fields) = @_;

    $fields //= $self->basic_video_info_fields;
    my $info = $self->_get_results($self->_make_feed_url("videos/$id", fields => $fields))->{results};

    if (ref($info) eq 'HASH' and exists $info->{videoId} and exists $info->{title}) {
        return $info;
    }

    return;
}

sub _ytdl_video_details {
    my ($self, $id) = @_;
    $self->_info_from_ytdl($id);
}

sub _fallback_video_details {
    my ($self, $id, $fields) = @_;

    if ($self->get_debug) {
        say STDERR ":: Extracting video info with youtube-dl...";
    }

    my $info = $self->_ytdl_video_details($id);

    if (defined($info) and ref($info) eq 'HASH') {
        return scalar {

            title   => $info->{fulltitle} // $info->{title},
            videoId => $id,

#<<<
            videoThumbnails => [
                map {
                    scalar {
                            quality => 'medium',
                            url     => $_->{url},
                            width   => $_->{width},
                            height  => $_->{height},
                           }
                } @{$info->{thumbnails}}
            ],
#>>>

            liveNow       => ($info->{is_live} ? 1 : 0),
            description   => $info->{description},
            lengthSeconds => $info->{duration},

            likeCount    => $info->{like_count},
            dislikeCount => $info->{dislike_count},

            category    => eval { $info->{categories}[0] } // $info->{category},
            publishDate => $info->{upload_date},

            keywords  => $info->{tags},
            viewCount => $info->{view_count},

            author   => $info->{channel},
            authorId => $info->{channel_id} // $info->{uploader_id},
            rating   => $info->{average_rating},
        };
    }
    else {
        #$info = $self->_invidious_video_details($id, $fields);     # too slow
    }

    return {};
}

sub video_details {
    my ($self, $id, $fields) = @_;

    if ($self->get_debug) {
        say STDERR ":: Extracting video info using the fallback method...";
    }

    my %video_info = $self->_get_video_info($id);
    my $video = $self->parse_json_string($video_info{player_response} // return $self->_fallback_video_details($id, $fields));

    state %cache;
    my $extra_info = ($cache{$id} //= $self->yt_video_info(id => $id));

    my $videoDetails = {};
    my $microformat  = {};

    if (exists $video->{videoDetails}) {

        $videoDetails = $video->{videoDetails};

        # Workaround for "Video Not Available" issue
        if ($videoDetails->{videoId} ne $id) {
            if ($self->get_debug) {
                say STDERR ":: Different video ID detected: $videoDetails->{videoId}";
            }
            return $self->_fallback_video_details($id, $fields);
        }
    }
    else {
        return $self->_fallback_video_details($id, $fields);
    }

    if (exists $video->{microformat}) {
        $microformat = eval { $video->{microformat}{playerMicroformatRenderer} } // {};
    }

    my %details = (
        title   => eval { $microformat->{title}{simpleText} } // $videoDetails->{title},
        videoId => $videoDetails->{videoId},

#<<<
        videoThumbnails => [
            map {
                scalar {
                        quality => 'medium',
                        url     => $_->{url},
                        width   => $_->{width},
                        height  => $_->{height},
                       }
            } @{$videoDetails->{thumbnail}{thumbnails}}
        ],
#>>>

        liveNow       => ($videoDetails->{isLiveContent} || (($videoDetails->{lengthSeconds} || 0) == 0)),
        description   => eval { $microformat->{description}{simpleText} } // $videoDetails->{shortDescription},
        lengthSeconds => $videoDetails->{lengthSeconds}                   // $microformat->{lengthSeconds},

        category    => $microformat->{category},
        publishDate => $microformat->{publishDate},

        keywords  => $videoDetails->{keywords},
        viewCount => $videoDetails->{viewCount} // $microformat->{viewCount},

        author   => $videoDetails->{author}    // $microformat->{ownerChannelName},
        authorId => $videoDetails->{channelId} // $microformat->{externalChannelId},
        rating   => $videoDetails->{averageRating},
    );

    if (defined($extra_info) and ref($extra_info) eq 'HASH') {

        #require WWW::PipeViewer::Utils;
        #state $yv_utils = WWW::PipeViewer::Utils->new();

        my $like_count = $extra_info->{likeCount};

        $details{likeCount} = $like_count;
        ##$details{likeCount} = $yv_utils->short_human_number($like_count);

        if ($like_count and $details{rating} and $details{rating} > 1) {

            my $rating        = $details{rating};
            my $dislike_count = sprintf('%.0f', $like_count * ((5 - $rating) / ($rating - 1)));

            $details{dislikeCount} = $dislike_count;
            ##$details{dislikeCount} = $yv_utils->short_human_number($dislike_count);
        }

        $details{author} //= $extra_info->{author};
        $details{title}  //= $extra_info->{title};

        if (not defined($details{publishDate})) {
            $details{publishedText} = $extra_info->{publishDate};
        }
    }

    return \%details;
}

=head2 Return details

Each function returns a HASH ref, with a key called 'results', and another key, called 'url'.

The 'url' key contains a string, which is the URL for the retrieved content.

The 'results' key contains another HASH ref with the keys 'etag', 'items' and 'kind'.
From the 'results' key, only the 'items' are relevant to us. This key contains an ARRAY ref,
with a HASH ref for each result. An example of the item array's content are shown below.

=cut

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::PipeViewer::Videos


=head1 LICENSE AND COPYRIGHT

Copyright 2013-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<https://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::PipeViewer::Videos

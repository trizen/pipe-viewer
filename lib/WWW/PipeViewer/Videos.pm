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

sub video_details {
    my ($self, $id, $fields) = @_;

    #~ $fields //= $self->basic_video_info_fields;
    #~ my $info = $self->_get_results($self->_make_feed_url("videos/$id", fields => $fields))->{results};

    #~ if (ref($info) eq 'HASH' and exists $info->{videoId} and exists $info->{title}) {
        #~ return $info;
    #~ }

    if ($self->get_debug) {
        say STDERR ":: Extracting video info using the fallback method...";
    }

    # Fallback using the `get_video_info` URL
    my %video_info = $self->_get_video_info($id);
    my $video      = $self->parse_json_string($video_info{player_response} // return);

    if (exists $video->{videoDetails}) {
        $video = $video->{videoDetails};
    }
    else {
        return;
    }

    my %details = (
        title   => $video->{title},
        videoId => $video->{videoId},

        videoThumbnails => [
            map {
                scalar {
                        quality => 'medium',
                        url     => $_->{url},
                        width   => $_->{width},
                        height  => $_->{height},
                       }
            } @{$video->{thumbnail}{thumbnails}}
        ],

        liveNow       => $video->{isLiveContent},
        description   => $video->{shortDescription},
        lengthSeconds => $video->{lengthSeconds},

        keywords  => $video->{keywords},
        viewCount => $video->{viewCount},

        author   => $video->{author},
        authorId => $video->{channelId},
        rating   => $video->{averageRating},
                  );

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

See L<http://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::PipeViewer::Videos

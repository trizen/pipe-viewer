package WWW::PipeViewer::Channels;

use utf8;
use 5.014;
use warnings;

=head1 NAME

WWW::PipeViewer::Channels - Channels interface.

=head1 SYNOPSIS

    use WWW::PipeViewer;
    my $obj = WWW::PipeViewer->new(%opts);
    my $videos = $obj->uploads($channel_id);

=head1 SUBROUTINES/METHODS

=cut

sub _make_channels_url {
    my ($self, %opts) = @_;
    return $self->_make_feed_url('channels', %opts);
}

=head2 channel_info($channel_id or $channel_name)

Get a channel information (name and ID).

=cut

sub channel_info {
    my ($self, $channel) = @_;
    my $info;
    my $title;
    my $id;
    if ($info = $self->yt_channel_info($channel)) {
        my $header = $self->_extract_channel_header($info) // return;
        $title = eval { $header->{title} }     // return;
        $id    = eval { $header->{channelId} } // eval { $header->{externalId} } // return;
    }
    elsif ($info = $self->_get_results($self->_make_feed_url("channels/$channel"))) {
        $title = eval { $info->{results}->{author} }   // return;
        $id    = eval { $info->{results}->{authorId} } // return;
    }
    return {author => $title, authorId => $id};
}

=head2 uploads($channel_id)

Get the uploads for a given channel ID.

=cut

sub uploads {
    my ($self, $channel_id) = @_;

    if (my $results = $self->yt_channel_uploads($channel_id)) {
        return $results;
    }

    my $url = $self->_make_feed_url("channels/$channel_id/videos");
    return $self->_get_results($url);
}

=head2 streams($channel_id)

Get the livestreams for a given channel ID.

=cut

sub streams {
    my ($self, $channel_id) = @_;

    if (my $results = $self->yt_channel_streams($channel_id)) {
        return $results;
    }

    my $url = $self->_make_feed_url("channels/$channel_id/streams");    # FIXME
    return $self->_get_results($url);
}

=head2 shorts($channel_id)

Get the shorts for a given channel ID.

=cut

sub shorts {
    my ($self, $channel_id) = @_;

    if (my $results = $self->yt_channel_shorts($channel_id)) {
        return $results;
    }

    my $url = $self->_make_feed_url("channels/$channel_id/shorts");    # FIXME
    return $self->_get_results($url);
}

=head2 popular_videos($channel_id)

Get the most popular videos for a given channel ID.

=cut

sub popular_videos {
    my ($self, $channel_id) = @_;

    if (not defined($channel_id)) {    # trending popular videos
        return $self->_get_results($self->_make_feed_url('popular'));
    }

    if (my $results = $self->yt_channel_uploads($channel_id, sort_by => 'popular')) {
        return $results;
    }

    my $url = $self->_make_feed_url("channels/$channel_id/videos", sort_by => 'popular');
    return $self->_get_results($url);
}

=head2 popular_streams($channel_id)

Get the most popular livestreams for a given channel ID.

=cut

sub popular_streams {
    my ($self, $channel_id) = @_;

    if (my $results = $self->yt_channel_streams($channel_id, sort_by => 'popular')) {
        return $results;
    }

    my $url = $self->_make_feed_url("channels/$channel_id/streams", sort_by => 'popular');    # FIXME
    return $self->_get_results($url);
}

=head2 popular_shorts($channel_id)

Get the most popular shorts for a given channel ID.

=cut

sub popular_shorts {
    my ($self, $channel_id) = @_;

    if (my $results = $self->yt_channel_shorts($channel_id, sort_by => 'popular')) {
        return $results;
    }

    my $url = $self->_make_feed_url("channels/$channel_id/shorts", sort_by => 'popular');    # FIXME
    return $self->_get_results($url);
}

=head2 channels_info($channel_id)

Return information for the comma-separated list of the YouTube channel ID(s).

=cut

sub channels_info {
    my ($self, $channel_id) = @_;
    return $self->_get_results($self->_make_channels_url(id => $channel_id));
}

=head2 channel_id_from_username($username)

Return the channel ID for an username.

=cut

sub channel_id_from_username {
    my ($self, $username) = @_;

    state $cache = {};

    if (exists $cache->{username}) {
        return $cache->{username};
    }

    if (defined(my $id = $self->yt_channel_id($username))) {
        if (ref($id) eq '' and $id =~ /\S/) {
            $cache->{$username} = $id;
            return $id;
        }
    }

    # A channel's username (if it doesn't include spaces) is also valid in place of ucid.
    if ($username =~ /\w/ and not $username =~ /\s/) {
        return $username;
    }

    # Unable to resolve channel name to channel ID (return as it is)
    return $username;
}

=head2 channel_title_from_id($channel_id)

Return the channel title for a given channel ID.

=cut

sub channel_title_from_id {
    my ($self, $channel_id) = @_;

    $channel_id // return;

    state $cache = {};

    if (exists $cache->{channel_id}) {
        return $cache->{channel_id};
    }

    if (defined(my $title = $self->yt_channel_title($channel_id))) {
        if (ref($title) eq '' and $title =~ /\S/) {
            $cache->{$channel_id} = $title;
            return $title;
        }
    }

    my $info = $self->channels_info($channel_id) // return;

    (ref($info) eq 'HASH' and ref($info->{results}) eq 'HASH' and ref($info->{results}{items}) eq 'ARRAY' and ref($info->{results}{items}[0]) eq 'HASH')
      ? $info->{results}{items}[0]{snippet}{title}
      : ();
}

=head2 channels_contentDetails($channelID)

=head2 channels_statistics($channelID);

=head2 channels_topicDetails($channelID)

=cut

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::PipeViewer::Channels


=head1 LICENSE AND COPYRIGHT

Copyright 2013-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<https://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::PipeViewer::Channels

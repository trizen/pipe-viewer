package WWW::PipeViewer::PlaylistItems;

use utf8;
use 5.014;
use warnings;

=head1 NAME

WWW::PipeViewer::PlaylistItems - Manage playlist entries.

=head1 SYNOPSIS

    use WWW::PipeViewer;
    my $obj = WWW::PipeViewer->new(%opts);
    my $videos = $obj->videos_from_playlistID($playlist_id);

=head1 SUBROUTINES/METHODS

=cut

sub _make_playlistItems_url {
    my ($self, %opts) = @_;
    return
      $self->_make_feed_url(
                            'playlistItems',
                            pageToken => $self->page_token,
                            %opts
                           );
}

=head2 videos_from_playlist_id($playlist_id)

Get videos from a specific playlistID.

=cut

sub videos_from_playlist_id {
    my ($self, $id) = @_;

    if (my $results = $self->yt_playlist_videos($id)) {
        return $results;
    }

    my $url = $self->_make_feed_url("playlists/$id");
    $self->_get_results($url);
}

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::PipeViewer::PlaylistItems


=head1 LICENSE AND COPYRIGHT

Copyright 2013-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<https://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::PipeViewer::PlaylistItems

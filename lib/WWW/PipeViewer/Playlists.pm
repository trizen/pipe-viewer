package WWW::PipeViewer::Playlists;

use utf8;
use 5.014;
use warnings;

=head1 NAME

WWW::PipeViewer::Playlists - YouTube playlists related mehods.

=head1 SYNOPSIS

    use WWW::PipeViewer;
    my $obj = WWW::PipeViewer->new(%opts);
    my $info = $obj->playlist_from_id($playlist_id);

=head1 SUBROUTINES/METHODS

=cut

sub _make_playlists_url {
    my ($self, %opts) = @_;

    if (not exists $opts{'part'}) {
        $opts{'part'} = 'snippet,contentDetails';
    }

    $self->_make_feed_url('playlists', %opts,);
}

sub get_playlist_id {
    my ($self, $playlist_name, %fields) = @_;

    my $url = $self->_simple_feeds_url('channels', qw(part contentDetails), %fields);
    my $res = $self->_get_results($url);

    ref($res->{results}{items}) eq 'ARRAY' || return;
    @{$res->{results}{items}}              || return;

    return $res->{results}{items}[0]{contentDetails}{relatedPlaylists}{$playlist_name};
}

=head2 playlist_from_id($playlist_id)

Return info for one or more playlists.
PlaylistIDs can be separated by commas.

=cut

sub playlist_from_id {
    my ($self, $id, $part) = @_;
    $self->_get_results($self->_make_playlists_url(id => $id, part => ($part // 'snippet')));
}

=head2 playlists($channel_id)

Get and return playlists from a channel ID.

=cut

sub playlists {
    my ($self, $channel_id) = @_;

    if (my $results = $self->yt_channel_created_playlists($channel_id)) {
        return $results;
    }

    if (my $results = $self->yt_channel_all_playlists($channel_id)) {
        return $results;
    }

    my $url = $self->_make_feed_url("channels/playlists/$channel_id");
    $self->_get_results($url);
}

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::PipeViewer::Playlists


=head1 LICENSE AND COPYRIGHT

Copyright 2013-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<https://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::PipeViewer::Playlists

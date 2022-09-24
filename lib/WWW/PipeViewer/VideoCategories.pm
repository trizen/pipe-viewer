package WWW::PipeViewer::VideoCategories;

use utf8;
use 5.014;
use warnings;

=head1 NAME

WWW::PipeViewer::VideoCategories - videoCategory resource handler.

=head1 SYNOPSIS

    use WWW::PipeViewer;
    my $obj = WWW::PipeViewer->new(%opts);
    my $cats = $obj->video_categories();

=head1 SUBROUTINES/METHODS

=cut

=head2 video_categories()

Return video categories for a specific region ID.

=cut

sub video_categories {
    my ($self) = @_;

    return [{id => "music",    title => "Music"},
            {id => "gaming",   title => "Gaming"},
            {id => "movies",   title => "Movies"},
            {id => "trending", title => "Trending"},
            {id => "popular",  title => "Popular"},
           ];
}

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::PipeViewer::VideoCategories


=head1 LICENSE AND COPYRIGHT

Copyright 2013-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<https://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::PipeViewer::VideoCategories

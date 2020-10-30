package WWW::PipeViewer::GuideCategories;

use utf8;
use 5.014;
use warnings;

=head1 NAME

WWW::PipeViewer::GuideCategories - Categories interface.

=head1 SYNOPSIS

    use WWW::PipeViewer;
    my $obj = WWW::PipeViewer->new(%opts);
    my $videos = $obj->youtube_categories('US');

=head1 SUBROUTINES/METHODS

=cut

sub _make_guideCategories_url {
    my ($self, %opts) = @_;

    if (not exists $opts{id}) {
        $opts{region} //= $self->get_region;
    }

    $self->_make_feed_url('guideCategories', %opts);
}

=head2 guide_categories(;$region_id)

Return guide categories for a specific region ID.

=head2 guide_categories_info($category_id)

Return info for a list of comma-separated category IDs.

=cut

{
    no strict 'refs';

    foreach my $method (
                        {
                         key  => 'id',
                         name => 'guide_categories_info',
                        },
                        {
                         key  => 'region',
                         name => 'guide_categories',
                        },
      ) {
        *{__PACKAGE__ . '::' . $method->{name}} = sub {
            my ($self, $id) = @_;
            return $self->_get_results($self->_make_guideCategories_url($method->{key} => $id // return));
        };
    }
}

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::PipeViewer::GuideCategories


=head1 LICENSE AND COPYRIGHT

Copyright 2013-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::PipeViewer::GuideCategories

package WWW::PipeViewer::ParseJSON;

use utf8;
use 5.014;
use warnings;

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(
  make_json_string
  parse_json_string
  parse_utf8_json_string
);

=head1 NAME

WWW::PipeViewer::ParseJSON - Parse JSON content.

=head1 SYNOPSIS

    use WWW::PipeViewer::ParseJSON;
    my $obj = WWW::PipeViewer::ParseJSON->new(%opts);

=head1 SUBROUTINES/METHODS

=cut

=head2 parse_json_string($json_string)

Parse a JSON string and return a HASH ref.

=cut

sub parse_utf8_json_string {
    my ($json) = @_;

    if (not defined($json) or $json eq '') {
        return {};
    }

    require JSON;
    my $hash = eval { JSON::from_json($json) };
    return $@ ? do { warn "[JSON]: $@\n"; {} } : $hash;
}

sub parse_json_string {
    my ($json) = @_;

    if (not defined($json) or $json eq '') {
        return {};
    }

    require JSON;
    my $hash = eval { JSON::decode_json($json) };
    return $@ ? do { warn "[JSON]: $@\n"; {} } : $hash;
}

=head2 make_json_string($ref)

Create a JSON string from a HASH or ARRAY ref.

=cut

sub make_json_string {
    my ($ref) = @_;

    require JSON;
    my $str = eval { JSON::encode_json($ref) };
    return $@ ? do { warn "[JSON]: $@\n"; '' } : $str;
}

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::PipeViewer::ParseJSON


=head1 LICENSE AND COPYRIGHT

Copyright 2013-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<https://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::PipeViewer::ParseJSON

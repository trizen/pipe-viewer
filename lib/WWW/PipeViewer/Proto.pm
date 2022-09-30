package WWW::PipeViewer::Proto;

use 5.014;
use warnings;

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(
  proto_uint
  proto_nested
);

# https://developers.google.com/protocol-buffers/docs/encoding#varints
sub _encode_varint {
    my ($uint) = @_;
    my @bytes;
    do {
        my $b = $uint & 127;
        $uint >>= 7;
        if ($uint) {
            $b += 128;
        }
        push @bytes, $b;
    } while ($uint);
    return @bytes;
}

sub _proto_field {
    my ($wire_type, $field_number, @data_bytes) = @_;
    unshift @data_bytes, _encode_varint(($field_number << 3) | $wire_type);
    return @data_bytes;
}

sub proto_uint {
    my ($field_number, $uint) = @_;
    return _proto_field(0, $field_number, _encode_varint($uint));
}

sub proto_nested {
    my ($field_number, @data_bytes) = @_;
    return _proto_field(2, $field_number, _encode_varint(scalar @data_bytes), @data_bytes);
}

# vim: expandtab sw=4 ts=4

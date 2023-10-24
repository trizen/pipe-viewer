package WWW::PipeViewer::Utils;

use utf8;
use 5.014;
use warnings;

use List::Util qw(first);

=head1 NAME

WWW::PipeViewer::Utils - Various utils.

=head1 SYNOPSIS

    use WWW::PipeViewer::Utils;

    my $yv_utils = WWW::PipeViewer::Utils->new(%opts);

    print $yv_utils->format_time(3600);

=head1 SUBROUTINES/METHODS

=head2 new(%opts)

Options:

=over 4

=item thousand_separator => ""

Character used as thousand separator.

=item months => []

Month names for I<format_date()>

=item youtube_video_url_format => ""

A video YouTube URL format for sprintf(format, videoID).

=item youtube_channel_url_format => ""

A channel YouTube URL format for sprintf(format, channelID).

=item youtube_playlist_url_format => ""

A playlist YouTube URL format for sprintf(format, playlistID).

=back

=cut

sub new {
    my ($class, %opts) = @_;

    my $self = bless {
                      thousand_separator          => q{,},
                      youtube_video_url_format    => 'https://www.youtube.com/watch?v=%s',
                      youtube_channel_url_format  => 'https://www.youtube.com/channel/%s',
                      youtube_playlist_url_format => 'https://www.youtube.com/playlist?list=%s',
                     }, $class;

    $self->{months} = [
        qw(
          Jan Feb Mar
          Apr May Jun
          Jul Aug Sep
          Oct Nov Dec
          )
    ];

    foreach my $key (keys %{$self}) {
        $self->{$key} = delete $opts{$key}
          if exists $opts{$key};
    }

    foreach my $invalid_key (keys %opts) {
        warn "Invalid key: '${invalid_key}'";
    }

    return $self;
}

=head2 extension($type)

Returns the extension format from a given type.

From a string like 'video/webm;+codecs="vp9"', it returns 'webm'.

=cut

sub extension {
    my ($self, $type) = @_;

    $type //= '';

        $type =~ /\bflv\b/i      ? q{flv}
      : $type =~ /\bopus\b/i     ? q{opus}
      : $type =~ /\b3gpp?\b/i    ? q{3gp}
      : $type =~ m{^video/(\w+)} ? $1
      : $type =~ m{^audio/(\w+)} ? $1
      : $type =~ /\bwebm\b/i     ? q{webm}
      :                            q{mp4};
}

=head2 format_time($sec)

Returns time from seconds.

=cut

sub format_time {
    my ($self, $sec) = @_;

    $sec //= 0;

    $sec >= 3600
      ? join q{:}, map { sprintf '%02d', $_ } $sec / 3600 % 24, $sec / 60 % 60, $sec % 60
      : join q{:}, map { sprintf '%02d', $_ } $sec / 60 % 60, $sec % 60;
}

=head2 format_duration($duration)

Return seconds from duration (PT1H20M10S).

=cut

# PT5M3S     -> 05:03
# PT1H20M10S -> 01:20:10
# PT16S      -> 00:16

sub format_duration {
    my ($self, $duration) = @_;

    $duration // return 0;
    my ($hour, $min, $sec) = (0, 0, 0);

    $hour = $1 if ($duration =~ /(\d+)H/);
    $min  = $1 if ($duration =~ /(\d+)M/);
    $sec  = $1 if ($duration =~ /(\d+)S/);

    $hour * 60 * 60 + $min * 60 + $sec;
}

=head2 format_date($date)

Return string "04 May 2010" from "2010-05-04T00:25:55.000Z"

=cut

sub format_date {
    my ($self, $date) = @_;

    $date // return undef;

    # 2010-05-04T00:25:55.000Z
    # to: 04 May 2010

    $date =~ s{^
    (?<year>\d{4})
           -
    (?<month>\d{2})
           -
    (?<day>\d{2})
        .*
    }
    {$+{day} $self->{months}[$+{month} - 1] $+{year}}x;

    return $date;
}

=head2 date_to_age($date)

Return the (approximated) age for a given date of the form "2010-05-04T00:25:55.000Z".

=cut

sub date_to_age {
    my ($self, $date) = @_;

    $date // return undef;

    $date =~ m{^
        (?<year>\d{4})
           -
        (?<month>\d{2})
           -
        (?<day>\d{2})
        [a-zA-Z]
        (?<hour>\d{2})
            :
        (?<min>\d{2})
            :
        (?<sec>\d{2})
    }x || return undef;

    my ($sec, $min, $hour, $day, $month, $year) = gmtime(time);

    $year  += 1900;
    $month += 1;

    my %month_days = (
                      1  => 31,
                      2  => 28,
                      3  => 31,
                      4  => 30,
                      5  => 31,
                      6  => 30,
                      7  => 31,
                      8  => 31,
                      9  => 30,
                      10 => 31,
                      11 => 30,
                      12 => 31,
                     );

    my $lambda = sub {

        if ($year == $+{year}) {
            if ($month == $+{month}) {
                if ($day == $+{day}) {
                    if ($hour == $+{hour}) {
                        if ($min == $+{min}) {
                            return join(' ', $sec - $+{sec}, 'seconds');
                        }
                        return join(' ', $min - $+{min}, 'minutes');
                    }
                    return join(' ', $hour - $+{hour}, 'hours');
                }
                return join(' ', $day - $+{day}, 'days');
            }

            if ($month - $+{month} == 1) {
                my $day_diff = $+{day} - $day;
                if ($day_diff > 0 and $day_diff < $month_days{$+{month} + 0}) {
                    return join(' ', $month_days{$+{month} + 0} - $day_diff, 'days');
                }
            }

            return join(' ', $month - $+{month}, 'months');
        }

        if ($year - $+{year} == 1) {
            my $month_diff = $+{month} - $month;
            if ($month_diff > 0) {
                return join(' ', 12 - $month_diff, 'months');
            }
        }

        return join(' ', $year - $+{year}, 'years');
    };

    my $age = $lambda->();

    if ($age =~ /^1\s/) {    # singular mode
        $age =~ s/s\z//;
    }

    return $age;
}

=head2 get_entries($result)

Returns the entries for a given result.

=cut

sub get_entries {
    my ($self, $result) = @_;

    $result // return [];

    if (ref($result->{results}) eq 'HASH') {

        foreach my $type (qw(comments videos playlists entries)) {
            if (exists $result->{results}{$type}) {

                if (ref($result->{results}{$type}) ne 'ARRAY') {
                    die "Probably the selected invidious instance is down.\n"
                      . "\nTry changing the `api_host` in configuration file:\n\n"
                      . qq{\tapi_host => "auto",\n}
                      . qq{\nSee also: https://github.com/trizen/pipe-viewer#invidious-instances\n};
                }

                return $result->{results}{$type};
            }
        }
    }

    if (ref($result->{results}) eq 'ARRAY') {
        return $result->{results};
    }

    return [];
}

=head2 has_entries($result)

Returns true if a given result has entries.

=cut

sub has_entries {
    my ($self, $result) = @_;
    return scalar @{$self->get_entries($result)};
}

=head2 normalize_filename($title, $fat32safe)

Replace file-unsafe characters and trim spaces.

=cut

sub normalize_filename {
    my ($self, $title, $fat32safe) = @_;

    state $unix_like = $^O =~ /^(?:linux|freebsd|openbsd)\z/i;

    if (not $fat32safe and not $unix_like) {
        $fat32safe = 1;
    }

    if ($fat32safe) {

        state $has_unidecode = eval { require Text::Unidecode; 1 };

        if ($has_unidecode) {
            $title = Text::Unidecode::unidecode($title);
        }

        $title =~ s/: / - /g;
        $title =~ tr{:"*/?\\|}{;'+%!%%};    # "
        $title =~ tr/<>//d;
    }
    else {
        $title =~ s{/+}{%}g;
    }

    $title =~ s{%+}{%}g;
    $title =~ s{\$+(?=[A-Za-z])}{}g;

    my $basename = join(q{ }, split(q{ }, $title));
    $basename = substr($basename, 0, 200);    # make sure the filename is not too long
    return $basename;
}

=head2 format_text(%opt)

Formats a text with information from streaming and video info.

The structure of C<%opt> is:

    (
        streaming => HASH,
        info      => HASH,
        text      => STRING,
        escape    => BOOL,
        fat32safe => BOOL,
    )

=cut

sub format_text {
    my ($self, %opt) = @_;

    my $streaming = $opt{streaming};
    my $info      = $opt{info};
    my $text      = $opt{text};
    my $escape    = $opt{escape};
    my $fat32safe = $opt{fat32safe};

    my %special_tokens = (
        ID        => sub { $self->get_video_id($info) // $self->get_playlist_id($info) // $self->get_channel_id($info) },
        AUTHOR    => sub { $self->get_channel_title($info) },
        CHANNELID => sub { $self->get_channel_id($info) },

        VIEWS       => sub { $self->get_views($info) },
        VIEWS_SHORT => sub { $self->get_views_approx($info) },

        VIDEOS       => sub { $self->set_thousands($self->get_channel_video_count($info)) },
        VIDEOS_SHORT => sub { $self->short_human_number($self->get_channel_video_count($info)) },

        SUBS       => sub { $self->get_channel_subscriber_count($info) },
        SUBS_SHORT => sub { $self->short_human_number($self->get_channel_subscriber_count($info)) },

        ITEMS       => sub { $self->set_thousands($self->get_playlist_item_count($info)) },
        ITEMS_SHORT => sub { $self->short_human_number($self->get_playlist_item_count($info)) },

        LIKES => sub { $self->get_likes($info) },

        DURATION    => sub { $self->get_duration($info) },
        TIME        => sub { $self->get_time($info) },
        TITLE       => sub { $self->get_title($info) },
        FTITLE      => sub { $self->normalize_filename($self->get_title($info), $fat32safe) },
        PUBLISHED   => sub { $self->get_publication_date($info) },
        AGE         => sub { $self->get_publication_age($info) },
        AGE_SHORT   => sub { $self->get_publication_age_approx($info) },
        DESCRIPTION => sub { $self->get_description($info) },
        RATING      => sub { $self->get_rating($info) },

        (
         defined($streaming)
         ? (
            RESOLUTION => sub { $streaming->{resolution} },
            ITAG       => sub { $streaming->{streaming}{itag} },
            SUB        => sub { $streaming->{srt_file} },
            VIDEO      => sub { $streaming->{streaming}{url} },
            FORMAT     => sub { $self->extension($streaming->{streaming}{type}) },

            AUDIO => sub {
                ref($streaming->{streaming}{__AUDIO__}) eq 'HASH'
                  ? $streaming->{streaming}{__AUDIO__}{url}
                  : q{};
            },

            AOV => sub {
                ref($streaming->{streaming}{__AUDIO__}) eq 'HASH'
                  ? $streaming->{streaming}{__AUDIO__}{url}
                  : $streaming->{streaming}{url};
            },
           )
         : ()
        ),

        URL => sub {
            if (defined(my $video_id = $self->get_video_id($info))) {
                return sprintf($self->{youtube_video_url_format}, $video_id);
            }

            if (defined(my $playlist_id = $self->get_playlist_id($info))) {
                return sprintf($self->{youtube_playlist_url_format}, $playlist_id);
            }

            if (defined(my $channel_id = $self->get_channel_id($info))) {
                return sprintf($self->{youtube_channel_url_format}, $channel_id);
            }

            return undef;
        },
    );

    my $tokens_re = do {
        local $" = '|';
        qr/\*(@{[keys %special_tokens]})\*/;
    };

    my %special_escapes = (
                           a => "\a",
                           b => "\b",
                           e => "\e",
                           f => "\f",
                           n => "\n",
                           r => "\r",
                           t => "\t",
                          );

    my $escapes_re = do {
        local $" = q{};
        qr/\\([@{[keys %special_escapes]}])/;
    };

    $text =~ s/$escapes_re/$special_escapes{$1}/g;

    $escape
      ? $text =~ s<$tokens_re><\Q${\($special_tokens{$1}() // '')}\E>gr
      : $text =~ s<$tokens_re><${\($special_tokens{$1}() // '')}>gr;
}

=head2 set_thousands($num)

Return the number with thousand separators.

=cut

sub set_thousands {    # ugly, but fast
    my ($self, $n) = @_;

    return 0 unless $n;

    if ($n =~ /[KMB]/) {    # human-readable number
        return $n;
    }

    length($n) > 3 or return $n;

    my $l = length($n) - 3;
    my $i = ($l - 1) % 3 + 1;
    my $x = substr($n, 0, $i) . $self->{thousand_separator};

    while ($i < $l) {
        $x .= substr($n, $i, 3) . $self->{thousand_separator};
        $i += 3;
    }

    return $x . substr($n, $i);
}

=head2 get_video_id($info)

Get videoID.

=cut

sub get_video_id {
    my ($self, $info) = @_;
    $info->{videoId};
}

sub get_playlist_id {
    my ($self, $info) = @_;
    $info->{playlistId};
}

sub get_playlist_video_count {
    my ($self, $info) = @_;
    $info->{videoCount};
}

=head2 get_description($info)

Get description.

=cut

sub get_description {
    my ($self, $info) = @_;

    my $desc = $info->{descriptionHtml} // $info->{description} // '';

    require URI::Escape;
    require HTML::Entities;

    # Decode external links
    $desc =~ s{<a href="/redirect\?(.*?)".*?>.*?</a>}{
        my $url = $1;
        if ($url =~ /(?:^|;)q=([^&]+)/) {
            URI::Escape::uri_unescape($1);
        }
        else {
            $url;
        }
    }segi;

    # Decode hashtags
    $desc =~ s{<a href="/results\?search_query=.*?".*?>(.*?)</a>}{$1}sgi;

    # Decode internal links to videos / playlists
    $desc =~ s{<a href="/(watch\?.*?)".*?>(https://www\.youtube\.com)/watch\?.*?</a>}{
        my $url = $2;
        my $params = URI::Escape::uri_unescape($1);
        "$url/$params";
    }segi;

    # Decode internal youtu.be links
    $desc =~ s{<a href="/watch\?v=(.*?)".*?>(https://youtu\.be)/.*?</a>}{
        my $url = $2;
        my $params = URI::Escape::uri_unescape($1);
        "$url/$params";
    }segi;

    # Decode other internal links
    $desc =~ s{<a href="/(.*?)".*?>.*?</a>}{https://youtube.com/$1}sgi;

    $desc =~ s{<br/?>}{\n}gi;
    $desc =~ s{<a href="(.*?)".*?>.*?</a>}{$1}sgi;
    $desc =~ s/<.*?>//gs;

    $desc = HTML::Entities::decode_entities($desc);
    $desc =~ s/^\s+//;

    if (not $desc =~ /\S/ or length($desc) < length($info->{description} // '')) {
        $desc = $info->{description} // '';
    }

    ($desc =~ /\S/) ? $desc : 'No description available...';
}

sub read_lines_from_file {
    my ($self, $file, $mode) = @_;

    $mode //= '<';

    open(my $fh, $mode, $file) or return;
    chomp(my @lines = <$fh>);
    close $fh;

    my %seen;

    # Keep the most recent ones
    @lines = reverse(@lines);
    @lines = grep { !$seen{$_}++ } @lines;

    return @lines;
}

sub default_channels {
    my ($self) = @_;

    my %channels = (
                    'UC1_uAIS3r8Vu6JjXWvastJg' => 'Mathologer',
                    'UCSju5G2aFaWMqn-_0YBtq5A' => 'Stand-Up Maths',
                    'UC-WICcSW1k3HsScuXxDrp0w' => 'Curry On!',
                    'UCShHFwKyhcDo3g7hr4f1R8A' => 'World Science Festival',
                    'UCYO_jab_esuFRV4b17AJtAw' => '3Blue1Brown',
                    'UCWnPjmqvljcafA0z2U1fwKQ' => 'Confreaks',
                    'UC_QIfHvN9auy2CoOdSfMWDw' => 'Strange Loop Conference',
                    'UCK8XIGR5kRidIw2fWqwyHRA' => 'Reducible',
                    'UC9-y-6csu5WGm29I7JiwpnA' => 'Computerphile',
                    'UCoxcjq-8xIDTYp3uz647V5A' => 'Numberphile',
                    'UC6107grRI4m0o2-emgoDnAA' => 'SmarterEveryDay',
                    'UC1znqKFL3jeR0eoA0pHpzvw' => 'SpaceRip',
                    'UCvjgXvBlbQiydffZU7m1_aw' => 'The Coding Train',
                    'UCotwjyJnb-4KW7bmsOoLfkg' => 'Art of the Problem',
                    'UCGHZpIpAWJQ-Jy_CeCdXhMA' => 'Cool Worlds',
                    'UCmG6gHgD8JaEZVxuHWJijGQ' => 'UConn Mathematics',
                    'UC81mayGa63QaJE1SjKIYp0w' => 'metaRising',
                    'UCmFeOdJI3IXgTBDzqBLD8qg' => 'Moon',
                    'UCoOjH8D2XAgjzQlneM2W0EQ' => 'Jake Tran',
                    'UCYVU6rModlGxvJbszCclGGw' => 'Rob Braxman Tech',
                    'UCHnyfMqiRRG1u-2MsSQLbXA' => 'Veritasium',
                    'UCiRiQGCHGjDLT9FQXFW0I3A' => 'Academy of Ideas',
                    'UCFAbxaVl6PJMwbMMXX9ZcNw' => 'StoneAgeMan',
                    'UCkf4VIqu3Acnfzuk3kRIFwA' => 'gotbletu',
                    'UCjr2bPAyPV7t35MvcgT3W8Q' => 'The Hated One',
                    'UCFeK8ZdHbCqAq3gekWs8aEQ' => 'Larken Rose',
                    'UCHmVAKGT0AcuD24zyjG1xYQ' => 'Eric Rowland',
                   );

    my @channels = map { [$_, $channels{$_}] } keys %channels;

    # Sort channels by channel name
    @channels = sort { CORE::fc($a->[1]) cmp CORE::fc($b->[1]) } @channels;

    return @channels;
}

sub read_channels_from_file {
    my ($self, $file, $mode) = @_;

    $mode //= '<:utf8';

    # Read channels and remove duplicates
    my %channels = map { split(/ /, $_, 2) } grep { not /^#/ } grep { /\S\s+\S/ } $self->read_lines_from_file($file, $mode);

    # Filter valid channels and pair with channel ID with title
    my @channels = map { [$_, $channels{$_}] } grep { defined($channels{$_}) } keys %channels;

    # Sort channels by channel name
    @channels = sort { CORE::fc($a->[1]) cmp CORE::fc($b->[1]) } @channels;

    return @channels;
}

sub get_local_playlist_filenames {
    my ($self, $dir) = @_;
    require Encode;
    grep { -f $_ } sort { CORE::fc($a) cmp CORE::fc($b) } map { Encode::decode_utf8($_) } glob("$dir/*.dat");
}

sub make_local_playlist_filename {
    my ($self, $title, $playlistID) = @_;
    my $basename = $title . ' -- ' . $playlistID . '.txt';
    $basename = $self->normalize_filename($basename);
    return $basename;
}

sub local_playlist_snippet {
    my ($self, $id) = @_;

    require File::Basename;
    my $title = File::Basename::basename($id);

    $title =~ s/\.dat\z//;
    $title =~ s/ -- PL[-\w]+\z//;
    $title =~ s/_/ /g;
    $title = ucfirst($title);

    require Storable;
    my $entries = eval { Storable::retrieve($id) } // [];

    if (ref($entries) ne 'ARRAY') {
        $entries = [];
    }

    my $video_count = 0;
    my $video_id    = undef;

    if (@$entries) {
        $video_id    = $self->get_video_id($entries->[0]);
        $video_count = scalar(@$entries);
    }

    my @thumbnails;

    if (defined($video_id)) {
#<<<
        my @video_thumbs = qw(
          default        120  90
          mqdefault      320 180
          hqdefault      480 360
          sddefault      640 480
          maxresdefault 1280 720
        );
#>>>
        while (scalar @video_thumbs) {
            (my $quality, my $width, my $height, @video_thumbs) = @video_thumbs;
            push @thumbnails,
              scalar {
                      "url"    => "https://i.ytimg.com/vi/$video_id/$quality.jpg",
                      'width'  => $width,
                      'height' => $height,
                     };
        }
    }

    scalar {
            author             => "local",
            authorId           => "local",
            description        => $title,
            playlistId         => $id,
            playlistThumbnails => \@thumbnails,
            title              => $title,
            type               => "playlist",
            videoCount         => $video_count,
           };
}

sub local_channel_snippet {
    my ($self, $id, $title) = @_;

    scalar {
            author      => $title,
            authorId    => $id,
            type        => "channel",
            description => "<local channel>",
            subCount    => undef,
            videoCount  => undef,
           };
}

=head2 get_title($info)

Get title.

=cut

sub get_title {
    my ($self, $info) = @_;
    $info->{title};
}

=head2 get_thumbnail($info;$xsize,$ysize)

Get smallest thumbnail of at least ${xsize}x${ysize}.

=cut

sub get_thumbnail {
    my ($self, $info, $xsize, $ysize) = @_;

    if (exists $info->{videoId}) {
        $info->{type} = 'video';
    }

    my $available_thumbs;

    if ($info->{type} eq 'playlist') {
        $available_thumbs = $info->{playlistThumbnails} // eval {

            # Old extraction format.
            my %thumb = (
                         'url'    => $info->{playlistThumbnail},
                         'width'  => 320,
                         'height' => 180,
                        );
            [\%thumb];
        };
    }

    if ($info->{type} eq 'channel') {
        $available_thumbs = $info->{authorThumbnails};
    }

    if ($info->{type} eq 'video') {
        $available_thumbs = $info->{videoThumbnails};
    }

    ref($available_thumbs) eq 'ARRAY' or return '';

#<<<
    # Sort available thumbnails by size (height first, then width).
    my @by_increasing_size = sort {
           ($a->{height} // 0) <=> ($b->{height} // 0)
        or ($a->{width}  // 0) <=> ($b->{width}  // 0)
    } map { ref($_) eq 'ARRAY' ? @{$_} : $_ } @{$available_thumbs};
#>>>

#<<<
    # Choose smallest size equal or above requested.
    my $choice = first {
            ($_->{width}  // 0) >= $xsize
        and ($_->{height} // 0) >= $ysize
    } @by_increasing_size;
#>>>

    # Fall back to the best available quality.
    $choice //= $by_increasing_size[-1];

    return $choice;
}

sub get_channel_title {
    my ($self, $info) = @_;
    $info->{author} // $info->{title};
}

sub get_author {
    my ($self, $info) = @_;
    $info->{author};
}

sub get_comment_id {
    my ($self, $info) = @_;
    $info->{commentId} // $info->{id};
}

sub get_video_count {
    my ($self, $info) = @_;
    $info->{videoCount} // 0;
}

sub get_subscriber_count {
    my ($self, $info) = @_;
    $info->{subCount} // 0;
}

sub get_channel_subscriber_count {
    my ($self, $info) = @_;
    $info->{subCount} // 0;
}

sub get_channel_video_count {
    my ($self, $info) = @_;
    $info->{videoCount} // 0;
}

sub get_playlist_item_count {
    my ($self, $info) = @_;
    $info->{videoCount} // 0;
}

sub get_comment_content {
    my ($self, $info) = @_;
    $info->{content} // $info->{text};
}

sub get_rating {
    my ($self, $info) = @_;

    my $likes = $self->get_likes($info);
    my $views = $self->get_views($info);
    my $rating;

    if ($likes and $views and $views >= 1 and $views >= $likes) {
        $rating = sprintf("%.2g%%", log($likes + 1) / log($views + 1) * 100);
    }

    return $rating;
}

sub get_channel_id {
    my ($self, $info) = @_;
    $info->{authorId};
}

sub get_category_name {
    my ($self, $info) = @_;
    $info->{genre} // $info->{category};
}

sub get_publication_date {
    my ($self, $info) = @_;

    if (defined $info->{publishedText}) {
        return $info->{publishedText};
    }

    require Encode;
    require Time::Piece;

    my $time;

    if (defined($info->{published})) {
        $time = eval { Time::Piece->new($info->{published}) };
    }
    elsif (defined($info->{timestamp})) {
        $time = eval { Time::Piece->new($info->{timestamp}) };
    }
    elsif (defined($info->{publishDate})) {
        if ($info->{publishDate} =~ /^[0-9]+\z/) {    # time given as "%yyyy%mm%dd" (from youtube-dl)
            $time = eval { Time::Piece->strptime($info->{publishDate}, '%Y%m%d') };
        }
        else {
            $time = eval { Time::Piece->strptime($info->{publishDate}, '%Y-%m-%d') };
        }
    }

    defined($time) ? Encode::decode_utf8($time->strftime("%d %B %Y")) : undef;
}

sub get_publication_time {
    my ($self, $info) = @_;

    require Time::Piece;
    require Time::Seconds;

    if ($self->get_time($info) eq 'LIVE') {
        my $time = $info->{timestamp} // Time::Piece->new();

        if (ref($time) eq 'ARRAY') {
            $time = bless($time, "Time::Piece");
        }

        return $time;
    }

    if (defined($info->{publishedText})) {

        my $age = $info->{publishedText};
        my $t   = $info->{timestamp} // Time::Piece->new();

        if (ref($t) eq 'ARRAY') {
            $t = bless($t, "Time::Piece");
        }

        if ($age =~ /^(\d+) sec/) {
            $t -= $1;
        }

        if ($age =~ /^(\d+) min/) {
            $t -= $1 * Time::Seconds::ONE_MINUTE();
        }

        if ($age =~ /^(\d+) hour/) {
            $t -= $1 * Time::Seconds::ONE_HOUR();
        }

        if ($age =~ /^(\d+) day/) {
            $t -= $1 * Time::Seconds::ONE_DAY();
        }

        if ($age =~ /^(\d+) week/) {
            $t -= $1 * Time::Seconds::ONE_WEEK();
        }

        if ($age =~ /^(\d+) month/) {
            $t -= $1 * Time::Seconds::ONE_MONTH();
        }

        if ($age =~ /^(\d+) year/) {
            $t -= $1 * Time::Seconds::ONE_YEAR();
        }

        return $t;
    }

    return $self->get_publication_date($info);    # should not happen
}

sub get_publication_age {
    my ($self, $info) = @_;
    ($info->{publishedText} // $info->{time_text} // '') =~ s/\sago\z//r;
}

sub get_publication_age_approx {
    my ($self, $info) = @_;

    my $age = $self->get_publication_age($info) // '';

    if ($age =~ /hour|min|sec/) {
        return "0d";
    }

    if ($age =~ /^(\d+) day/) {
        return "$1d";
    }

    if ($age =~ /^(\d+) week/) {
        return "$1w";
    }

    if ($age =~ /^(\d+) month/) {
        return "$1m";
    }

    if ($age =~ /^(\d+) year/) {
        return "$1y";
    }

    return $age;
}

sub get_duration {
    my ($self, $info) = @_;
    $info->{lengthSeconds};
}

sub get_time {
    my ($self, $info) = @_;

    if ($info->{liveNow} and ($self->get_duration($info) || 0) == 0) {
        return 'LIVE';
    }

    $self->format_time($self->get_duration($info));
}

sub get_views {
    my ($self, $info) = @_;
    $info->{viewCount} // 0;
}

sub short_human_number {
    my ($self, $int) = @_;

    $int // return undef;

    if ($int < 1000) {
        return $int;
    }

    if ($int >= 10 * 1e9) {    # ten billions
        return sprintf("%dB", int($int / 1e9));
    }

    if ($int >= 1e9) {         # billions
        return sprintf("%.2gB", $int / 1e9);
    }

    if ($int >= 10 * 1e6) {    # ten millions
        return sprintf("%dM", int($int / 1e6));
    }

    if ($int >= 1e6) {         # millions
        return sprintf("%.2gM", $int / 1e6);
    }

    if ($int >= 10 * 1e3) {    # ten thousands
        return sprintf("%dK", int($int / 1e3));
    }

    if ($int >= 1e3) {         # thousands
        return sprintf("%.2gK", $int / 1e3);
    }

    return $int;
}

sub get_views_approx {
    my ($self, $info) = @_;
    my $views = $self->get_views($info);
    $self->short_human_number($views);
}

sub get_likes {
    my ($self, $info) = @_;
    $info->{likeCount};
}

{
    no strict 'refs';
    foreach my $pair ([playlist => {'playlist' => 1}], [channel => {'channel' => 1}], [video => {'video' => 1, 'playlistItem' => 1}],) {

        *{__PACKAGE__ . '::' . 'is_' . $pair->[0]} = sub {
            my ($self, $item) = @_;

            if ($pair->[0] eq 'video') {
                return 1 if defined $item->{videoId};
            }

            if ($pair->[0] eq 'playlist') {
                return 1 if defined $item->{playlistId};
            }

            exists $pair->[1]{$item->{type} // ''};
        };

    }
}

sub is_channelID {
    my ($self, $id) = @_;
    $id || return;
    $id =~ /^UC[-a-zA-Z0-9_]{22}\z/ or $id =~ /^\@[-a-zA-Z0-9_]+\z/;
}

sub is_playlistID {
    my ($self, $id) = @_;
    $id || return;
    $id =~ m{^PL[-a-zA-Z0-9_]{32}\z};
}

sub is_videoID {
    my ($self, $id) = @_;
    $id || return;
    $id =~ /^[-a-zA-Z0-9_]{11}\z/;
}

sub period_to_date {
    my ($self, $amount, $period) = @_;

    state $day   = 60 * 60 * 24;
    state $week  = $day * 7;
    state $month = $day * 30.4368;
    state $year  = $day * 365.242;

    my $time = $amount * (
                            $period =~ /^d/i ? $day
                          : $period =~ /^w/i ? $week
                          : $period =~ /^m/i ? $month
                          : $period =~ /^y/i ? $year
                          : 0
                         );

    my $now  = time;
    my @time = gmtime($now - $time);
    join('-', $time[5] + 1900, sprintf('%02d', $time[4] + 1), sprintf('%02d', $time[3])) . 'T'
      . join(':', sprintf('%02d', $time[2]), sprintf('%02d', $time[1]), sprintf('%02d', $time[0])) . 'Z';
}

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::PipeViewer::Utils


=head1 LICENSE AND COPYRIGHT

Copyright 2012-2020 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<https://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::PipeViewer::Utils

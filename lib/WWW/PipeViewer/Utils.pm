package WWW::PipeViewer::Utils;

use utf8;
use 5.014;
use warnings;

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

=item youtube_url_format => ""

A youtube URL format for sprintf(format, videoID).

=back

=cut

sub new {
    my ($class, %opts) = @_;

    my $self = bless {
                      thousand_separator => q{,},
                      youtube_url_format => 'https://www.youtube.com/watch?v=%s',
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

=head2 has_entries($result)

Returns true if a given result has entries.

=cut

sub has_entries {
    my ($self, $result) = @_;

    $result // return 0;

    if (ref($result->{results}) eq 'HASH') {

        foreach my $type (qw(comments videos playlists entries)) {
            if (exists $result->{results}{$type}) {
                ref($result->{results}{$type}) eq 'ARRAY' or return 0;
                return (@{$result->{results}{$type}} > 0);
            }
        }

        my $type = $result->{results}{type} // '';

        if ($type eq 'playlist') {
            return ($result->{results}{videoCount} > 0);
        }
    }

    if (ref($result->{results}) eq 'ARRAY') {
        return (@{$result->{results}} > 0);
    }

    if (ref($result->{results}) eq 'HASH' and not keys %{$result->{results}}) {
        return 0;
    }

    return 1;    # maybe?
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
        $title =~ s/: / - /g;
        $title =~ tr{:"*/?\\|}{;'+%!%%};    # "
        $title =~ tr/<>//d;
    }
    else {
        $title =~ tr{/}{%};
    }

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
        ID         => sub { $self->get_video_id($info) },
        AUTHOR     => sub { $self->get_channel_title($info) },
        CHANNELID  => sub { $self->get_channel_id($info) },
        DEFINITION => sub { $self->get_definition($info) },
        DIMENSION  => sub { $self->get_dimension($info) },

        VIEWS       => sub { $self->get_views($info) },
        VIEWS_SHORT => sub { $self->get_views_approx($info) },

        VIDEOS       => sub { $self->set_thousands($self->get_channel_video_count($info)) },
        VIDEOS_SHORT => sub { $self->short_human_number($self->get_channel_video_count($info)) },

        SUBS       => sub { $self->get_channel_subscriber_count($info) },
        SUBS_SHORT => sub { $self->short_human_number($self->get_channel_subscriber_count($info)) },

        ITEMS       => sub { $self->set_thousands($self->get_playlist_item_count($info)) },
        ITEMS_SHORT => sub { $self->short_human_number($self->get_playlist_item_count($info)) },

        LIKES    => sub { $self->get_likes($info) },
        DISLIKES => sub { $self->get_dislikes($info) },

        COMMENTS    => sub { $self->get_comments($info) },
        DURATION    => sub { $self->get_duration($info) },
        TIME        => sub { $self->get_time($info) },
        TITLE       => sub { $self->get_title($info) },
        FTITLE      => sub { $self->normalize_filename($self->get_title($info), $fat32safe) },
        CAPTION     => sub { $self->get_caption($info) },
        PUBLISHED   => sub { $self->get_publication_date($info) },
        AGE         => sub { $self->get_publication_age($info) },
        AGE_SHORT   => sub { $self->get_publication_age_approx($info) },
        DESCRIPTION => sub { $self->get_description($info) },

        RATING => sub {
            my $likes    = $self->get_likes($info)    // 0;
            my $dislikes = $self->get_dislikes($info) // 0;

            my $rating = 0;
            if ($likes + $dislikes > 0) {
                $rating = $likes / ($likes + $dislikes) * 5;
            }

            sprintf('%.2f', $rating);
        },

        (
         defined($streaming)
         ? (
            RESOLUTION => sub {
                $streaming->{resolution} =~ /^\d+\z/
                  ? $streaming->{resolution} . 'p'
                  : $streaming->{resolution};
            },

            ITAG   => sub { $streaming->{streaming}{itag} },
            SUB    => sub { $streaming->{srt_file} },
            VIDEO  => sub { $streaming->{streaming}{url} },
            FORMAT => sub { $self->extension($streaming->{streaming}{type}) },

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

        URL => sub { sprintf($self->{youtube_url_format}, $self->get_video_id($info)) },
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

sub read_channels_from_file {
    my ($self, $file, $mode) = @_;

    $mode //= '<:utf8';

    sort { CORE::fc($a->[1]) cmp CORE::fc($b->[1]) }
      map { [split(/ /, $_, 2)] } $self->read_lines_from_file($file, $mode);
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

    scalar {
            author            => "local",
            authorId          => "local",
            description       => $title,
            playlistId        => $id,
            playlistThumbnail => (defined($video_id) ? "https://i.ytimg.com/vi/$video_id/mqdefault.jpg" : undef),
            title             => $title,
            type              => "playlist",
            videoCount        => $video_count,
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

=head2 get_thumbnail_url($info;$type='default')

Get thumbnail URL.

=cut

sub get_thumbnail_url {
    my ($self, $info, $type) = @_;

    if (exists $info->{videoId}) {
        $info->{type} = 'video';
    }

    if ($info->{type} eq 'playlist') {
        return $info->{playlistThumbnail};
    }

    if ($info->{type} eq 'channel') {
        ref($info->{authorThumbnails}) eq 'ARRAY' or return '';

        foreach my $thumbnail (map { ref($_) eq 'ARRAY' ? @{$_} : $_ } @{$info->{authorThumbnails}}) {
            if (exists $thumbnail->{quality} and $thumbnail->{quality} eq $type) {
                return $thumbnail->{url};
            }
        }

        return eval { $info->{authorThumbnails}[0]{url} } // '';
    }

    ref($info->{videoThumbnails}) eq 'ARRAY' or return '';

    my @thumbs = map  { ref($_) eq 'ARRAY' ? @{$_} : $_ } @{$info->{videoThumbnails}};
    my @wanted = grep { $_->{quality} eq $type } grep { ref($_) eq 'HASH' } @thumbs;

    my $url;

    if (@wanted) {
        $url = eval { $wanted[0]{url} } // return '';
    }
    else {
        ## warn "[!] Couldn't find thumbnail of type <<$type>>...";
        $url = eval { $thumbs[0]{url} } // return '';
    }

    # Clean URL of trackers and other junk
    $url =~ s/\.(?:jpg|png|webp)\K\?.*//;

    return $url;
}

sub get_channel_title {
    my ($self, $info) = @_;

    #$info->{snippet}{channelTitle} || $self->get_channel_id($info);
    $info->{author} // $info->{title};
}

sub get_author {
    my ($self, $info) = @_;
    $info->{author};
}

sub get_comment_id {
    my ($self, $info) = @_;
    $info->{commentId};
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
    $info->{content};
}

sub get_id {
    my ($self, $info) = @_;
    $info->{videoId};
}

sub get_rating {
    my ($self, $info) = @_;
    my $rating = $info->{rating} // return;
    sprintf('%.2f', $rating);
}

sub get_channel_id {
    my ($self, $info) = @_;
    $info->{authorId};
}

sub get_category_id {
    my ($self, $info) = @_;
    $info->{genre} // $info->{category} // 'Unknown';
}

sub get_category_name {
    my ($self, $info) = @_;

    state $categories = {
                         1  => 'Film & Animation',
                         2  => 'Autos & Vehicles',
                         10 => 'Music',
                         15 => 'Pets & Animals',
                         17 => 'Sports',
                         19 => 'Travel & Events',
                         20 => 'Gaming',
                         22 => 'People & Blogs',
                         23 => 'Comedy',
                         24 => 'Entertainment',
                         25 => 'News & Politics',
                         26 => 'Howto & Style',
                         27 => 'Education',
                         28 => 'Science & Technology',
                         29 => 'Nonprofits & Activism',
                        };

    $info->{genre} // $info->{category} // 'Unknown';
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
    elsif (defined($info->{publishDate})) {
        $time = eval { Time::Piece->strptime($info->{publishDate}, '%Y-%m-%d') };
    }

    defined($time) ? Encode::decode_utf8($time->strftime("%d %B %Y")) : undef;
}

sub get_publication_time {
    my ($self, $info) = @_;

    require Time::Piece;
    require Time::Seconds;

    if ($self->get_time($info) eq 'LIVE') {
        my $time = $info->{timestamp} // Time::Piece->new();
        return $time;
    }

    if (defined($info->{publishedText})) {

        my $age = $info->{publishedText};
        my $t   = $info->{timestamp} // Time::Piece->new();

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
    ($info->{publishedText} // '') =~ s/\sago\z//r;
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

sub get_definition {
    my ($self, $info) = @_;

    #uc($info->{contentDetails}{definition} // '-');
    #...;
    "unknown";
}

sub get_dimension {
    my ($self, $info) = @_;

    #uc($info->{contentDetails}{dimension});
    #...;
    "unknown";
}

sub get_caption {
    my ($self, $info) = @_;

    #$info->{contentDetails}{caption};
    #...;
    "unknown";
}

sub get_views {
    my ($self, $info) = @_;
    $info->{viewCount} // 0;
}

sub short_human_number {
    my ($self, $int) = @_;

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
    $info->{likeCount} // 0;
}

sub get_dislikes {
    my ($self, $info) = @_;
    $info->{dislikeCount} // 0;
}

sub get_comments {
    my ($self, $info) = @_;

    #$info->{statistics}{commentCount};
    1;
}

{
    no strict 'refs';
    foreach my $pair ([playlist => {'playlist' => 1}],
                      [channel      => {'channel'      => 1}],
                      [video        => {'video'        => 1, 'playlistItem' => 1}],
                      [subscription => {'subscription' => 1}],
                      [activity     => {'activity'     => 1}],
      ) {

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
    $id =~ /^UC[-a-zA-Z0-9_]{22}\z/;
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

See L<http://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::PipeViewer::Utils

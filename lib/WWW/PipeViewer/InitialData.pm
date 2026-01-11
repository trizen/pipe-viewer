package WWW::PipeViewer::InitialData;

use utf8;
use 5.014;
use warnings;

use MIME::Base64 qw(encode_base64url);
use List::Util qw(pairs);

use WWW::PipeViewer::ParseJSON;
use WWW::PipeViewer::Proto;

=head1 NAME

WWW::PipeViewer::InitialData - Extract initial data from YouTube pages.

=head1 SYNOPSIS

    use WWW::PipeViewer;
    my $obj = WWW::PipeViewer->new(%opts);

    my $results   = $obj->yt_search(q => $keywords);
    my $playlists = $obj->yt_channel_created_playlists($channel_ID);

=head1 DESCRIPTION

This module provides methods for extracting and parsing YouTube data from
initial page data and API responses.

=cut

#==============================================================================
# CONSTANTS
#==============================================================================

my %DATE_FILTERS = (
    anytime => 0,
    hour    => 1,
    today   => 2,
    week    => 3,
    month   => 4,
    year    => 5,
);

my %DURATION_FILTERS = (
    any     => 0,
    short   => 1,
    long    => 2,
    average => 3,
);

my %FEATURE_FILTERS = (
    hd               => 4,
    subtitles        => 5,
    creative_commons => 6,
    '3d'             => 7,
    live             => 8,
    '4k'             => 14,
    '360'            => 15,
    hdr              => 25,
    vr180            => 26,
);

my %ORDER_FILTERS = (
    relevance   => 0,
    rating      => 1,
    upload_date => 2,
    view_count  => 3,
);

my %TYPE_FILTERS = (
    all      => 0,
    video    => 1,
    channel  => 2,
    playlist => 3,
    movie    => 4,
);

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

sub _time_to_seconds {
    my ($time) = @_;

    my ($hours, $minutes, $seconds) = (0, 0, 0);

    if ($time =~ /(\d+):(\d+):(\d+)/) {
        ($hours, $minutes, $seconds) = ($1, $2, $3);
    }
    elsif ($time =~ /(\d+):(\d+)/) {
        ($minutes, $seconds) = ($1, $2);
    }
    elsif ($time =~ /(\d+)/) {
        $seconds = $1;
    }

    return $hours * 3600 + $minutes * 60 + $seconds;
}

sub _human_number_to_int {
    my ($text) = @_;

    return undef unless defined $text;

    # Handle formats like: 7.6K -> 7600, 7.6M -> 7600000
    if ($text =~ /([\d,.]+)\s*([KMB])/i) {
        my $value = $1;
        my $unit = $2;
        my $multiplier = $unit eq 'K' ? 1e3 : $unit eq 'M' ? 1e6 : $unit eq 'B' ? 1e9 : 1;

        $value =~ tr/,/./;
        return int($value * $multiplier);
    }

    if ($text =~ /([\d,.]+)/) {
        my $value = $1;
        $value =~ tr/,.//d;
        return int($value);
    }

    return 0;
}

sub _fix_url_protocol {
    my ($url) = @_;

    return undef unless defined $url;
    return $url if $url =~ m{^https://};

    if ($url =~ s{^.*?//}{}) {
        return "https://$url";
    }

    if ($url =~ /^\w+\./) {
        return "https://$url";
    }

    return $url;
}

sub _unscramble {
    my ($str) = @_;

    my $i = my $length = length($str);

    $str =~ s/(.)(.{$i})/$2$1/sg while (--$i > 0);
    $str =~ s/(.)(.{$i})/$2$1/sg while (++$i < $length);

    return $str;
}

#==============================================================================
# DATA EXTRACTION FUNCTIONS
#==============================================================================

sub _extract_video_id {
    my ($info) = @_;
    return eval { $info->{videoId} }
        || eval { $info->{navigationEndpoint}{watchEndpoint}{videoId} }
        || eval { $info->{onTap}{innertubeCommand}{reelWatchEndpoint}{videoId} }
        || undef;
}

sub _extract_length_seconds {
    my ($info) = @_;
    return eval { $info->{lengthSeconds} }
        || _time_to_seconds(eval { $info->{thumbnailOverlays}[0]{thumbnailOverlayTimeStatusRenderer}{text}{runs}[0]{text} } // 0)
        || _time_to_seconds(eval { $info->{lengthText}{runs}[0]{text} // 0 });
}

sub _extract_published_text {
    my ($info) = @_;

    my $text = eval { $info->{publishedTimeText}{runs}[0]{text} };
    return undef unless defined $text;

    return "$1 $2 ago" if $text =~ /(\d+)\s*(\w+)/;
    return $text;
}

sub _extract_author_name {
    my ($info) = @_;
    return eval { $info->{longBylineText}{runs}[0]{text} }
        // eval { $info->{shortBylineText}{runs}[0]{text} }
        // eval { ($info->{channelThumbnail}{channelThumbnailWithLinkRenderer}{navigationEndpoint}{commandMetadata}{webCommandMetadata}{url} // '') =~ s{.*/([^/]+)\z}{$1}r };
}

sub _extract_channel_id {
    my ($info) = @_;
    return eval { $info->{channelId} }
        // eval { $info->{shortBylineText}{runs}[0]{navigationEndpoint}{browseEndpoint}{browseId} }
        // eval { $info->{navigationEndpoint}{browseEndpoint}{browseId} }
        // eval { $info->{channelThumbnail}{channelThumbnailWithLinkRenderer}{navigationEndpoint}{browseEndpoint}{browseId} };
}

sub _extract_view_count_text {
    my ($info) = @_;
    return eval { $info->{shortViewCountText}{runs}[0]{text} }
        // eval { $info->{overlayMetadata}{secondaryText}{content} };
}

sub _extract_view_count {
    my ($info) = @_;
    return _human_number_to_int(eval { $info->{viewCountText}{runs}[0]{text} } || 0)
        || _human_number_to_int(eval { ($info->{headline}{accessibility}{accessibilityData}{label} // '') =~ m{.* (\S+) views\b} ? $1 : undef } || 0)
        || _human_number_to_int(eval { $info->{shortViewCountText}{runs}[0]{text} } || 0)
        || _human_number_to_int(eval { ($info->{overlayMetadata}{secondaryText}{content} // '') =~ m{^(\S+) views\b} ? $1 : undef } || 0);
}

sub _extract_thumbnails {
    my ($info) = @_;
    return eval {
        [
            map {
                my %thumb = %$_;
                $thumb{url} = _fix_url_protocol($thumb{url});
                \%thumb;
            } @{$info}
        ]
    };
}

sub _extract_title {
    my ($info) = @_;
    return eval { $info->{title}{runs}[0]{text} }
        // eval { $info->{title}{accessibility}{accessibilityData}{label} }
        // eval { $info->{headline}{runs}[0]{text} }
        // eval { $info->{overlayMetadata}{primaryText}{content} };
}

sub _extract_description {
    my ($info) = @_;
    return eval { $info->{title}{accessibility}{accessibilityData}{label} }
        // eval { $info->{headline}{accessibility}{accessibilityData}{label} }
        // eval { $info->{accessibilityText} };
}

sub _extract_video_count {
    my ($info) = @_;
    return _human_number_to_int(
        eval { $info->{videoCountShortText}{runs}[0]{text} }
        || eval { $info->{videoCountText}{runs}[0]{text} }
        || 0
    );
}

sub _extract_subscriber_count {
    my ($info) = @_;
    return _human_number_to_int(eval { $info->{subscriberCountText}{runs}[0]{text} } || 0);
}

sub _extract_playlist_id {
    my ($info) = @_;
    return eval { $info->{playlistId} };
}

#==============================================================================
# COMPLEX EXTRACTION FUNCTIONS
#==============================================================================

sub _extract_youtube_mix {
    my ($self, $data) = @_;

    my $info = eval { $data->{callToAction}{watchCardHeroVideoRenderer} } || return;
    my $header = eval { $data->{header}{watchCardRichHeaderRenderer} };

    my %mix = (type => 'playlist');

    $mix{title} = eval { $header->{title}{runs}[0]{text} }
        // eval { $info->{accessibility}{accessibilityData}{label} }
        // eval { $info->{callToActionButton}{callToActionButtonRenderer}{label}{runs}[0]{text} }
        // 'Youtube Mix';

    $mix{playlistId} = eval { $info->{navigationEndpoint}{watchEndpoint}{playlistId} } || return;

    $mix{playlistThumbnails} = _extract_thumbnails(
        $header->{avatar}{thumbnails}
        // $info->{heroImage}{collageHeroImageRenderer}{leftThumbnail}{thumbnails}
    );

    $mix{description} = _extract_description({title => $info});
    $mix{author} = eval { $header->{title}{runs}[0]{text} } // "YouTube";
    $mix{authorId} = eval { $header->{titleNavigationEndpoint}{browseEndpoint}{browseId} } // "youtube";

    return \%mix;
}

sub _extract_itemSection_entry {
    my ($self, $data, %args) = @_;

    return unless ref($data) eq 'HASH';

    # Skip albums
    return if $args{type} eq 'all' && exists $data->{horizontalCardListRenderer};

    # Extract video data
    if (exists($data->{compactVideoRenderer})
        || exists($data->{playlistVideoRenderer})
        || exists($data->{videoWithContextRenderer})) {
        
        return $self->_extract_video_entry($data, %args);
    }

    # Extract shorts data
    if (exists($data->{shortsLockupViewModel})) {
        return $self->_extract_shorts_entry($data, %args);
    }

    # Extract playlist data
    if ($args{type} ne 'video'
        && (exists($data->{compactPlaylistRenderer}) || exists($data->{playlistWithContextRenderer}))) {
        
        return $self->_extract_playlist_entry($data, %args);
    }

    # Extract channel data
    if ($args{type} ne 'video'
        && (exists($data->{compactChannelRenderer}) || exists($data->{channelWithContextRenderer}))) {
        
        return $self->_extract_channel_entry($data, %args);
    }

    return;
}

sub _extract_video_entry {
    my ($self, $data, %args) = @_;

    my $info = $data->{compactVideoRenderer}
        // $data->{playlistVideoRenderer}
        // $data->{videoWithContextRenderer};

    # Skip deleted/unplayable videos
    return if defined(eval { $info->{isPlayable} }) && !$info->{isPlayable};

    my %video = (type => 'video');

    $video{videoId} = _extract_video_id($info) // return;
    $video{title} = _extract_title($info) // return;
    $video{lengthSeconds} = _extract_length_seconds($info) || 0;
    $video{liveNow} = ($video{lengthSeconds} == 0);
    $video{author} = _extract_author_name($info);
    $video{authorId} = _extract_channel_id($info);
    $video{publishedText} = _extract_published_text($info);
    $video{viewCountText} = _extract_view_count_text($info);
    $video{videoThumbnails} = _extract_thumbnails($info->{thumbnail}{thumbnails});
    $video{description} = _extract_description($info);
    $video{viewCount} = _extract_view_count($info);

    # Filter out private/deleted videos from playlists
    if (exists($data->{playlistVideoRenderer})) {
        return unless defined $video{author} && defined $video{authorId};
    }

    return \%video;
}

sub _extract_shorts_entry {
    my ($self, $data, %args) = @_;

    my $info = $data->{shortsLockupViewModel};

    my %video = (type => 'video');

    $video{videoId} = _extract_video_id($info) // return;
    $video{title} = _extract_title($info) // return;
    $video{lengthSeconds} = _extract_length_seconds($info) || 0;
    $video{liveNow} = ($video{lengthSeconds} == 0);
    $video{author} = _extract_author_name($info);
    $video{authorId} = _extract_channel_id($info);
    $video{publishedText} = _extract_published_text($info);
    $video{viewCountText} = _extract_view_count_text($info);
    $video{videoThumbnails} = _extract_thumbnails($info->{thumbnail}{sources});
    $video{description} = _extract_description($info);
    $video{viewCount} = _extract_view_count($info);

    return \%video;
}

sub _extract_playlist_entry {
    my ($self, $data, %args) = @_;

    my $info = $data->{compactPlaylistRenderer} // $data->{playlistWithContextRenderer};

    my %playlist = (type => 'playlist');

    $playlist{title} = _extract_title($info) // return;
    $playlist{playlistId} = _extract_playlist_id($info) // return;
    $playlist{author} = _extract_author_name($info);
    $playlist{authorId} = _extract_channel_id($info);
    $playlist{videoCount} = _extract_video_count($info);
    $playlist{playlistThumbnails} = _extract_thumbnails(
        $info->{thumbnailRenderer}{playlistVideoThumbnailRenderer}{thumbnail}{thumbnails}
        // $info->{thumbnail}{thumbnails}
    );
    $playlist{description} = _extract_description($info);

    return \%playlist;
}

sub _extract_channel_entry {
    my ($self, $data, %args) = @_;

    my $info = $data->{compactChannelRenderer} // $data->{channelWithContextRenderer};

    my %channel = (type => 'channel');

    $channel{author} = _extract_title($info) // return;
    $channel{authorId} = _extract_channel_id($info) // return;
    $channel{subCount} = _extract_subscriber_count($info);
    $channel{videoCount} = _extract_video_count($info);
    $channel{authorThumbnails} = _extract_thumbnails($info->{thumbnail}{thumbnails});
    $channel{description} = _extract_description($info);

    return \%channel;
}

#==============================================================================
# PARSING FUNCTIONS
#==============================================================================

sub _parse_itemSection {
    my ($self, $data, %args) = @_;

    return unless eval { ref($data->{contents}) eq 'ARRAY' };

    my @results;

    foreach my $entry (@{$data->{contents}}) {
        my $item = $self->_extract_itemSection_entry($entry, %args);
        push @results, $item if defined($item) && ref($item) eq 'HASH';
    }

    # Handle continuation tokens
    if (exists($data->{continuations}) && ref($data->{continuations}) eq 'ARRAY') {
        my $token = eval { $data->{continuations}[0]{nextContinuationData}{continuation} };

        if (defined $token) {
            push @results, {
                type => 'nextpage',
                token => "ytplaylist:$args{type}:" . make_json_string({
                    token => $token,
                    args => {},
                }),
            };
        }
    }

    return @results;
}

sub _parse_itemSection_nextpage {
    my ($self, $entry, %args) = @_;

    return unless eval { ref($entry->{contents}) eq 'ARRAY' };

    foreach my $entry (@{$entry->{contents}}) {
        if (exists $entry->{continuationItemRenderer}) {
            my $info = $entry->{continuationItemRenderer};
            my $token = eval { $info->{continuationEndpoint}{continuationCommand}{token} };

            if (defined $token) {
                return {
                    type => 'nextpage',
                    token => "ytbrowse:$args{type}:" . make_json_string({
                        token => $token,
                        args => {
                            (defined($args{author_name}) ? (author_name => $args{author_name}) : ())
                        },
                    }),
                };
            }
        }
    }

    return;
}

sub _extract_sectionList_results {
    my ($self, $data, %args) = @_;

    return unless defined $data && ref($data) eq 'HASH';
    return unless exists $data->{contents} && ref($data->{contents}) eq 'ARRAY';

    my @results;

    foreach my $entry (@{$data->{contents}}) {
        $self->_process_section_entry($entry, \@results, %args);
    }

    if (@results && exists $data->{continuations}) {
        push @results, $self->_parse_itemSection($data, %args);
    }

    return @results;
}

sub _process_section_entry {
    my ($self, $entry, $results, %args) = @_;

    # Playlists
    if (eval { ref($entry->{shelfRenderer}{content}{verticalListRenderer}{items}) eq 'ARRAY' }) {
        my $res = {contents => $entry->{shelfRenderer}{content}{verticalListRenderer}{items}};
        push @$results, $self->_parse_itemSection($res, %args);
        push @$results, $self->_parse_itemSection_nextpage($res, %args);
        return;
    }

    # Playlist videos
    if (eval { ref($entry->{itemSectionRenderer}{contents}[0]{playlistVideoListRenderer}) eq 'HASH' }
        && eval { ref($entry->{itemSectionRenderer}{contents}[0]{playlistVideoListRenderer}{contents}) eq 'ARRAY' }) {
        
        my $res = $entry->{itemSectionRenderer}{contents}[0]{playlistVideoListRenderer};
        push @$results, $self->_parse_itemSection($res, %args);
        push @$results, $self->_parse_itemSection_nextpage($res, %args, (@$results ? (author_name => $results->[-1]{author}) : ()));
        return;
    }

    # YouTube Mix
    if ($args{type} eq 'all' && exists $entry->{universalWatchCardRenderer}) {
        my $mix = $self->_extract_youtube_mix($entry->{universalWatchCardRenderer});
        push @$results, $mix if defined $mix;
    }

    # Video results (v2)
    if (exists($entry->{richItemRenderer}) && ref($entry->{richItemRenderer}) eq 'HASH') {
        my $res = $entry->{richItemRenderer}{content};
        push @$results, $self->_parse_itemSection({contents => [$res]}, %args);
        push @$results, $self->_parse_itemSection_nextpage($res, %args);
    }

    # Video results
    if (exists $entry->{itemSectionRenderer}) {
        my $res = $entry->{itemSectionRenderer};
        push @$results, $self->_parse_itemSection($res, %args);
        push @$results, $self->_parse_itemSection_nextpage($res, %args);
    }

    # Continuation page
    if (exists $entry->{continuationItemRenderer}) {
        $self->_process_continuation_item($entry->{continuationItemRenderer}, $results, %args);
    }
}

sub _process_continuation_item {
    my ($self, $info, $results, %args) = @_;

    my $token = eval { $info->{continuationEndpoint}{continuationCommand}{token} };
    my $type = eval { $info->{continuationEndpoint}{commandMetadata}{webCommandMetadata}{apiUrl} };

    return unless defined $token;

    my $token_type = $type =~ m{/browse\z} ? 'ytbrowse' : 'ytsearch';

    push @$results, {
        type => 'nextpage',
        token => "$token_type:$args{type}:" . make_json_string({
            token => $token,
            args => {},
        }),
    };
}

#==============================================================================
# CHANNEL DATA FUNCTIONS
#==============================================================================

sub _extract_channel_header {
    my ($self, $data, %args) = @_;
    return eval { $data->{header}{c4TabbedHeaderRenderer} }
        // eval { $data->{metadata}{channelMetadataRenderer} };
}

sub _extract_channel_tabs {
    my ($self, $hash) = @_;

    my %channel_tabs;
    my $section_list = $self->_find_sectionList($hash);

    return %channel_tabs unless defined $section_list && ref($section_list) eq 'HASH';
    return %channel_tabs unless exists $section_list->{header};

    my $header = $section_list->{header};
    return %channel_tabs unless ref($header) eq 'HASH' && exists($header->{feedFilterChipBarRenderer});

    my $chip_bar = $header->{feedFilterChipBarRenderer};
    return %channel_tabs unless ref($chip_bar) eq 'HASH' && exists($chip_bar->{contents}) && ref($chip_bar->{contents}) eq 'ARRAY';

    foreach my $entry (@{$chip_bar->{contents}}) {
        next unless ref($entry) eq 'HASH';
        
        my $item = $entry->{chipCloudChipRenderer} // next;
        next unless ref($item) eq 'HASH';
        
        my $text = $item->{text} // next;
        $text = $text->{simpleText} // next if ref($text) eq 'HASH';
        
        $channel_tabs{$text} = {%$item};
    }

    return %channel_tabs;
}

sub _extract_videos_from_channel_data {
    my ($self, $url, $hash, %args) = @_;

    return unless defined $hash;

    my @results = $self->_extract_channel_uploads($hash, %args, type => 'video');
    my $author_name = @results ? $results[0]->{author} : undef;

    # Handle popular videos
    if (defined($args{sort_by}) && $args{sort_by} eq 'popular') {
        my %channel_tabs = $self->_extract_channel_tabs($hash);
        
        foreach my $key (keys %channel_tabs) {
            next unless $key =~ /popular/i;
            
            my $value = $channel_tabs{$key};
            next unless ref($value) eq 'HASH';
            
            my $token = eval { $value->{navigationEndpoint}{continuationCommand}{token} } // next;
            my $popular_videos = $self->yt_browse_request($url, $token, %args, type => 'video', author_name => $author_name);
            return $popular_videos;
        }
    }

    return $self->_prepare_results_for_return(\@results, %args, url => $url);
}

sub _add_author_to_results {
    my ($self, $data, $results, %args) = @_;

    my $header = $self->_extract_channel_header($data, %args);

    my $channel_id = eval { $header->{channelId} } // eval { $header->{externalId} };
    my $channel_name = eval { $header->{title} } // $args{author_name};

    # Try to extract channel ID from service tracking params
    if (!defined $channel_id) {
        if (eval { ref($data->{responseContext}{serviceTrackingParams}) eq 'ARRAY' }) {
            foreach my $entry (@{$data->{responseContext}{serviceTrackingParams}}) {
                next unless ref($entry) eq 'HASH' && exists($entry->{params}) && ref($entry->{params}) eq 'ARRAY';
                
                foreach my $param (@{$entry->{params}}) {
                    if (($param->{key} // '') eq 'browse_id') {
                        $channel_id = $param->{value};
                        last;
                    }
                }
            }
        }
    }

    $channel_name //= $channel_id;

    # Add author info to all results
    foreach my $result (@$results) {
        if (ref($result) eq 'HASH') {
            $result->{author} = $channel_name if defined $channel_name;
            $result->{authorId} = $channel_id if defined $channel_id;
        }
    }

    # Update nextpage token with author name
    if (@$results && defined($channel_name) && $results->[-1]{type} eq 'nextpage') {
        my $token = $results->[-1]{token};
        
        if (defined($token) && $token =~ /^ytbrowse:(\w+):(.*)/s) {
            my ($type, $json) = ($1, $2);
            
            if ($json =~ /^\{/) {
                my $info = parse_json_string($json);
                $info->{args}{author_name} = $channel_name;
                $results->[-1]{token} = "ytbrowse:$type:" . make_json_string($info);
            }
        }
    }

    return 1;
}

sub _find_sectionList {
    my ($self, $data) = @_;

    return undef unless defined $data && ref($data) eq 'HASH';

    # Check for error alerts
    if (exists $data->{alerts}) {
        if (ref($data->{alerts}) eq 'ARRAY'
            && grep { eval { $_->{alertRenderer}{type} =~ /error/i } } @{$data->{alerts}}) {
            return undef;
        }
    }

    return undef unless exists $data->{contents};

    my $section = eval {
        (grep {
            eval { exists($_->{tabRenderer}{content}{sectionListRenderer}{contents}) }
        } @{$data->{contents}{singleColumnBrowseResultsRenderer}{tabs}})[0]{tabRenderer}{content}{sectionListRenderer}
    } // eval {
        (grep {
            eval { exists($_->{tabRenderer}{content}{richGridRenderer}{contents}) }
        } @{$data->{contents}{singleColumnBrowseResultsRenderer}{tabs}})[0]{tabRenderer}{content}{richGridRenderer}
    } // undef;

    return $section;
}

sub _extract_channel_uploads {
    my ($self, $data, %args) = @_;

    my @results = $self->_extract_sectionList_results($self->_find_sectionList($data), %args);
    $self->_add_author_to_results($data, \@results, %args);
    return @results;
}

sub _extract_channel_playlists {
    my ($self, $data, %args) = @_;

    my @results = $self->_extract_sectionList_results($self->_find_sectionList($data), %args);
    $self->_add_author_to_results($data, \@results, %args);
    return @results;
}

sub _extract_playlist_videos {
    my ($self, $data, %args) = @_;

    my @results = $self->_extract_sectionList_results($self->_find_sectionList($data), %args);
    $self->_add_author_to_results($data, \@results, %args);
    return @results;
}

#==============================================================================
# DATA RETRIEVAL FUNCTIONS
#==============================================================================

sub _get_initial_data {
    my ($self, $url) = @_;

    return if $self->get_prefer_invidious();

    my $content = $self->lwp_get($url) // return;

    # Try to extract from JavaScript variable
    if ($content =~ m{var\s+ytInitialData\s*=\s*'(.*?)'}is) {
        my $json = $1;

        $json =~ s{\\x([[:xdigit:]]{2})}{chr(hex($1))}ge;
        $json =~ s{\\u([[:xdigit:]]{4})}{chr(hex($1))}ge;
        $json =~ s{\\(["&<>])}{$1}g;

        my $hash = parse_utf8_json_string($json);
        return $hash;
    }

    # Try to extract from HTML comment
    if ($content =~ m{<div id="initial-data"><!--(.*?)--></div>}is) {
        my $json = $1;
        my $hash = parse_utf8_json_string($json);
        return $hash;
    }

    return;
}

sub _channel_data {
    my ($self, $channel, %args) = @_;

    state $yv_utils = WWW::PipeViewer::Utils->new();

    my $url = $self->get_m_youtube_url;

    if ($channel =~ /^\@/) {
        $url .= "/$channel/$args{type}";
    }
    elsif ($yv_utils->is_channelID($channel)) {
        $url .= "/channel/$channel/$args{type}";
    }
    else {
        $url .= "/c/$channel/$args{type}";
    }

    my %params = (hl => "en");

    # Handle sort parameter (no longer works)
    if (defined(my $sort = $args{sort_by})) {
        if ($sort eq 'popular') {
            $params{sort} = 'p';
        }
        elsif ($sort eq 'old') {
            $params{sort} = 'da';
        }
    }

    if (exists($args{params}) && ref($args{params}) eq 'HASH') {
        %params = (%params, %{$args{params}});
    }

    $url = $self->_append_url_args($url, %params);
    my $result = $self->_get_initial_data($url);

    # Fallback: try /user/ if /c/ failed
    if ((!defined($result) || !scalar(keys %$result)) && $url =~ s{/c/}{/user/}) {
        $result = $self->_get_initial_data($url);
    }

    return ($url, $result);
}

sub _prepare_results_for_return {
    my ($self, $results, %args) = @_;

    return unless defined($results) && ref($results) eq 'ARRAY';

    my @results = @$results;
    return unless @results;

    # Handle continuation page token
    if (@results && $results[-1]{type} eq 'nextpage') {
        my $nextpage = pop(@results);

        if (defined($nextpage->{token}) && @results) {
            if ($self->get_debug) {
                say STDERR ":: Returning results with a continuation page token...";
            }

            return {
                url => $args{url},
                results => {
                    entries => \@results,
                    continuation => $nextpage->{token},
                },
            };
        }
    }

    # Don't include mobile URLs
    my $url = $args{url};
    $url = undef if $url =~ m{^https://m\.youtube\.com};

    return {
        url => $url,
        results => \@results,
    };
}

sub _build_search_params {
    my ($self, %args) = @_;

    my @sp;

    push @sp, proto_uint(1, $ORDER_FILTERS{$self->get_order // 'relevance'});

    # Build filter parameters
    my @filters;

    push @filters, proto_uint(1, $DATE_FILTERS{$self->get_date // 'anytime'});
    push @filters, proto_uint(2, $TYPE_FILTERS{$args{type} // 'video'});
    push @filters, proto_uint(3, $DURATION_FILTERS{$self->get_videoDuration // 'any'});

    foreach my $feat (@{$self->get_features || []}) {
        push @filters, proto_uint($FEATURE_FILTERS{$feat}, 1);
    }

    push @sp, proto_nested(2, @filters);

    # Build paging parameters
    my $page = $self->get_page;
    my $count = $self->get_maxResults;

    # Minimum 20 results to avoid breaking pagination
    $count = 20 if $count < 20;

    push @sp, proto_uint(9, ($page - 1) * $count) if $page > 1;
    push @sp, proto_uint(10, $count);

    return encode_base64url(pack('C*', @sp));
}

sub _build_api_context {
    my ($self, $url) = @_;

    return {
        context => {
            client => {
                browserName => "Firefox",
                browserVersion => "136.0",
                clientFormFactor => "LARGE_FORM_FACTOR",
                clientName => "MWEB",
                clientVersion => "2.20250314.01.00",
                deviceMake => "Mozilla",
                deviceModel => "Firefox for Android",
                hl => "en",
                mainAppWebInfo => {
                    graftUrl => $url,
                },
                originalUrl => $url,
                osName => "Android",
                osVersion => "16",
                platform => "MOBILE",
                playerType => "UNIPLAYER",
                screenDensityFloat => 1,
                screenHeightPoints => 500,
                screenPixelDensity => 1,
                screenWidthPoints => 1800,
                timeZone => "UTC",
                userAgent => "Mozilla/5.0 (Android 16 Beta 2; Mobile; rv:136.0) Gecko/136.0 Firefox/136.0,gzip(gfe)",
                userInterfaceTheme => "USER_INTERFACE_THEME_LIGHT",
                utcOffsetMinutes => 0,
            },
            request => {
                consistencyTokenJars => [],
                internalExperimentFlags => [],
            },
            user => {},
        },
    };
}

#==============================================================================
# PUBLIC API METHODS
#==============================================================================

=head2 yt_video_info($id)

Get video info for a given YouTube video ID by scraping the YouTube watch page.

=cut

sub yt_video_info {
    my ($self, %args) = @_;

    my $url = $self->get_m_youtube_url . "/watch";
    my %params = (
        hl => 'en',
        v => $args{id},
    );

    $url = $self->_append_url_args($url, %params);
    my $hash = $self->_get_initial_data($url) // return;

    return unless ref($hash) eq 'HASH';

    my %video_info;

    # Extract metadata from watch page
    if (ref(my $metadata = eval { $hash->{contents}{singleColumnWatchNextResults}{results}{results}{contents} }) eq 'ARRAY') {
        $self->_extract_video_metadata($metadata, \%video_info);
    }

    # Extract engagement panel data
    my $engagements = $hash->{engagementPanels} // return \%video_info;
    return \%video_info unless ref($engagements) eq 'ARRAY';

    foreach my $entry (@$engagements) {
        next unless ref($entry) eq 'HASH';
        $self->_extract_engagement_data($entry, \%video_info);
    }

    return \%video_info;
}

sub _extract_video_metadata {
    my ($self, $metadata, $video_info) = @_;

    foreach my $entry (@$metadata) {
        next unless ref($entry) eq 'HASH';

        if (ref(my $section = eval { $entry->{slimVideoMetadataSectionRenderer}{contents} }) eq 'ARRAY') {
            foreach my $part (@$section) {
                next unless ref($part) eq 'HASH';

                # Extract title
                if (my $info = $part->{slimVideoInformationRenderer}) {
                    $video_info->{title} = eval { $info->{title}{runs}[0]{text} };
                }

                # Extract like count
                if (ref(my $buttons = $part->{slimVideoActionBarRenderer}{buttons}) eq 'ARRAY') {
                    $self->_extract_like_count($buttons, $video_info);
                }
            }
        }
    }
}

sub _extract_like_count {
    my ($self, $buttons, $video_info) = @_;

    foreach my $toggle_button (@$buttons) {
        next unless ref($toggle_button) eq 'HASH';
        
        my $button = $toggle_button->{slimMetadataToggleButtonRenderer};
        next unless ref($button) eq 'HASH' && $button->{isLike};

        my $like_button = eval { $button->{button}{toggleButtonRenderer} };
        next unless ref($like_button) eq 'HASH';

        $video_info->{likeCount} = eval { _human_number_to_int($like_button->{defaultText}{accessibility}{accessibilityData}{label}) }
            // eval { (_human_number_to_int($like_button->{toggledText}{accessibility}{accessibilityData}{label}) // 0) - 1 };

        delete $video_info->{likeCount} if !defined($video_info->{likeCount}) || $video_info->{likeCount} <= 0;
    }
}

sub _extract_engagement_data {
    my ($self, $entry, $video_info) = @_;

    if (ref(my $main_info = eval { $entry->{engagementPanelSectionListRenderer}{content}{structuredDescriptionContentRenderer}{items} }) eq 'ARRAY') {
        foreach my $item (@$main_info) {
            next unless ref($item) eq 'HASH';

            # Extract header information
            if (my $desc = $item->{videoDescriptionHeaderRenderer}) {
                $self->_extract_description_header($desc, $video_info);
            }

            # Extract description body
            if (my $desc_body = $item->{expandableVideoDescriptionBodyRenderer}) {
                $video_info->{description} //= eval { $desc_body->{descriptionBodyText}{runs}[0]{text} };
            }
        }
    }
}

sub _extract_description_header {
    my ($self, $desc, $video_info) = @_;

    # Extract like count from factoids
    if (ref($desc->{factoid}) eq 'ARRAY') {
        foreach my $factoid (@{$desc->{factoid}}) {
            next unless ref($factoid) eq 'HASH';
            
            if (my $likes_info = $factoid->{sentimentFactoidRenderer}) {
                $video_info->{likeCount} //= eval { (_human_number_to_int($likes_info->{factoidIfLiked}{factoidRenderer}{value}{runs}[0]{text}) // 0) - 1 };
                delete $video_info->{likeCount} if !defined($video_info->{likeCount}) || $video_info->{likeCount} <= 0;
            }
        }
    }

    $video_info->{author} //= eval { $desc->{channel}{runs}[0]{text} };
    $video_info->{publishDate} //= eval { $desc->{publishDate}{runs}[0]{text} };
    $video_info->{title} //= eval { $desc->{title}{runs}[0]{text} };
    $video_info->{viewCount} //= eval { _human_number_to_int($desc->{views}{runs}[0]{text} || 0) };
}

=head2 yt_search(q => $keyword, %args)

Search for videos given a keyword string (uri-escaped).

=cut

sub yt_search {
    my ($self, %args) = @_;

    my $url = $self->get_m_youtube_url . "/results";

    my %params = (
        hl => 'en',
        search_query => $args{q},
        sp => $self->_build_search_params(%args),
    );

    $url = $self->_append_url_args($url, %params);

    my $hash = $self->_get_initial_data($url) // return;
    my @results = $self->_extract_sectionList_results(
        eval { $hash->{contents}{sectionListRenderer} } // undef,
        %args
    );

    return $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 yt_channel_search($channel, q => $keyword, %args)

Search for videos given a keyword string from a channel ID or username.

=cut

sub yt_channel_search {
    my ($self, $channel, %args) = @_;
    
    my ($url, $hash) = $self->_channel_data($channel, %args, type => 'search', params => {query => $args{q}});
    return unless defined $hash;

    my @results = $self->_extract_sectionList_results($self->_find_sectionList($hash), %args, type => 'video');
    return $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 yt_channel_uploads($channel, %args)

Latest uploads for a given channel ID or username.

For popular videos, use: sort_by => 'popular'

=cut

sub yt_channel_uploads {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => 'videos');
    return $self->_extract_videos_from_channel_data($url, $hash, %args);
}

=head2 yt_channel_streams($channel, %args)

Latest streams for a given channel ID or username.

For popular streams, use: sort_by => 'popular'

=cut

sub yt_channel_streams {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => 'streams');
    return $self->_extract_videos_from_channel_data($url, $hash, %args);
}

=head2 yt_channel_shorts($channel, %args)

Latest short videos for a given channel ID or username.

For popular shorts, use: sort_by => 'popular'

=cut

sub yt_channel_shorts {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => 'shorts');
    return $self->_extract_videos_from_channel_data($url, $hash, %args);
}

=head2 yt_channel_info($channel, %args)

Channel info (such as title) for a given channel ID or username.

=cut

sub yt_channel_info {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => '');
    return $hash;
}

=head2 yt_channel_title($channel, %args)

Extract the channel title (as a string) for a given channel ID or username.

=cut

sub yt_channel_title {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => '');
    return unless defined $hash;
    
    my $header = $self->_extract_channel_header($hash, %args) // return;
    my $title = eval { $header->{title} };
    return $title;
}

=head2 yt_channel_id($username, %args)

Extract the channel ID (as a string) for a given channel username.

=cut

sub yt_channel_id {
    my ($self, $username, %args) = @_;
    my ($url, $hash) = $self->_channel_data($username, %args, type => '');
    return unless defined $hash;
    
    my $header = $self->_extract_channel_header($hash, %args) // return;
    my $id = eval { $header->{channelId} } // eval { $header->{externalId} };
    return $id;
}

=head2 yt_channel_created_playlists($channel, %args)

Playlists created by a given channel ID or username.

=cut

sub yt_channel_created_playlists {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => 'playlists', params => {view => 1});
    return unless defined $hash;

    my @results = $self->_extract_channel_playlists($hash, %args, type => 'playlist');
    return $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 yt_channel_all_playlists($channel, %args)

All playlists for a given channel ID or username.

=cut

sub yt_channel_all_playlists {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => 'playlists');
    return unless defined $hash;

    my @results = $self->_extract_channel_playlists($hash, %args, type => 'playlist');
    return $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 yt_playlist_videos($playlist_id, %args)

Videos from a given playlist ID.

=cut

sub yt_playlist_videos {
    my ($self, $playlist_id, %args) = @_;

    my $url = $self->_append_url_args($self->get_m_youtube_url . "/playlist", list => $playlist_id, hl => "en");
    my $hash = $self->_get_initial_data($url) // return;

    my @results = $self->_extract_sectionList_results($self->_find_sectionList($hash), %args, type => 'video');
    return $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 yt_playlist_next_page($url, $token, %args)

Load more items from a playlist, given a continuation token.

=cut

sub yt_playlist_next_page {
    my ($self, $url, $token, %args) = @_;

    my $request_url = $self->_append_url_args($url, ctoken => $token);
    my $hash = $self->_get_initial_data($request_url) // return;

    my @results = $self->_parse_itemSection(
        eval { $hash->{continuationContents}{playlistVideoListContinuation} }
        // eval { $hash->{continuationContents}{itemSectionContinuation} },
        %args
    );

    if (!@results) {
        @results = $self->_extract_sectionList_results(
            eval { $hash->{continuationContents}{sectionListContinuation} } // undef,
            %args
        );
    }

    $self->_add_author_to_results($hash, \@results, %args);
    return $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 yt_browse_request($url, $token, %args)

Make a browse request to the YouTube API with a continuation token.

=cut

sub yt_browse_request {
    my ($self, $url, $token, %args) = @_;

    my %request = (
        %{$self->_build_api_context($url)},
        continuation => $token,
    );

    my $api_url = $self->get_m_youtube_url . _unscramble('o/ebbrky?u1wi//evsuyto=e') . _unscramble('1HUCiSlOalFEcYQSS8_9q1LW4y8JAwI2zT_qA_G');
    my $content = $self->post_as_json($api_url, \%request) // return;

    my $hash = parse_json_string($content);

    my $res = eval { $hash->{continuationContents}{playlistVideoListContinuation} }
        // eval { $hash->{continuationContents}{itemSectionContinuation} }
        // $self->_extract_append_continuation($hash)
        // $self->_extract_reload_continuation($hash)
        // undef;

    my @results = $self->_parse_itemSection($res, %args);

    if (@results) {
        push @results, $self->_parse_itemSection_nextpage($res, %args);
    }

    if (!@results) {
        @results = $self->_extract_sectionList_results(
            eval { $hash->{continuationContents}{sectionListContinuation} } // $res,
            %args
        );
    }

    $self->_add_author_to_results($hash, \@results, %args);
    return $self->_prepare_results_for_return(\@results, %args, url => $url);
}

sub _extract_append_continuation {
    my ($self, $hash) = @_;
    my $v = eval { $hash->{onResponseReceivedActions}[0]{appendContinuationItemsAction}{continuationItems} };
    return defined($v) ? {contents => $v} : undef;
}

sub _extract_reload_continuation {
    my ($self, $hash) = @_;
    my $v = eval { $hash->{onResponseReceivedActions}[0]{reloadContinuationItemsCommand}{continuationItems} };
    return defined($v) ? {contents => $v} : undef;
}

=head2 yt_search_next_page($url, $token, %args)

Load more search results, given a continuation token.

=cut

sub yt_search_next_page {
    my ($self, $url, $token, %args) = @_;

    my %request = (
        %{$self->_build_api_context($url)},
        continuation => $token,
    );

    # Update client context for search
    $request{context}{client}{gl} = "US";
    $request{context}{client}{screenHeightPoints} = 600;

    my $api_url = $self->get_m_youtube_url . _unscramble('o/ebseky?u1ri//hvcuyta=e') . _unscramble('1HUCiSlOalFEcYQSS8_9q1LW4y8JAwI2zT_qA_G');
    my $content = $self->post_as_json($api_url, \%request) // return;

    my $hash = parse_json_string($content);

    my @results = $self->_extract_sectionList_results(
        {
            contents => eval { $hash->{onResponseReceivedCommands}[0]{appendContinuationItemsAction}{continuationItems} } // undef
        },
        %args
    );

    return $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::PipeViewer::InitialData

=head1 LICENSE AND COPYRIGHT

Copyright 2013-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<https://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::PipeViewer::InitialData
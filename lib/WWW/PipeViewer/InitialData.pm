package WWW::PipeViewer::InitialData;

use utf8;
use 5.014;
use warnings;

use MIME::Base64 qw(encode_base64url);
use List::Util   qw(pairs);

use WWW::PipeViewer::ParseJSON;
use WWW::PipeViewer::Proto;

=head1 NAME

WWW::PipeViewer::InitialData - Extract initial data.

=head1 SYNOPSIS

    use WWW::PipeViewer;
    my $obj = WWW::PipeViewer->new(%opts);

    my $results   = $obj->yt_search(q => $keywords);
    my $playlists = $obj->yt_channel_created_playlists($channel_ID);

=head1 SUBROUTINES/METHODS

=cut

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

    $hours * 3600 + $minutes * 60 + $seconds;
}

sub _human_number_to_int {
    my ($text) = @_;

    $text // return undef;

    # 7.6K -> 7600; 7.6M -> 7600000
    if ($text =~ /([\d,.]+)\s*([KMB])/i) {

        my $v = $1;
        my $u = $2;
        my $m = ($u eq 'K' ? 1e3 : ($u eq 'M' ? 1e6 : ($u eq 'B' ? 1e9 : 1)));

        $v =~ tr/,/./;

        return int($v * $m);
    }

    if ($text =~ /([\d,.]+)/) {
        my $v = $1;
        $v =~ tr/,.//d;
        return int($v);
    }

    return 0;
}

sub _fix_url_protocol {
    my ($url) = @_;

    $url // return undef;

    if ($url =~ m{^https://}) {    # ok
        return $url;
    }
    if ($url =~ s{^.*?//}{}) {
        return "https://" . $url;
    }
    if ($url =~ /^\w+\./) {
        return "https://" . $url;
    }

    return $url;
}

sub _unscramble {
    my ($str) = @_;

    my $i = my $l = length($str);

    $str =~ s/(.)(.{$i})/$2$1/sg while (--$i > 0);
    $str =~ s/(.)(.{$i})/$2$1/sg while (++$i < $l);

    return $str;
}

sub _extract_youtube_mix {
    my ($self, $data) = @_;

    my $info   = eval { $data->{callToAction}{watchCardHeroVideoRenderer} } || return;
    my $header = eval { $data->{header}{watchCardRichHeaderRenderer} };

    my %mix;

    $mix{type} = 'playlist';

    $mix{title} =
      eval    { $header->{title}{runs}[0]{text} }
      // eval { $info->{accessibility}{accessibilityData}{label} }
      // eval { $info->{callToActionButton}{callToActionButtonRenderer}{label}{runs}[0]{text} } // 'Youtube Mix';

    $mix{playlistId} = eval { $info->{navigationEndpoint}{watchEndpoint}{playlistId} } || return;

    $mix{playlistThumbnails} = _extract_thumbnails($header->{avatar}{thumbnails} // $info->{heroImage}{collageHeroImageRenderer}{leftThumbnail}{thumbnails});

    $mix{description} = _extract_description({title => $info});

    $mix{author}   = eval { $header->{title}{runs}[0]{text} }                              // "YouTube";
    $mix{authorId} = eval { $header->{titleNavigationEndpoint}{browseEndpoint}{browseId} } // "youtube";

    return \%mix;
}

sub _extract_video_id {
    my ($info) = @_;
         eval { $info->{videoId} }
      || eval { $info->{navigationEndpoint}{watchEndpoint}{videoId} }
      || eval { $info->{onTap}{innertubeCommand}{reelWatchEndpoint}{videoId} }
      || undef;
}

sub _extract_length_seconds {
    my ($info) = @_;
    eval { $info->{lengthSeconds} }
      || _time_to_seconds(eval { $info->{thumbnailOverlays}[0]{thumbnailOverlayTimeStatusRenderer}{text}{runs}[0]{text} } // 0)
      || _time_to_seconds(eval { $info->{lengthText}{runs}[0]{text} // 0 });
}

sub _extract_published_text {
    my ($info) = @_;

    my $text = eval { $info->{publishedTimeText}{runs}[0]{text} } || return undef;

    if ($text =~ /(\d+)\s+(\w+)/) {
        return "$1 $2 ago";
    }

    if ($text =~ /(\d+)\s*(\w+)/) {
        return "$1 $2 ago";
    }

    return $text;
}

sub _extract_author_name {
    my ($info) = @_;
#<<<
       eval { $info->{longBylineText}{runs}[0]{text} }
    // eval { $info->{shortBylineText}{runs}[0]{text} }
    // eval { ($info->{channelThumbnail}{channelThumbnailWithLinkRenderer}{navigationEndpoint}{commandMetadata}{webCommandMetadata}{url} // '') =~ s{.*/([^/]+)\z}{$1}r };
#>>>
}

sub _extract_channel_id {
    my ($info) = @_;
#<<<
         eval { $info->{channelId} }
      // eval { $info->{shortBylineText}{runs}[0]{navigationEndpoint}{browseEndpoint}{browseId} }
      // eval { $info->{navigationEndpoint}{browseEndpoint}{browseId} }
      // eval { $info->{channelThumbnail}{channelThumbnailWithLinkRenderer}{navigationEndpoint}{browseEndpoint}{browseId} };
#>>>
}

sub _extract_view_count_text {
    my ($info) = @_;
    eval { $info->{shortViewCountText}{runs}[0]{text} } // eval { $info->{overlayMetadata}{secondaryText}{content} }
}

sub _extract_view_count {
    my ($info) = @_;
#<<<
         _human_number_to_int(eval { $info->{viewCountText}{runs}[0]{text} } || 0)
      || _human_number_to_int(eval { ($info->{headline}{accessibility}{accessibilityData}{label} // '') =~ m{.* (\S+) views\b} ? $1 : undef } || 0)
      || _human_number_to_int(eval { $info->{shortViewCountText}{runs}[0]{text} } || 0)
      || _human_number_to_int(eval { ($info->{overlayMetadata}{secondaryText}{content} // '') =~ m{^(\S+) views\b} ? $1 : undef } || 0);
#>>>
}

sub _extract_thumbnails {
    my ($info) = @_;
    eval {
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
#<<<
         eval { $info->{title}{runs}[0]{text} }
      // eval { $info->{title}{accessibility}{accessibilityData}{label} }
      // eval { $info->{headline}{runs}[0]{text} }
      // eval { $info->{overlayMetadata}{primaryText}{content} };
#>>>
}

sub _extract_description {
    my ($info) = @_;

    # This is not the video description...
#<<<
         eval { $info->{title}{accessibility}{accessibilityData}{label} }
      // eval { $info->{headline}{accessibility}{accessibilityData}{label} }
      // eval { $info->{accessibilityText} };
#>>>
}

sub _extract_video_count {
    my ($info) = @_;
    _human_number_to_int(eval { $info->{videoCountShortText}{runs}[0]{text} } || eval { $info->{videoCountText}{runs}[0]{text} } || 0);
}

sub _extract_subscriber_count {
    my ($info) = @_;
    _human_number_to_int(eval { $info->{subscriberCountText}{runs}[0]{text} } || 0);
}

sub _extract_playlist_id {
    my ($info) = @_;
    eval { $info->{playlistId} };
}

sub _extract_itemSection_entry {
    my ($self, $data, %args) = @_;

    ref($data) eq 'HASH' or return;

    # Album
    if ($args{type} eq 'all' and exists $data->{horizontalCardListRenderer}) {    # TODO
        return;
    }

    # Video
    if (   exists($data->{compactVideoRenderer})
        or exists($data->{playlistVideoRenderer})
        or exists($data->{videoWithContextRenderer})) {

        my %video;
        my $info = $data->{compactVideoRenderer} // $data->{playlistVideoRenderer} // $data->{videoWithContextRenderer};

        $video{type} = 'video';

        # Deleted video
        if (defined(eval { $info->{isPlayable} }) and not $info->{isPlayable}) {
            return;
        }

        $video{videoId}         = _extract_video_id($info) // return;
        $video{title}           = _extract_title($info)    // return;
        $video{lengthSeconds}   = _extract_length_seconds($info) || 0;
        $video{liveNow}         = ($video{lengthSeconds} == 0);
        $video{author}          = _extract_author_name($info);
        $video{authorId}        = _extract_channel_id($info);
        $video{publishedText}   = _extract_published_text($info);
        $video{viewCountText}   = _extract_view_count_text($info);
        $video{videoThumbnails} = _extract_thumbnails($info->{thumbnail}{thumbnails});
        $video{description}     = _extract_description($info);
        $video{viewCount}       = _extract_view_count($info);

        # Filter out private/deleted videos from playlists
        if (exists($data->{playlistVideoRenderer})) {
            $video{author}   // return;
            $video{authorId} // return;
        }

        return \%video;
    }

    # Shorts
    if (exists($data->{shortsLockupViewModel})) {

        my %video;
        my $info = $data->{shortsLockupViewModel};

        $video{type} = 'video';

        $video{videoId}         = _extract_video_id($info) // return;
        $video{title}           = _extract_title($info)    // return;
        $video{lengthSeconds}   = _extract_length_seconds($info) || 0;                # FIXME
        $video{liveNow}         = ($video{lengthSeconds} == 0);                       # FIXME
        $video{author}          = _extract_author_name($info);
        $video{authorId}        = _extract_channel_id($info);
        $video{publishedText}   = _extract_published_text($info);                     # FIXME
        $video{viewCountText}   = _extract_view_count_text($info);
        $video{videoThumbnails} = _extract_thumbnails($info->{thumbnail}{sources});
        $video{description}     = _extract_description($info);
        $video{viewCount}       = _extract_view_count($info);

        return \%video;
    }

    # Playlist
    if ($args{type} ne 'video' and (exists($data->{compactPlaylistRenderer}) or exists($data->{playlistWithContextRenderer}))) {

        my %playlist;
        my $info = $data->{compactPlaylistRenderer} // $data->{playlistWithContextRenderer};

        $playlist{type} = 'playlist';

        $playlist{title}      = _extract_title($info)       // return;
        $playlist{playlistId} = _extract_playlist_id($info) // return;
        $playlist{author}     = _extract_author_name($info);
        $playlist{authorId}   = _extract_channel_id($info);
        $playlist{videoCount} = _extract_video_count($info);
        $playlist{playlistThumbnails} =
          _extract_thumbnails($info->{thumbnailRenderer}{playlistVideoThumbnailRenderer}{thumbnail}{thumbnails} // $info->{thumbnail}{thumbnails});
        $playlist{description} = _extract_description($info);

        return \%playlist;
    }

    # Channel
    if ($args{type} ne 'video' and (exists($data->{compactChannelRenderer}) or exists($data->{channelWithContextRenderer}))) {

        my %channel;
        my $info = $data->{compactChannelRenderer} // $data->{channelWithContextRenderer};

        $channel{type} = 'channel';

        $channel{author}           = _extract_title($info)      // return;
        $channel{authorId}         = _extract_channel_id($info) // return;
        $channel{subCount}         = _extract_subscriber_count($info);
        $channel{videoCount}       = _extract_video_count($info);
        $channel{authorThumbnails} = _extract_thumbnails($info->{thumbnail}{thumbnails});
        $channel{description}      = _extract_description($info);

        return \%channel;
    }

    return;
}

sub _parse_itemSection {
    my ($self, $data, %args) = @_;

    eval { ref($data->{contents}) eq 'ARRAY' } || return;

    my @results;

    foreach my $entry (@{$data->{contents}}) {

        my $item = $self->_extract_itemSection_entry($entry, %args);

        if (defined($item) and ref($item) eq 'HASH') {
            push @results, $item;
        }
    }

    if (exists($data->{continuations}) and ref($data->{continuations}) eq 'ARRAY') {

        my $token = eval { $data->{continuations}[0]{nextContinuationData}{continuation} };

        if (defined($token)) {
            push @results,
              scalar {
                      type  => 'nextpage',
                      token => "ytplaylist:$args{type}:"
                        . make_json_string(
                                           scalar {
                                                   token => $token,
                                                   args  => {},
                                                  }
                                          ),
                     };
        }
    }

    return @results;
}

sub _parse_itemSection_nextpage {
    my ($self, $entry, %args) = @_;

    eval { ref($entry->{contents}) eq 'ARRAY' } || return;

    foreach my $entry (@{$entry->{contents}}) {

        # Continuation page
        if (exists $entry->{continuationItemRenderer}) {

            my $info  = $entry->{continuationItemRenderer};
            my $token = eval { $info->{continuationEndpoint}{continuationCommand}{token} };

            if (defined($token)) {
                return
                  scalar {
                          type  => 'nextpage',
                          token => "ytbrowse:$args{type}:"
                            . make_json_string(
                                               scalar {
                                                       token => $token,
                                                       args  => {
                                                                (
                                                                 defined($args{author_name})
                                                                 ? (author_name => $args{author_name})
                                                                 : ()
                                                                )
                                                               },
                                                      }
                                              ),
                         };
            }
        }
    }

    return;
}

sub _extract_sectionList_results {
    my ($self, $data, %args) = @_;

    $data // return;
    ref($data) eq 'HASH' or return;
    $data->{contents} // return;
    ref($data->{contents}) eq 'ARRAY' or return;

    my @results;

    foreach my $entry (@{$data->{contents}}) {

        # Playlists
        if (eval { ref($entry->{shelfRenderer}{content}{verticalListRenderer}{items}) eq 'ARRAY' }) {
            my $res = {contents => $entry->{shelfRenderer}{content}{verticalListRenderer}{items}};
            push @results, $self->_parse_itemSection($res, %args);
            push @results, $self->_parse_itemSection_nextpage($res, %args);
            next;
        }

        # Playlist videos
        if (    eval { ref($entry->{itemSectionRenderer}{contents}[0]{playlistVideoListRenderer}) eq 'HASH' }
            and eval { ref($entry->{itemSectionRenderer}{contents}[0]{playlistVideoListRenderer}{contents}) eq 'ARRAY' }) {
            my $res = $entry->{itemSectionRenderer}{contents}[0]{playlistVideoListRenderer};
            push @results, $self->_parse_itemSection($res, %args);
            push @results, $self->_parse_itemSection_nextpage($res, %args, (@results ? (author_name => $results[-1]{author}) : ()));
            next;
        }

        # YouTube Mix
        if ($args{type} eq 'all' and exists $entry->{universalWatchCardRenderer}) {

            my $mix = $self->_extract_youtube_mix($entry->{universalWatchCardRenderer});

            if (defined($mix)) {
                push(@results, $mix);
            }
        }

        # Video results (v2)
        if (exists($entry->{richItemRenderer}) and ref($entry->{richItemRenderer}) eq 'HASH') {
            my $res = $entry->{richItemRenderer}{content};
            push @results, $self->_parse_itemSection({contents => [$res]}, %args);
            push @results, $self->_parse_itemSection_nextpage($res, %args);
        }

        # Video results
        if (exists $entry->{itemSectionRenderer}) {
            my $res = $entry->{itemSectionRenderer};
            push @results, $self->_parse_itemSection($res, %args);
            push @results, $self->_parse_itemSection_nextpage($res, %args);
        }

        # Continuation page
        if (exists $entry->{continuationItemRenderer}) {

            my $info  = $entry->{continuationItemRenderer};
            my $token = eval { $info->{continuationEndpoint}{continuationCommand}{token} };
            my $type  = eval { $info->{continuationEndpoint}{commandMetadata}{webCommandMetadata}{apiUrl} };

            if (defined($token)) {
                if ($type =~ m{/browse\z}) {

                    push @results,
                      scalar {
                              type  => 'nextpage',
                              token => "ytbrowse:$args{type}:"
                                . make_json_string(
                                                   scalar {
                                                           token => $token,
                                                           args  => {},
                                                          }
                                                  ),
                             };
                }
                else {
                    push @results,
                      scalar {
                              type  => 'nextpage',
                              token => "ytsearch:$args{type}:"
                                . make_json_string(
                                                   scalar {
                                                           token => $token,
                                                           args  => {},
                                                          }
                                                  )
                             };
                }
            }
        }
    }

    if (@results and exists $data->{continuations}) {
        push @results, $self->_parse_itemSection($data, %args);
    }

    return @results;
}

sub _extract_channel_header {
    my ($self, $data, %args) = @_;
    eval { $data->{header}{c4TabbedHeaderRenderer} } // eval { $data->{metadata}{channelMetadataRenderer} };
}

sub _extract_channel_tabs {
    my ($self, $hash) = @_;

    my %channel_tabs;
    my $section_list = $self->_find_sectionList($hash);

    if (defined($section_list) and ref($section_list) eq 'HASH' and exists($section_list->{header})) {
        my $header = $section_list->{header};
        if (ref($header) eq 'HASH' and exists($header->{feedFilterChipBarRenderer})) {
            my $chip_bar = $header->{feedFilterChipBarRenderer};
            if (ref($chip_bar) eq 'HASH' and exists($chip_bar->{contents}) and ref($chip_bar->{contents}) eq 'ARRAY') {
                foreach my $entry (@{$chip_bar->{contents}}) {
                    ref($entry) eq 'HASH' or next;
                    my $item = $entry->{chipCloudChipRenderer} // next;
                    ref($item) eq 'HASH' or next;
                    my $text = $item->{text} // next;
                    if (ref($text) eq 'HASH') {
                        $text = $text->{simpleText} // next;
                    }
                    $channel_tabs{$text} = {%$item};
                }
            }
        }
    }

    return %channel_tabs;
}

sub _extract_videos_from_channel_data {
    my ($self, $url, $hash, %args) = @_;

    $hash // return;

    my @results     = $self->_extract_channel_uploads($hash, %args, type => 'video');
    my $author_name = @results ? $results[0]->{author} : undef;

    # Popular videos
    if (defined($args{sort_by}) and $args{sort_by} eq 'popular') {
        my %channel_tabs = $self->_extract_channel_tabs($hash);
        foreach my $key (keys %channel_tabs) {
            $key =~ /popular/i or next;
            my $value = $channel_tabs{$key};
            ref($value) eq 'HASH' or next;
            my $token          = eval { $value->{navigationEndpoint}{continuationCommand}{token} } // next;
            my $popular_videos = $self->yt_browse_request($url, $token, %args, type => 'video', author_name => $author_name);
            return $popular_videos;
        }
    }

    $self->_prepare_results_for_return(\@results, %args, url => $url);
}

sub _add_author_to_results {
    my ($self, $data, $results, %args) = @_;

    my $header = $self->_extract_channel_header($data, %args);

    my $channel_id   = eval { $header->{channelId} } // eval { $header->{externalId} };
    my $channel_name = eval { $header->{title} }     // $args{author_name};

    if (not defined($channel_id)) {
        if (eval { ref($data->{responseContext}{serviceTrackingParams}) eq 'ARRAY' }) {
            foreach my $entry (@{$data->{responseContext}{serviceTrackingParams}}) {
                ref($entry) eq 'HASH' or next;
                if (exists($entry->{params}) and ref($entry->{params}) eq 'ARRAY') {
                    foreach my $param (@{$entry->{params}}) {
                        if (($param->{key} // '') eq 'browse_id') {
                            $channel_id = $param->{value};
                            last;
                        }
                    }
                }
            }
        }
    }

    $channel_name //= $channel_id;

    foreach my $result (@$results) {
        if (ref($result) eq 'HASH') {
            $result->{author}   = $channel_name if defined($channel_name);
            $result->{authorId} = $channel_id   if defined($channel_id);
        }
    }

    if (@$results and defined($channel_name) and $results->[-1]{type} eq 'nextpage') {
        my $token = $results->[-1]{token};
        if (defined($token) and $token =~ /^ytbrowse:(\w+):(.*)/s) {

            my $type = $1;
            my $json = $2;

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

    $data // return undef;
    ref($data) eq 'HASH' or return undef;

    if (exists($data->{alerts})) {
        if (
            ref($data->{alerts}) eq 'ARRAY' and grep {
                eval { $_->{alertRenderer}{type} =~ /error/i }
            } @{$data->{alerts}}
          ) {
            return undef;
        }
    }

    if (not exists $data->{contents}) {
        return undef;
    }

    my $section = (
        eval {
            (
             grep {
                 eval { exists($_->{tabRenderer}{content}{sectionListRenderer}{contents}) }
             } @{$data->{contents}{singleColumnBrowseResultsRenderer}{tabs}}
            )[0]{tabRenderer}{content}{sectionListRenderer};
        } // eval {
            (
             grep {
                 eval { exists($_->{tabRenderer}{content}{richGridRenderer}{contents}) }
             } @{$data->{contents}{singleColumnBrowseResultsRenderer}{tabs}}
            )[0]{tabRenderer}{content}{richGridRenderer};
          } // undef
    );

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

sub _get_initial_data {
    my ($self, $url) = @_;

    $self->get_prefer_invidious() and return;

    my $content = $self->lwp_get($url) // return;

    if ($content =~ m{var\s+ytInitialData\s*=\s*'(.*?)'}is) {
        my $json = $1;

        $json =~ s{\\x([[:xdigit:]]{2})}{chr(hex($1))}ge;
        $json =~ s{\\u([[:xdigit:]]{4})}{chr(hex($1))}ge;
        $json =~ s{\\(["&<>])}{$1}g;

        my $hash = parse_utf8_json_string($json);
        return $hash;
    }

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

    # This no longer works
    if (defined(my $sort = $args{sort_by})) {
        if ($sort eq 'popular') {
            $params{sort} = 'p';
        }
        elsif ($sort eq 'old') {
            $params{sort} = 'da';
        }
    }

    if (exists($args{params}) and ref($args{params}) eq 'HASH') {
        %params = (%params, %{$args{params}});
    }

    $url = $self->_append_url_args($url, %params);
    my $result = $self->_get_initial_data($url);

    # When /c/ failed, try /user/
    if ((!defined($result) or !scalar(keys %$result)) and $url =~ s{/c/}{/user/}) {
        $result = $self->_get_initial_data($url);
    }

    ($url, $result);
}

sub _prepare_results_for_return {
    my ($self, $results, %args) = @_;

    (defined($results) and ref($results) eq 'ARRAY') || return;

    my @results = @$results;

    @results || return;

    if (@results and $results[-1]{type} eq 'nextpage') {

        my $nextpage = pop(@results);

        if (defined($nextpage->{token}) and @results) {

            if ($self->get_debug) {
                say STDERR ":: Returning results with a continuation page token...";
            }

            return {
                    url     => $args{url},
                    results => {
                                entries      => \@results,
                                continuation => $nextpage->{token},
                               },
                   };
        }
    }

    my $url = $args{url};

    if ($url =~ m{^https://m\.youtube\.com}) {
        $url = undef;
    }

    return {
            url     => $url,
            results => \@results,
           };
}

=head2 yt_video_info($id)

Get video info for a given YouTube video ID, by scrapping the YouTube C<watch> page.

=cut

sub yt_video_info {
    my ($self, %args) = @_;

    my $url = $self->get_m_youtube_url . "/watch";

    my %params = (
                  hl => 'en',
                  v  => $args{id},
                 );

    $url = $self->_append_url_args($url, %params);
    my $hash = $self->_get_initial_data($url) // return;

    ref($hash) eq 'HASH' or return;

    my %video_info;

    if (ref(my $metadata = eval { $hash->{contents}{singleColumnWatchNextResults}{results}{results}{contents} }) eq 'ARRAY') {

        foreach my $entry (@$metadata) {

            ref($entry) eq 'HASH' or next;

            if (ref(my $section = eval { $entry->{slimVideoMetadataSectionRenderer}{contents} }) eq 'ARRAY') {
                foreach my $part (@$section) {
                    ref($part) eq 'HASH' or next;

                    if (my $info = $part->{slimVideoInformationRenderer}) {
                        $video_info{title} = eval { $info->{title}{runs}[0]{text} };
                    }

                    if (ref(my $buttons = $part->{slimVideoActionBarRenderer}{buttons}) eq 'ARRAY') {
                        foreach my $toggle_button (@$buttons) {

                            ref($toggle_button) eq 'HASH' or next;
                            my $button = $toggle_button->{slimMetadataToggleButtonRenderer};

                            if (    ref($button) eq 'HASH'
                                and $button->{isLike}
                                and ref(my $like_button = eval { $button->{button}{toggleButtonRenderer} }) eq 'HASH') {

                                $video_info{likeCount} = eval { _human_number_to_int($like_button->{defaultText}{accessibility}{accessibilityData}{label}); }
                                  // eval { (_human_number_to_int($like_button->{toggledText}{accessibility}{accessibilityData}{label}) // 0) - 1; };

                                if (not defined($video_info{likeCount}) or $video_info{likeCount} <= 0) {
                                    delete $video_info{likeCount};
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    my $engagements = $hash->{engagementPanels} // return \%video_info;
    ref($engagements) eq 'ARRAY' or return \%video_info;

    foreach my $entry (@$engagements) {

        ref($entry) eq 'HASH' or next;

        if (ref(my $main_info = eval { $entry->{engagementPanelSectionListRenderer}{content}{structuredDescriptionContentRenderer}{items} }) eq 'ARRAY') {

            foreach my $entry (@$main_info) {

                ref($entry) eq 'HASH' or next;

                if (my $desc = $entry->{videoDescriptionHeaderRenderer}) {

                    if (ref($desc->{factoid}) eq 'ARRAY') {
                        foreach my $factoid (@{$desc->{factoid}}) {
                            ref($factoid) eq 'HASH' or next;
                            if (my $likes_info = $factoid->{sentimentFactoidRenderer}) {

                                $video_info{likeCount} //=
                                  eval { (_human_number_to_int($likes_info->{factoidIfLiked}{factoidRenderer}{value}{runs}[0]{text}) // 0) - 1; };

                                if (not defined($video_info{likeCount}) or $video_info{likeCount} <= 0) {
                                    delete $video_info{likeCount};
                                }
                            }
                        }
                    }

                    $video_info{author}      //= eval { $desc->{channel}{runs}[0]{text} };
                    $video_info{publishDate} //= eval { $desc->{publishDate}{runs}[0]{text} };
                    $video_info{title}       //= eval { $desc->{title}{runs}[0]{text} };
                    $video_info{viewCount}   //= eval { _human_number_to_int($desc->{views}{runs}[0]{text} || 0) };
                }

                if (my $desc_body = $entry->{expandableVideoDescriptionBodyRenderer}) {
                    $video_info{description} //= eval { $desc_body->{descriptionBodyText}{runs}[0]{text} };
                }
            }
        }
    }

    return \%video_info;
}

my %_DATE = (
             'anytime' => 0,
             'hour'    => 1,
             'today'   => 2,
             'week'    => 3,
             'month'   => 4,
             'year'    => 5,
            );

my %_DURATION = (
                 'any'     => 0,
                 'short'   => 1,
                 'long'    => 2,
                 'average' => 3,
                );

my %_FEATURES = (
                 'hd'               => 4,
                 'subtitles'        => 5,
                 'creative_commons' => 6,
                 '3d'               => 7,
                 'live'             => 8,
                 '4k'               => 14,
                 '360'              => 15,
                 'hdr'              => 25,
                 'vr180'            => 26,
                );

my %_ORDER = (
              'relevance'   => 0,
              'rating'      => 1,
              'upload_date' => 2,
              'view_count'  => 3,
             );

my %_TYPE = (
             'all'      => 0,
             'video'    => 1,
             'channel'  => 2,
             'playlist' => 3,
             'movie'    => 4,
            );

=head2 yt_search(q => $keyword, %args)

Search for videos given a keyword string (uri-escaped).

=cut

sub yt_search {
    my ($self, %args) = @_;

    my $url = $self->get_m_youtube_url . "/results";

    my %params = (
                  hl           => 'en',
                  search_query => $args{q},
                 );

    my @sp;

    push @sp, proto_uint(1, $_ORDER{$self->get_order // 'relevance'});

    # Filtering.
    {
        my @filters;

        push @filters, proto_uint(1, $_DATE{$self->get_date              // 'anytime'});
        push @filters, proto_uint(2, $_TYPE{$args{type}                  // 'video'});
        push @filters, proto_uint(3, $_DURATION{$self->get_videoDuration // 'any'});

        foreach my $feat (@{$self->get_features || []}) {
            push @filters, proto_uint($_FEATURES{$feat}, 1);
        }

        push @sp, proto_nested(2, @filters);
    }

    # Paging.
    {
        my $page  = $self->get_page;
        my $count = $self->get_maxResults;

        # Asking for less than 20 maximum results breaks paging:
        # e.g. with `$page=1` and `$count=5` the next page link
        # will return result 20-25, instead 5-10.
        if ($count < 20) {
            $count = 20;
        }

        if ($page > 1) {
            push @sp, proto_uint(9, ($page - 1) * $count);
        }

        push @sp, proto_uint(10, $count);
    }

    $params{sp} = encode_base64url(pack('C*', @sp));

    $url = $self->_append_url_args($url, %params);

    my $hash    = $self->_get_initial_data($url) // return;
    my @results = $self->_extract_sectionList_results(eval { $hash->{contents}{sectionListRenderer} } // undef, %args);

    $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 yt_channel_search($channel, q => $keyword, %args)

Search for videos given a keyword string (uri-escaped) from a given channel ID or username.

=cut

sub yt_channel_search {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => 'search', params => {query => $args{q}});

    $hash // return;

    my @results = $self->_extract_sectionList_results($self->_find_sectionList($hash), %args, type => 'video');
    $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 yt_channel_uploads($channel, %args)

Latest uploads for a given channel ID or username.

Additionally, for getting the popular videos, call the function with the arguments:

    sort_by => 'popular',

=cut

sub yt_channel_uploads {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => 'videos');
    $self->_extract_videos_from_channel_data($url, $hash, %args);
}

=head2 yt_channel_streams($channel, %args)

Latest streams for a given channel ID or username.

Additionally, for getting the popular streams, call the function with the arguments:

    sort_by => 'popular',

=cut

sub yt_channel_streams {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => 'streams');
    $self->_extract_videos_from_channel_data($url, $hash, %args);
}

=head2 yt_channel_shorts($channel, %args)

Latest short videos for a given channel ID or username.

Additionally, for getting the popular short videos, call the function with the arguments:

    sort_by => 'popular',

=cut

sub yt_channel_shorts {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => 'shorts');
    $self->_extract_videos_from_channel_data($url, $hash, %args);
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

Exact the channel title (as a string) for a given channel ID or username.

=cut

sub yt_channel_title {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => '');
    $hash // return;
    my $header = $self->_extract_channel_header($hash, %args) // return;
    my $title  = eval { $header->{title} };
    return $title;
}

=head2 yt_channel_id($username, %args)

Exact the channel ID (as a string) for a given channel username.

=cut

sub yt_channel_id {
    my ($self, $username, %args) = @_;
    my ($url, $hash) = $self->_channel_data($username, %args, type => '');
    $hash // return;
    my $header = $self->_extract_channel_header($hash, %args) // return;
    my $id     = eval { $header->{channelId} }                // eval { $header->{externalId} };
    return $id;
}

=head2 yt_channel_created_playlists($channel, %args)

Playlists created by a given channel ID or username.

=cut

sub yt_channel_created_playlists {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => 'playlists', params => {view => 1});

    $hash // return;

    my @results = $self->_extract_channel_playlists($hash, %args, type => 'playlist');
    $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 yt_channel_all_playlists($channel, %args)

All playlists for a given channel ID or username.

=cut

sub yt_channel_all_playlists {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => 'playlists');

    $hash // return;

    my @results = $self->_extract_channel_playlists($hash, %args, type => 'playlist');
    $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 yt_playlist_videos($playlist_id, %args)

Videos from a given playlist ID.

=cut

sub yt_playlist_videos {
    my ($self, $playlist_id, %args) = @_;

    my $url  = $self->_append_url_args($self->get_m_youtube_url . "/playlist", list => $playlist_id, hl => "en");
    my $hash = $self->_get_initial_data($url) // return;

    my @results = $self->_extract_sectionList_results($self->_find_sectionList($hash), %args, type => 'video');
    $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 yt_playlist_next_page($url, $token, %args)

Load more items from a playlist, given a continuation token.

=cut

sub yt_playlist_next_page {
    my ($self, $url, $token, %args) = @_;

    my $request_url = $self->_append_url_args($url, ctoken => $token);
    my $hash        = $self->_get_initial_data($request_url) // return;

    my @results =
      $self->_parse_itemSection(eval { $hash->{continuationContents}{playlistVideoListContinuation} }
                                             // eval { $hash->{continuationContents}{itemSectionContinuation} },
                                %args);

    if (!@results) {
        @results =
          $self->_extract_sectionList_results(eval { $hash->{continuationContents}{sectionListContinuation} } // undef, %args);
    }

    $self->_add_author_to_results($hash, \@results, %args);
    $self->_prepare_results_for_return(\@results, %args, url => $url);
}

sub yt_browse_request {
    my ($self, $url, $token, %args) = @_;

    my %request = (
                   context => {
                               client => {
                                          browserName      => "Firefox",
                                          browserVersion   => "136.0",
                                          clientFormFactor => "LARGE_FORM_FACTOR",
                                          clientName       => "MWEB",
                                          clientVersion    => "2.20250314.01.00",
                                          deviceMake       => "Mozilla",
                                          deviceModel      => "Firefox for Android",
                                          hl               => "en",
                                          mainAppWebInfo   => {
                                                             graftUrl => $url,
                                                            },
                                          originalUrl        => $url,
                                          osName             => "Android",
                                          osVersion          => "16",
                                          platform           => "MOBILE",
                                          playerType         => "UNIPLAYER",
                                          screenDensityFloat => 1,
                                          screenHeightPoints => 500,
                                          screenPixelDensity => 1,
                                          screenWidthPoints  => 1800,
                                          timeZone           => "UTC",
                                          userAgent          => "Mozilla/5.0 (Android 16 Beta 2; Mobile; rv:136.0) Gecko/136.0 Firefox/136.0,gzip(gfe)",
                                          userInterfaceTheme => "USER_INTERFACE_THEME_LIGHT",
                                          utcOffsetMinutes   => 0,
                                         },
                               request => {
                                           consistencyTokenJars    => [],
                                           internalExperimentFlags => [],
                                          },
                               user => {},
                              },
                   continuation => $token,
                  );

    my $content =
      $self->post_as_json($self->get_m_youtube_url . _unscramble('o/ebbrky?u1wi//evsuyto=e') . _unscramble('1HUCiSlOalFEcYQSS8_9q1LW4y8JAwI2zT_qA_G'),
                          \%request) // return;

    my $hash = parse_json_string($content);

    my $res = eval { $hash->{continuationContents}{playlistVideoListContinuation} } // eval { $hash->{continuationContents}{itemSectionContinuation} } // do {
        my $v = eval { $hash->{onResponseReceivedActions}[0]{appendContinuationItemsAction}{continuationItems} };
        defined($v) ? scalar {contents => $v} : undef;
      }
      // do {
        my $v = eval { $hash->{onResponseReceivedActions}[0]{reloadContinuationItemsCommand}{continuationItems} };
        defined($v) ? scalar {contents => $v} : undef;
      }
      // undef;

    my @results = $self->_parse_itemSection($res, %args);

    if (@results) {
        push @results, $self->_parse_itemSection_nextpage($res, %args);
    }

    if (!@results) {
        @results =
          $self->_extract_sectionList_results(eval { $hash->{continuationContents}{sectionListContinuation} } // $res, %args);
    }

    $self->_add_author_to_results($hash, \@results, %args);
    $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 yt_search_next_page($url, $token, %args)

Load more search results, given a continuation token.

=cut

sub yt_search_next_page {
    my ($self, $url, $token, %args) = @_;

    my %request = (
                   "context" => {
                                 "client" => {
                                              "browserName"      => "Firefox",
                                              "browserVersion"   => "136.0",
                                              "clientFormFactor" => "LARGE_FORM_FACTOR",
                                              "clientName"       => "MWEB",
                                              "clientVersion"    => "2.20250314.01.00",
                                              "deviceMake"       => "Mozilla",
                                              "deviceModel"      => "Firefox for Android",
                                              "gl"               => "US",
                                              "hl"               => "en",
                                              "mainAppWebInfo"   => {
                                                                   "graftUrl" => $url,
                                                                  },
                                              "osName"             => "Android",
                                              "osVersion"          => "16",
                                              "platform"           => "MOBILE",
                                              "playerType"         => "UNIPLAYER",
                                              "screenDensityFloat" => 1,
                                              "screenHeightPoints" => 600,
                                              "screenPixelDensity" => 1,
                                              "screenWidthPoints"  => 1800,
                                              "userAgent"          => "Mozilla/5.0 (Android 16 Beta 2; Mobile; rv:136.0) Gecko/136.0 Firefox/136.0,gzip(gfe)",
                                              "userInterfaceTheme" => "USER_INTERFACE_THEME_LIGHT",
                                              "utcOffsetMinutes"   => 0,
                                             },
                                 "request" => {
                                               "consistencyTokenJars"    => [],
                                               "internalExperimentFlags" => [],
                                              },
                                 "user" => {}
                                },
                   "continuation" => $token,
                  );

    my $content =
      $self->post_as_json($self->get_m_youtube_url . _unscramble('o/ebseky?u1ri//hvcuyta=e') . _unscramble('1HUCiSlOalFEcYQSS8_9q1LW4y8JAwI2zT_qA_G'),
                          \%request) // return;

    my $hash = parse_json_string($content);

    my @results = $self->_extract_sectionList_results(
                                                      scalar {
                                                            contents =>
                                                              eval { $hash->{onResponseReceivedCommands}[0]{appendContinuationItemsAction}{continuationItems}; }
                                                              // undef
                                                             },
                                                      %args
                                                     );

    $self->_prepare_results_for_return(\@results, %args, url => $url);
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

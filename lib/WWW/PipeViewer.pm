package WWW::PipeViewer;

use utf8;
use 5.016;
use warnings;

use Memoize qw(memoize);
use WWW::PipeViewer::ParseJSON;

our $VERSION = '0.5.6';

# ============================================================================
# MEMOIZATION SETUP
# ============================================================================

use Memoize::Expire;
tie my %_INTERNAL_CACHE => 'Memoize::Expire',
    LIFETIME => 600,
    NUM_USES => 3;

memoize '_get_youtubei_content', SCALAR_CACHE => [HASH => \%_INTERNAL_CACHE];
memoize '_info_from_ytdl',       SCALAR_CACHE => [HASH => \%_INTERNAL_CACHE];
memoize '_ytdl_is_available';

# ============================================================================
# INHERITANCE
# ============================================================================

use parent qw(
    WWW::PipeViewer::InitialData
    WWW::PipeViewer::Search
    WWW::PipeViewer::Videos
    WWW::PipeViewer::Channels
    WWW::PipeViewer::Playlists
    WWW::PipeViewer::ParseJSON
    WWW::PipeViewer::PlaylistItems
    WWW::PipeViewer::CommentThreads
    WWW::PipeViewer::VideoCategories
);

use WWW::PipeViewer::Utils;

# ============================================================================
# CONFIGURATION & VALIDATION
# ============================================================================

my %valid_options = (
    # Main options
    v          => {valid => q[],                                           default => 3},
    page       => {valid => qr/^(?!0+\z)\d+\z/,                            default => 1},
    http_proxy => {valid => qr/./,                                         default => undef},
    maxResults => {valid => [1 .. 50],                                     default => 10},
    order      => {valid => [qw(relevance rating upload_date view_count)], default => 'relevance'},
    date       => {valid => [qw(anytime hour today week month year)],      default => 'anytime'},
    channelId  => {valid => qr/^[-\w]{2,}\z/,                              default => undef},

    # Video only options
    videoDuration => {valid => [qw(short average long)], default => undef},
    features      => {
        valid => sub {
            my ($array_ref) = @_;
            my @supported = qw(360 3d 4k subtitles creative_commons hd hdr live vr180);
            my %lookup;
            @lookup{@supported} = ();
            foreach my $item (@$array_ref) {
                exists($lookup{$item}) or return 0;
            }
            return 1;
        },
        default => undef
    },
    region => {valid => qr/^[A-Z]{2}\z/i, default => undef},

    comments_order => {valid => [qw(top new)], default => 'top'},

    # Misc
    debug       => {valid => [0 .. 3],   default => 0},
    timeout     => {valid => qr/^\d+\z/, default => 10},
    config_dir  => {valid => qr/^./,     default => q{.}},
    cache_dir   => {valid => qr/^./,     default => q{.}},
    cookie_file => {valid => qr/^./,     default => undef},

    # Support for yt-dlp / youtube-dl
    ytdl     => {valid => [1, 0], default => 1},
    ytdl_cmd => {valid => qr/\w/,  default => "yt-dlp"},

    # yt-dlp comment options
    ytdlp_comments     => {valid => [1, 0],             default => 0},
    ytdlp_max_comments => {valid => qr/^\d+\z/,         default => 50},
    ytdlp_max_replies  => {valid => qr/^(?:\d+|all)\z/, default => 0},

    # Booleans
    env_proxy                  => {valid => [1, 0], default => 1},
    escape_utf8                => {valid => [1, 0], default => 0},
    prefer_mp4                 => {valid => [1, 0], default => 0},
    prefer_av1                 => {valid => [1, 0], default => 0},
    prefer_invidious           => {valid => [1, 0], default => 0},
    force_fallback             => {valid => [1, 0], default => 0},
    bypass_age_gate_native     => {valid => [1, 0], default => 0},
    bypass_age_gate_with_proxy => {valid => [1, 0], default => 0},
    dislikes_api               => {valid => [1, 0], default => 0},
    skip_youtube_extraction    => {valid => [1, 0], default => 0},

    api_host => {valid => qr/\w/, default => "auto"},

    # No input value allowed
    api_path         => {valid => q[], default => '/api/v1/'},
    www_content_type => {valid => q[], default => 'application/x-www-form-urlencoded'},
    m_youtube_url    => {valid => q[], default => 'https://m.youtube.com'},
    youtubei_url     => {valid => q[], default => 'https://youtubei.googleapis.com/youtubei/v1/%s?key=' . reverse("8Wcq11_9Y_wliCGLHETS4Q8UqlS2JF_OAySazIA")},
    user_agent       => {valid => qr/^.{5}/, default => 'Mozilla/5.0 (Android 16 Beta 2; Mobile; rv:136.0) Gecko/136.0 Firefox/136.0,gzip(gfe)'},
);

# ============================================================================
# CONSTRUCTOR & ACCESSORS
# ============================================================================

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;

    foreach my $key (keys %valid_options) {
        if (exists $opts{$key}) {
            my $method = "set_$key";
            $self->$method(delete $opts{$key});
        }
    }

    foreach my $invalid_key (keys %opts) {
        warn "Invalid key: '${invalid_key}'";
    }

    return $self;
}

# Auto-generate getters and setters
{
    no strict 'refs';

    foreach my $key (keys %valid_options) {
        if (ref($valid_options{$key}{valid})) {
            *{__PACKAGE__ . '::set_' . $key} = sub {
                my ($self, $value) = @_;
                $self->{$key} = _our_smartmatch($value, $valid_options{$key}{valid})
                    ? $value
                    : $valid_options{$key}{default};
            };
        }

        *{__PACKAGE__ . '::get_' . $key} = sub {
            my ($self) = @_;
            if (not exists $self->{$key}) {
                return ($self->{$key} = $valid_options{$key}{default});
            }
            $self->{$key};
        };
    }
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

sub _our_smartmatch {
    my ($value, $arg) = @_;

    $value // return 0;

    if (not ref($arg)) {
        return ($value eq $arg);
    }

    if (ref($arg) eq ref(qr//)) {
        return scalar($value =~ $arg);
    }

    if (ref($arg) eq 'ARRAY') {
        foreach my $item (@$arg) {
            return 1 if __SUB__->($value, $item);
        }
    }

    if (ref($arg) eq 'CODE') {
        return $arg->($value);
    }

    return 0;
}

sub basic_video_info_fields {
    join(',', qw(
        title videoId description descriptionHtml published publishedText
        viewCount likeCount genre author authorId lengthSeconds rating liveNow
    ));
}

sub extra_video_info_fields {
    my ($self) = @_;
    join(',', $self->basic_video_info_fields, qw(
        subCountText captions isFamilyFriendly
    ));
}

sub page_token {
    my ($self) = @_;
    my $page = $self->get_page;
    return undef if ($page == 1);
    return $page;
}

sub escape_string {
    my ($self, $string) = @_;
    require URI::Escape;
    $self->get_escape_utf8
        ? URI::Escape::uri_escape_utf8($string)
        : URI::Escape::uri_escape($string);
}

sub list_to_url_arguments {
    my ($self, %args) = @_;
    join(q{&}, map { "$_=$args{$_}" } grep { defined $args{$_} } sort keys %args);
}

sub _append_url_args {
    my ($self, $url, %args) = @_;
    %args ? ($url . ($url =~ /\?/ ? '&' : '?') . $self->list_to_url_arguments(%args)) : $url;
}

sub default_arguments {
    my ($self, %args) = @_;
    my %defaults = (hl => 'en-US', %args);
    $self->list_to_url_arguments(%defaults);
}

# ============================================================================
# LWP USER AGENT SETUP
# ============================================================================

sub set_lwp_useragent {
    my ($self) = @_;

    my $lwp = (
        eval { require LWP::UserAgent::Cached; 'LWP::UserAgent::Cached' }
        // do { require LWP::UserAgent; 'LWP::UserAgent' }
    );

    my $agent = $lwp->new(
        cookie_jar    => {},
        timeout       => $self->get_timeout,
        show_progress => $self->get_debug,
        agent         => $self->get_user_agent,
        ssl_opts      => {verify_hostname => 1},
        $self->_get_cache_options($lwp),
        env_proxy     => (defined($self->get_http_proxy) ? 0 : $self->get_env_proxy),
    );

    $self->_configure_agent($agent);
    $self->_setup_cookies($agent);

    push @{$agent->requests_redirectable}, 'POST';
    $self->{lwp} = $agent;
    return $agent;
}

sub _get_cache_options {
    my ($self, $lwp) = @_;

    return () unless $lwp eq 'LWP::UserAgent::Cached';

    return (
        cache_dir  => $self->get_cache_dir,
        nocache_if => sub {
            my ($response) = @_;
            my $code = $response->code;
            $code >= 300
                or $response->request->method ne 'GET'
                or (($response->header('cache-control') // '') =~ /\b(?:max-age=0|no-store|no-cache)\b/)
                or (($response->header('content-type') // '') =~ /\b(?:audio|image|video)\b/);
        },
        recache_if => sub {
            my ($response, $path) = @_;
            not($response->is_fresh) or ($response->code == 404 && -M $path > 1);
        }
    );
}

sub _configure_agent {
    my ($self, $agent) = @_;

    require LWP::ConnCache;
    state $cache = LWP::ConnCache->new;
    $cache->total_capacity(undef);
    $agent->conn_cache($cache);

    state $accepted_encodings = do {
        require HTTP::Message;
        HTTP::Message::decodable();
    };

    $agent->ssl_opts(Timeout => $self->get_timeout);
    $agent->default_header(
        'Accept-Encoding'           => $accepted_encodings,
        'Accept'                    => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language'           => 'en-US,en;q=0.5',
        'Connection'                => 'keep-alive',
        'Upgrade-Insecure-Requests' => '1'
    );

    $agent->proxy(['http', 'https'], $self->get_http_proxy) if defined($self->get_http_proxy);
}

sub _setup_cookies {
    my ($self, $agent) = @_;

    my $cookie_file = $self->get_cookie_file;

    if (defined($cookie_file) and -f $cookie_file) {
        if ($self->get_debug) {
            say STDERR ":: Using cookies from: $cookie_file";
        }

        require HTTP::Cookies::Netscape;
        my $cookies = HTTP::Cookies::Netscape->new(
            hide_cookie2 => 1,
            autosave     => 1,
            file         => $cookie_file,
        );
        $cookies->load;
        $agent->cookie_jar($cookies);
    }
    else {
        require HTTP::Cookies;
        my $cookies = HTTP::Cookies->new();
        $self->_set_default_cookies($cookies);
        $agent->cookie_jar($cookies);
    }
}

sub _set_default_cookies {
    my ($self, $cookies) = @_;

    my $rand_value = '17' . join('', map { int(rand(10)) } 1 .. 8);

    $cookies->set_cookie(0, "CONSENT", "PENDING+233", "/", ".youtube.com", undef, 0, 1, $rand_value, 0, {});
    $cookies->set_cookie(0, "PREF", "tz=UTC", "/", ".youtube.com", undef, 0, 1, $rand_value, 0, {});
    $cookies->set_cookie(0, "SOCS", "CAESEwgDEgk1NTE1MDQ0NTkaAmVuIAEaBgiA0JamBg", "/", ".youtube.com", undef, 0, 1, $rand_value, 0, {});
    $cookies->set_cookie(0, "__Secure-YEC", "CgtCWUtqdVpZQXJUNCiL3pmmBg%3D%3D", "/", ".youtube.com", undef, 0, 1, $rand_value, 0, {});
    $cookies->set_cookie(0, "SOCS", "CAI", "/", ".youtube.com", undef, 0, 1, $rand_value, 0, {});
}

# ============================================================================
# HTTP REQUEST METHODS
# ============================================================================

sub _warn_response_error {
    my ($resp, $url) = @_;
    warn sprintf("[%s] Error occurred on URL: %s\n", $resp->status_line, $url);
}

sub lwp_get {
    my ($self, $url, %opt) = @_;

    $url || return;
    $self->{lwp} // $self->set_lwp_useragent();

    state @LWP_CACHE;

    $url = $self->_normalize_url($url);

    # Check cache
    if (my $cached = $self->_get_from_cache(\@LWP_CACHE, $url)) {
        return $cached;
    }

    my $response = $self->_execute_get_request($url);

    if ($response->is_success) {
        my $content = $response->decoded_content;
        $self->_add_to_cache(\@LWP_CACHE, $url, $content);
        return $content;
    }

    $opt{depth} ||= 0;

    # Retry on 500+ errors
    if ($opt{depth} < 1 && $response->code() >= 500 &&
        $response->status_line() =~ /(?:Temporary|Server) Error|Timeout|Service Unavailable/i) {
        return $self->lwp_get($url, %opt, depth => $opt{depth} + 1);
    }

    _warn_response_error($response, $url);
    return;
}

sub _normalize_url {
    my ($self, $url) = @_;

    if ($url =~ m{^//}) {
        $url = 'https:' . $url;
    }

    if ($url =~ m{^/vi/}) {
        $url = 'https://i.ytimg.com' . $url;
    }

    $url =~ s{^https?://[^/]+(/vi/.*\.jpg)\z}{https://i.ytimg.com$1};

    return $url;
}

sub _get_from_cache {
    my ($self, $cache_ref, $url) = @_;

    foreach my $entry (@$cache_ref) {
        if ($entry->{url} eq $url && time - $entry->{timestamp} <= 600) {
            return $entry->{content};
        }
    }

    return;
}

sub _add_to_cache {
    my ($self, $cache_ref, $url, $content) = @_;

    unshift(@$cache_ref, {url => $url, content => $content, timestamp => time});
    pop(@$cache_ref) if (scalar(@$cache_ref) >= 50);
}

sub _execute_get_request {
    my ($self, $url) = @_;

    my $r;

    if ($url =~ m{^https?://[^/]+\.onion/}) {
        if (not defined($self->get_http_proxy)) {
            if ($self->get_env_proxy && (defined($ENV{HTTP_PROXY}) || defined($ENV{HTTPS_PROXY}))) {
                # LWP::UserAgent will use proxy from ENV
            }
            else {
                say ":: Setting proxy for onion websites..." if $self->get_debug;
                $self->{lwp}->proxy(['http', 'https'], 'socks://localhost:9050');
                $r = $self->{lwp}->get($url);
                $self->{lwp}->proxy(['http', 'https'], undef);
            }
        }
    }

    return $r // $self->{lwp}->get($url);
}

sub lwp_post {
    my ($self, $url, @args) = @_;

    $self->{lwp} // $self->set_lwp_useragent();

    my $response = $self->{lwp}->post($url, @args);

    if ($response->is_success) {
        return $response->decoded_content;
    }
    else {
        _warn_response_error($response, $url);
    }

    return;
}

sub lwp_mirror {
    my ($self, $url, $output_file) = @_;
    $self->{lwp} // $self->set_lwp_useragent();
    $self->{lwp}->mirror($url, $output_file);
}

sub _get_results {
    my ($self, $url, %opt) = @_;
    return scalar {
        url     => $url,
        results => parse_json_string($self->lwp_get($url, %opt)),
    };
}

sub post_as_json {
    my ($self, $url, $ref) = @_;
    my $json_str = make_json_string($ref);
    $self->_save('POST', $url, $json_str);
}

sub _request {
    my ($self, $req) = @_;

    $self->{lwp} // $self->set_lwp_useragent();

    my $res = $self->{lwp}->request($req);

    if ($res->is_success) {
        return $res->decoded_content;
    }
    else {
        warn 'Request error: ' . $res->status_line();
    }

    return;
}

sub _prepare_request {
    my ($self, $req, $length) = @_;
    $req->header('Content-Length' => $length) if ($length);
    return 1;
}

sub _save {
    my ($self, $method, $uri, $content) = @_;

    require HTTP::Request;
    my $req = HTTP::Request->new($method => $uri);
    $req->content_type('application/json; charset=UTF-8');
    $self->_prepare_request($req, length($content));
    $req->content($content);

    $self->_request($req);
}

# ============================================================================
# INVIDIOUS INSTANCE MANAGEMENT
# ============================================================================

sub get_invidious_instances {
    my ($self) = @_;

    require File::Spec;
    my $instances_file = File::Spec->catfile($self->get_config_dir, 'instances.json');

    if ((not -e $instances_file) or (-M _) > 1 / 24) {
        $self->_update_instances_file($instances_file);
    }

    open(my $fh, '<', $instances_file) or return;
    my $json_string = do { local $/; <$fh> };
    parse_json_string($json_string);
}

sub _update_instances_file {
    my ($self, $instances_file) = @_;

    require LWP::UserAgent;
    my $lwp = LWP::UserAgent->new(timeout => $self->get_timeout);
    $lwp->show_progress(1) if $self->get_debug;
    my $resp = $lwp->get("https://api.invidious.io/instances.json");

    $resp->is_success() or return;

    my $json = $resp->decoded_content() || return;
    open(my $fh, '>', $instances_file) or return;
    print $fh $json;
    close $fh;
}

sub select_good_invidious_instances {
    my ($self, %args) = @_;

    state $instances = $self->get_invidious_instances;
    ref($instances) eq 'ARRAY' or return;

    my %ignored = (
        'yewtu.be'                 => 1,
        'invidious.tube'           => 1,
        'invidious.site'           => 1,
        'invidious.zee.li'         => 1,
        'invidious.048596.xyz'     => 1,
        'invidious.xyz'            => 1,
        'invidious.ggc-project.de' => 1,
        'invidious.toot.koeln'     => 1,
        'invidious.kavin.rocks'    => 1,
        'invidious.snopyta.org'    => 1,
        'invidious.moomoo.me'      => 1,
        'y.com.cm'                 => 1,
        'invidious.exonip.de'      => 1,
        'invidious-us.kavin.rocks' => 1,
        'invidious-jp.kavin.rocks' => 1,
    );

    my @candidates =
        grep { not $ignored{$_->[0]} }
        grep { $args{lax} ? 1 : eval { lc($_->[1]{monitor}{dailyRatios}[0]{label} // '') eq 'success' } }
        grep { $args{lax} ? 1 : eval { lc($_->[1]{monitor}{statusClass} // '') eq 'success' } }
        grep { lc($_->[1]{type} // '') eq 'https' } @$instances;

    if ($self->get_debug) {
        my @hosts = map { $_->[0] } @candidates;
        my $count = scalar(@candidates);
        print STDERR ":: Found $count invidious instances: @hosts\n";
    }

    return @candidates;
}

sub _find_working_instance {
    my ($self, $candidates, $extra_candidates) = @_;

    require File::Spec;
    my $current_instance_file = File::Spec->catfile($self->get_config_dir, 'current_instance.json');

    if (my $instance = $self->_get_cached_instance($current_instance_file)) {
        return $instance;
    }

    require List::Util;
    state $yv_utils = WWW::PipeViewer::Utils->new();

    foreach my $instance (List::Util::shuffle(@$candidates), List::Util::shuffle(@$extra_candidates)) {
        ref($instance) eq 'ARRAY' or next;

        my $uri = $instance->[1]{uri} // next;
        $uri =~ s{/+\z}{};

        local $self->{api_host}         = $uri;
        local $self->{prefer_invidious} = 1;

        my $t0 = time;
        my $results = $self->search_videos('test');

        if ($yv_utils->has_entries($results)) {
            if (time - $t0 <= 5) {
                $self->_cache_instance($current_instance_file, $instance);
            }
            return $instance;
        }
    }

    return;
}

sub _get_cached_instance {
    my ($self, $file) = @_;

    open(my $fh, '<:raw', $file) or return;
    my $instance = parse_json_string(do { local $/; scalar <$fh> });
    close $fh;

    if (ref($instance) eq 'ARRAY' && time - $instance->[1]{_time} <= 3600) {
        return $instance;
    }

    return;
}

sub _cache_instance {
    my ($self, $file, $instance) = @_;

    open(my $fh, '>:raw', $file) or return;
    $instance->[1]{_time} = time;
    say $fh make_json_string($instance);
    close $fh;
}

sub pick_random_instance {
    my ($self) = @_;

    my @candidates       = $self->select_good_invidious_instances();
    my @extra_candidates = $self->select_good_invidious_instances(lax => 1);

    if ($self->get_prefer_invidious) {
        if (defined(my $instance = $self->_find_working_instance(\@candidates, \@extra_candidates))) {
            return $instance;
        }
    }

    @candidates = @extra_candidates if not @candidates;
    return $candidates[rand @candidates];
}

sub pick_and_set_random_instance {
    my ($self) = @_;

    my $instance = $self->pick_random_instance() // return;
    ref($instance) eq 'ARRAY' or return;

    my $uri = $instance->[1]{uri} // return;
    $uri =~ s{/+\z}{};

    $self->set_api_host($uri);
}

sub get_api_url {
    my ($self) = @_;

    my $host = $self->get_api_host;
    $host =~ s/^\s+//;
    $host =~ s/\s+\z//;
    $host =~ s{/+\z}{};

    if ($host =~ /\w\.\w/ && $host !~ m{^\w+://}) {
        my $protocol = ($host =~ m{^[^/]+\.onion\z}) ? 'http://' : 'https://';
        $host = $protocol . $host;
    }

    if ($host eq 'auto' || $host =~ m{^https://(?:www\.)?invidio\.us\b}) {
        if (defined($self->pick_and_set_random_instance())) {
            $host = $self->get_api_host();
            print STDERR ":: Changed the instance to: $host\n" if $self->get_debug;
        }
        else {
            $host = "https://invidious.fdn.fr";
            $self->set_api_host($host);
            print STDERR ":: Failed to change the instance. Using: $host\n" if $self->get_debug;
        }
    }

    join('', $host, $self->get_api_path);
}

sub _simple_feeds_url {
    my ($self, $path, %args) = @_;
    $self->get_api_url . $path . '?' . $self->list_to_url_arguments(%args);
}

sub _make_feed_url {
    my ($self, $path, %args) = @_;

    my $extra_args = $self->default_arguments(%args);
    my $url        = $self->get_api_url . $path;

    if ($extra_args) {
        $url .= '?' . $extra_args;
    }

    return $url;
}

# ============================================================================
# YOUTUBE DATA EXTRACTION
# ============================================================================

sub _get_youtubei_content {
    my ($self, $endpoint, $videoID, %args) = @_;

    my $url = sprintf($self->get_youtubei_url(), $endpoint);

    require Time::Piece;

    my $android_useragent = 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';

    my %android = (
        "videoId" => $videoID,
        "context" => {
            "client" => {
                'hl'                => 'en',
                'gl'                => 'US',
                'clientName'        => 'ANDROID',
                'clientVersion'     => '20.10.38',
                'androidSdkVersion' => 30,
                'userAgent'         => $android_useragent,
                %args,
            }
        },
    );

    $self->{lwp} // $self->set_lwp_useragent();

    my $agent = $self->{lwp}->agent;
    $self->{lwp}->agent($android_useragent) if ($endpoint ne 'next');

    my $client_version = sprintf("2.%s.00.00", Time::Piece->new(time)->strftime("%Y%m%d"));

    my %mweb = (
        "videoId" => $videoID,
        "context" => {
            "client" => {
                "hl"            => "en",
                "gl"            => "US",
                "clientName"    => "MWEB",
                "clientVersion" => $client_version,
                %args,
            },
        },
    );

    my $content;
    for (1 .. 3) {
        $content = $self->post_as_json($url, $endpoint eq 'next' ? \%mweb : \%android);
        last if defined $content;
    }

    $self->{lwp}->agent($agent);
    return $content;
}

sub _get_video_info {
    my ($self, $videoID, %args) = @_;
    my $content = $self->_get_youtubei_content('player', $videoID, %args);
    my %info = (player_response => $content);
    return %info;
}

sub _get_video_next_info {
    my ($self, $videoID) = @_;
    $self->_get_youtubei_content('next', $videoID);
}

# ============================================================================
# YT-DLP / YOUTUBE-DL INTEGRATION
# ============================================================================

sub _ytdl_is_available {
    my ($self) = @_;
    ($self->proxy_stdout($self->get_ytdl_cmd(), '--version') // '') =~ /\d/;
}

sub _info_from_ytdl {
    my ($self, $videoID) = @_;

    $self->_ytdl_is_available() || return undef;

    my @ytdl_cmd = ($self->get_ytdl_cmd(), '--all-formats', '--dump-single-json');

    my $cookie_file = $self->get_cookie_file;
    if (defined($cookie_file) && -f $cookie_file) {
        push @ytdl_cmd, '--cookies', quotemeta($cookie_file);
    }

    my $json = $self->proxy_stdout(@ytdl_cmd, quotemeta("https://www.youtube.com/watch?v=" . $videoID));
    my $ref  = parse_json_string($json // return undef);

    if ($self->get_debug >= 3) {
        require Data::Dump;
        Data::Dump::pp($ref);
    }

    return $ref;
}

sub _extract_from_ytdl {
    my ($self, $videoID) = @_;

    my $ref = $self->_info_from_ytdl($videoID) // return;

    my @formats;

    if (ref($ref) eq 'HASH' && exists($ref->{formats}) && ref($ref->{formats}) eq 'ARRAY') {
        foreach my $format (@{$ref->{formats}}) {
            if (exists($format->{format_id}) && exists($format->{url})) {
                my $id = $format->{format_id};

                # Keep only the original audio track
                if ($id =~ /(^[0-9]+)-[0-9]/) {
                    $id = $1;
                    ($format->{format_note} // '') =~ /\boriginal\b/i or next;
                }

                my $entry = {
                    itag => $id,
                    url  => $format->{url},
                    type => ((($format->{format} // '') =~ /audio only/i) ? 'audio/' : 'video/') . $format->{ext},
                };

                push @formats, $entry;
            }
        }
    }

    return @formats;
}

sub _extract_from_invidious {
    my ($self, $videoID) = @_;

    my @candidates       = $self->select_good_invidious_instances();
    my @extra_candidates = $self->select_good_invidious_instances(lax => 1);

    require List::Util;

    my %seen;
    my @instances = grep { !$seen{$_}++ } (
        List::Util::shuffle(map { $_->[0] } @candidates),
        List::Util::shuffle(map { $_->[0] } @extra_candidates),
    );

    if (@instances) {
        push @instances, 'invidious.fdn.fr';
    }
    else {
        @instances = qw(
            invidious.fdn.fr
            vid.puffyan.us
            invidious.privacydev.net
            invidious.flokinet.to
        );
    }

    if ($self->get_debug) {
        print STDERR ":: Invidious instances: @instances\n";
    }

    # Limit to first 5 instances
    if (scalar(@instances) > 5) {
        $#instances = 4;
    }

    my $tries      = 2 * scalar(@instances);
    my $instance   = shift(@instances);
    my $url_format = "https://%s/api/v1/videos/%s?fields=formatStreams,adaptiveFormats";
    my $url        = sprintf($url_format, $instance, $videoID);

    my $resp = $self->{lwp}->get($url);

    while (not $resp->is_success() && --$tries >= 0) {
        $url  = sprintf($url_format, shift(@instances), $videoID) if (@instances && ($tries % 2 == 0));
        $resp = $self->{lwp}->get($url);
    }

    $resp->is_success() || return;

    my $json = $resp->decoded_content() // return;
    my $ref  = parse_json_string($json) // return;

    my @formats;

    if (exists($ref->{adaptiveFormats}) && ref($ref->{adaptiveFormats}) eq 'ARRAY') {
        push @formats, @{$ref->{adaptiveFormats}};
    }

    if (exists($ref->{formatStreams}) && ref($ref->{formatStreams}) eq 'ARRAY') {
        push @formats, @{$ref->{formatStreams}};
    }

    return @formats;
}

sub _fallback_extract_urls {
    my ($self, $videoID) = @_;

    my @formats;

    # Try youtube-dl/yt-dlp first
    if ($self->get_ytdl && $self->_ytdl_is_available) {
        if ($self->get_debug) {
            my $cmd = $self->get_ytdl_cmd;
            say STDERR ":: Using $cmd to extract the streaming URLs...";
        }

        push @formats, $self->_extract_from_ytdl($videoID);

        if ($self->get_debug) {
            my $count = scalar(@formats);
            my $cmd   = $self->get_ytdl_cmd;
            say STDERR ":: $cmd: found $count streaming URLs...";
        }

        @formats && return @formats;
    }

    # Fallback to invidious
    if ($self->get_debug) {
        say STDERR ":: Using invidious to extract the streaming URLs...";
    }

    if ($self->get_debug) {
        my $count = scalar(@formats);
        say STDERR ":: invidious: found $count streaming URLs...";
    }

    return @formats;
}

# ============================================================================
# CAPTION EXTRACTION
# ============================================================================

sub _make_translated_captions {
    my ($self, $caption_urls) = @_;

    my @languages = qw(
        af am ar az be bg bn bs ca ceb co cs cy da de el en eo es et eu fa fi fil
        fr fy ga gd gl gu ha haw hi hmn hr ht hu hy id ig is it iw ja jv ka kk km
        kn ko ku ky la lb lo lt lv mg mi mk ml mn mr ms mt my ne nl no ny or pa pl
        ps pt ro ru rw sd si sk sl sm sn so sq sr st su sv sw ta te tg th tk tr tt
        ug uk ur uz vi xh yi yo zh-Hans zh-Hant zu
    );

    my %trans_languages = map { $_->{languageCode} => 1 } @$caption_urls;
    @languages = grep { not exists $trans_languages{$_} } @languages;

    my @asr;
    foreach my $caption (@$caption_urls) {
        foreach my $lang_code (@languages) {
            my %caption_copy = %$caption;
            $caption_copy{languageCode} = $lang_code;
            $caption_copy{baseUrl}      = $caption_copy{baseUrl} . "&tlang=$lang_code";
            push @asr, \%caption_copy;
        }
    }

    return @asr;
}

sub _fallback_extract_captions {
    my ($self, $videoID) = @_;

    if ($self->get_debug) {
        my $cmd = $self->get_ytdl_cmd;
        say STDERR ":: Extracting closed-caption URLs with $cmd";
    }

    my $ytdl_info = $self->_info_from_ytdl($videoID);

    my @caption_urls;

    if (defined($ytdl_info) && ref($ytdl_info) eq 'HASH') {
        my $has_subtitles = 0;

        foreach my $key (qw(subtitles automatic_captions)) {
            my $ccaps = $ytdl_info->{$key} // next;
            ref($ccaps) eq 'HASH' or next;

            foreach my $lang_code (sort keys %$ccaps) {
                my ($caption_info) = grep { $_->{ext} eq 'srv1' } @{$ccaps->{$lang_code}};

                if (defined($caption_info) && ref($caption_info) eq 'HASH' && defined($caption_info->{url})) {
                    push @caption_urls, scalar {
                        kind         => ($key eq 'automatic_captions' ? 'asr' : ''),
                        languageCode => $lang_code,
                        baseUrl      => $caption_info->{url},
                    };

                    if ($key eq 'subtitles') {
                        $has_subtitles = 1;
                    }
                }
            }

            last if $has_subtitles;
        }

        # Auto-translated captions
        if ($has_subtitles) {
            if ($self->get_debug) {
                say STDERR ":: Generating translated closed-caption URLs...";
            }
            push @caption_urls, $self->_make_translated_captions(\@caption_urls);
        }
    }

    return @caption_urls;
}

# ============================================================================
# STREAMING URL EXTRACTION
# ============================================================================

sub _check_streaming_urls {
    my ($self, $videoID, $results) = @_;

    foreach my $video (@$results) {
        if (exists $video->{s} || exists $video->{signatureCipher} || exists $video->{cipher}) {
            if ($self->get_debug) {
                say STDERR ":: Detected an encrypted signature...";
            }

            my @formats = $self->_fallback_extract_urls($videoID);

            foreach my $format (@formats) {
                foreach my $ref (@$results) {
                    if (defined($ref->{itag}) && ($ref->{itag} eq $format->{itag})) {
                        $ref->{url} = $format->{url};
                        last;
                    }
                }
            }

            last;
        }
    }

    foreach my $video (@$results) {
        if (exists $video->{mimeType}) {
            $video->{type} = $video->{mimeType};
        }
    }

    return 1;
}

sub _extract_streaming_urls {
    my ($self, $json, $videoID) = @_;

    if ($self->get_debug) {
        say STDERR ":: Using `player_response` to extract the streaming URLs...";
    }

    if ($self->get_debug >= 2) {
        require Data::Dump;
        Data::Dump::pp($json);
    }

    ref($json) eq 'HASH' or return;

    my @results;
    if (exists $json->{streamingData}) {
        my $streamingData = $json->{streamingData};

        if (defined $streamingData->{dashManifestUrl}) {
            say STDERR ":: Contains DASH manifest URL" if $self->get_debug;
        }

        if (exists $streamingData->{adaptiveFormats}) {
            push @results, @{$streamingData->{adaptiveFormats}};
        }

        if (exists $streamingData->{formats}) {
            push @results, @{$streamingData->{formats}};
        }
    }

    $self->_check_streaming_urls($videoID, \@results);

    # Filter streams
    @results = grep { $_->{itag} == 22 || (exists($_->{contentLength}) && $_->{contentLength} > 0) } @results;
    @results = grep { $_->{url} !~ /\bdur=0\.000\b/ } grep { defined($_->{url}) } @results;

    # Handle livestreams
    if (!@results && exists($json->{streamingData}) && exists($json->{streamingData}{hlsManifestUrl})) {
        if ($self->get_debug) {
            say STDERR ":: Live stream detected...";
        }

        @results = $self->_fallback_extract_urls($videoID);

        if (!@results) {
            push @results, {
                itag => 38,
                type => "video/mp4",
                wkad => 1,
                url  => $json->{streamingData}{hlsManifestUrl},
            };
        }
    }

    if (!@results) {
        @results = $self->_fallback_extract_urls($videoID);
    }

    return @results;
}

sub get_streaming_urls {
    my ($self, $videoID) = @_;

    no warnings 'redefine';
    local *_get_video_info = memoize(\&_get_video_info);

    my %info = $self->_get_video_info($videoID);
    my $json = defined($info{player_response}) ? parse_json_string($info{player_response}) : {};

    if ($self->get_debug >= 2) {
        say STDERR ":: JSON data from player_response";
        require Data::Dump;
        Data::Dump::pp($json);
    }

    my @caption_urls;

    # Handle age-restricted content
    if (not defined $json->{streamingData}) {
        say STDERR ":: Trying to bypass age-restricted gate..." if $self->get_debug;

        my @fallback_methods = $self->_get_age_gate_bypass_methods($videoID);

        foreach my $fallback_method (@fallback_methods) {
            $fallback_method->();
            $json = defined($info{player_response}) ? parse_json_string($info{player_response}) : {};
            if (defined($json->{streamingData})) {
                push @caption_urls, $self->_fallback_extract_captions($videoID);
                last;
            }
        }
    }

    my @streaming_urls = $self->_extract_streaming_urls($json, $videoID);

    # Extract captions
    if (eval { ref($json->{captions}{playerCaptionsTracklistRenderer}{captionTracks}) eq 'ARRAY' }) {
        my @caption_tracks = @{$json->{captions}{playerCaptionsTracklistRenderer}{captionTracks}};
        my @human_made_cc  = grep { ($_->{kind} // '') ne 'asr' } @caption_tracks;

        push @caption_urls, @human_made_cc, @caption_tracks;

        foreach my $caption (@caption_urls) {
            $caption->{baseUrl} =~ s{\bfmt=srv[0-9]\b}{fmt=srv1}g;
        }

        push @caption_urls, $self->_make_translated_captions(\@caption_urls);
    }

    # Fallback if no streaming URLs found
    if (1 || !@streaming_urls ||
        (($json->{playabilityStatus}{status} // '') =~ /fail|error|unavailable|not available/i) ||
        $self->get_force_fallback ||
        (($json->{videoDetails}{videoId} // '') ne $videoID)) {

        @streaming_urls = $self->_fallback_extract_urls($videoID);

        if (!@caption_urls) {
            push @caption_urls, $self->_fallback_extract_captions($videoID);
        }
    }

    if ($self->get_debug) {
        my $count = scalar(@streaming_urls);
        say STDERR ":: Found $count streaming URLs...";
    }

    # Filter by format preference
    if ($self->get_prefer_mp4 || $self->get_prefer_av1) {
        @streaming_urls = $self->_filter_streaming_urls_by_preference(@streaming_urls);
    }

    # Filter out zero-length streams
    @streaming_urls = grep { defined($_->{clen}) ? ($_->{clen} > 0) : 1 } @streaming_urls;

    # Default fallback
    if (!@streaming_urls) {
        push @streaming_urls, {
            itag => 38,
            type => "video/mp4",
            wkad => 1,
            url  => "https://www.youtube.com/watch?v=$videoID",
        };
    }

    if ($self->get_debug >= 2) {
        require Data::Dump;
        Data::Dump::pp(\%info) if ($self->get_debug >= 3);
        Data::Dump::pp(\@streaming_urls);
        Data::Dump::pp(\@caption_urls);
    }

    return (\@streaming_urls, \@caption_urls, \%info);
}

sub _get_age_gate_bypass_methods {
    my ($self, $videoID) = @_;

    my @methods;

    if ($self->get_bypass_age_gate_native) {
        push @methods, sub {
            my %info = $self->_get_video_info(
                $videoID,
                "clientName"    => "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
                "clientVersion" => "2.0"
            );
        };
    }

    if ($self->get_bypass_age_gate_with_proxy) {
        push @methods, sub {
            my $proxy_url = "https://youtube-proxy.zerody.one/getPlayer?";
            $proxy_url .= $self->list_to_url_arguments(
                videoId       => $videoID,
                reason        => "LOGIN_REQUIRED",
                clientName    => "ANDROID",
                clientVersion => "16.20",
                hl            => "en",
            );
            my %info = (player_response => $self->lwp_get($proxy_url) // undef);
        };
    }

    return @methods;
}

sub _filter_streaming_urls_by_preference {
    my ($self, @streaming_urls) = @_;

    my @video_urls;
    my @audio_urls;

    require WWW::PipeViewer::Itags;
    state $itags = WWW::PipeViewer::Itags::get_itags();

    my %audio_itags;
    @audio_itags{map { $_->{value} } @{$itags->{audio}}} = ();

    foreach my $url (@streaming_urls) {
        if (exists($audio_itags{$url->{itag}})) {
            push @audio_urls, $url;
            next;
        }

        if ($url->{type} =~ /\bvideo\b/i) {
            if ($url->{type} =~ /\bav[0-9]+\b/i) {
                push @video_urls, $url if $self->get_prefer_av1;
            }
            elsif ($self->get_prefer_mp4 && $url->{type} =~ /\bmp4\b/i) {
                push @video_urls, $url;
            }
        }
        else {
            push @audio_urls, $url;
        }
    }

    return @video_urls ? (@video_urls, @audio_urls) : @streaming_urls;
}

# ============================================================================
# PARSING & PAGINATION
# ============================================================================

sub parse_query_string {
    my ($self, $str, %opt) = @_;

    if (not defined($str)) {
        return;
    }

    require URI::Escape;

    my @pairs;
    foreach my $statement (split(/,/, $str)) {
        foreach my $pair (split(/&/, $statement)) {
            push @pairs, $pair;
        }
    }

    my %result;

    foreach my $pair (@pairs) {
        my ($key, $value) = split(/=/, $pair, 2);

        if (not defined($value) || $value eq '') {
            next;
        }

        $value = URI::Escape::uri_unescape($value =~ tr/+/ /r);

        if ($opt{multi}) {
            push @{$result{$key}}, $value;
        }
        else {
            $result{$key} = $value;
        }
    }

    return %result;
}

sub _group_keys_with_values {
    my ($self, %data) = @_;

    my @hashes;

    foreach my $key (keys %data) {
        foreach my $i (0 .. $#{$data{$key}}) {
            $hashes[$i]{$key} = $data{$key}[$i];
        }
    }

    return @hashes;
}

sub next_page_with_token {
    my ($self, $url, $token) = @_;

    if (ref($token) eq 'CODE') {
        return $token->();
    }

    if ($token =~ /^ytdlp:comments:(.*?):(\d+):(.*?):(.*)/) {
        my ($video_id, $page, $prev_root_comment_id, $prev_comment_id) = ($1, $2, $3, $4);
        return $self->comments_from_ytdlp($video_id, $page, $prev_root_comment_id, $prev_comment_id);
    }

    if ($token =~ /^yt(search|browse|playlist):(\w+):(.*)/s) {
        my $method = $1;
        my $type   = $2;
        my $json   = $3;

        my $info = (($json =~ /^\{/) ? parse_json_string($json) : {token => $json, args => {}});

        my $method_name;
        if ($method eq 'browse') {
            $method_name = 'yt_browse_request';
        }
        elsif ($method eq 'search') {
            $method_name = 'yt_search_next_page';
        }
        elsif ($method eq 'playlist') {
            $method_name = 'yt_playlist_next_page';
        }
        else {
            die "[BUG] Invalid method: <<$method>>";
        }

        return $self->$method_name($url, $info->{token}, type => $type, url => $url, %{$info->{args}});
    }

    if ($url =~ m{^https://m\.youtube\.com}) {
        return scalar { url => $url, results => [] };
    }

    if (not $url =~ s{[?&]continuation=\K([^&]+)}{$token}) {
        $url = $self->_append_url_args($url, continuation => $token);
    }

    my $res = $self->_get_results($url);
    $res->{url} = $url;
    return $res;
}

sub next_page {
    my ($self, $url, $token) = @_;

    if ($token) {
        return $self->next_page_with_token($url, $token);
    }

    if ($url =~ m{^https://m\.youtube\.com}) {
        return scalar { url => $url, results => [] };
    }

    if (not $url =~ s{[?&]page=\K(\d+)}{$1+1}e) {
        $url = $self->_append_url_args($url, page => 2);
    }

    my $res = $self->_get_results($url);
    $res->{url} = $url;
    return $res;
}

# ============================================================================
# PROXY UTILITIES
# ============================================================================

{
    no strict 'refs';

    foreach my $name ('exec', 'system', 'stdout') {
        *{__PACKAGE__ . '::proxy_' . $name} = sub {
            my ($self, @args) = @_;

            $self->{lwp} // $self->set_lwp_useragent();

            local $ENV{http_proxy}  = $self->{lwp}->proxy('http');
            local $ENV{https_proxy} = $self->{lwp}->proxy('https');
            local $ENV{HTTP_PROXY}  = $self->{lwp}->proxy('http');
            local $ENV{HTTPS_PROXY} = $self->{lwp}->proxy('https');

            local $" = " ";

            $name eq 'exec'   ? exec(@args)
          : $name eq 'system' ? system(@args)
          : $name eq 'stdout' ? qx(@args)
          :                     ();
        };
    }
}

# ============================================================================
# POD DOCUMENTATION
# ============================================================================

=head1 NAME

WWW::PipeViewer - A simple interface to YouTube.

=head1 SYNOPSIS

    use WWW::PipeViewer;

    my $yv_obj = WWW::PipeViewer->new();

=head1 DESCRIPTION

This module provides an interface to interact with YouTube, including
searching, retrieving video information, and extracting streaming URLs.

=head1 METHODS

=head2 new(%opts)

Returns a blessed object with the specified options.

=head2 escape_string($string)

Escapes a string with URI::Escape and returns it.

=head2 set_lwp_useragent()

Initializes the LWP::UserAgent module and returns it.

=head2 lwp_get($url, %opt)

Get and return the content for C<$url>.

=head2 lwp_post($url, [@args])

Post and return the content for $url.

=head2 lwp_mirror($url, $output_file)

Downloads the $url into $output_file. Returns true on success.

=head2 list_to_url_arguments(\%options)

Returns a valid string of arguments, with defined values.

=head2 default_arguments(%args)

Merge the default arguments with %args and concatenate them together.

=head2 parse_query_string($string, multi => [0,1])

Parse a query string and return a data structure back.

When the B<multi> option is set to a true value, the function will store
multiple values for a given key.

Returns back a list of key-value pairs.

=head2 get_streaming_urls($videoID)

Returns a list of streaming URLs for a videoID.
({itag=>..., url=>...}, {itag=>..., url=>....}, ...)

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>

=head1 SEE ALSO

https://developers.google.com/youtube/v3/docs/

=head1 LICENSE AND COPYRIGHT

Copyright 2012-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<https://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

1;    # End of WWW::PipeViewer

__END__
#!/usr/bin/perl
# Comprehensive test for all Profile menu features
use lib '/home/ihorman/Documents/DevRepository/pipe-viewer/lib';
use WWW::PipeViewer;
use utf8;
binmode STDOUT, ':utf8';

my $PASS = 0;
my $FAIL = 0;
my $TOTAL = 0;

sub test {
    my ($name, $condition, $detail) = @_;
    $TOTAL++;
    if ($condition) {
        $PASS++;
        print "  PASS: $name\n";
    }
    else {
        $FAIL++;
        print "  FAIL: $name";
        print " ($detail)" if $detail;
        print "\n";
    }
}

print "=" x 60, "\n";
print "COMPREHENSIVE FEATURE TEST\n";
print "=" x 60, "\n\n";

# Test 1: Cookie extraction
print "--- Test 1: Cookie Extraction ---\n";
my $yv = WWW::PipeViewer->new(cookies_from_browser => 'chromium', debug => 0);
test("Object created", defined $yv);
test("Profile loaded", $yv->get_profile_loaded == 1, "profile_loaded=" . $yv->get_profile_loaded);
test("Cookies from browser set", defined $yv->get_cookies_from_browser);

# Test 2: Subscription feed
print "\n--- Test 2: Subscription Feed ---\n";
my $subs = eval { $yv->subscription_feed() };
test("Subscription feed returned data", defined $subs && ref($subs) eq 'HASH');
if ($subs && ref($subs) eq 'HASH') {
    my @e = @{$subs->{results} // []};
    test("Subscription feed has results", scalar @e > 0, "count=" . scalar @e);
    test("First result has title", defined $e[0]{title} && length($e[0]{title}) > 0);
    test("First result has videoId", defined $e[0]{videoId} && length($e[0]{videoId}) > 0);
    print "  Sample: $e[0]{title}\n" if $e[0]{title};
}

# Test 3: YouTube History
print "\n--- Test 3: YouTube History ---\n";
my $hist = eval { $yv->youtube_history() };
test("History returned data", defined $hist && ref($hist) eq 'HASH');
if ($hist && ref($hist) eq 'HASH') {
    my @e = @{$hist->{results} // []};
    test("History has results", scalar @e > 0, "count=" . scalar @e);
    if (@e) {
        test("First result has title", defined $e[0]{title} && length($e[0]{title}) > 0);
        test("First result has videoId", defined $e[0]{videoId} && length($e[0]{videoId}) > 0);
        print "  Sample: $e[0]{title}\n" if $e[0]{title};
    }
}

# Test 4: YouTube Playlists
print "\n--- Test 4: YouTube Playlists ---\n";
my $playlists = eval { $yv->youtube_playlists() };
test("Playlists returned data", defined $playlists && ref($playlists) eq 'HASH');
if ($playlists && ref($playlists) eq 'HASH') {
    my @e = @{$playlists->{results} // []};
    test("Playlists has results", scalar @e > 0, "count=" . scalar @e);
    if (@e) {
        test("First result has title", defined $e[0]{title} && length($e[0]{title}) > 0);
        test("First result has playlistId", defined $e[0]{playlistId} && length($e[0]{playlistId}) > 0);
        print "  Sample: $e[0]{title}\n" if $e[0]{title};
    }
}

# Test 5: Trending
print "\n--- Test 5: Trending ---\n";
my $trending = eval { $yv->trending_videos_from_category(undef) };
test("Trending returned data", defined $trending && ref($trending) eq 'HASH');
if ($trending && ref($trending) eq 'HASH') {
    my @e = @{$trending->{results} // []};
    test("Trending has results", scalar @e > 0, "count=" . scalar @e);
    if (@e) {
        test("First result has title", defined $e[0]{title} && length($e[0]{title}) > 0);
        print "  Sample: $e[0]{title}\n" if $e[0]{title};
    }
}

# Test 6: Shorts
print "\n--- Test 6: Shorts ---\n";
my $shorts = eval { $yv->youtube_shorts() };
test("Shorts returned data", defined $shorts && ref($shorts) eq 'HASH');
if ($shorts && ref($shorts) eq 'HASH') {
    my @e = @{$shorts->{results} // []};
    test("Shorts has results", scalar @e > 0, "count=" . scalar @e);
    if (@e) {
        test("First result has title", defined $e[0]{title} && length($e[0]{title}) > 0);
        test("First result has videoId", defined $e[0]{videoId} && length($e[0]{videoId}) > 0);
        print "  Sample: $e[0]{title}\n" if $e[0]{title};
    }
}

# Test 7: Search (basic functionality)
print "\n--- Test 7: Search ---\n";
my $search = eval { $yv->search_videos('linux') };
test("Search returned data", defined $search && ref($search) eq 'HASH');
if ($search && ref($search) eq 'HASH') {
    my $entries = $search->{results}{entries} // $search->{results};
    if (ref($entries) eq 'ARRAY') {
        test("Search has results", scalar @$entries > 0, "count=" . scalar @$entries);
        if (@$entries) {
            test("First result has title", defined $entries->[0]{title} && length($entries->[0]{title}) > 0);
            print "  Sample: $entries->[0]{title}\n" if $entries->[0]{title};
        }
    }
}

# Summary
print "\n", "=" x 60, "\n";
print "RESULTS: $PASS/$TOTAL passed, $FAIL failed\n";
print "=" x 60, "\n";

exit($FAIL > 0 ? 1 : 0);

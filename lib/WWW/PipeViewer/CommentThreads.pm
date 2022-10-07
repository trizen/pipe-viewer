package WWW::PipeViewer::CommentThreads;

use utf8;
use 5.014;
use warnings;

use WWW::PipeViewer::ParseJSON;

=head1 NAME

WWW::PipeViewer::CommentThreads - Retrieve comments threads.

=head1 SYNOPSIS

    use WWW::PipeViewer;
    my $obj = WWW::PipeViewer->new(%opts);
    my $videos = $obj->comments_from_video_id($video_id);

=head1 SUBROUTINES/METHODS

=cut

sub comments_from_ytdlp {
    my ($self, $video_id, $page, $prev_root_comment_id, $prev_comment_id) = @_;

    $page //= 1;

    my $max_comments   = $self->get_ytdlp_max_comments;
    my $max_replies    = $self->get_ytdlp_max_replies;
    my $comments_order = $self->get_comments_order;
    my $ytdl_cmd       = $self->get_ytdl_cmd;

    my $max_comments_per_page = $max_comments;
    $max_comments = $page * $max_comments;

    my @cmd = (
        $ytdl_cmd,
        '--write-comments',
        '--extractor-args',
#<<<
        quotemeta("youtube:comment_sort=$comments_order;skip=hls,dash,translated_subs;player_skip=js;max_comments=$max_comments,all,all,$max_replies"),
#>>>
        '--no-check-formats',
        '--ignore-no-formats-error',
        '--dump-single-json',
        quotemeta("https://www.youtube.com/watch?v=$video_id"),
    );

    if ($self->get_debug) {
        say STDERR ":: Extracting comments with `yt-dlp`...";
    }

    my $info = parse_json_string($self->proxy_stdout(@cmd) // return);

    (ref($info) eq 'HASH' and exists($info->{comments}) and ref($info->{comments}) eq 'ARRAY')
      || return;

    my @comments      = @{$info->{comments}};
    my $comment_count = $info->{comment_count} // scalar(@comments);

    my $last_comment_id      = undef;
    my $last_root_comment_id = undef;

    if (@comments) {
        $last_comment_id = $comments[-1]{id};
    }

    for (my $i = $#comments ; $i >= 0 ; --$i) {
        my $comment = $comments[$i];
        if ($comment->{parent} eq 'root') {
            $last_root_comment_id = $comment->{id};
            last;
        }
    }

    $last_comment_id      //= $prev_comment_id      // '';
    $last_root_comment_id //= $prev_root_comment_id // '';

    if ($page > 1) {
        my $prev_root_comment;

        foreach my $i (0 .. $#comments) {
            my $comment = $comments[$i];

            if ($prev_root_comment_id and $comment->{id} eq $prev_root_comment_id) {
                $prev_root_comment = $comment;
            }

            if ($prev_comment_id and $comment->{id} eq $prev_comment_id) {
                @comments = splice(@comments, $i + 1);
                last;
            }
        }

        if (defined($prev_root_comment)) {
            $prev_root_comment->{_hidden} = 1;
            unshift @comments, $prev_root_comment;
        }
    }

    my %table;
    foreach my $comment (@comments) {
        my $id = $comment->{id} // "root";
        $table{$id} = $comment;
    }

    my @formatted_comments;
    foreach my $comment (@comments) {
        my $parent = $comment->{parent} // "root";

        if ($parent ne "root" and exists($table{$parent})) {
            push @{$table{$parent}{replies}}, $comment;
        }
        else {
            push @formatted_comments, $comment;
        }
    }

    my $url          = undef;
    my $continuation = undef;

    if ($comment_count >= $max_comments) {
        $url          = 'https://yt-dlp';
        $continuation = join(':', 'ytdlp:comments', $video_id, $page + 1, $last_root_comment_id, $last_comment_id);
    }

    scalar {
            results => {
                        comments     => \@formatted_comments,
                        videoId      => $video_id,
                        continuation => $continuation,
                       },
            url => $url,
           };
}

=head2 comments_from_videoID($videoID)

Retrieve comments from a video ID.

=cut

sub comments_from_video_id {
    my ($self, $video_id) = @_;

    if ($self->get_ytdlp_comments) {
        my $comments = $self->comments_from_ytdlp($video_id);
        defined($comments) and return $comments;
    }

    $self->_get_results($self->_make_feed_url("comments/$video_id", sort_by => $self->get_comments_order));
}

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::PipeViewer::CommentThreads


=head1 LICENSE AND COPYRIGHT

Copyright 2015-2016 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<https://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::PipeViewer::CommentThreads

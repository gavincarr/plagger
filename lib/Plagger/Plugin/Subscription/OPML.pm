package Plagger::Plugin::Subscription::OPML;
use strict;
use base qw( Plagger::Plugin );

use Plagger::UserAgent;
use URI;
use XML::OPML;

sub register {
    my($self, $context) = @_;

    $context->register_hook(
        $self,
        'subscription.load' => \&load,
    );
}

sub load {
    my($self, $context) = @_;
    my $uri = URI->new($self->conf->{url})
        or $context->error("config 'url' is missing");

    my $xml;
    if ($uri->scheme =~ /^https?$/) {
        $context->log(debug => "Fetch remote OPML from $uri");
        my $response = Plagger::UserAgent->new->get($uri);
        unless ($response->is_success) {
            $context->error("Fetch $uri failed: ". $response->status_line);
        }
        $xml = $response->content;
    }
    elsif ($uri->scheme eq 'file') {
        $context->log(debug => "Open local OPML file " . $uri->path);
        open my $fh, '<', $uri->path
            or $context->error( $uri->path . ": $!" );
        $xml = join '', <$fh>;
    }
    else {
        $context->error("Unsupported URI scheme: " . $uri->scheme);
    }

    my $opml = XML::OPML->new;
    $opml->parse($xml);
    for my $outline (@{ $opml->outline }) {
        $self->walk_down($outline, $context, 0, []);
    }
}

sub walk_down {
    my($self, $outline, $context, $depth, $containers) = @_;

    if (delete $outline->{opmlvalue}) {
        my $title = delete $outline->{title};
        push @$containers, $title if $title ne 'Subscriptions';
        for my $channel (values %$outline) {
            $self->walk_down($channel, $context, $depth + 1, $containers);
        }
        pop @$containers if $title ne 'Subscriptions';
    } else {
        my $feed = Plagger::Feed->new;
        $feed->url($outline->{xmlUrl});
        $feed->link($outline->{htmlUrl});
        $feed->title($outline->{title});
        $feed->tags($containers);
        $context->dumper($feed->tags);
        $context->subscription->add($feed);
    }
}

1;
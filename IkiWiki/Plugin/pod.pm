#!/usr/bin/perl
# POD as a wiki page type.
package IkiWiki::Plugin::pod;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::pod - process pages written in POD format.

=head1 VERSION

This describes version B<0.01> of IkiWiki::Plugin::pod

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

In the ikiwiki setup file, enable this plugin by adding it to the
list of active plugins.

    add_plugins => [qw{goodstuff pod ....}],

=head1 DESCRIPTION

IkiWiki::Plugin::pod is an IkiWiki plugin enabling ikiwiki to
process pages written in POD (Plain Old Documentation) format.
This will treat files with a B<.pod> or B<.pm> extension as files
which contain POD markup.

=head1 OPTIONS

The following options can be set in the ikiwiki setup file.

=over

=item pod_index

If true, this will generate an index (table of contents) for the page.

=item pod_toplink

The label to be used for links back to the top of the page.
If this is empty, then no top-links will be generated.

=back

=head1 PREREQUISITES

    IkiWiki
    Pod::Xhtml
    IO::String

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2009 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

use IkiWiki 3.00;
use Pod::Xhtml;
use IO::String;

sub import {
	hook(type => "getsetup", id => "pod", call => \&getsetup);
	hook(type => "checkconfig", id => "pod", call => \&checkconfig);
	hook(type => "htmlize", id => "pod", call => \&htmlize);
	hook(type => "htmlize", id => "pm", call => \&htmlize);
}

sub getsetup () {
	return
		plugin => {
			description => "process pages written in POD format",
			safe => 1,
			rebuild => undef,
		},
		pod_index => {
			type => "boolean",
			example => "0",
			description => "if true, make an index for the page",
			safe => 0,
			rebuild => 0,
		},
		pod_toplink => {
			type => "string",
			example => "Top",
			description => "label for link to top of page",
			safe => 0,
			rebuild => 0,
		},
}

sub checkconfig () {
    if (!defined $config{pod_index})
    {
	$config{pod_index} = 1;
    }
    if (!defined $config{pod_toplink})
    {
	$config{pod_toplink} = '';
    }
    return 1;
}

sub htmlize (@) {
    my %params=@_;
    my $content = $params{content};
    my $page = $params{page};

    my $toplink = $config{pod_toplink} ?
	sprintf '<p><a href="#TOP" class="toplink">%s</a></p>',
	$config{pod_toplink} : '';

    my $parser = new Pod::Xhtml(
				StringMode => 1,
				FragmentOnly => 1,
				MakeIndex  => $config{pod_index},
				TopLinks   => $toplink,
			       );
    my $io = IO::String->new($content);
    $parser->parse_from_filehandle($io);

    return $parser->asString;
}

1;

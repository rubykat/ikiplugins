#!/usr/bin/perl
# Plain text (texttohtml) as a wiki page type.
package IkiWiki::Plugin::texttohtml;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::texttohtml - process pages written in plain text format.

=head1 VERSION

This describes version B<0.01> of IkiWiki::Plugin::texttohtml

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

In the ikiwiki setup file, enable this plugin by adding it to the
list of active plugins.

    add_plugins => [qw{goodstuff texttohtml ....}],

=head1 DESCRIPTION

IkiWiki::Plugin::texttohtml is an IkiWiki plugin enabling ikiwiki to
process pages written in plain text format (as understood by
the txt2html (HTML::TextToHTML) converter).
This will treat files with a B<.text> extension as files
which contain plain text markup, and convert them to HTML.

=head1 OPTIONS

The following options can be set in the ikiwiki setup file.

=over

=item texttohtml_options

A hash containing additional options to pass to HTML::TextToHTML.

=back

=head1 PREREQUISITES

    IkiWiki
    HTML::TextToHTML
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
use HTML::TextToHTML;
use IO::Scalar;

my $Parser;

my %Opts;

sub import {
	hook(type => "getsetup", id => "texttohtml", call => \&getsetup);
	hook(type => "checkconfig", id => "texttohtml", call => \&checkconfig);
	hook(type => "htmlize", id => "text", call => \&htmlize);
	$Parser = new HTML::TextToHTML(
	    escape_HTML_chars => 0,
	    extract => 1,
	);
}

sub getsetup () {
	return
		plugin => {
			description => "process pages written in plain text format",
			safe => 1,
			rebuild => undef,
		},
		texttohtml_options => {
			type => "hash",
			example => "{ short_line_length => 80, }",
			description => "options to pass to txt2html",
			safe => 0,
			rebuild => 1,
		},
		txt_custom_heading_regexp => {
			type => "array",
			example => "['==== [a-zA-Z0-9 ]+ ====']",
			description => "regular expression for custom headings",
			safe => 0,
			rebuild => 1,
		},
}

sub checkconfig () {
    if (defined $config{texttohtml_options}
	and ref $config{texttohtml_options} ne 'HASH')
    {
	error("texttohtml: texttohtml_options expects a hash");
	return 0;
    }
    %Opts = ($config{texttohtml_options}
		? %{$config{texttohtml_options}}
		: ());
    if ($config{txt_custom_heading_regexp})
    {
	if (!ref $config{txt_custom_heading_regexp})
	{
	    $Opts{custom_heading_regexp} = [$config{txt_custom_heading_regexp}];
	}
	else
	{
	    $Opts{custom_heading_regexp} = $config{txt_custom_heading_regexp};
	}
    }
    return 1;
}

sub htmlize (@) {
    my %params=@_;
    my $page = $params{page};

    $Parser->args(%Opts);
    # if we have fields, check for temporary overrides of some options
    if (UNIVERSAL::can("IkiWiki::Plugin::field", "import"))
    {
	foreach my $opt (qw{mailmode make_tables short_line_length})
	{
	    my $val =
		IkiWiki::Plugin::field::field_get_value("texttohtml_${opt}",
							$params{page});
		if ($val)
		{
		    $Parser->args($opt=>$val);
		}
	}
    }

    my $out = $Parser->process_chunk($params{content});
    # because we have set escape_HTML_chars to false (to allow
    # use of HTML tags) we need to fix up random ampersands.
    $out =~ s{ & }{&amp;}ogs;

    return $out;
}

1;

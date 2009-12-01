#!/usr/bin/perl
# Ikiwiki xslt plugin.
package IkiWiki::Plugin::xslt;
use warnings;
use strict;
=head NAME

IkiWiki::Plugin::xslt - ikiwiki directive to process an XML file with XSLT

=head VERSION

This describes version B<0.02> of IkiWiki::Plugin::xslt

=cut

our $VERSION = '0.02';

=head1 SYNOPSIS

[[!xslt file="data1.xml" stylesheet="style1.xsl"]

=head1 DESCRIPTION

IkiWiki::Plugin::xslt is an IkiWiki plugin implementing a directive
to process an input XML data file with XSLT, and output the result in
the page where the directive was called.

It is expected that the XSLT stylesheet will output valid HTML markup.

=head1 OPTIONS

There are two arguments to this directive.

=over

=item file

The file which contains XML data to be processed.  This file is searched
for using the usual IkiWiki mechanism, thus finding the file first
in the same directory as the page, then in the directory above, and so on.
This MUST have an extension of B<.xml>

=item stylesheet

The file which contains XSLT stylesheet to apply to the XML data.
This MUST have an extension of B<.xsl>

This file is searched for using the usual IkiWiki mechanism, thus
finding the file first in the same directory as the page, then in the
directory above, and so on.

=back

=head1 PREREQUISITES

    IkiWiki
    XML::LibXML
    XML::LibXSLT

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2009 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

use IkiWiki 3.00;
use XML::LibXSLT;
use XML::LibXML;

my $XSLT_parser;
my $XSLT_xslt;

sub import {
	hook(type => "getsetup", id => "xslt",  call => \&getsetup);
	hook(type => "checkconfig", id => "xslt", call => \&checkconfig);
	hook(type => "preprocess", id => "xslt", call => \&preprocess);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub checkconfig () {
    debug("xslt plugin checkconfig");
    $XSLT_parser = XML::LibXML->new();
    $XSLT_xslt = XML::LibXSLT->new();
}

sub preprocess (@) {
    my %params=@_;

    # check the files exist
    my %near = ();
    foreach my $param (qw{stylesheet file}) {
	if (! exists $params{$param})
	{
	    error sprintf(gettext('%s parameter is required'), $param);
	}
	if ($param eq 'stylesheet' and $params{$param} !~ /.xsl$/)
	{
	    error sprintf(gettext('%s must have .xsl extension'), $param);
	}
	if ($param eq 'file' and $params{$param} !~ /.xml$/)
	{
	    error sprintf(gettext('%s must have .xml extension'), $param);
	}
	$near{$param} = bestlink($params{page}, $params{$param});
	if (! $near{$param})
	{
	    error sprintf(gettext('cannot find bestlink for "%s"'),
			  $params{$param});
	}
	if (! exists $pagesources{$near{$param}})
	{
	    error sprintf(gettext('cannot find file "%s"'), $near{$param});
	}
	add_depends($params{page}, $near{$param});
    }

    my $source = $XSLT_parser->parse_file(srcfile($near{file}));
    my $style_doc = $XSLT_parser->parse_file(srcfile($near{stylesheet}));
    my $stylesheet = $XSLT_xslt->parse_stylesheet($style_doc);
    my $results = $stylesheet->transform($source);
    return $stylesheet->output_string($results);
}

1;
__END__
